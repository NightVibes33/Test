#!/usr/bin/env python3
"""Identify storage/display driver STRING EVIDENCE in original Apple kernelcache.

An absent string does NOT prove the driver/extension is absent. Kernelcache
sections may be encoded, stripped, compressed or dynamically loaded.
No Apple kernelcache bytes are included in the uploaded report.
"""
import argparse
import hashlib
import json
import mmap
from pathlib import Path

NEEDLES = {
    "AppleANS": b"AppleANS",
    "AppleANS2": b"AppleANS2",
    "AppleANS3": b"AppleANS3",
    "AppleNVMe": b"AppleNVMe",
    "AppleNAND": b"AppleNAND",
    "IONVMe": b"IONVMe",
    "AppleStorage": b"AppleStorage",
    "AppleDCP": b"AppleDCP",
    "AppleDisplay": b"AppleDisplay",
    "AppleSART": b"AppleSART",
    "RTBuddy": b"RTBuddy",
    "AppleRTKit": b"AppleRTKit",
    "IOGPU": b"IOGPU",
    "AppleARM": b"AppleARM",
    "AppleSEP": b"AppleSEP",
}
MAX_MATCH_SAMPLE = 12


def scan_bytes(data):
    """Byte-exact strings only. Substrings may be class names, not kext IDs."""
    result = {}
    for label, term in NEEDLES.items():
        found = []
        offset = 0
        count = 0
        while True:
            index = data.find(term, offset)
            if index < 0:
                break
            count += 1
            if len(found) < MAX_MATCH_SAMPLE:
                found.append(hex(index))
            offset = index + len(term)
        result[label] = {
            "literal_bytes_found": count > 0, "match_count": count,
            "sample_file_offsets": found,
            "kext_driver_present_or_loaded_proven": False,
        }
    return result


def scan_file(path):
    image = Path(path)
    if not image.is_file() or image.stat().st_size < 4096:
        raise ValueError("Original Apple kernelcache input missing or too small")
    digest = hashlib.sha256()
    with image.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    with image.open("rb") as stream:
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as mem:
            result = scan_bytes(mem)
            magic = mem[:4].hex()
    return {
        "source": "original Apple HomeView 24V514 decrypted kernelcache.release.homeaccessory17",
        "image_byte_length": image.stat().st_size,
        "sha256": digest.hexdigest(),
        "first_four_bytes_hex": magic,
        "MachO_magic_detected": magic in ("cffaedfe", "feedfacf"),
        "literal_class_symbol_markers": result,
        "AppleANS_kernel_driver_running_in_guest_verified": False,
        "AppleDCP_display_driver_running_in_guest_verified": False,
        "runtime_kext_loading_proven": False,
        "missing_string_proves_missing_kext": False,
        "note": ("Raw literal strings are not linked symbols or executable "
                 "kext verification; negative results cannot establish absence.")
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--kernelcache", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    data = scan_file(a.kernelcache)
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"image_bytes": data["image_byte_length"],
                      "sha256": data["sha256"],
                      "markers": {name: d["match_count"] for name, d
                                  in data["literal_class_symbol_markers"].items()}}))


if __name__ == "__main__":
    main()
