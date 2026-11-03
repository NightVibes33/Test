#!/usr/bin/env python3
"""Copy one disk image into the ramdisk slot only when it fits.

Images outside the slot stay unstaged. Nothing is mounted or booted here.
"""
import argparse
import json
import shutil
from pathlib import Path


def stage(root, dest, max_bytes):
    root = Path(root)
    dest = Path(dest)
    dmgs = []
    if root.is_dir():
        dmgs = [path for path in root.rglob("*.dmg") if path.is_file()]
    if not dmgs:
        return {
            "staged": False,
            "reason": "no_dmg",
            "largest_file_bytes": 0,
            "nand_block_device_present": False,
            "booted": False,
        }
    largest = max(dmgs, key=lambda path: path.stat().st_size)
    size = largest.stat().st_size
    if size <= 1024 or size > max_bytes:
        if dest.is_file():
            dest.unlink()
        return {
            "staged": False,
            "reason": "outside_ramdisk_slot",
            "largest_file_bytes": size,
            "nand_block_device_present": False,
            "booted": False,
        }
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(largest, dest)
    return {
        "staged": True,
        "reason": "fits_ramdisk_slot",
        "largest_file_bytes": size,
        "nand_block_device_present": False,
        "booted": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--dest", required=True)
    parser.add_argument("--max-bytes", type=int, required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = stage(args.dir, args.dest, args.max_bytes)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"staged": report["staged"], "bytes": report["largest_file_bytes"]}))


if __name__ == "__main__":
    main()
