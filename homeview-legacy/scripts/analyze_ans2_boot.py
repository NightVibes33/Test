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
    r"guest=(0x[0-9a-f]{8,16}) cpu=(\d+)"
    r"(?: mode=([A-Za-z0-9:_-]+))?"
    r"(?: class=([A-Za-z_][A-Za-z0-9_]*))?"
    r"(?: slot=(\d+))?", re.I)
SLID_PC_HIT = re.compile(
    r"HOMEVIEW_PC_TRACE slid_pc_hit static=(0x[0-9a-f]{8,16}) "
    r"guest=(0x[0-9a-f]{8,16}) cpu=(\d+) slide=(0x[0-9a-f]+)", re.I)
SLIDE_CONSENSUS = re.compile(
    r"HOMEVIEW_PC_TRACE slide_consensus slide=(0x[0-9a-f]+) "
    r"witness_signatures=(\d+)", re.I)
DCP_ACCESS = re.compile(
    r"HOMEVIEW_MMIO_TRACE (read|write) (arm-io/(?:dcp|dcp0-expert|sgx))\s+off=0x([0-9a-f]+)",
    re.I)


def fingerprint_record(match):
    static = int(match.group(1), 16)
    guest = int(match.group(2), 16)
    delta = (guest - static) & 0xFFFFFFFFFFFFFFFF
    aligned = bool(delta) and delta < 0x1000000000 and (delta & 0x3FFF) == 0
    record = {
        "static_vaddr": match.group(1).lower(),
        "runtime_guest_vaddr": match.group(2).lower(),
        "cpu": int(match.group(3)),
        "kernelcache_slide": hex(delta) if aligned else None,
        "slide_is_16k_aligned": aligned,
    }
    if match.group(4):
        record["mode"] = match.group(4)
    if match.group(5):
        record["class"] = match.group(5)
    if match.group(6):
        record["vtable_slot"] = int(match.group(6))
    return record


def consensus_slide(hits):
    # Distinct *original* methods are required; repeated matches of one
    # 48-byte sequence, even at multiple guest locations, are not consensus.
    votes = {}
    for hit in hits:
        slide = hit.get("kernelcache_slide")
        static = hit.get("static_vaddr")
        if slide and static:
            votes.setdefault(slide, set()).add(static)
    if not votes:
        return None
    best = max(votes, key=lambda slide: (len(votes[slide]), slide))
    if len(votes[best]) < 2:
        return None
    for hit in hits:
        hit["on_consensus_kernelcache_slide"] = hit.get("kernelcache_slide") == best
    return best


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
        "framebuffer_missing_count": text.lower().count("unable to get framebuffer"),
        "display_list_missing_logged": "unable to get display list" in text.lower(),
        "AFKResource_allocation_error_count": text.count('Couldn\'t alloc class "AFKResource"'),
        "DCP_RTBuddy_start_logged": "RTBuddy(DCP)" in text,
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
        "PC_trace_candidate_budget_exhausted": "candidate_budget_exhausted=true" in text,
        "PC_trace_candidate_allocation_failed": "candidate_allocation_failed=true" in text,
        "observed_guest_PC_hits": [
            {"target_vaddr": m.group(1), "cpu": int(m.group(2))}
            for m in list(PC_HIT.finditer(text))[:24]],
        "PC_hit_proves_dispatch_not_method_completion": True,
        "relocated_guest_PC_hits": [
            {"static_vaddr": m.group(1).lower(),
             "runtime_guest_vaddr": m.group(2).lower(),
             "cpu": int(m.group(3)), "kernelcache_slide": m.group(4).lower()}
            for m in list(SLID_PC_HIT.finditer(text))[:24]],
        "runtime_slide_consensus_events": [
            {"slide": m.group(1).lower(), "witness_signatures": int(m.group(2))}
            for m in list(SLIDE_CONSENSUS.finditer(text))[:8]],
        "original_code_fingerprint_hits": [
            fingerprint_record(m) for m in list(FINGERPRINT_HIT.finditer(text))[:16]],
        "DCP_or_SGX_MMIO_access_count": len(list(DCP_ACCESS.finditer(text))),
        "fingerprint_match_is_not_an_ANS_driver_start_proof": True,
        "no_PC_hits_does_not_exclude_KASLR_or_missing_targets": True,
    }


def dcp_firmware_window(inventory):
    """DCP's nub is not an ANS-style firmware carve.

    iop-dcp-nub advertises no-firmware-service and has no region-base.
    Mapping a DRAM window there would contradict the device tree.
    """
    nodes = inventory.get("nodes") if isinstance(inventory, dict) else None
    nub = None
    if isinstance(nodes, list):
        for node in nodes:
            path = node.get("path") if isinstance(node, dict) else ""
            if str(path).endswith("/arm-io/dcp/iop-dcp-nub"):
                nub = node
                break
    names = set(nub.get("property_names") or []) if isinstance(nub, dict) else set()
    no_fw = "no-firmware-service" in names
    has_region = "region-base" in names and "region-size" in names
    if nub is None:
        reason = "dcp nub not in inventory"
    elif no_fw and not has_region:
        reason = (
            "iop-dcp-nub sets no-firmware-service and has no region-base; "
            "RTBuddy will not map an ADT firmware window. Display firmware "
            "has to come from AFKFirmwareService after AFKResource exists.")
    else:
        reason = "dcp nub properties recorded"
    return {
        "nub_present": nub is not None,
        "no_firmware_service": no_fw,
        "region_base_property_present": "region-base" in names,
        "quiesced": "quiesced" in names,
        "dram_carve_applicable": bool(has_region and not no_fw),
        "reason": reason,
    }


def compare(control_text, experiment_text, qemu_text="", pc_trace_text="", inventory=None):
    control = observe_serial(control_text)
    trial = observe_serial(experiment_text)
    qemu = observe_qemu(qemu_text + "\n" + pc_trace_text)
    qemu["independent_PC_trace_file_present"] = bool(pc_trace_text)
    qemu["independent_PC_trace_initialized"] = bool(PC_CONFIG.search(pc_trace_text))
    qemu["zero_hits_are_inconclusive"] = (
        not qemu["independent_PC_trace_initialized"]
        or qemu["PC_trace_candidate_budget_exhausted"]
        or qemu["PC_trace_candidate_allocation_failed"])
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
    relocated = qemu["relocated_guest_PC_hits"] + serial_pc["relocated_guest_PC_hits"]
    qemu["relocated_guest_PC_hits"] = [
        {"static_vaddr": static, "runtime_guest_vaddr": guest,
         "cpu": cpu, "kernelcache_slide": slide}
        for static, guest, cpu, slide in sorted({
            (h["static_vaddr"], h["runtime_guest_vaddr"], h["cpu"],
             h["kernelcache_slide"]) for h in relocated})][:24]
    qemu["relocated_guest_PC_hit_count"] = len(qemu["relocated_guest_PC_hits"])
    events = qemu["runtime_slide_consensus_events"] + serial_pc["runtime_slide_consensus_events"]
    qemu["runtime_slide_consensus_events"] = [
        {"slide": slide, "witness_signatures": witnesses}
        for slide, witnesses in sorted({
            (e["slide"], e["witness_signatures"]) for e in events})][:8]
    merged = {}
    for hit in (qemu["original_code_fingerprint_hits"] +
                serial_pc["original_code_fingerprint_hits"]):
        key = (hit["static_vaddr"], hit["runtime_guest_vaddr"], hit["cpu"])
        merged.setdefault(key, hit)
    qemu["original_code_fingerprint_hits"] = [
        merged[key] for key in sorted(merged)][:16]
    qemu["original_code_fingerprint_hit_count"] = len(
        qemu["original_code_fingerprint_hits"])
    qemu["kernelcache_slide_consensus"] = consensus_slide(
        qemu["original_code_fingerprint_hits"])
    qemu["fingerprint_hits_on_consensus_slide"] = sum(
        hit.get("on_consensus_kernelcache_slide", False)
        for hit in qemu["original_code_fingerprint_hits"])
    qemu["fingerprint_hits_off_consensus_slide"] = sum(
        hit.get("on_consensus_kernelcache_slide") is False
        for hit in qemu["original_code_fingerprint_hits"])
    qemu["slid_PC_hits_agree_with_fingerprint_consensus"] = all(
        hit["kernelcache_slide"] == qemu["kernelcache_slide_consensus"]
        for hit in qemu["relocated_guest_PC_hits"])
    qemu["runtime_slide_events_agree_with_fingerprints"] = all(
        event["slide"] == qemu["kernelcache_slide_consensus"]
        for event in qemu["runtime_slide_consensus_events"])
    trace_blob = "\n".join((qemu_text, pc_trace_text, experiment_text))
    qemu["exec_callbacks_confirmed"] = (
        "exec_callback_fired" in trace_blob or
        "instrumentation_active=true" in trace_blob)
    qemu["configured_fingerprints_absent_while_instrumentation_active"] = (
        "classification=no_hit_instrumentation_active" in trace_blob and
        qemu["original_code_fingerprint_hit_count"] == 0)
    dcp = qemu["DCP_or_SGX_MMIO_access_count"] + serial_pc["DCP_or_SGX_MMIO_access_count"]
    qemu["DCP_or_SGX_MMIO_access_count"] = dcp
    # Even with a complete trace, no hits cannot rule out incorrect static
    # addresses, a different KASLR slide, or unmapped original code.
    qemu["zero_hits_are_not_proof_of_driver_absence"] = True
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
        "storage_stop": (
            "probe_scores_logged_controller_start_absent_no_ANS_MMIO"
            if trial["ANS_controller_probe_count"] and
            not trial["ANS_controller_start_observed"] and
            qemu["ANS_or_SART_MMIO_access_count"] == 0
            else "ANS_MMIO_observed_protocol_not_implemented"
            if qemu["ANS_or_SART_MMIO_access_count"]
            else "no_ANS_MMIO_observed"),
        "framebuffer_stop": (
            "userspace_display_service_missing_no_DCP_MMIO"
            if trial["framebuffer_missing_count"] and
            qemu["DCP_or_SGX_MMIO_access_count"] == 0
            else "DCP_MMIO_observed_display_not_implemented"
            if qemu["DCP_or_SGX_MMIO_access_count"]
            else "framebuffer_error_not_logged"),
        "display_provider_stop": (
            "DCP_RTBuddy_start_not_logged"
            if trial["framebuffer_missing_count"] and not trial["DCP_RTBuddy_start_logged"]
            else "DCP_RTBuddy_start_logged"
            if trial["DCP_RTBuddy_start_logged"]
            else "display_provider_not_observed"),
        "AFKResource_alloc_failed_before_controller_start": (
            trial["AFKResource_allocation_error_count"] > 0 and
            not trial["ANS_controller_start_observed"]),
        "dcp_firmware_window": dcp_firmware_window(inventory),
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
    parser.add_argument("--pc-log", help="Independent read-only QEMU TCG trace artifact")
    parser.add_argument("--hardware-inventory")
    parser.add_argument("--output", required=True)
    a = parser.parse_args()
    inventory = None
    if a.hardware_inventory and Path(a.hardware_inventory).is_file():
        inventory = json.loads(Path(a.hardware_inventory).read_text(encoding="utf-8"))
    result = compare(read_limited(a.control), read_limited(a.experiment),
                     read_limited(a.qemu_log),
                     read_limited(a.pc_log) if a.pc_log else "",
                     inventory)
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
