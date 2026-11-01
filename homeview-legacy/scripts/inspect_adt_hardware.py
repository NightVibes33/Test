#!/usr/bin/env python3
"""Inventory real HomeAccessory17,1 J490 hardware described by original ADT.

Reads operator-prepared firmware only. Emits names/compatibility/shape of
hardware definitions, never firmware payloads or cryptographic material.
"""
import argparse
import importlib.util
import json
import pathlib

KINDS = {
    "storage": ("nand", "ans", "nvme", "apfs", "sart", "storage", "flash"),
    "display_gpu": ("gpu", "agx", "display", "dcp", "framebuffer", "fb0", "backlight", "gfx"),
    "usb_input": ("usb", "hid", "touch", "keyboard", "mouse", "spi"),
    "audio": ("audio", "speaker", "codec", "amp", "i2s", "mic"),
    "network": ("wifi", "wlan", "ethernet", "bluetooth", "bt-"),
}

def as_string(value):
    if isinstance(value, (bytes,bytearray)):
        return bytes(value).split(b"\x00",1)[0].decode("utf-8","replace")
    return str(value) if value is not None else ""

def candidates(root):
    def walk(node, base):
        name=as_string(node.props.get("name","unknown"))
        location=base+"/"+name
        fields=set(node.props)
        compatible=as_string(node.props.get("compatible", ""))
        lowered=(location+" "+compatible).lower()
        categories=[kind for kind,needles in KINDS.items() if any(t in lowered for t in needles)]
        if categories:
            yield {
                "path":location,
                "categories":categories,
                "compatible_first":compatible[:180],
                "has_reg": "reg" in fields or "reg-block" in fields,
                "has_interrupts":"interrupts" in fields,
                "property_names":sorted(str(k) for k in fields)[:60],
            }
        for child in node.children:
            yield from walk(child,location)
    return list(walk(root,""))

def report(nodes):
    totals={k:sum(k in node["categories"] for node in nodes) for k in KINDS}
    return {
        "device":"HomeAccessory17,1",
        "board":"J490AP",
        "source":"original HomeView 27.2 Apple DeviceTree (decrypted locally in CI)",
        "matching_hardware_nodes":len(nodes),
        "category_counts":totals,
        "nodes":nodes[:500],
        "apple_nand_emulation_implemented":False,
        "apple_display_emulation_implemented":False,
        "real_homeview_gui_booted":False,
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("adt")
    ap.add_argument("--upstream",required=True)
    ap.add_argument("--output",required=True)
    a=ap.parse_args()
    spec=importlib.util.spec_from_file_location("darwin_vm_dt",a.upstream)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    root=module.ADTNode()
    module.decode_node(pathlib.Path(a.adt).read_bytes(),root)
    result=report(candidates(root))
    dest=pathlib.Path(a.output)
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"category_counts":result["category_counts"],
        "matching_hardware_nodes":result["matching_hardware_nodes"]},indent=2))

if __name__=="__main__":
    main()
