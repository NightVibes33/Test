#!/usr/bin/env python3
"""Conservative side-by-side Apple HomeView QEMU Pumpkin experiment report.

Observations of identical restore stalls do not establish MobileGestalt
behavior; only explicit guest log lines count as API values. MMIO logging
reveals access attempts, not a working ANS, DCP, NAND or framebuffer.
"""
import argparse
import glob
import json
from pathlib import Path
import re

CONTROL = "software-update-dock-removed-control"
PUMPKIN = "software-update-dock-removed-pumpkin"
ANS_PROBE = "software-update-ans-binding-probe"
TRACE = re.compile(
    r"HOMEVIEW_MMIO_TRACE\s+(read|write)\s+(arm-io/[\w-]+)\s+off=0x([0-9a-fA-F]+)"
    r"(?:\s+value=0x([0-9a-fA-F]+))?\s+size=(\d+)")
INSTALL = re.compile(r"HOMEVIEW_MMIO_TRACE installed (arm-io/[\w-]+)")


def mmio_summary(log_text):
    devices = {}
    for match in INSTALL.finditer(log_text):
        devices.setdefault(match.group(1), {
            "installed": True, "reads": 0, "writes": 0,
            "offsets": [], "write_values_sample": []})
    for m in TRACE.finditer(log_text):
        kind, dev, offset, value, size = m.groups()
        entry = devices.setdefault(dev, {
            "installed": False, "reads": 0, "writes": 0,
            "offsets": [], "write_values_sample": []})
        entry["reads" if kind == "read" else "writes"] += 1
        formatted = "0x" + offset.lower()
        if formatted not in entry["offsets"] and len(entry["offsets"]) < 96:
            entry["offsets"].append(formatted)
        if kind == "write" and len(entry["write_values_sample"]) < 24:
            entry["write_values_sample"].append(
                {"offset": formatted, "value": "0x" + value.lower() if value else None,
                 "size": int(size)})
    return {"devices": devices, "accesses_observed": sum(
        v["reads"] + v["writes"] for v in devices.values()),
        "real_hardware_functionality_verified": False}


def compare_ans_probe(boot, observations, ans_adt, qemu_logs=None):
    qemu_logs = qemu_logs or {}
    attempts = {a.get("variant"): a for a in boot.get("attempts", [])}
    records = observations.get("results", {})
    compare = {}
    for name in (CONTROL, ANS_PROBE):
        a = attempts.get(name)
        o = records.get("native-homeview-" + name + "-serial.log")
        trace = mmio_summary(qemu_logs.get("qemu-" + name + ".log", ""))
        compare[name] = {
            "observed_variant": a is not None and o is not None,
            "boot_stage": a.get("stage") if a else None,
            "first_panic": a.get("first_kernel_panic") if a else None,
            "nand_wait_count": a.get("nand_service_wait_count") if a else None,
            "framebuffer_error_count": a.get("framebuffer_missing_count") if a else None,
            "apple_guest_mmio_trace": trace,
            "ANS_mmio_register_accesses": sum(
                trace["devices"].get(k, {}).get("reads", 0)
                + trace["devices"].get(k, {}).get("writes", 0)
                for k in ("arm-io/ans", "arm-io/sart-ans")),
            "MG_value_observed": bool(o and o.get("mg_pumpkinmode_return_evidence")),
        }
    paired = all(compare[name]["observed_variant"] for name in (CONTROL, ANS_PROBE))
    raw_verified = (ans_adt.get("original_apple_compatible_values_preserved") is True
                    and ans_adt.get("all_other_ADT_fields_unchanged") is True)
    c, p = compare[CONTROL], compare[ANS_PROBE]
    return {
        "experiment": "J490 native-ANS-original-compatibility-driver-probe",
        "control_and_probe_serial_observed": paired,
        "original_compatible_only_change_verified": raw_verified,
        "variants": compare,
        "ANS_mmio_delta": (p["ANS_mmio_register_accesses"] -
                            c["ANS_mmio_register_accesses"]) if paired else None,
        "new_mmio_access_detected": (
            p["ANS_mmio_register_accesses"] > c["ANS_mmio_register_accesses"]
            if paired else None),
        "boot_stage_changed": (p["boot_stage"] != c["boot_stage"]) if paired else None,
        "result": ("not_evaluable_unverified_ADT" if not raw_verified else
                   "not_evaluable_missing_boot_records" if not paired else
                   "additional_ANS_register_accesses_observed"
                       if p["ANS_mmio_register_accesses"] > c["ANS_mmio_register_accesses"]
                   else "no_additional_ANS_register_accesses_observed"),
        "Apple_ANS_driver_binding_proven": False,
        "Apple_ANS_storage_service_implemented": False,
        "persistent_APFS_or_NAND_present": False,
        "note": ("A register access is useful driver-probe evidence, not proof "
                 "of a functional ANS controller. A lack of reads is not "
                 "proof a driver never attempted to match.")
    }


def compare(boot, observations, adt, qemu_logs=None):
    qemu_logs = qemu_logs or {}
    attempts = {a.get("variant"): a for a in boot.get("attempts", [])}
    log_observations = observations.get("results", {})
    pair = {}
    for name in (CONTROL, PUMPKIN):
        serial = "native-homeview-" + name + "-serial.log"
        qemu_name = "qemu-" + name + ".log"
        a = attempts.get(name)
        o = log_observations.get(serial)
        pair[name] = {
            "attempt_record_present": a is not None,
            "guest_serial_observed": o is not None,
            "boot_stage": a.get("stage") if a else None,
            "restore_userspace": a.get("apple_restore_userspace_started") if a else None,
            "nand_waits": a.get("nand_service_wait_count") if a else None,
            "framebuffer_failures": a.get("framebuffer_missing_count") if a else None,
            "first_panic": a.get("first_kernel_panic") if a else None,
            "guest_MG_query_logged": o.get("mg_pumpkinmode_query_observed") if o else None,
            "guest_MG_return": (o.get("mg_pumpkinmode_returned")
                                if o and o.get("mg_pumpkinmode_return_evidence") else None),
            "MG_return_evidence": o.get("mg_pumpkinmode_return_evidence") if o else False,
            "Apple_shell_start_logged": o.get("selected_homeview_shell") if o else None,
            "mmio": mmio_summary(qemu_logs.get(qemu_name, "")),
        }
    paired = all(pair[name]["attempt_record_present"]
                 and pair[name]["guest_serial_observed"] for name in (CONTROL, PUMPKIN))
    isolated = (adt.get("exactly_one_property_added") is True
                and adt.get("all_other_nodes_and_properties_identical") is True
                and adt.get("property") == "/chosen/PumpkinMode")
    c, p = pair[CONTROL], pair[PUMPKIN]
    both_values = paired and c["MG_return_evidence"] and p["MG_return_evidence"]
    return {
        "source_guest": "Apple HomeView 27.2 (24V514) / HomeAccessory17,1",
        "matched_apple_adt_diff_confirmed": isolated,
        "paired_boot_observed": paired,
        "variants": pair,
        "boot_stage_changed": (c["boot_stage"] != p["boot_stage"]) if paired else None,
        "nand_wait_delta_experimental_minus_control": (
            p["nand_waits"] - c["nand_waits"]
            if paired and isinstance(c["nand_waits"], int)
            and isinstance(p["nand_waits"], int) else None),
        "framebuffer_error_delta_experimental_minus_control": (
            p["framebuffer_failures"] - c["framebuffer_failures"]
            if paired and isinstance(c["framebuffer_failures"], int)
            and isinstance(p["framebuffer_failures"], int) else None),
        "MG_both_return_values_observed": bool(both_values),
        "MG_return_changed": (c["guest_MG_return"] != p["guest_MG_return"]
                              if both_values else None),
        "result": ("not_evaluable_no_verified_ADT_pair" if not isolated
                   else "not_evaluable_missing_guest_evidence" if not paired
                   else "MG_value_difference_logged_backing_source_unproven"
                       if both_values and c["guest_MG_return"] != p["guest_MG_return"]
                   else "same_MG_value_logged_backing_source_unproven" if both_values
                   else "boot_compared_no_MG_return_evidence"),
        "Apple_MobileGestalt_getter_source_proven": False,
        "HomeView_normal_UI_verified": False,
        "interpretation": ("Only an explicit guest MG query and return can show a value. "
                           "Missing serial logs do not establish absence of a call. "
                           "MMIO traces are passive register-access probes and "
                           "do not implement Apple ANS/DCP services.")
    }


def read_json(path):
    p = Path(path)
    return json.loads(p.read_text()) if p.is_file() else {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--boot", required=True)
    parser.add_argument("--observations", required=True)
    parser.add_argument("--adt", required=True)
    parser.add_argument("--ans-adt")
    parser.add_argument("--qemu-logs", nargs="*", default=[])
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    debug = {}
    for pattern in args.qemu_logs:
        for path in glob.glob(pattern):
            debug[Path(path).name] = Path(path).read_text(errors="replace")
    boot = read_json(args.boot)
    observations = read_json(args.observations)
    result = compare(boot, observations, read_json(args.adt), debug)
    if args.ans_adt:
        result["ANS_driver_binding_experiment"] = compare_ans_probe(
            boot, observations, read_json(args.ans_adt), debug)
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        "result": result["result"],
        "paired_boot_observed": result["paired_boot_observed"],
        "MG_both_return_values_observed": result["MG_both_return_values_observed"],
        "matched_apple_adt_diff_confirmed": result["matched_apple_adt_diff_confirmed"]}))
    # Zero runtime proof is a research result, not proof of a boot. The
    # separate native GUI acceptance gate is intentionally still blocking.


if __name__ == "__main__":
    main()
