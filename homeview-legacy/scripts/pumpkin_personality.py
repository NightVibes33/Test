#!/usr/bin/env python3
"""Centralized HomeAccessory J490/Pumpkin identity for Apple ADT emulation.

Loads a source-labeled device profile. Default mode only validates identity.
Experimental --enable-pumpkin-probe injects an *unproven* /chosen/PumpkinMode
property in a disposable QEMU guest's DeviceTree; it DOES NOT force Apple's
MobileGestalt API to return true. Never write Apple system firmware, NVRAM
or entitlements on the host device.
"""
import json
from pathlib import Path

PROFILE_PATH = Path(__file__).resolve().parents[1] / "profiles" / "pumpkin-homeaccessory-j490.json"

def load_profile(path=PROFILE_PATH):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    assert data["schema_version"] == 1
    assert data["identity"]["product_type"].startswith("HomeAccessory")
    assert data["gestalt"]["key"] == "PumpkinMode"
    assert data["gestalt"]["obfuscated_key"] == "WnCqFWpQgAFLfacM07K0RA"
    assert data["device_tree"]["preserve_original_apple_nodes"] is True
    return data

def walk_path(root, path):
    node = root
    for label in path.strip("/").split("/"):
        matches=[child for child in node.children
                 if str(child.props.get("name","")).strip("\0")==label]
        if len(matches)!=1:
            raise ValueError("Missing or ambiguous original Apple ADT path: "+path)
        node=matches[0]
    return node

def apply(root, profile, enable_pumpkin_probe=False):
    original = {key:str(root.props.get(key,"<absent>"))
                for key in ("model","compatible","platform-name","device_type")}
    checks={}
    for p in profile["device_tree"]["known"]:
        try:
            walk_path(root,p)
            checks[p]=True
        except ValueError:
            checks[p]=False
    # Presence is reported, not forced: some product firmware hardware paths
    # may be missing from a stripped/recovery ADT.
    injected=[]
    if enable_pumpkin_probe:
        cfg=profile["device_tree"]["experimental_probe"]
        if cfg["path"]!="/chosen" or cfg["property"]!="PumpkinMode" or cfg["type"]!="u32":
            raise ValueError("Refusing unexpected experimental ADT property")
        chosen=walk_path(root,cfg["path"])
        if cfg["property"] in chosen.props:
            raise ValueError("Apple ADT already has PumpkinMode, refuse overwrite")
        chosen.props[cfg["property"]]=f'u32:{int(cfg["value"])}'
        injected.append("/chosen/PumpkinMode")
    return {
       "profile_id":profile["profile_id"],
       "apple_original_root_properties":original,
       "profile_product_type":profile["identity"]["product_type"],
       "profile_board_config":profile["identity"]["board_config"],
       "apple_hardware_nodes_present":checks,
       "experimental_injected_properties":injected,
       "pumpkin_probe_injected":bool(injected),
       "mobilegestalt_pumpkinmode_returned_value":None,
       "mobilegestalt_pumpkinmode_query_observed":False,
       "guest_isPumpkin_branch_observed":False,
       "guest_homeaccessory_detection_observed":False,
       "nvram_pumpkin_keys_injected":[],
       "homeview_gui_verified":False,
       "warning":"Experimental /chosen/PumpkinMode injection does not prove MobileGestalt reads it."
    }
