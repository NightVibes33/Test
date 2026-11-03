#!/usr/bin/env python3
"""Classify a path listing from the mounted Apple restore ramdisk.

The listing is paths only. No file bytes are read or uploaded.
A restore ramdisk is not the installed HomeView system.
"""
import argparse
import json
from pathlib import Path

MARKERS = (
    "SpringBoard",
    "BreadBoard",
    "AppleFirmwareKit",
    "AFKResource",
)


def classify(text, mount_ok):
    lines = []
    for raw in text.splitlines():
        path = raw.strip().lstrip("/")
        if not path or len(path) > 300 or "\x00" in path:
            continue
        if path in ("MOUNT_OK", "MOUNT_FAILED"):
            continue
        lines.append(path)
        if len(lines) >= 200:
            break
    found = {name: [] for name in MARKERS}
    for path in lines:
        for name in MARKERS:
            if name.lower() in path.lower() and len(found[name]) < 20:
                found[name].append(path)
    return {
        "source": "read-only mount of the original HomeView software-update ramdisk",
        "mount_succeeded": bool(mount_ok),
        "paths_recorded": len(lines),
        "marker_paths": found,
        "SpringBoard_present_on_restore_ramdisk": bool(found["SpringBoard"]),
        "BreadBoard_present_on_restore_ramdisk": bool(found["BreadBoard"]),
        "AppleFirmwareKit_present_on_restore_ramdisk": bool(found["AppleFirmwareKit"]),
        "restore_ramdisk_is_installed_HomeView_system": False,
        "SpringBoard_boot_proven": False,
        "note": (
            "Path names from the restore ramdisk do not prove a process ran. "
            "SpringBoard is the installed-system UI, not the update ramdisk."
        ),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listing", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--mount-ok", action="store_true")
    args = parser.parse_args()
    listing = Path(args.listing)
    text = listing.read_text(encoding="utf-8", errors="replace") if listing.is_file() else ""
    mount_ok = args.mount_ok or "MOUNT_OK" in text
    if "MOUNT_FAILED" in text and "MOUNT_OK" not in text:
        mount_ok = False
    result = classify(text, mount_ok)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "mount": result["mount_succeeded"],
        "SpringBoard": result["SpringBoard_present_on_restore_ramdisk"],
        "BreadBoard": result["BreadBoard_present_on_restore_ramdisk"],
        "AppleFirmwareKit": result["AppleFirmwareKit_present_on_restore_ramdisk"],
    }))


if __name__ == "__main__":
    main()
