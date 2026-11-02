#!/usr/bin/env python3
"""Compare exact direct BL calls in original HomeView J490 vtable disassemblies.

No names are invented for branch destinations. These are static code
references, NOT runtime instruction hits or evidence of RTKit/NAND success.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

INSTRUCTION = re.compile(r"^\s*(0x[0-9a-fA-F]{8,16}):")
DIRECT_CALL = re.compile(r"\bbl\s+(0x[0-9a-fA-F]{8,16})(?:\s|$)")
INDIRECT_CALL = re.compile(r"\bblr(?:a[ab]|b[ab])?\s+")


def extract_calls(target):
    if not target.get("requested_vaddr_is_first_instruction"):
        return {"verified_entry": False, "direct_calls": [],
                "indirect_call_count": 0}
    lines = target.get("assembly_excerpt", [])
    if not isinstance(lines, list):
        raise ValueError("Disassembly excerpt is not a list")
    calls = []
    indirect = 0
    for line in lines[:96]:
        if not isinstance(line, str):
            continue
        loc = INSTRUCTION.search(line)
        if not loc:
            continue
        direct = DIRECT_CALL.search(line)
        if direct:
            calls.append({"site": loc.group(1).lower(),
                          "target": direct.group(1).lower()})
        if INDIRECT_CALL.search(line):
            indirect += 1
    return {"verified_entry": True, "direct_calls": calls,
            "indirect_call_count": indirect,
            "sample_may_omit_later_calls": bool(target.get(
                "assembly_excerpt_truncated", True))}


def analyze(data):
    targets = data.get("targets", [])
    if not isinstance(targets, list):
        raise ValueError("Expected original firmware disassembly records")
    records = []
    destinations = defaultdict(lambda: {"classes": set(), "call_sites": []})
    for item in targets[:64]:
        klass = item.get("class")
        slot = item.get("vtable_slot")
        if not isinstance(klass, str) or type(slot) is not int:
            continue
        parsed = extract_calls(item)
        records.append({"class": klass, "vtable_slot": slot,
                        "original_entrypoint": item.get("address"),
                        **parsed})
        for call in parsed["direct_calls"]:
            entry = destinations[call["target"]]
            entry["classes"].add(klass)
            entry["call_sites"].append({"class": klass, "slot": slot,
                                        "site": call["site"]})
    shared = sorted(
        ({"destination": addr,
          "distinct_calling_classes": sorted(v["classes"]),
          "call_sites": v["call_sites"][:20],
          "function_semantics_proven": False}
         for addr, v in destinations.items()
         if len(v["classes"]) >= 2),
        key=lambda r: (-len(r["distinct_calling_classes"]), r["destination"]))
    return {
        "source": "Original Apple 24V514 J490 exact kernelcache disassembly",
        "analysis": "bounded direct ARM64 BL call sites and cross-class overlap",
        "analyzed_original_vtable_entries": records,
        "shared_direct_call_targets": shared,
        "static_branches_are_not_proof_of_runtime_execution": True,
        "target_name_or_purpose_inferred": False,
        "ANS2_controller_successful_start_proven": False,
        "RTBuddy_firmware_handshake_proven": False,
        "note": ("Direct BL shows potential code relationships within an "
                 "original method excerpt only. It does not establish runtime "
                 "dispatch, callee semantics or Apple storage availability."),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--disassembly", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    result = analyze(json.loads(Path(a.disassembly).read_text()))
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"verified_entries": sum(
        r["verified_entry"] for r in result["analyzed_original_vtable_entries"]),
        "shared_call_targets": len(result["shared_direct_call_targets"])}))


if __name__ == "__main__":
    main()
