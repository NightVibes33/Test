#!/usr/bin/env python3
"""Extract DeepAI Code's REAL React client from its user-supplied macOS DMG.

Standard library only. Handles UDIF(zlib) -> GPT Apple_HFS -> HFS+ catalog ->
Electron ASAR -> apps/server/dist/client. This does not convert macOS binaries.

Usage: python3 Scripts/extract_deepai_dmg.py DeepAI-Code-0.3.40-arm64.dmg
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import struct
import tempfile
import zlib

SECTOR = 512

def u16(buf, pos): return struct.unpack_from('>H', buf, pos)[0]
def u32(buf, pos): return struct.unpack_from('>I', buf, pos)[0]
def u64(buf, pos): return struct.unpack_from('>Q', buf, pos)[0]

def udif_to_hfs(dmg: Path, output: Path):
    with dmg.open('rb') as inp:
        inp.seek(-512, os.SEEK_END)
        trailer = inp.read(512)
        if trailer[:4] != b'koly': raise ValueError('Not an Apple UDIF DMG (koly not found)')
        xoff, xsize = u64(trailer, 0xd8), u64(trailer, 0xe0)
        if xsize < 100 or xsize > 20_000_000 or xoff + xsize > dmg.stat().st_size:
            raise ValueError('Invalid UDIF resource-fork XML length')
        inp.seek(xoff)
        plist = plistlib.loads(inp.read(xsize))
        sections = plist.get('resource-fork', {}).get('blkx', [])
        section = next((e for e in sections if 'Apple_HFS' in e.get('Name', '')), None)
        if not section: raise ValueError('No Apple_HFS partition found; unsupported DMG')
        blkx = section['Data']
        if blkx[:4] != b'mish': raise ValueError('Invalid UDIF block map')
        sector_count, n = u64(blkx, 16), u32(blkx, 0xc8)
        if sector_count * SECTOR > 8_000_000_000 or n > 500_000:
            raise ValueError('Disk image exceeds safe extraction limit')
        if 0xcc + 40 * n > len(blkx): raise ValueError('Truncated block map')
        datafork_offset = u64(trailer, 0x18)
        with output.open('wb') as dst:
            dst.truncate(sector_count * SECTOR)
            for idx in range(n):
                typ, _, sector_start, sectors, offset, length = struct.unpack_from('>IIQQQQ', blkx, 0xcc + idx * 40)
                if typ == 0xffffffff: continue
                if sector_start + sectors > sector_count: raise ValueError('Invalid sector range')
                if typ == 2: continue  # sparse/zero
                if length > 500_000_000: raise ValueError('Suspicious compressed extent')
                inp.seek(datafork_offset + offset)
                blob = inp.read(length)
                if len(blob) != length: raise ValueError('Truncated compressed extent')
                if typ == 0x80000005: blob = zlib.decompress(blob)
                elif typ != 1: raise ValueError(f'Unsupported DMG extent compression type 0x{typ:x}')
                if len(blob) != sectors * SECTOR: raise ValueError('Uncompressed extent length mismatch')
                dst.seek(sector_start * SECTOR)
                dst.write(blob)
        return sector_count * SECTOR

def fork_extents(buf: bytes, off: int):
    return [(u32(buf, off + 16 + 8 * i), u32(buf, off + 20 + 8 * i)) for i in range(8)]

class HFS:
    def __init__(self, image: Path):
        self.fp = image.open('rb')
        self.fp.seek(1024)
        header = self.fp.read(512)
        if u16(header, 0) not in (0x482b, 0x4858):
            raise ValueError('Volume is not HFS+')
        self.block_size = u32(header, 40)
        if self.block_size < 512 or self.block_size > 65536:
            raise ValueError('Invalid HFS+ block size')
        self.catalog_extents = fork_extents(header, 272)

    def readfork(self, extents, offset: int, size: int):
        output = bytearray()
        if size > 512_000_000: raise ValueError('Fork exceeds size limit')
        for start, count in extents:
            if not count: break
            extent_bytes = count * self.block_size
            if offset >= extent_bytes:
                offset -= extent_bytes
                continue
            n = min(extent_bytes - offset, size - len(output))
            self.fp.seek(start * self.block_size + offset)
            output.extend(self.fp.read(n))
            offset = 0
            if len(output) == size: break
        if len(output) != size: raise ValueError('File spans HFS+ overflow extents not supported by this extractor')
        return bytes(output)

    def files(self):
        header = self.readfork(self.catalog_extents, 0, 4096)
        node_size = u16(header, 32)
        first_leaf = u32(header, 24)
        if not 512 <= node_size <= 65536: raise ValueError('Invalid HFS+ catalog node size')
        records, seen, node_id = [], set(), first_leaf
        while node_id and node_id not in seen:
            seen.add(node_id)
            node = self.readfork(self.catalog_extents, node_id * node_size, node_size)
            if node[8] != 0xff: raise ValueError('Non-leaf HFS+ catalog node')
            for i in range(u16(node, 10)):
                pos = u16(node, node_size - 2 * (i + 1))
                if pos < 14 or pos > node_size - 8: continue
                keylen = u16(node, pos)
                if pos + 2 + keylen > node_size: continue
                parent, name_len = u32(node, pos + 2), u16(node, pos + 6)
                if name_len > 255: continue
                name = node[pos + 8:pos + 8 + name_len * 2].decode('utf-16-be', 'replace')
                record_offset = pos + 2 + keylen
                kind = u16(node, record_offset)
                if kind not in (1, 2): continue
                size = 248 if kind == 2 else 88
                body = node[record_offset:record_offset + size]
                records.append(dict(kind=kind, id=u32(body, 8), parent=parent, name=name, body=body))
            node_id = u32(node, 0)
        folders = {e['id']: e for e in records if e['kind'] == 1}
        def filename(e):
            parts, path, ids = [], e, set()
            while path is not None:
                parts.append(path['name'])
                if path['parent'] in ids: break
                ids.add(path['parent'])
                path = folders.get(path['parent'])
            return '/'.join(reversed(parts))
        return [(filename(e), e) for e in records if e['kind'] == 2]

    def getfile(self, record):
        return self.readfork(fork_extents(record['body'], 88), 0, u64(record['body'], 88))


def extract_asar_client(asar: Path, destination: Path):
    with asar.open('rb') as archive:
        prefix = archive.read(16)
        if len(prefix) < 16 or int.from_bytes(prefix[:4], 'little') != 4:
            raise ValueError('Invalid ASAR pickle header')
        header_size = int.from_bytes(prefix[4:8], 'little')
        json_size = int.from_bytes(prefix[12:16], 'little')
        if header_size > 10_000_000 or json_size > header_size:
            raise ValueError('Invalid ASAR header length')
        header = json.loads(archive.read(json_size))
        base = header_size + 8
        def resolve(path):
            curr = header['files']
            for key in path.split('/'):
                ent = curr[key]
                curr = ent.get('files', {})
            return ent
        metadata = resolve('package.json')
        archive.seek(base + int(metadata['offset']))
        package = json.loads(archive.read(metadata['size']))
        root = resolve('apps/server/dist/client')
        if 'files' not in root: raise ValueError('No original React client in ASAR')
        exported = 0
        def walk(files, parts):
            nonlocal exported
            for name, meta in files.items():
                if not name or name in ('.', '..') or '/' in name or '\\' in name:
                    raise ValueError('Unsafe ASAR file path')
                names = parts + [name]
                if 'files' in meta:
                    walk(meta['files'], names)
                elif not meta.get('unpacked'):
                    size = int(meta['size'])
                    offset = int(meta['offset'])
                    if size > 30_000_000 or offset < 0: raise ValueError('Suspicious ASAR file extent')
                    target = destination.joinpath(*names)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    archive.seek(base + offset)
                    blob = archive.read(size)
                    if len(blob) != size: raise ValueError('Truncated ASAR file')
                    target.write_bytes(blob)
                    exported += 1
        walk(root['files'], [])
        return package, exported



def extract_asar_server(asar: Path, destination: Path):
    """Recover the original bundled Node server and JS dependencies.

    Native macOS `.node` add-ons are intentionally not treated as iOS binaries.
    Source stays inside the build workspace; the repository does not publish
    copied DeepAI server files.
    """
    with asar.open('rb') as archive:
        prefix = archive.read(16)
        header_size = int.from_bytes(prefix[4:8], 'little')
        json_size = int.from_bytes(prefix[12:16], 'little')
        if prefix[:4] != b"\x04\x00\x00\x00" or json_size > header_size or header_size > 10_000_000:
            raise ValueError('Invalid Electron ASAR header')
        header = json.loads(archive.read(json_size))
        base = header_size + 8
        def locate(path):
            node = None
            children = header['files']
            for segment in path.split('/'):
                node = children[segment]
                children = node.get('files', {})
            return node
        total, bytes_read = 0, 0
        def walk(entries, segments):
            nonlocal total, bytes_read
            for name, meta in entries.items():
                if not name or name in ('.', '..') or any(ch in name for ch in ('/', '\\', '\x00')):
                    raise ValueError('Unsafe ASAR filename')
                parts = segments + [name]
                if 'files' in meta:
                    walk(meta['files'], parts)
                    continue
                if meta.get('unpacked'):
                    # macOS executables and add-ons cannot execute on iOS.
                    continue
                if 'offset' not in meta: continue
                size = int(meta['size'])
                offset = int(meta['offset'])
                if size < 0 or size > 40_000_000 or offset < 0:
                    raise ValueError('ASAR entry exceeds size limit')
                archive.seek(base + offset)
                blob = archive.read(size)
                if len(blob) != size:
                    raise ValueError('Truncated original server component')
                target = destination.joinpath(*parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(blob)
                total += 1
                bytes_read += size
        for path in ('apps/server/dist', 'node_modules'):
            node = locate(path)
            walk(node['files'], path.split('/'))
        pkg = locate('package.json')
        archive.seek(base + int(pkg['offset']))
        (destination / 'package.json').write_bytes(archive.read(pkg['size']))
        total += 1
        # Replace non-iOS ffi-rs fuzzy-finder with real on-device JS filesystem search.
        compatibility = Path(__file__).resolve().parent.parent / 'Compatibility/fff-ios.mjs'
        finder = destination / 'node_modules/@ff-labs/fff-node/dist/src/index.js'
        if compatibility.is_file() and finder.is_file():
            finder.with_name('index.js.desktop-original').write_bytes(finder.read_bytes())
            finder.write_bytes(compatibility.read_bytes())
        # node-pty is imported during boot; shell subprocesses are unavailable on iOS.
        pty_source = Path(__file__).resolve().parent.parent / 'Compatibility/node-pty'
        pty_dest = destination / 'node_modules/node-pty'
        if pty_source.is_dir():
            pty_dest.mkdir(exist_ok=True, parents=True)
            for filename in ('package.json', 'index.js'):
                (pty_dest / filename).write_bytes((pty_source / filename).read_bytes())
        if not (destination / 'apps/server/dist/bin.mjs').is_file():
            raise ValueError('Original server entry point missing')
        return {'files': total, 'bytes': bytes_read, 'entry': 'apps/server/dist/bin.mjs'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dmg', type=Path)
    parser.add_argument('--destination', type=Path, default=Path(__file__).resolve().parent.parent / 'OriginalWebClient')
    parser.add_argument('--with-server', action='store_true', help='also extract the original Node backend to OriginalServer')
    parser.add_argument('--server-destination', type=Path, default=Path(__file__).resolve().parent.parent / 'OriginalServer')
    args = parser.parse_args()
    src = args.dmg.resolve()
    if not src.is_file(): parser.error(f'No file: {src}')
    digest = hashlib.sha256(src.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='deepai-udif-') as tmp:
        image = Path(tmp) / 'hfs.img'
        size = udif_to_hfs(src, image)
        volume = HFS(image)
        matches = [(path, rec) for path, rec in volume.files() if path.endswith('/DeepAI Code.app/Contents/Resources/app.asar')]
        if len(matches) != 1: raise ValueError(f'Expected one DeepAI Code app.asar; found {len(matches)}')
        asar = Path(tmp) / 'app.asar'
        asar.write_bytes(volume.getfile(matches[0][1]))
        volume.fp.close()
        package, files = extract_asar_client(asar, args.destination)
        server = extract_asar_server(asar, args.server_destination) if args.with_server else None
    result = {'source': src.name, 'sha256': digest, 'dmg_hfs_bytes': size, 'original_app': package.get('name'),
              'version': package.get('version'), 'upstream_hash': package.get('t3codeCommitHash'),
              'original_client_files': files, 'output': str(args.destination.resolve()),
              'original_server': server}
    if not (args.destination / 'index.html').is_file(): raise ValueError('Client entrypoint is missing')
    print(json.dumps(result, indent=2))
    return result

if __name__ == '__main__': main()
