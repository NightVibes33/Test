#!/usr/bin/env python3
"""Summarize an `ipsw ota ls` listing. Paths and sizes only, no file bytes."""
import argparse
import json
import re
from pathlib import Path

MARKERS = ("SpringBoard", "BreadBoard", "AppleFirmwareKit", "launchd", "dyld")
# These two trustcaches belong to the restore/update ramdisks already booted.
RAMDISK_TRUSTCACHE = (
    "141-21782-189.dmg.trustcache",
    "arm64eSURamDisk.dmg.trustcache",
)
RAMDISK_DMG = (
    "141-21782-189.dmg",
    "arm64eSURamDisk.dmg",
)
# qemu-sptm presents the root as a ramdisk in guest RAM. A larger image cannot
# be attached: this machine has no NAND block device.
# qemu-sptm copies the ramdisk into guest RAM. 8 GiB is the largest root this
# job will try; bigger images need the ANS block device, which is not ready.
GUEST_RAMDISK_LIMIT = 8 * 1024 * 1024 * 1024
SIZE = re.compile(r"(\d+(?:\.\d+)?)\s*([kKmMgG]i?B)")
UNITS = {
    "kb": 1000, "mb": 1000 ** 2, "gb": 1000 ** 3,
    "kib": 1024, "mib": 1024 ** 2, "gib": 1024 ** 3,
}


def parse_size(line):
    match = SIZE.search(line)
    if not match:
        return None
    token = match.group(2).lower()
    scale = UNITS.get(token)
    if scale is None and token.endswith("b"):
        scale = UNITS.get(token[:-1] + "b")
    if scale is None:
        return None
    return int(float(match.group(1)) * scale)


def path_of(line):
    for token in reversed(line.split()):
        if "/" in token or token.endswith(".trustcache"):
            return token.lstrip("./")
    return None


def summarize(text):
    hits = []
    for raw in text.splitlines():
        if len(raw) > 2000:
            continue
        path = path_of(raw)
        if not path:
            continue
        interesting = (
            any(marker in path for marker in MARKERS)
            or path.endswith(".trustcache")
            or path.endswith(".dmg")
            or "dyld_shared_cache" in path
        )
        if not interesting:
            continue
        hits.append({"path": path[:300], "listed_bytes": parse_size(raw)})
        if len(hits) >= 400:
            break

    def pick(substr):
        return [item for item in hits if substr in item["path"]]

    spring = pick("SpringBoard")
    bread = pick("BreadBoard")
    firmware = pick("AppleFirmwareKit")
    launchd = [item for item in hits if item["path"].endswith("sbin/launchd")
               or item["path"].endswith("/launchd")]
    dyld = [item for item in hits if "dyld" in item["path"]]
    trust = [item for item in hits if item["path"].endswith(".trustcache")]
    system_trust = [item for item in trust
                    if not any(name in item["path"] for name in RAMDISK_TRUSTCACHE)]
    dmg_paths = [item["path"] for item in hits if item["path"].endswith(".dmg")]
    for item in system_trust:
        derived = item["path"][:-len(".trustcache")] if item["path"].endswith(".dmg.trustcache") else None
        if derived and derived not in dmg_paths:
            dmg_paths.append(derived)
    candidate_dmgs = [path for path in dmg_paths
                      if not any(name in path for name in RAMDISK_DMG)]
    boot_parts = spring + bread + launchd + dyld
    known = [item["listed_bytes"] for item in boot_parts]
    total = sum(known) if known and all(size is not None for size in known) else None
    fits = bool(spring) and total is not None and total <= GUEST_RAMDISK_LIMIT
    return {
        "source": "ipsw ota ls of the original HomeView 24V514 AEA",
        "interesting_paths": hits[:80],
        "springboard_listed": bool(spring),
        "breadboard_listed": bool(bread),
        "applefirmwarekit_listed": bool(firmware),
        "launchd_listed": bool(launchd),
        "dyld_listed": bool(dyld),
        "listing_line_count": len(text.splitlines()),
        "payload_line_count": sum(1 for line in text.splitlines() if "payload" in line.lower()),
        "system_trustcache_paths": [item["path"] for item in system_trust[:12]],
        "candidate_system_dmgs": candidate_dmgs[:12],
        "listed_boot_bytes": total,
        "fits_qemu_ramdisk_slot": fits,
        "guest_ramdisk_limit_bytes": GUEST_RAMDISK_LIMIT,
        "qemu_has_nand_block_device": False,
        "volume_built": False,
        "springboard_boot_proven": False,
        "note": (
            "A listed path is not an extracted file and not a running process. "
            "qemu-sptm's darwin machine can only root a ramdisk, so a system "
            "image larger than guest RAM cannot be booted until NAND exists."
        ),
    }


def write_partial_manifest(image, output):
    image = Path(image)
    size = image.stat().st_size if image.is_file() else 0
    present = image.is_file() and size > 1024
    fits = present and size <= GUEST_RAMDISK_LIMIT
    manifest = {
        "springboard_file_present": present,
        "trustcache_from_ota": False,
        "trustcache_is_restore_ramdisk": False,
        "source": "ipsw ota extract payloadv2",
        "image_bytes": size,
        "fits_qemu_ramdisk_slot": fits,
        "root_slot": "qemu-sptm ramdisk",
        "nand_block_device_present": False,
        "springboard_boot_proven": False,
        "note": "Partial payload extract is not booted without its own trustcache.",
    }
    Path(output).write_text(json.dumps(manifest, indent=2) + "\n")
    if present and not fits:
        image.unlink()
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listing")
    parser.add_argument("--output", required=True)
    parser.add_argument("--partial-image")
    args = parser.parse_args()
    if args.partial_image:
        manifest = write_partial_manifest(args.partial_image, args.output)
        print(json.dumps({"partial_image_bytes": manifest["image_bytes"],
                          "fits": manifest["fits_qemu_ramdisk_slot"]}))
        return
    listing = Path(args.listing)
    text = listing.read_text(encoding="utf-8", errors="replace") if listing.is_file() else ""
    result = summarize(text)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "springboard": result["springboard_listed"],
        "fits_ramdisk": result["fits_qemu_ramdisk_slot"],
        "system_trustcaches": len(result["system_trustcache_paths"]),
        "listed_boot_bytes": result["listed_boot_bytes"],
    }))


if __name__ == "__main__":
    main()
