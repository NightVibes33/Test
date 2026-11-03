#!/usr/bin/env python3
"""Make uniquely identifiable 12-instruction fingerprints from original Apple code.

First eight instructions of AppleANS2CGv2Controller and AppleANS3CGv2Controller
slot 85 are byte-identical. No 8-instruction fingerprint may attribute them.
48-byte fingerprints require 12 contiguous 4-byte original ARM64 instructions.
A match at guest runtime can locate slid code without patching firmware.
"""
from collections import Counter
import re

CODE = re.compile(r"^\s*(0x[0-9a-fA-F]{8,16}):\s+((?:[0-9a-fA-F]{2}\s+){4})")
WORDS = 12
MAX_SIGNATURES = 8


def from_disassembly(report):
    sigs = []
    for item in report.get("targets", []):
        if not item.get("requested_vaddr_is_first_instruction"):
            continue
        address = item.get("address")
        if not isinstance(address, str) or not address.startswith("0x"):
            continue
        lines = item.get("assembly_excerpt", [])
        if not isinstance(lines, list):
            continue
        expected = int(address, 16)
        instruction_bytes = []
        for line in lines[:WORDS]:
            if not isinstance(line, str):
                break
            match = CODE.match(line)
            if not match or int(match.group(1), 16) != expected:
                break
            instruction_bytes.extend(bytes.fromhex(match.group(2)))
            expected += 4
        if len(instruction_bytes) != WORDS * 4:
            continue
        sigs.append({"static_vaddr": address.lower(),
                     "signature_hex": bytes(instruction_bytes).hex(),
                     "class": item.get("class"),
                     "slot": item.get("vtable_slot"),
                     "signature_static_only_not_guest_execution": True})
    counts = Counter(s["signature_hex"] for s in sigs)
    result = [s for s in sigs if counts[s["signature_hex"]] == 1]
    return result[:MAX_SIGNATURES]


def plugin_args(report):
    args = []
    for item in from_disassembly(report):
        args.append(f"sig={item['static_vaddr']}:{item['signature_hex']}")
        klass = item.get("class") or ""
        slot = item.get("slot")
        if isinstance(klass, str) and klass.isidentifier() and isinstance(slot, int):
            args.append(f"who={item['static_vaddr']}:{klass}:{slot}")
    return args
