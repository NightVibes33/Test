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



def candidates_for(matched, provider, io_class=None, name=None, role=None):
    """Find declared IOKit personalities, not live IORegistry matches."""
    result = []
    for entry in matched:
        for personality in entry["matching_personalities"]:
            selectors = personality["selectors"]
            if selectors.get("IOProviderClass") != provider:
                continue
            if io_class and selectors.get("IOClass") != io_class:
                continue
            if name:
                options = selectors.get("IONameMatch")
                names = options if isinstance(options, list) else [options]
                if name not in names:
                    continue
            if role is not None:
                conditions = selectors.get("IOPropertyMatch")
                if not isinstance(conditions, dict) or conditions.get("role") != role:
                    continue
            result.append({
                "bundle_id": entry["bundle_id"],
                "personality_name": personality["personality_name"],
                "IOClass": selectors.get("IOClass"),
                "IOProviderClass": provider,
                "guest_IOService_started": False,
            })
    return sorted(result, key=lambda x: (x["bundle_id"], x["personality_name"]))


def hardware_identity_graph(matched, contract):
    """IOKit selector graph; no claims about firmware execution or RTKit."""
    nodes = (contract or {}).get("nodes") or {}
    storage = nodes.get("arm-io/ans") or {}
    storage_nub = nodes.get("arm-io/ans/iop-ans-nub") or {}
    graphics = nodes.get("arm-io/dcp") or {}
    graphics_nub = nodes.get("arm-io/dcp/iop-dcp-nub") or {}
    caps = (contract or {}).get("ANS_original_firmware_capabilities") or {}
    role = (caps.get("role") or {}).get("value")
    if not isinstance(role, str) or len(role) > 24:
        role = None
    graph = {}
    for target, wrapper, nub, target_role in (
        ("ANS", storage, storage_nub, role),
        ("DCP", graphics, graphics_nub, "DCP"),
    ):
        compat = wrapper.get("original_compatible")
        nub_compat = nub.get("original_compatible")
        # A declared compatibility is necessary but cannot prove IOService matching.
        requirements = [
            ("asc_wrapper", "AppleARMIODevice", None, compat, None),
            ("rtbuddy", "AppleA7IOPNub", "RTBuddy", nub_compat, None),
            ("rtbuddy_service", "RTBuddy", "RTBuddyService", None, None),
            ("controller_or_firmware_service", "RTBuddyService", None,
             None, target_role),
        ]
        stages = []
        for stage, provider, klass, match, role_requirement in requirements:
            usable = (stage not in ("asc_wrapper", "rtbuddy") or
                      isinstance(match, str) and bool(match)) and (
                      stage != "controller_or_firmware_service" or
                      isinstance(role_requirement, str) and bool(role_requirement))
            found = candidates_for(
                matched, provider, io_class=klass, name=match,
                role=role_requirement) if usable else []
            if target == "ANS" and stage == "controller_or_firmware_service":
                # Original IONVMeFamily also exposes CGv2 ANS2/ANS3 classes,
                # despite those names not containing the substring "NVMe".
                found = [c for c in found if str(c["IOClass"]).startswith("AppleANS")]
            elif target == "DCP" and stage == "controller_or_firmware_service":
                found = [c for c in found if "Firmware" in str(c["IOClass"])]
            stages.append({
                "stage": stage, "expected_Apple_ADT_compatible": match,
                "expected_Apple_ADT_role": role_requirement,
                "required_provider_class": provider,
                "kernelcache_personalities": found,
                "kernelcache_matching_rule_found": bool(found),
                "actual_matching_or_service_creation_observed": False,
            })
        graph[target] = {
            "apple_adt_node_present": bool(wrapper.get("present")),
            "original_compatible": compat,
            "original_nub_compatible": nub_compat,
            "firmware_role": target_role,
            "stages": stages,
            "all_required_matching_rules_found": all(
                x["kernelcache_matching_rule_found"] for x in stages),
            "controller_selection_is_ambiguous": (
                len(stages[-1]["kernelcache_personalities"]) > 1),
            "guest_IORegistry_runtime_verification": False,
            "ASC_mailbox_RTKit_handshake_implemented": False,
            "storage_or_display_operational": False,
        }
    return graph

AFK_BUNDLE = re.compile(r"AFK|FirmwareKit|ConvergedIPC|ConvergedPCI", re.I)


def personality_map(item):
    personalities = item.get("io_kit_personalities")
    if personalities is None and isinstance(item.get("info"), dict):
        personalities = item["info"].get("IOKitPersonalities")
    return personalities if isinstance(personalities, dict) else {}


def afk_census(raw):
    """Record FirmwareKit/AFK bundle IDs and whether AFKResource is an IOClass.

    A personality name is not a registered metaclass and not a guest start().
    """
    bundles = []
    declared = False
    for item in raw:
        if not isinstance(item, dict):
            continue
        bundle = item.get("id")
        if not isinstance(bundle, str) or not BUNDLE_RE.fullmatch(bundle):
            continue
        classes = []
        personalities = []
        for name, raw_personality in personality_map(item).items():
            if not isinstance(raw_personality, dict) or not isinstance(name, str):
                continue
            io_class = raw_personality.get("IOClass")
            if isinstance(io_class, str) and io_class.startswith("AFK"):
                classes.append(io_class[:64])
                if io_class == "AFKResource":
                    declared = True
            if io_class == "AFKResource" or AFK_BUNDLE.search(bundle):
                personalities.append({
                    "personality_name": name[:96],
                    "selectors": {k: compact(raw_personality.get(k))
                                  for k in FIELDS
                                  if compact(raw_personality.get(k)) is not None},
                })
        if (AFK_BUNDLE.search(bundle) or classes) and len(bundles) < 40:
            bundles.append({
                "bundle_id": bundle,
                "afk_ioclasses": sorted(set(classes))[:12],
                "personalities": personalities[:8],
                "declares_IOClass_AFKResource": "AFKResource" in classes,
                "metaclass_registered_in_guest": False,
                "guest_start_observed": False,
            })
    return bundles, declared


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
        selected = matching_personalities(personality_map(item))
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
    afk_bundles, afk_declared = afk_census(raw)
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
        "AFK_and_firmware_kit_bundles": afk_bundles,
        "AFKResource_IOClass_declared_in_kernelcache_personalities": afk_declared,
        "AFKResource_metaclass_registered_in_guest": False,
        "original_Apple_J490_ANS_identity": identity,
        "source_backed_IOKit_service_dependency_graph":
            hardware_identity_graph(matched, contract),
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
