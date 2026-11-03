#!/usr/bin/env python3
"""See whether an extracted AppleFirmwareKit Mach-O actually contains AFKResource.

A plist executable name is not a linked metaclass. This reads one kext tree
and does not keep the binary.
"""
import argparse
import json
from pathlib import Path

MACHO = (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")


def inspect(root):
    root = Path(root)
    found = []
    if root.is_dir():
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            try:
                size = path.stat().st_size
                magic = path.read_bytes()[:4]
            except OSError:
                continue
            if magic not in MACHO or size < 64:
                continue
            data = path.read_bytes()
            found.append({
                "name": path.name[:128],
                "bytes": size,
                "contains_AFKResource_string": b"AFKResource" in data,
            })
            if len(found) >= 8:
                break
    linked = any(item["contains_AFKResource_string"] and item["bytes"] > 4096 for item in found)
    return {
        "macho_count": len(found),
        "machos": found,
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
