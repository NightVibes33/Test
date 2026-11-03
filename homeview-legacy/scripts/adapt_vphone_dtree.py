#!/usr/bin/env python3
"""Prepare a vphone600 device tree for qemu-sptm.

lakr233/vphone-cli boots this tree under Virtualization.framework. qemu-sptm's
darwin machine still needs its firmware-version and memory-map fixup. The
upstream fixup removes dockchannel-uart, which this virtual board does not
have, so a missing child is skipped instead of aborting the boot.
"""
import argparse
import importlib.util
import json
from pathlib import Path


def tolerate_missing_children(node_cls):
    original = node_cls.remove_child
    skipped = []

    def remove_child(self, child_name):
        try:
            original(self, child_name)
        except ValueError:
            skipped.append(str(child_name))

    node_cls.remove_child = remove_child
    return skipped


def adapt(raw, output, upstream_path, nvram_path):
    """Set only the firmware name qemu-sptm checks.

    The full darwin-vm fixup rewrites an iPhone board and crashes on this
    virtual tree, which has no dockchannel-uart and no uart interrupt-parent.
    """
    del nvram_path
    spec = importlib.util.spec_from_file_location("darwin_vm_dt_fixup", upstream_path)
    if spec is None or spec.loader is None:
        raise ValueError("Cannot load upstream darwin-vm ADT fixup")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    root = mod.ADTNode()
    mod.decode_node(Path(raw).read_bytes(), root)
    chosen = root["chosen"]
    chosen.props["firmware-version"] = "qemu-sptm"
    chosen.props["system-firmware-version"] = "qemu-sptm"
    defaults = root["defaults"] if "defaults" in root else None
    if defaults is not None and "vmm-present" not in defaults.props:
        defaults.props["vmm-present"] = "u32:1"
    Path(output).write_bytes(mod.encode_node(root))
    return {
        "fixup": "firmware-version only",
        "firmware_version": chosen.props.get("firmware-version"),
        "vmm_present": None if defaults is None else defaults.props.get("vmm-present"),
        "output_bytes": Path(output).stat().st_size,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("raw")
    parser.add_argument("output")
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--nvram", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    report = adapt(args.raw, args.output, args.upstream, args.nvram)
    Path(args.report).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
