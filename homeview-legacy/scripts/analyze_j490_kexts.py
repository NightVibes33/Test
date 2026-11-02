#!/usr/bin/env python3
"""Source-backed KEXT/IOKit identity evidence from original HomeView J490 cache.
No executable firmware is distributed; a bundled personality is not a guest match.
"""
import argparse
import json
import re
from pathlib import Path

DRIVER_RE = re.compile(r"ans|nvme|nand|sart|dcp|display|agx|gpu|rtbuddy|rtkit|ascwrap", re.I)
BUNDLE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,256}$")
FIELDS = ("IOClass", "IOProviderClass", "IONameMatch", "IOResourceMatch",
          "IOParentMatch", "IOPropertyMatch", "IOProbeScore", "IOMatchCategory",
          "IOUserClientClass")


def compact(value, depth=0):
    """Bounded allowlisted selectors; never expose original binary payloads."""
    if isinstance(value, (str, int, bool)) and len(str(value)) <= 192:
        return value
    if isinstance(value, list) and depth < 2:
        return [x for x in (compact(v, depth + 1) for v in value[:8]) if x is not None]
    if isinstance(value, dict) and depth < 2:
        allowed = ("name", "role", "compatible", "IONameMatch", "IOProviderClass", "IOClass")
        return {k: v for k, x in list(value.items())[:12]
                if isinstance(k, str) and k in allowed
                if (v := compact(x, depth + 1)) is not None}
    return None


def matching_personalities(personalities):
    result = []
    if not isinstance(personalities, dict):
        return result
    for name, raw in sorted(personalities.items()):
        if not isinstance(name, str) or not isinstance(raw, dict):
            continue
        selectors = {k: v for k in FIELDS
                     if (v := compact(raw.get(k))) is not None}
        searchable = name + " " + " ".join(str(v) for v in selectors.values())
        if DRIVER_RE.search(searchable):
            result.append({"personality_name": name[:192],
                           "selectors": selectors,
                           "guest_matched_verified": False})
        if len(result) >= 24:
            break
    return result


def summarize(raw, contract=None):
    if isinstance(raw, dict):
        raw = raw.get("kexts") or raw.get("extensions")
    if not isinstance(raw, list):
        raise ValueError("ipsw KEXT JSON must contain an array")
    matched = []
    parsed = 0
    for item in raw:
        if not isinstance(item, dict):
            continue
        bundle = item.get("id")
        if not isinstance(bundle, str) or not BUNDLE_RE.fullmatch(bundle):
            continue
        parsed += 1
        personalities = item.get("io_kit_personalities")
        if personalities is None and isinstance(item.get("info"), dict):
            personalities = item["info"].get("IOKitPersonalities")
        selected = matching_personalities(personalities)
        if not DRIVER_RE.search(bundle) and not selected:
            continue
        version = item.get("version")
        matched.append({
            "bundle_id": bundle,
            "version": str(version)[:64]
                       if isinstance(version, (str, int, float)) else None,
            "evidence": "kernelcache_embedded_KEXT_Info_plist",
            "matching_personalities": selected,
            "driver_loaded_or_matched_in_guest": False,
        })
        if len(matched) >= 120:
            break
    if parsed == 0:
        raise ValueError("no KEXT bundle IDs parsed from original kernelcache")
    caps = (contract or {}).get("ANS_original_firmware_capabilities") or {}
    identity = {k: caps[k] for k in
                ("role", "nvme-num-sl", "nvme-queue-entries",
                 "nvme-interrupt-idx", "iommu-parent")
                if isinstance(caps.get(k), dict)}
    return {
        "source_build": "Apple HomeView 27.2 (24V514), J490AP",
        "tool": "ipsw kernel kexts --json original decrypted Apple kernelcache",
        "parsed_KEXT_records": parsed,
        "matching_storage_graphics_RTKit_KEXTs": matched,
        "matched_KEXT_count": len(matched),
        "original_Apple_J490_ANS_identity": identity,
        "role_ANS2_matches_an_original_kernelcache_IOKit_personality_proven": False,
        "runtime_driver_loaded_or_start_success_proven": False,
        "NAND_service_or_APFS_system_available_proven": False,
        "native_DCP_framebuffer_available_proven": False,
        "note": ("Bundled KEXT Info.plist matching criteria are only candidate "
                 "driver evidence, not an IOService match, firmware handshake, "
                 "NVMe namespace, or native display.")
    }


def report(path, contract_path, exit_code):
    source = Path(path)
    result = {"listing_success": False,
              "error": "kernelcache KEXT listing unavailable",
              "raw_kernel_uploaded": False}
    if exit_code != 0 or not source.is_file():
        return result
    try:
        raw = json.loads(source.read_text(encoding="utf-8"))
        contract_file = Path(contract_path)
        contract = json.loads(contract_file.read_text()) if contract_file.is_file() else None
        result = summarize(raw, contract)
        result["listing_success"] = True
        result["raw_kernel_uploaded"] = False
    except (ValueError, TypeError, OSError) as exc:
        result["error"] = "KEXT listing not parseable: " + type(exc).__name__
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--kext-json", required=True)
    p.add_argument("--contract", required=True)
    p.add_argument("--list-exit-code", required=True, type=int)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    out = Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    data = report(a.kext_json, a.contract, a.list_exit_code)
    out.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"success": data["listing_success"],
                      "records": data.get("parsed_KEXT_records"),
                      "candidate_KEXTs": data.get("matched_KEXT_count")}))


if __name__ == "__main__":
    main()
