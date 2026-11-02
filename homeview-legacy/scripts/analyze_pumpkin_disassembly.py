#!/usr/bin/env python3
"""Conservatively summarize original iOS 27.2 MobileGestalt ARM64 disassembly.

This identifies instructions, not the getter's backing source. An indirect
call or nearby string never proves a DeviceTree/NVRAM or product-type read.
"""
import argparse
import json
import pathlib
import re

ANSI = re.compile(r"\x1b\[[0-9;]*m")
INSTRUCTION = re.compile(
    r"^\s*(0x[0-9a-fA-F]{8,16}):\s+(?:(?:[0-9a-fA-F]{2}\s+){4})?"
    r"([a-z][a-z0-9._]*)\b\s*(.*)$", re.I)
SOURCE_SYMBOLS = {
    "IORegistry": ("IORegistryEntry", "IOServiceGetMatching", "IORegistryGet"),
    "NVRAM": ("IODTNVRAM", "IONVRAM", "PEGetNVRAM", "nvram_get"),
    "sysctl": ("sysctl",),
    "MobileGestalt_cache": ("MGCopyAnswer", "MobileGestaltCache", "MGCache"),
    "DeviceTree": ("IODeviceTree", "dt_get_prop"),
    "PlatformExpert": ("PEGet", "PlatformExpert"),
    "entitlement": ("SecTaskCopyValueForEntitlement", "audit_token_to_entitlement"),
}

def analyze(text):
    clean = ANSI.sub("", text)
    instructions = []
    for line in clean.splitlines():
        match = INSTRUCTION.match(line)
        if match:
            instructions.append({
                "address": match.group(1).lower(),
                "opcode": match.group(2).lower(),
                "operand": match.group(3).strip(),
                "text": line.strip()[:350],
            })
    calls = [inst for inst in instructions
             if inst["opcode"] in ("bl", "blr", "blraaz", "blrabz", "blraa", "blrab")]
    direct = [c for c in calls if c["opcode"] == "bl"]
    indirect = [c for c in calls if c["opcode"] != "bl"]
    source_hints = []
    for call in direct:
        for source, symbols in SOURCE_SYMBOLS.items():
            if any(symbol.lower() in call["operand"].lower() for symbol in symbols):
                source_hints.append({
                    "source": source,
                    "instruction": call["text"],
                    "evidence": "named direct call; data flow not yet traced",
                })
    # A cache lookup may use indirect calls; no matching name proves nothing.
    valid = len(instructions) >= 4 and not re.search(
        r"(?im)^\s*(?:error:|unknown flag:|usage: ipsw dyld disass)", clean)
    return {
        "target": "_MobileGestalt_get_pumpkinMode",
        "source_build": "iOS 27.2 beta 4 (24B5110a)",
        "instruction_level_disassembly_present": valid,
        "instruction_count": len(instructions),
        "direct_call_count": len(direct),
        "indirect_call_count": len(indirect),
        "return_instruction_count": sum(
            inst["opcode"] in ("ret", "retaa", "retab") for inst in instructions),
        "direct_calls": direct[:100],
        "indirect_calls": indirect[:40],
        "symbol_named_source_hints": source_hints[:40],
        "backing_source_verified": False,
        "actual_pumpkinmode_return_verified": False,
        "experimental_chosen_property_used_by_apple": None,
        "note": "Resolve targets, dataflow and actual getter callers in original Mach-O before asserting a source.",
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("disassembly")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    result = analyze(pathlib.Path(args.disassembly).read_text(errors="replace"))
    out = pathlib.Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in (
        "instruction_level_disassembly_present", "instruction_count",
        "direct_call_count", "indirect_call_count", "symbol_named_source_hints")}))
    if not result["instruction_level_disassembly_present"]:
        raise SystemExit("No verifiable ARM64 instruction stream: getter unresolved")

if __name__ == "__main__":
    main()
