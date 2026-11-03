#!/usr/bin/env python3
"""Search decompressed Mach-O images for an AFKResource symbol or vtable.

A raw string in an Info.plist is not a metaclass. This walks symbol tables
and, when the kernelcache is a fileset, each embedded Mach-O. It does not
keep the binaries.
"""
import argparse
import json
import struct
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
LC_SYMTAB = 0x2
LC_FILESET_ENTRY = 0x80000035
NEEDLE = b"AFKResource"


def _c_string(data, start, limit):
    if start < 0 or start >= len(data):
        return b""
    end = data.find(b"\x00", start, min(len(data), start + limit))
    if end < 0:
        return b""
    return data[start:end]


def symbol_names(data):
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        return []
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    offset = 32
    end = min(len(data), 32 + sizeofcmds)
    symoff = nsyms = stroff = strsize = None
    seen = 0
    while offset + 8 <= end and seen < ncmds:
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmdsize < 8 or offset + cmdsize > len(data):
            break
        if cmd == LC_SYMTAB and offset + 24 <= len(data):
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, offset + 8)
        offset += cmdsize
        seen += 1
    if symoff is None or nsyms is None:
        return []
    names = []
    for index in range(min(nsyms, 300000)):
        entry = symoff + index * 16
        if entry + 8 > len(data):
            break
        n_strx = struct.unpack_from("<I", data, entry)[0]
        name = _c_string(data, stroff + n_strx, 240)
        if name:
            names.append(name)
    return names


def fileset_entries(data):
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        return []
    ncmds, sizeofcmds = struct.unpack_from("<II", data, 16)
    offset = 32
    end = min(len(data), 32 + sizeofcmds)
    entries = []
    seen = 0
    while offset + 8 <= end and seen < ncmds:
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmdsize < 8 or offset + cmdsize > len(data):
            break
        if cmd == LC_FILESET_ENTRY and offset + 32 <= len(data):
            vmaddr, fileoff = struct.unpack_from("<QQ", data, offset + 8)
            ident_off = struct.unpack_from("<I", data, offset + 24)[0]
            name = _c_string(data, offset + ident_off, 180)
            entries.append({
                "name": name.decode("ascii", "replace")[:160],
                "fileoff": fileoff,
                "vmaddr": vmaddr,
            })
        offset += cmdsize
        seen += 1
    return entries


def classify_name(name):
    return {
        "symbol": name.decode("ascii", "replace")[:180],
        "is_vtable": b"_ZTV" in name or b"vtable" in name.lower(),
        "is_metaclass": b"MetaClass" in name or b"10OSMetaClass" in name,
    }


def inspect_image(data, label):
    hits = [classify_name(name) for name in symbol_names(data) if NEEDLE in name]
    return {
        "label": label[:160],
        "bytes": len(data),
        "macho": len(data) >= 4 and struct.unpack_from("<I", data, 0)[0] == MH_MAGIC_64 if len(data) >= 4 else False,
        "string_count": data.count(NEEDLE),
        "symbol_hits": hits[:24],
    }


def scan(kernelcache=None, kext_dir=None):
    images = []
    not_macho = 0
    fileset = []
    if kernelcache:
        blob = Path(kernelcache).read_bytes() if Path(kernelcache).is_file() else b""
        if blob:
            images.append(inspect_image(blob, Path(kernelcache).name))
            ordered = sorted(fileset_entries(blob), key=lambda item: item["fileoff"])
            offsets = [item["fileoff"] for item in ordered]
            for index, entry in enumerate(ordered):
                fileset.append(entry["name"])
                start = entry["fileoff"]
                end = offsets[index + 1] if index + 1 < len(offsets) else len(blob)
                if start < 0 or start + 32 > len(blob) or end <= start:
                    not_macho += 1
                    continue
                if struct.unpack_from("<I", blob, start)[0] != MH_MAGIC_64:
                    not_macho += 1
                    continue
                images.append(inspect_image(blob[start:end], entry["name"] or "fileset-entry"))
                if len(images) >= 400:
                    break
    if kext_dir and Path(kext_dir).is_dir():
        for path in sorted(Path(kext_dir).rglob("*")):
            if not path.is_file() or path.stat().st_size < 64:
                continue
            data = path.read_bytes()
            if len(data) < 4 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
                continue
            images.append(inspect_image(data, path.name))
            if len(images) >= 400:
                break
    symbol_hits = []
    string_hits = 0
    for image in images:
        string_hits += image["string_count"]
        for hit in image["symbol_hits"]:
            symbol_hits.append({"image": image["label"], **hit})
    return {
        "images_scanned": len(images),
        "fileset_entry_count": len(fileset),
        "fileset_entries_not_macho": not_macho,
        "fileset_entry_names": fileset[:40],
        "afkresource_string_count": string_hits,
        "afkresource_symbol_hits": symbol_hits[:40],
        "implementation_found": any(
            hit["is_vtable"] or hit["is_metaclass"] or hit["symbol"] for hit in symbol_hits),
        "guest_metaclass_registered_proven": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernelcache")
    parser.add_argument("--kext-dir")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = scan(args.kernelcache, args.kext_dir)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "images": report["images_scanned"],
        "symbols": len(report["afkresource_symbol_hits"]),
        "strings": report["afkresource_string_count"],
    }))


if __name__ == "__main__":
    main()
