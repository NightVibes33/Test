#!/usr/bin/env python3
"""Count entries in a version-1 static trustcache.

The bytes are produced by a public trustcache tool. This only reads the header.
"""
import argparse
import json
import struct
from pathlib import Path


def count_v1_entries(blob):
    if len(blob) < 24:
        return None
    version = struct.unpack_from("<I", blob, 0)[0]
    if version != 1:
        return None
    count = struct.unpack_from("<I", blob, 20)[0]
    entry = 22  # 20-byte cdhash + hash type + flags
    if 24 + count * entry > len(blob):
        return None
    return count


def build_with_tool(root, tool, output, limit=20000):
    import os
    import subprocess
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            path = os.path.join(dirpath, name)
            try:
                if os.path.getsize(path) > 64:
                    files.append(path)
            except OSError:
                continue
            if len(files) >= limit:
                break
        if len(files) >= limit:
            break
    files.sort(key=lambda path: (0 if path.endswith(("/BreadBoard", "/launchd", "/dyld")) else 1, path))
    if not files:
        return 0
    subprocess.run([tool, "create", "-v", "1", "-o", output, files[0]], check=False)
    for start in range(1, len(files), 40):
        subprocess.run([tool, "append", "-u", "0", output, *files[start:start + 40]], check=False)
    blob = Path(output).read_bytes() if Path(output).is_file() else b""
    return count_v1_entries(blob) or 0


# A BreadBoard+launchd+dyld stub is not an installed system. Boot only a
# tree large enough to be the payload root, and only when it fits the
# ramdisk slot. qemu-sptm still has no NAND block device.
MIN_BOOT_FILES = 1000
RAMDISK_SLOT_BYTES = 6 * 1024 * 1024 * 1024


def write_boot_manifest(image, trustcache, output, firmware_dir, extracted_files=0):
    image = Path(image)
    trustcache = Path(trustcache)
    size = image.stat().st_size if image.is_file() else 0
    entries = count_v1_entries(trustcache.read_bytes()) if trustcache.is_file() else None
    try:
        extracted_files = int(extracted_files)
    except (TypeError, ValueError):
        extracted_files = 0
    fits = bool(size and entries and size <= RAMDISK_SLOT_BYTES and extracted_files >= MIN_BOOT_FILES)
    manifest = {
        "boot_payload_root": fits,
        "trustcache_generated": bool(entries),
        "trustcache_entries": entries or 0,
        "trustcache_from_ota": False,
        "trustcache_is_restore_ramdisk": False,
        "springboard_file_present": False,
        "breadboard_extracted": True,
        "extracted_file_count": extracted_files,
        "partial_payload_root": extracted_files < MIN_BOOT_FILES,
        "image_bytes": size,
        "image_exceeds_ramdisk_slot": size > RAMDISK_SLOT_BYTES,
        "fits_qemu_ramdisk_slot": fits,
        "guest_ram": "12G",
        "root_slot": "qemu-sptm ramdisk holding the extracted payload root",
        "nand_block_device_present": False,
        "bridge": "darwin machine has no ANS disk; the payload root is the ramdisk file",
        "springboard_boot_proven": False,
    }
    text = json.dumps(manifest, indent=2) + "\n"
    Path(output).write_text(text)
    firmware = Path(firmware_dir)
    if fits:
        (firmware / "system-volume-manifest.json").write_text(text)
    elif image.is_file():
        image.unlink()
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--trustcache", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--build-root")
    parser.add_argument("--tool")
    parser.add_argument("--image")
    parser.add_argument("--firmware-dir")
    parser.add_argument("--extracted-files", type=int, default=0)
    args = parser.parse_args()
    if args.build_root and args.tool:
        build_with_tool(args.build_root, args.tool, args.trustcache)
    path = Path(args.trustcache)
    blob = path.read_bytes() if path.is_file() else b""
    count = count_v1_entries(blob)
    report = {
        "bytes": len(blob),
        "version_1_entry_count": count,
        "usable": bool(count),
        "generated_by": "external trustcache create -v 1",
        "amfi_acceptance_proven": False,
    }
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"entries": count, "bytes": len(blob)}))
    if args.image and args.firmware_dir:
        manifest = write_boot_manifest(
            args.image, args.trustcache, args.output + ".manifest-unused",
            args.firmware_dir, args.extracted_files)
        # The count report stays at --output. The boot manifest is the firmware copy plus out/.
        Path(args.output).with_name("homeview-system-volume-manifest.json").write_text(
            Path(args.firmware_dir, "system-volume-manifest.json").read_text()
            if manifest["boot_payload_root"]
            else json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
