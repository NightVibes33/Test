#!/usr/bin/env python3
"""Check that opt-in QEMU MMIO regions match the original J490 ADT.

A matching map proves the virtual trace address is correct, not that a real
Apple ANS/DCP/SART controller is implemented or any driver has matched.
"""
import argparse
import glob
import json
from pathlib import Path
import re

INSTALL = re.compile(
    r"HOMEVIEW_MMIO_TRACE installed (arm-io/[a-z0-9_-]+) "
    r"base=0x([0-9a-fA-F]+) length=0x([0-9a-fA-F]+)(?: index=(\d+))?")
SKIP = re.compile(
    r"HOMEVIEW_MMIO_TRACE skipped_overlap (arm-io/[a-z0-9_-]+) "
    r"base=0x([0-9a-fA-F]+) length=0x([0-9a-fA-F]+) index=(\d+)")
ACCESS = re.compile(
    r"HOMEVIEW_MMIO_TRACE (read|write) (arm-io/[a-z0-9_-]+) "
    r"off=0x([0-9a-fA-F]+).*?size=(\d+)(?: index=(\d+))?")


def check(contract, trace):
    evidence, skipped, seen = [], [], set()
    for m in INSTALL.finditer(trace):
        name, base, length, idx = m.groups()
        index = int(idx or 0)
        windows = contract.get("nodes", {}).get(name, {}).get("reg_windows", [])
        if not 0 <= index < len(windows):
            raise ValueError("Installed MMIO index absent from Apple ADT: " + name)
        win = windows[index]
        expected_base = int(win["guest_physical_base"], 0)
        expected_length = min(int(win["length"], 0), 0x4000)
        if (int(base, 16), int(length, 16)) != (expected_base, expected_length):
            raise ValueError("QEMU MMIO window disagrees with Apple J490 ADT: " + name)
        if (name, index) in seen:
            raise ValueError("Duplicate MMIO trace mapping for " + name)
        seen.add((name, index))
        evidence.append({"node": name, "window_index": index,
                         "base": hex(expected_base), "length": hex(expected_length),
                         "mapping_matches_Apple_ADT": True})
    mapped = [(int(d["base"], 0), int(d["base"], 0) + int(d["length"], 0))
              for d in evidence]
    for m in SKIP.finditer(trace):
        name, base, length, idx = m.groups()
        index = int(idx)
        windows = contract.get("nodes", {}).get(name, {}).get("reg_windows", [])
        if not 0 <= index < len(windows):
            raise ValueError("Skipped MMIO index absent from Apple ADT: " + name)
        win = windows[index]
        start, size = int(base, 16), int(length, 16)
        if start != int(win["guest_physical_base"], 0) or size != min(
                int(win["length"], 0), 0x4000):
            raise ValueError("Skipped MMIO window disagrees with Apple ADT")
        if not any(start < end and begin < start + size for begin, end in mapped):
            raise ValueError("Skipped overlap not demonstrated by registered regions")
        skipped.append({"node": name, "window_index": index, "base": hex(start)})
    accesses = []
    for m in ACCESS.finditer(trace):
        mode, name, offset, size, idx = m.groups()
        index = int(idx or 0)
        if (name, index) not in seen:
            raise ValueError("MMIO access recorded for unregistered region: " + name)
        length = next(int(d["length"], 0) for d in evidence
                      if d["node"] == name and d["window_index"] == index)
        if int(offset, 16) + int(size) > length:
            raise ValueError("MMIO register access exceeds mapped window")
        accesses.append({"mode": mode, "node": name, "window_index": index,
                         "offset": hex(int(offset, 16)), "size": int(size)})
    return {"registered_regions": evidence,
            "registered_region_count": len(evidence),
            "skipped_overlap_windows": skipped,
            "access_count": len(accesses),
            "access_sample": accesses[:96],
            "all_observed_mappings_match_original_Apple_ADT": True,
            "zero_return_stubs_can_change_guest_behavior": True,
            "no_access_does_not_prove_no_driver_match": True,
            "ANS_NAND_or_display_controller_implemented": False}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--contract", required=True)
    p.add_argument("--qemu-logs", nargs="+", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    contract = json.loads(Path(a.contract).read_text())
    files = []
    for pattern in a.qemu_logs:
        files += glob.glob(pattern)
    result = {"source": contract["source"], "logs": {},
              "kernel_MMIO_accesses_are_not_service_activation": True}
    for file in sorted(set(files)):
        result["logs"][Path(file).name] = check(
            contract, Path(file).read_text(errors="replace"))
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"logs": len(result["logs"]), "registered": sum(
        v["registered_region_count"] for v in result["logs"].values()),
        "accesses": sum(v["access_count"] for v in result["logs"].values())}))


if __name__ == "__main__":
    main()
