#!/usr/bin/env python3
"""Disassemble *original* HomeView J490 C++ vtable entry points at exact VAs.

These are sample vtable targets, not independently identified start() methods.
The tool does not execute firmware or claim an instantiated IOService.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

# Selected from genuine 24V514 kernelcache class-specific slots, not fabricated
# offsets. Match them to the new listing on each run before disassembling.
TARGETS = {
    "AppleANS3CGv2Controller": ("com.apple.iokit.IONVMeFamily", (85, 260, 352)),
    "AppleANS2CGv2Controller": ("com.apple.iokit.IONVMeFamily", (85, 260)),
    "RTBuddy": ("com.apple.driver.RTBuddy", (86, 181)),
    "AppleASCWrapV6": ("com.apple.driver.AppleA7IOP-ASCWrap-v6", (181,)),
}
MAX_BYTES = 128000
MAX_INSTRUCTIONS = 48
VA = re.compile(r"^0x[0-9a-f]{8,16}$")
LINE = re.compile(r"(?:0x)?([0-9a-f]{8,16}):\s", re.I)


def select_targets(classes):
    data = classes.get("class_inspection", {})
    selected = []
    for klass, (bundle, slots) in TARGETS.items():
        listing = data.get(klass, {})
        if not listing.get("inspection_completed"):
            continue
        available = {
            item["slot"]: item for item in
            listing.get("class_defined_vtable_slot_sample", [])
            if isinstance(item, dict) and type(item.get("slot")) is int
        }
        for slot in slots:
            item = available.get(slot)
            if not item:
                continue
            address = item.get("target")
            if not isinstance(address, str) or not VA.fullmatch(address):
                continue
            selected.append({
                "class": klass, "fileset_entry": bundle,
                "vtable_slot": slot, "vtable_offset": item["vtable_offset"],
                "address": address,
                "original_vtable_entry_confirmed": True,
            })
    return selected


def normalize(raw):
    text = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
    return [line[:280] for line in text.splitlines()[:MAX_INSTRUCTIONS+16]
            if line.strip()][:MAX_INSTRUCTIONS+10]


def analyze(classes, kernelcache, runner=subprocess.run):
    image = Path(kernelcache)
    if not image.is_file() or image.stat().st_size < 4096:
        raise ValueError("Original decrypted Apple kernelcache unavailable")
    reports = []
    for target in select_targets(classes):
        args = ["ipsw", "macho", "disass", str(image),
                "--fileset-entry", target["fileset_entry"],
                "--vaddr", target["address"], "--count", str(MAX_INSTRUCTIONS),
                "--quiet", "--no-color"]
        try:
            out = runner(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         stdin=subprocess.DEVNULL, timeout=45, check=False)
            content = out.stdout[:MAX_BYTES]
            lines = normalize(content)
            first = next((int(m.group(1), 16) for line in lines
                          if (m := LINE.search(line))), None)
            result = {
                **target, "exit_code": out.returncode,
                "disassembly_first_address": hex(first) if first else None,
                "requested_vaddr_is_first_instruction": first == int(target["address"], 16),
                "assembly_excerpt": lines,
                "binary_or_executable_embedded": False,
                "runtime_method_invocation_proven": False,
            }
        except (subprocess.TimeoutExpired, OSError) as exc:
            result = {**target, "error": type(exc).__name__,
                      "requested_vaddr_is_first_instruction": False,
                      "runtime_method_invocation_proven": False}
        reports.append(result)
    return {
        "source": "Original Apple HomeView 27.2 24V514 J490 kernelcache",
        "method": "ipsw macho disass --fileset-entry --vaddr --count 48",
        "selected_vtable_target_count": len(reports),
        "targets": reports,
        "kernelcache_executable_in_report": False,
        "Apple_ANS_NVMe_controller_start_confirmed": False,
        "RTKit_ASC_mailbox_protocol_implemented": False,
        "note": ("Vtable targets and disassembly are static original-firmware "
                 "evidence. They cannot prove a particular start() method "
                 "ran, that a controller was chosen, or that NAND is online."),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernelcache", required=True)
    ap.add_argument("--classes", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    class_file = Path(a.classes)
    if not class_file.is_file():
        raise SystemExit("Class vtable evidence unavailable")
    result = analyze(json.loads(class_file.read_text()), a.kernelcache)
    dest = Path(a.output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "selected": result["selected_vtable_target_count"],
        "confirmed_disassembly_entries": sum(
            x["requested_vaddr_is_first_instruction"] for x in result["targets"])
    }))


if __name__ == "__main__":
    main()
