#!/usr/bin/env python3
"""Bounded, no-binary inventory of ORIGINAL Apple HomeView 24V514 OTA.

Source is aeota/aastuff_standalone -l output, NOT a mounted or installed
HomeView volume. Never promote OTA delta entries to a bootable root filesystem.
"""
import argparse
import json
from pathlib import Path
import re

ASSET = re.compile(r"AssetData/[^\r\n]+")
KIND = ("boot", "payload", "payloadv2", "other")
SYSTEM_MARKERS = (
    "System/Library/CoreServices",
    "System/Library/PrivateFrameworks",
    "System/Library/Frameworks",
    "usr/lib/dyld",
    "sbin/launchd",
    "System/Library/LaunchDaemons",
    "System/Library/CoreServices/BreadBoard",
)
MAX_SAMPLES = 18
MAX_LINE = 5000


def normalize(line):
    """Tolerate logs with timestamp prefix but reject unbounded/file data."""
    line = line.strip()
    if len(line) > MAX_LINE:
        return None
    m = ASSET.search(line)
    if not m:
        return None
    path = m.group(0)
    if "\x00" in path:
        return None
    # Keep the listing verbatim after AssetData; no guessing archive layout.
    return path


def classify(lines, success):
    counts = {name: 0 for name in KIND}
    samples = {name: [] for name in KIND}
    system = {name: 0 for name in SYSTEM_MARKERS}
    images = []
    total, recognized = 0, 0
    for line in lines:
        total += 1
        path = normalize(line)
        if not path:
            continue
        recognized += 1
        second = path.split("/", 2)[1] if "/" in path else "other"
        bucket = second if second in counts else "other"
        counts[bucket] += 1
        if len(samples[bucket]) < MAX_SAMPLES:
            samples[bucket].append(path)
        lower = path.lower()
        for marker in system:
            if marker.lower() in lower:
                system[marker] += 1
        if len(images) < MAX_SAMPLES and path.lower().endswith(
                (".dmg", ".dmg.aea", ".img", ".apfs", ".ipsw")):
            images.append(path)
    return {
        "source": "Apple HomeView 24V514 HomeAccessory17,1 original AEA",
        "inspection_method": "aeota aastuff_standalone -l filtered to AssetData",
        "archive_listing_command_succeeded": bool(success),
        "listing_nonempty_and_decoded": bool(success and recognized),
        "listing_lines_seen": total,
        "asset_paths_seen": recognized,
        "asset_path_counts": counts,
        "sample_asset_paths": samples,
        "system_userland_path_markers": system,
        "sample_disk_image_names": images,
        "full_installed_rootfs_present_proven": False,
        "fully_reconstructable_APFS_system_volume_proven": False,
        "Apple_setup_assistant_or_BreadBoard_running_proven": False,
        "diagnostic_conclusion": (
            "archive_listing_unavailable" if not success else
            "no_AssetData_entries_parsed" if recognized == 0 else
            "OTA_layout_observed_not_installed_system"
        ),
        "note": ("OTA listings may contain deltas and recovery payloads; "
                 "file/path presence does not prove a complete signed APFS "
                 "volume or normal HomeView runtime.")
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listing", required=True)
    ap.add_argument("--list-exit-code", type=int, required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    listing = Path(args.listing)
    with listing.open(encoding="utf-8", errors="replace") if listing.is_file() else open("/dev/null") as f:
        result = classify(f, args.list_exit_code == 0 and listing.is_file())
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["diagnostic_conclusion"],
                      "counts": result["asset_path_counts"],
                      "system_markers": result["system_userland_path_markers"]}))


if __name__ == "__main__":
    main()
