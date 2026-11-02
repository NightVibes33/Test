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

# Public Asahi/Linux apple.c and Linux Apple ASC mailbox.c reference offsets.
# Register interpretation is a RESEARCH HYPOTHESIS for HomeView J490.
ANS_REGISTER_REFERENCES = {
    0x44: "coproc_cpu_control", 0x110: "asc_a2i_control",
    0x114: "asc_i2a_control", 0x800: "asc_a2i_send0",
    0x820: "asc_i2a_send0", 0x1004: "ans_admin_cq_doorbell",
    0x100c: "ans_io_cq_doorbell", 0x1300: "ans_boot_status",
    0x24908: "ans_linear_sq_control", 0x2490c: "ans_linear_admin_sq_db",
    0x24910: "ans_linear_io_sq_db", 0x28100: "ans_nvmmu_num_tcbs",
    0x28108: "ans_nvmmu_admin_tcb_base", 0x28110: "ans_nvmmu_io_tcb_base",
    0x28118: "ans_nvmmu_tcb_invalidate", 0x28120: "ans_nvmmu_tcb_status",
}

def expected_lengths(name, index, original_length):
    normal = min(original_length, 0x4000)
    if name == "arm-io/ans" and index == 0:
        # The full-window mode remains opt-in and differs from paired controls.
        return {normal, min(original_length, 0x100000)}
    return {normal}


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
        allowed_lengths = expected_lengths(name, index, int(win["length"], 0))
        if int(base, 16) != expected_base or int(length, 16) not in allowed_lengths:
            raise ValueError("QEMU MMIO window disagrees with Apple J490 ADT: " + name)
        if (name, index) in seen:
            raise ValueError("Duplicate MMIO trace mapping for " + name)
        seen.add((name, index))
        actual_length = int(length, 16)
        evidence.append({"node": name, "window_index": index,
                         "base": hex(expected_base), "length": hex(actual_length),
                         "mapping_matches_Apple_ADT": True,
                         "linux_ANS_reference_offsets_in_range": (
                             {name: hex(offset) for offset, name in ANS_REGISTER_REFERENCES.items()
                              if offset < actual_length}
                             if name == "arm-io/ans" and index == 0 else {})})
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
        if start != int(win["guest_physical_base"], 0) or size not in expected_lengths(
                name, index, int(win["length"], 0)):
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
        address = int(offset, 16)
        accesses.append({"mode": mode, "node": name, "window_index": index,
                         "offset": hex(address), "size": int(size),
                         "linux_register_reference": (
                             ANS_REGISTER_REFERENCES.get(address)
                             if name == "arm-io/ans" and index == 0 else None)})
    return {"registered_regions": evidence,
            "registered_region_count": len(evidence),
            "skipped_overlap_windows": skipped,
            "access_count": len(accesses),
            "access_sample": accesses[:96],
            "full_primary_ANS_window_installed": any(
                e["node"] == "arm-io/ans" and e["window_index"] == 0
                and int(e["length"], 0) > 0x4000 for e in evidence),
            "Apple_ANS_device_protocol_verified": False,
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
