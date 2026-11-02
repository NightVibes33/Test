#!/usr/bin/env python3
"""Bounded original HomeView kernelcache C++ inspection using blacktop ipsw.

Class and method text from a decrypted original Apple Mach-O is useful for
reverse engineering. It DOES NOT prove that the corresponding kext matched
or any driver method executed inside the QEMU guest.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

CLASSES = (
    "AppleASCWrapV6",
    "AppleA7IOPNub",
    "RTBuddy",
    "RTBuddyService",
    "AppleANS2NVMeController",
    "AppleANS2CGNVMeController",
    "AppleANS2CGv2Controller",
    "AppleANS2DARTNVMeController",
    "AppleANS3NVMeController",
    "AppleANS3CGv2Controller",
    "IOCoastGuardSARTMapper",
    "AppleDCPExpert",
)
MAX_LINES = 110
MAX_LINE_LENGTH = 260
TIMEOUT = 70
ADDR = re.compile(r"0x[0-9a-fA-F]{8,16}")
SLOT = re.compile(r"^\[\s*(\d+)\]\s+\+0x([0-9a-fA-F]+).*?\s+->\s+(0x[0-9a-fA-F]+)\b")
MAX_VTABLE_ROWS = 1500
MAX_CLASS_SPECIFIC_SLOTS = 60


def normalize_text(output, class_name=None):
    raw = output.decode("utf-8", "replace") if isinstance(output, bytes) else str(output)
    lines = raw.splitlines()
    filtered = []
    addresses = []
    for line in lines[:MAX_LINES]:
        clean = re.sub(r"\x1b\[[0-9;]*m", "", line).strip()
        if not clean:
            continue
        filtered.append(clean[:MAX_LINE_LENGTH])
        for match in ADDR.finditer(clean):
            if len(addresses) < 24 and match.group() not in addresses:
                addresses.append(match.group())
    # Vtables often contain 350+ slots. Preserve class-specific entries
    # from the WHOLE listing, not just the inherited first 110 lines.
    own = []
    for line in lines[:MAX_VTABLE_ROWS]:
        clean = re.sub(r"\x1b\[[0-9;]*m", "", line).strip()
        match = SLOT.match(clean)
        if match is None or not class_name or class_name + "::" not in clean:
            continue
        method = clean.rsplit(class_name + "::", 1)[-1].split("(", 1)[0].split()[0]
        own.append({
            "slot": int(match.group(1)),
            "vtable_offset": "0x" + match.group(2).lower(),
            "target": match.group(3).lower(),
            "printed_method": method[:96],
            "disassembled_method_or_runtime_call_verified": False,
        })
    tail = own[-20:] if len(own) > MAX_CLASS_SPECIFIC_SLOTS else []
    sample = (own[:MAX_CLASS_SPECIFIC_SLOTS - len(tail)] + tail)
    return {
        "sample_lines": filtered,
        "addresses_observed": addresses,
        "total_lines": len(lines),
        "output_truncated": len(lines) > MAX_LINES,
        "class_defined_vtable_slots_observed": len(own),
        "class_defined_vtable_slot_sample": sample,
        "class_defined_method_scan_truncated": len(lines) > MAX_VTABLE_ROWS,
        "class_specific_vtable_entries_are_not_start_invocations": True,
    }


def inspect(kernelcache, exe="ipsw", runner=subprocess.run):
    kernelcache = Path(kernelcache)
    if not kernelcache.is_file() or kernelcache.stat().st_size < 4096:
        raise ValueError("Original decrypted kernelcache unavailable")
    results = {}
    for klass in CLASSES:
        args = [exe, "kernel", "cpp", str(kernelcache), "--class", klass,
                "--methods"]
        try:
            completed = runner(args, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               timeout=TIMEOUT, check=False)
            evidence = normalize_text(completed.stdout, klass)
            evidence.update({
                "exit_code": completed.returncode,
                "inspection_completed": completed.returncode == 0,
                "actual_guest_class_or_method_called_proven": False,
            })
        except (subprocess.TimeoutExpired, OSError) as exc:
            evidence = {"inspection_completed": False,
                        "error": type(exc).__name__,
                        "actual_guest_class_or_method_called_proven": False}
        results[klass] = evidence
    return {
        "source": "original Apple HomeView 24V514 kernelcache.release.homeaccessory17",
        "method": "ipsw kernel cpp --class NAME --methods",
        "original_kernelcache_binary_included": False,
        "requested_class_count": len(CLASSES),
        "class_inspection": results,
        "vtable_method_addresses_are_not_proven_guest_calls": True,
        "ANS2_RTKit_or_NVMe_service_started": False,
        "note": "Class/vtable strings describe kernelcache contents, not live IORegistry or QEMU boot events."
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--kernelcache", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    result = inspect(a.kernelcache)
    dest = Path(a.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({name: rec["inspection_completed"]
                      for name, rec in result["class_inspection"].items()}))


if __name__ == "__main__":
    main()
