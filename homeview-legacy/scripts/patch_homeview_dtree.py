#!/usr/bin/env python3
"""One-pass HomeView J490 Apple Device Tree adaptation for qemu-sptm.

Uses the upstream darwin-vm decoder/fixup/encoder exactly once. The original
raw Apple ADT is never mutated. Snapintosh's J700 qemu oracle demonstrated
that removing /dock-connect during this same transformation is needed to
avoid AppleDockConnectAIC accessing unavailable hardware.
"""
import argparse
import importlib.util
import json
from pathlib import Path
from pumpkin_personality import apply as apply_personality, load_profile

def make_tree(raw, output, upstream_path, nvram_path, mode, profile_path=None, pumpkin_probe=False):
    spec = importlib.util.spec_from_file_location("darwin_vm_dt_fixup", upstream_path)
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load upstream darwin-vm ADT fixup")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    root = mod.ADTNode()
    data = Path(raw).read_bytes()
    mod.decode_node(data, root)
    with Path(nvram_path).open("rb") as nv:
        mod.fixup(root, nvram_file=nv, disable_network=False)
    names = []
    for child in list(root.children):
        name = child.props.get("name", "")
        if isinstance(name, bytes):
            name = name.split(b"\0", 1)[0].decode("utf-8", "replace")
        if name == "dock-connect":
            names.append("/dock-connect")
            if mode == "remove":
                root.children.remove(child)
            elif mode == "neutralize":
                child.props.pop("compatible", None)
                child.props["status"] = "disabled"
    if not names:
        raise ValueError("Expected J490 /dock-connect node missing")
    # Device personality is sourced from ONE canonical profile. Original
    # ProductType/board identity is preserved; no generic iPhone spoofing.
    profile = load_profile(profile_path) if profile_path else load_profile()
    personality_report = apply_personality(root, profile, pumpkin_probe)
    encoded = mod.encode_node(root)
    if not encoded:
        raise ValueError("Resulting Apple device tree is empty")
    Path(output).write_bytes(encoded)
    return {
        "mode": mode, "one_pass_darwin_vm_fixup": True,
        "source": "original Apple HomeView J490 IM4P payload",
        "dock_paths_affected": names, "raw_bytes": len(data),
        "output_bytes": len(encoded), "native_homeview_gui_proven": False,
        "device_personality": personality_report
    }

def main():
    p=argparse.ArgumentParser()
    p.add_argument("raw_dtree")
    p.add_argument("output_dtree")
    p.add_argument("--upstream", required=True)
    p.add_argument("--nvram", required=True)
    p.add_argument("--mode", choices=("remove","neutralize"), default="remove")
    p.add_argument("--report", required=True)
    p.add_argument("--profile")
    p.add_argument("--pumpkin-probe", action="store_true",
                   help="Inject experimental /chosen/PumpkinMode; not actual MG override")
    args=p.parse_args()
    report=make_tree(args.raw_dtree,args.output_dtree,args.upstream,args.nvram,args.mode,
                     profile_path=args.profile, pumpkin_probe=args.pumpkin_probe)
    Path(args.report).write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))

if __name__=="__main__":
    main()
