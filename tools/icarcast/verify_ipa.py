#!/usr/bin/env python3
"""Verify a purported decrypted IPA against its FairPlay-encrypted original.

Reject cryptid-only edits and retained SC_Info. Structural checks cannot prove
that decrypted plaintext runs: test the result on an authorized device.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path
from zipfile import ZipFile

def sha256(blob):
    return hashlib.sha256(blob).hexdigest()

def macho_encryption(blob):
    """Parse load commands from thin 32-/64-bit Mach-O files."""
    if len(blob) < 32:
        return []
    magic = blob[:4]
    if magic == b'\xcf\xfa\xed\xfe':
        endian, is64 = '<', True
    elif magic == b'\xce\xfa\xed\xfe':
        endian, is64 = '<', False
    elif magic == b'\xfe\xed\xfa\xcf':
        endian, is64 = '>', True
    elif magic == b'\xfe\xed\xfa\xce':
        endian, is64 = '>', False
    else:
        return []
    header = 32 if is64 else 28
    _, _, _, ncmds, sizeofcmds, _ = struct.unpack_from(endian + 'IIIIII', blob, 4)
    if ncmds > 4096 or sizeofcmds > len(blob) - header:
        raise ValueError('corrupt Mach-O commands')
    pos, results = header, []
    for _ in range(ncmds):
        if pos + 8 > header + sizeofcmds:
            raise ValueError('truncated Mach-O command')
        cmd, size = struct.unpack_from(endian + 'II', blob, pos)
        if size < 8 or pos + size > header + sizeofcmds:
            raise ValueError('invalid Mach-O command size')
        if cmd in (0x21, 0x2c):
            if size < 20:
                raise ValueError('truncated encryption command')
            off, length, cryptid = struct.unpack_from(endian + 'III', blob, pos + 8)
            if length and off + length > len(blob):
                raise ValueError('encrypted range beyond executable')
            results.append({'cryptoff': off, 'cryptsize': length, 'cryptid': cryptid})
        pos += size
    return results

def verify(original, output):
    with ZipFile(original) as src, ZipFile(output) as dst:
        if src.testzip() is not None or dst.testzip() is not None:
            raise ValueError('ZIP integrity failure')
        old_names, new_names = set(src.namelist()), set(dst.namelist())
        if len(old_names) != len(src.namelist()) or len(new_names) != len(dst.namelist()):
            raise ValueError('duplicate ZIP names')
        if any('/SC_Info/' in n for n in new_names):
            raise ValueError('output contains sensitive SC_Info files')
        retained = {n for n in old_names if '/SC_Info/' not in n}
        if not retained.issubset(new_names):
            raise ValueError('output missing app contents')
        changes = []
        for name in sorted(retained):
            before = src.read(name)
            commands = macho_encryption(before)
            for index, cmd in enumerate(commands):
                if cmd['cryptid'] == 0:
                    continue
                if cmd['cryptsize'] <= 0:
                    raise ValueError('invalid encrypted range')
                after = dst.read(name)
                commands_after = macho_encryption(after)
                if len(commands_after) != len(commands):
                    raise ValueError('encryption commands changed unexpectedly')
                next_cmd = commands_after[index]
                if next_cmd['cryptid'] != 0 or any(next_cmd[k] != cmd[k] for k in ('cryptoff','cryptsize')):
                    raise ValueError('executable still encrypted: ' + name)
                offset, end = cmd['cryptoff'], cmd['cryptoff'] + cmd['cryptsize']
                if before[offset:end] == after[offset:end]:
                    raise ValueError('cryptid-only patch: encrypted pages unchanged: ' + name)
                if len(before) != len(after):
                    raise ValueError('changed executable size: ' + name)
                changes.append({'name': name, 'cryptoff': offset, 'cryptsize': cmd['cryptsize'],
                                'encrypted_region_sha256': sha256(before[offset:end]),
                                'replacement_region_sha256': sha256(after[offset:end])})
        if not changes:
            raise ValueError('source IPA has no encrypted main executable')
    return {'status': 'structurally_verified_not_runtime_tested',
            'original_sha256': sha256(Path(original).read_bytes()),
            'output_sha256': sha256(Path(output).read_bytes()), 'changed_regions': changes}

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('original', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--report', type=Path)
    args = p.parse_args()
    try:
        result = verify(args.original, args.output)
        print(json.dumps(result, indent=2))
        if args.report:
            args.report.write_text(json.dumps(result, indent=2) + '\n')
    except Exception as e:
        print('VERIFICATION FAILED: ' + str(e), file=sys.stderr)
        sys.exit(1)
