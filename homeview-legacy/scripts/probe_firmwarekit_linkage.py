#!/usr/bin/env python3
"""See whether an extracted AppleFirmwareKit Mach-O actually contains AFKResource.

A plist executable name is not a linked metaclass. This reads one kext tree
and does not keep the binary.
"""
import argparse
import json
import struct
from pathlib import Path

MACHO = (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")
# MH_KEXT_BUNDLE is the filetype of a kernel extension executable.
MH_KEXT_BUNDLE = 0xB


def header_fields(data):
    if len(data) < 32 or data[:4] not in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        return {}
    endian = "<" if data[:4] == b"\xcf\xfa\xed\xfe" else ">"
    _magic, _cpu, _sub, filetype, ncmds, sizeofcmds, flags = struct.unpack_from(
        endian + "IIIIIII", data, 0)
    return {
        "mach_filetype": filetype,
        "mach_ncmds": ncmds,
        "mach_sizeofcmds": sizeofcmds,
        "mach_flags": flags,
        "is_kext_bundle": filetype == MH_KEXT_BUNDLE,
    }


def inspect(root):
    root = Path(root)
    found = []
    plist_has_class = False
    if root.is_dir():
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            try:
                size = path.stat().st_size
                data = path.read_bytes()
            except OSError:
                continue
            if path.suffix == ".plist" or path.name == "Info.plist":
                if b"AFKResource" in data:
                    plist_has_class = True
                continue
            if data[:4] not in MACHO or size < 64:
                continue
            item = {
                "name": path.name[:128],
                "bytes": size,
                "contains_AFKResource_string": b"AFKResource" in data,
                "AFK_string_count": data.count(b"AFK"),
                "IOService_string_present": b"IOService" in data,
            }
            item.update(header_fields(data))
            found.append(item)
            if len(found) >= 8:
                break
    linked = any(
        item["contains_AFKResource_string"] and item["bytes"] > 4096 and item.get("is_kext_bundle")
        for item in found)
    return {
        "macho_count": len(found),
        "machos": found,
        "sibling_plist_contains_AFKResource": plist_has_class,
        "linked_AFKResource_implementation": linked,
        "plist_only_if_no_macho": len(found) == 0,
        "guest_metaclass_registered_proven": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kext-dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = inspect(args.kext_dir)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "machos": report["macho_count"],
        "linked": report["linked_AFKResource_implementation"],
    }))


if __name__ == "__main__":
    main()
