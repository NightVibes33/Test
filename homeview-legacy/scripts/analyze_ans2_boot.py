#!/usr/bin/env python3
"""Compare genuine Apple HomeView 24V514 ANS2 guest logs and QEMU traces.

IOService matching, controller probe, driver start, and NAND service
publication are separate milestones. A probe score is NOT a winning driver.
"""
import argparse
import json
from pathlib import Path
import re

MAX_LOG = 8 * 1024 * 1024
PROBE = re.compile(r"\b(?P<klass>AppleANS[23][A-Za-z0-9_]+)::probe\([^\n]{0,180}?returning score\s+(?P<score>\d{1,9})", re.I)
CONTROLLER_START = re.compile(r"\b(AppleANS[23][A-Za-z0-9_]+)::start\(", re.I)
RTBUDDY = re.compile(r"\bRTBuddy\(ANS2\):\s*start\(", re.I)
INSTALL = re.compile(r"HOMEVIEW_MMIO_TRACE installed (arm-io/(?:ans|sart-ans))\s+base=0x[0-9a-f]+\s+length=0x([0-9a-f]+)(?:\s+index=(\d+))?", re.I)
ACCESS = re.compile(r"HOMEVIEW_MMIO_TRACE (read|write) (arm-io/(?:ans|sart-ans))\s+off=0x([0-9a-f]+)", re.I)
PC_CONFIG = re.compile(r"HOMEVIEW_PC_TRACE initialized targets=(\d+)", re.I)
PC_HIT = re.compile(r"HOMEVIEW_PC_TRACE hit target=(0x[0-9a-f]{8,16}) cpu=(\d+)", re.I)
FINGERPRINT_HIT = re.compile(
    r"HOMEVIEW_PC_TRACE fingerprint_hit static=(0x[0-9a-f]{8,16}) "
    r"guest=(0x[0-9a-f]{8,16}) cpu=(\d+)", re.I)


def observe_serial(text):
    records = {}
    for m in PROBE.finditer(text):
        records.setdefault(m.group("klass"), []).append(int(m.group("score")))
    ranked = sorted(
        ({"class": name, "scores": scores, "max_observed_probe_score": max(scores)}
         for name, scores in records.items()),
        key=lambda row: (-row["max_observed_probe_score"], row["class"]))
    starts = sorted(set(CONTROLLER_START.findall(text)))
    buddy_starts = len(RTBUDDY.findall(text))
    return {
        "ANS2_RTBuddy_start_invocation_count": buddy_starts,
        "ANS2_RTBuddy_start_was_invoked": bool(buddy_starts),
        "ANS_controller_probe_candidates": ranked,
        "ANS_controller_probe_count": sum(len(row["scores"]) for row in ranked),
        "highest_scored_candidate": ranked[0]["class"] if ranked else None,
        "highest_score_proves_winning_driver": False,
        "ANS_controller_start_methods_logged": starts,
        "ANS_controller_start_observed": bool(starts),
        "NAND_service_wait_count": text.lower().count("waiting for nand service to publish"),
        "NAND_service_publish_logged": bool(re.search(
            r"NAND service (?:published|found|available)\b", text, re.I)),
        "AFKResource_allocation_error_count": text.count('Couldn\'t alloc class "AFKResource"'),
        "Apple_runtime_RTBuddy_or_probe_evidence": bool(buddy_starts or ranked),
        "RTKit_mailbox_handshake_completed_proven": False,
        "NVMe_block_device_operational_proven": False,
    }


def observe_qemu(text):
    windows = [
        {"device": m.group(1), "mapped_bytes": int(m.group(2), 16),
         "window_index": int(m.group(3) or 0)} for m in INSTALL.finditer(text)]
    accesses = [
        {"operation": m.group(1).lower(), "device": m.group(2),
         "offset": "0x" + m.group(3).lower()} for m in ACCESS.finditer(text)]
    return {
        "registered_ANS_and_SART_windows": len(windows),
        "ANS_primary_544KiB_window_mapped": any(
            w["device"] == "arm-io/ans" and w["window_index"] == 0
            and w["mapped_bytes"] >= 0x88000 for w in windows),
        "ANS_or_SART_MMIO_access_count": len(accesses),
        "MMIO_access_sample": accesses[:40],
        "zero_MMIO_access_cannot_disprove_driver_probes": True,
        "QEMU_MMIO_zero_return_stubs_are_not_hardware_emulation": True,
        "PC_trace_plugin_initialized": bool(PC_CONFIG.search(text)),
        "observed_guest_PC_hits": [
            {"target_vaddr": m.group(1), "cpu": int(m.group(2))}
            for m in list(PC_HIT.finditer(text))[:24]],
        "PC_hit_proves_dispatch_not_method_completion": True,
        "original_code_fingerprint_hits": [
            {"static_vaddr": m.group(1), "runtime_guest_vaddr": m.group(2),
             "cpu": int(m.group(3))}
            for m in list(FINGERPRINT_HIT.finditer(text))[:16]],
        "fingerprint_match_is_not_an_ANS_driver_start_proof": True,
        "no_PC_hits_does_not_exclude_KASLR_or_missing_targets": True,
    }


def compare(control_text, experiment_text, qemu_text=""):
    control = observe_serial(control_text)
    trial = observe_serial(experiment_text)
    qemu = observe_qemu(qemu_text)
    # QEMU plugins may emit qemu_plugin_outs() to the configured -D log
    # OR to the captured guest stdout/stderr stream on different hosts.
    # Union both streams and remove duplicate address/CPU pairs.
    serial_pc = observe_qemu(experiment_text)
    qemu["PC_trace_plugin_initialized"] |= serial_pc["PC_trace_plugin_initialized"]
    hits = qemu["observed_guest_PC_hits"] + serial_pc["observed_guest_PC_hits"]
    qemu["observed_guest_PC_hits"] = [
        dict(target_vaddr=address, cpu=cpu)
        for address, cpu in sorted({(entry["target_vaddr"], entry["cpu"])
                                    for entry in hits})][:24]
    qemu["PC_hit_count"] = len(qemu["observed_guest_PC_hits"])
    hits = qemu["original_code_fingerprint_hits"] + serial_pc["original_code_fingerprint_hits"]
    qemu["original_code_fingerprint_hits"] = [
        {"static_vaddr": static, "runtime_guest_vaddr": guest, "cpu": cpu}
        for static, guest, cpu in sorted({
            (h["static_vaddr"], h["runtime_guest_vaddr"], h["cpu"])
            for h in hits})][:16]
    qemu["original_code_fingerprint_hit_count"] = len(
        qemu["original_code_fingerprint_hits"])
    if not control_text or not experiment_text:
        result = "incomplete_guest_log_pair"
    elif trial["ANS2_RTBuddy_start_was_invoked"] and not control["ANS2_RTBuddy_start_was_invoked"]:
        result = "original_compatibility_enables_ANS2_RTBuddy_probe_path"
    elif trial["ANS2_RTBuddy_start_was_invoked"]:
        result = "ANS2_RTBuddy_path_observed_in_both_guests"
    elif trial["ANS_controller_probe_count"]:
        result = "ANS2_controller_probes_without_RTBuddy_start_log"
    else:
        result = "no_ANS2_runtime_binding_evidence_in_logs"
    return {
        "source": "Original Apple HomeView 24V514 guest serial and original J490 ADT",
        "control": control,
        "original_ANS_compatible_experiment": trial,
        "experimental_QEMU_MMIO": qemu,
        "control_to_experiment_new_ANS2_probes": sorted(
            {v["class"] for v in trial["ANS_controller_probe_candidates"]}
            - {v["class"] for v in control["ANS_controller_probe_candidates"]}),
        "result": result,
        "functional_ANS2_device_verified": False,
        "normal_installed_HomeView_or_BreadBoard_boot_verified": False,
        "interpretation": (
            "Apple RTBuddy start() and ANS2 controller probe() scores demonstrate "
            "guest runtime matching activity, not successful NVMe controller start(), "
            "a firmware mailbox handshake, or NAND publishing. Diagnostic MMIO "
            "zero-return stubs can alter guest behavior; no access does not negate "
            "driver matching events."),
    }


def read_limited(path):
    file = Path(path)
    if not file.is_file():
        return ""
    if file.stat().st_size > MAX_LOG:
        raise ValueError("ANS2 serial log exceeds bounded size: " + file.name)
    return file.read_text(encoding="utf-8", errors="replace")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--control", required=True)
    parser.add_argument("--experiment", required=True)
    parser.add_argument("--qemu-log", required=True)
    parser.add_argument("--output", required=True)
    a = parser.parse_args()
    result = compare(read_limited(a.control), read_limited(a.experiment),
                     read_limited(a.qemu_log))
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    exp = result["original_ANS_compatible_experiment"]
    print(json.dumps({"result": result["result"],
                      "ANS2_probe_candidates": len(exp["ANS_controller_probe_candidates"]),
                      "RTBuddy_start_invoked": exp["ANS2_RTBuddy_start_was_invoked"],
                      "MMIO_access_count": result["experimental_QEMU_MMIO"]["ANS_or_SART_MMIO_access_count"]}))


if __name__ == "__main__":
    main()
