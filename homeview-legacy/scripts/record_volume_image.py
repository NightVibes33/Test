#!/usr/bin/env python3
"""Record the size of an extracted cryptex or dyld tree, then stop.

Does not mount the image, does not treat it as NAND, and does not keep
file contents in the report.
"""
import argparse
import json
from pathlib import Path


def describe(root, label, cap=5000):
    root = Path(root)
    count = 0
    largest = 0
    suffix = None
    dmg = False
    if root.is_dir():
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            count += 1
            try:
                size = path.stat().st_size
            except OSError:
                continue
            if size > largest:
                largest = size
                suffix = path.suffix[:16]
            if path.suffix == ".dmg":
                dmg = True
            if count >= cap:
                break
    return {
        "label": label,
        "files_seen": count,
        "scan_capped": count >= cap,
        "largest_file_bytes": largest,
        "largest_file_suffix": suffix,
        "dmg_present": dmg,
        "nand_block_device_present": False,
        "booted": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = describe(args.dir, args.label)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "label": report["label"],
        "files": report["files_seen"],
        "largest": report["largest_file_bytes"],
        "dmg": report["dmg_present"],
    }))


if __name__ == "__main__":
    main()
