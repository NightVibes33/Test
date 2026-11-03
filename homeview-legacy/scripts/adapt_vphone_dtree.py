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
    # qemu-sptm dereferences these with no NULL check. The vphone tree is
    # kept as-is when the property is already present.
    filled = []
    for key, value in (
        ("dram-base", "u64:0x10000000000"),
        ("dram-size", "u64:0x200000000"),
    ):
        if key not in chosen.props:
            chosen.props[key] = value
            filled.append(key)
    cpu0 = root["cpus"]["cpu0"] if "cpus" in root and "cpu0" in root["cpus"] else None
    if cpu0 is not None and "clock-frequency" not in cpu0.props:
        cpu0.props["clock-frequency"] = "u32:0x100000"
        filled.append("cpus/cpu0/clock-frequency")
    defaults = root["defaults"] if "defaults" in root else None
    if defaults is not None and "vmm-present" not in defaults.props:
        defaults.props["vmm-present"] = "u32:1"
    skipped = tolerate_missing_children(mod.ADTNode)
    if "memory-map" in chosen:
        # qemu-sptm exits if these SPTM regions are absent. vphone600 has no sgx.
        mod.fixup_sptm(root)
        filled.append("chosen/memory-map SPTM regions")
    Path(output).write_bytes(mod.encode_node(root))
    arm_children = []
    if "arm-io" in root:
        arm_children = [child.props.get("name") for child in root["arm-io"].children][:40]
    return {
        "fixup": "firmware-version and missing dram",
        "firmware_version": chosen.props.get("firmware-version"),
        "filled_missing_properties": filled,
        "skipped_missing_children": skipped,
        "chosen_properties": sorted(chosen.props)[:40],
        "arm_io_children": [str(name) for name in arm_children],
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
