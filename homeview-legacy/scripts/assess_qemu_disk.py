#!/usr/bin/env python3
"""See whether a qemu-sptm darwin machine source creates a block backend."""
import argparse
import json
from pathlib import Path


def assess(text):
    lowered = text.lower()
    virtio = "virtio-blk" in lowered or "virtio_blk" in lowered
    nvme = "nvme" in lowered and ("pci" in lowered or "block" in lowered)
    ramdisk = "-ramdisk" in text or "ramdisk" in lowered
    return {
        "machine": "darwin",
        "ramdisk_path_present": ramdisk,
        "virtio_blk_present": virtio,
        "nvme_block_backend_present": nvme,
        "qemu_creates_guest_disk": virtio or nvme,
        "apple_kernel_will_mount_that_disk_proven": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = assess(Path(args.source).read_text(encoding="utf-8", errors="replace"))
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"disk": report["qemu_creates_guest_disk"]}))


if __name__ == "__main__":
    main()
