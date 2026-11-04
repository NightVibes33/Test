#!/usr/bin/env python3
"""Compare J490 Apple ANS hardware with an independently authored QEMU ANS model.

Static, read-only migration assessment. Similar registers do not prove a
working RTKit handshake, NVMe queue, DMA path, NAND service, or HomeView boot.
The upstream ANS implementation is AGPL-3.0-or-later; source is not vendored.
"""
import argparse
import json
from pathlib import Path

UPSTREAM = "YahiaAngelo/qemu-vphone"
PIN = "f6b3bc9d8ec9ba3113a4dbae9e9584775cd0d1f2"


def assess(contract, ans_c, sart_c):
    if not isinstance(contract, dict):
        raise ValueError("J490 hardware contract must be a JSON object")
    nodes = contract.get("nodes") or {}
    ans = nodes.get("arm-io/ans") or {}
    sart = nodes.get("arm-io/sart-ans") or {}
    regions = ans.get("reg_windows") or []
    if not isinstance(regions, list):
        raise ValueError("ANS register-window inventory must be a list")
    sizes = [int(w.get("length", "0x0"), 16) for w in regions]
    vendor = sizes[3] if len(sizes) > 3 else None
    source_vendor = "NVME_APPLE_VENDOR_REG_SIZE (0x60000)" in ans_c
    model_vendor_match = vendor == 0x60000 and source_vendor
    expects_four = all(token in ans_c for token in (
        "sysbus_init_mmio(sbd", "reg[1]", "reg[3]", "reg[5]", "reg[7]"))
    zero_region_2 = len(sizes) > 2 and sizes[2] == 0
    has_rtkit = all(token in ans_c for token in (
        "AppleRTKitOps", "apple_rtkit_new(", "apple_ans_start("))
    has_nvme = all(token in ans_c for token in (
        "pci_new(-1, TYPE_NVME)", "is-apple-ans", "apple_ans_set_irq"))
    has_sart = all(token in sart_c for token in (
        "memory_region_init_iommu", "apple_sart_translate"))
    v6 = ans.get("original_compatible") == "iop,ascwrap-v6"
    older_v4 = "APPLE_A7IOP_V4" not in ans_c  # board version is supplied separately
    blockers = []
    if not ans.get("present") or not sart.get("present"):
        blockers.append("Original J490 ANS or SART hardware node not present")
    if not has_rtkit:
        blockers.append("Upstream RTKit start/wakeup path not located")
    if not has_nvme:
        blockers.append("Upstream ANS-to-NVMe device wiring not located")
    if not has_sart:
        blockers.append("Upstream SART IOMMU mapping not located")
    if zero_region_2 and expects_four:
        blockers.append("J490 ANS register pair 2 is zero-sized; older model maps this pair")
    if len(sizes) != 4 and expects_four:
        blockers.append("J490 ANS has additional MMIO windows not represented by older 4-region mapping")
    if v6:
        blockers.append("ASCWrap-v6/RTKit ABI and interrupt handshake not verified for J490")
    blockers.extend((
        "No real J490 DMA queue and NVMe namespace I/O proven",
        "No NAND service publication or native HomeView mount proven",
    ))
    return {
        "source_firmware": contract.get("source"),
        "target_device": contract.get("device"),
        "upstream_source": UPSTREAM,
        "upstream_revision": PIN,
        "upstream_license": "AGPL-3.0-or-later",
        "license_compliance_review_required_before_port": True,
        "ans_present": bool(ans.get("present")),
        "ans_original_compatible": ans.get("original_compatible"),
        "sart_present": bool(sart.get("present")),
        "sart_original_compatible": sart.get("original_compatible"),
        "original_ans_reg_window_count": len(sizes),
        "original_ans_reg_lengths": [hex(n) for n in sizes],
        "original_ans_zero_length_reg_indices": [i for i,n in enumerate(sizes) if not n],
        "older_model_uses_first_four_register_pairs": expects_four,
        "vendor_window_index": 3,
        "vendor_window_length_matches_upstream": model_vendor_match,
        "upstream_rtkit_hooks_present": has_rtkit,
        "upstream_nvme_device_construction_present": has_nvme,
        "upstream_sart_iommu_mapping_present": has_sart,
        "old_model_nvme_apple_boot_status_is_emulated": "NVME_APPLE_BOOT_STATUS_OK" in ans_c,
        "old_model_marks_firmware_as_preloaded": '"pre-loaded"' in ans_c,
        "j490_rtkit_abi_verified": False,
        "j490_storage_io_verified": False,
        "native_homeview_boot_verified": False,
        "safe_direct_port_verified": False,
        "blocking_differences": blockers,
        "recommendation": (
            "Reuse the older ANS source only as a licensed protocol reference. "
            "Adapt the v6 ASC, valid J490 MMIO windows, SART/DMA and IRQ mapping, "
            "then prove queue traffic and NAND publication using real guest traces."
        ),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", required=True)
    ap.add_argument("--upstream-ans", required=True)
    ap.add_argument("--upstream-sart", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    data = assess(json.loads(Path(a.contract).read_text()),
                  Path(a.upstream_ans).read_text(),
                  Path(a.upstream_sart).read_text())
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"vendor_window_matches": data["vendor_window_length_matches_upstream"],
                      "safe_direct_port_verified": False,
                      "blockers": len(data["blocking_differences"])}))


if __name__ == "__main__":
    main()
