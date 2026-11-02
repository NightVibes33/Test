#!/usr/bin/env python3
"""Source-backed J490 MMIO / interrupt contract from ORIGINAL Apple DeviceTree.

This is an address inventory for an Intel-hosted QEMU research machine, not
an ANS/DCP/NAND controller implementation. It does not copy firmware bytes.
The layout matches jprx/qemu-sptm's arm-io/ranges[1] + adt_io_reg.base.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import struct

TARGETS = (
    "arm-io/ans", "arm-io/ans/iop-ans-nub", "arm-io/sart-ans",
    "arm-io/dcp", "arm-io/dcp/iop-dcp-nub", "arm-io/dcp0-expert",
    "arm-io/dart-dcp", "arm-io/gfx-asc", "arm-io/sgx",
    "arm-io/spi1", "arm-io/spi1/multi-touch", "arm-io/usb-drd",
    "arm-io/i2c1/audio-speaker",
)
TRACE_TARGETS = ("arm-io/ans", "arm-io/sart-ans", "arm-io/dcp",
                 "arm-io/dcp0-expert", "arm-io/sgx")


def get_node(root, path):
    node = root
    for part in path.split("/"):
        found = [c for c in node.children if c.props.get("name") == part]
        if len(found) != 1:
            return None
        node = found[0]
    return node


def decode_u64(value, label):
    if not isinstance(value, bytes) or len(value) % 8:
        raise ValueError(label + " must be aligned raw u64 bytes")
    return struct.unpack("<" + "Q" * (len(value) // 8), value)


def parse_ranges(root):
    arm = get_node(root, "arm-io")
    if arm is None:
        raise ValueError("Missing Apple arm-io node")
    fields = decode_u64(arm.props.get("ranges"), "arm-io/ranges")
    if len(fields) < 3 or fields[0] != 0:
        raise ValueError("Unsupported arm-io range translation")
    return fields[1], fields


def parse_reg(value):
    if value is None:
        return []
    if not isinstance(value, bytes) or len(value) % 16:
        raise ValueError("Unsupported Apple reg field: must be pairs of u64")
    fields = decode_u64(value, "reg")
    return [(fields[i], fields[i+1]) for i in range(0, len(fields), 2)]


def parse_irq(value):
    if value is None:
        return []
    if isinstance(value, str) and value.startswith("u32:"):
        return [int(value[4:], 0)]
    if isinstance(value, bytes) and len(value) % 4 == 0:
        return list(struct.unpack("<" + "I" * (len(value)//4), value))
    raise ValueError("Unknown original Apple interrupts encoding")


def first_compatible(value):
    if isinstance(value, bytes):
        return value.split(b"\x00", 1)[0].decode("utf-8", "replace")
    return value if isinstance(value, str) else None


def collect(root):
    iobase, raw_ranges = parse_ranges(root)
    nodes = {}
    for path in TARGETS:
        node = get_node(root, path)
        if node is None:
            nodes[path] = {"present": False}
            continue
        regs = parse_reg(node.props.get("reg"))
        entries = []
        for offset, length in regs:
            if offset + iobase > 0xFFFFFFFFFFFFFFFF or length > 0xFFFFFFFFFFFFFFFF - (offset + iobase):
                raise ValueError("MMIO address overflow: " + path)
            entries.append({"relative_offset": hex(offset),
                            "guest_physical_base": hex(iobase + offset),
                            "length": hex(length)})
        nodes[path] = {
            "present": True,
            "original_compatible": first_compatible(node.props.get("compatible")),
            "reg_windows": entries,
            "interrupts_raw": parse_irq(node.props.get("interrupts")),
            "has_iommu_parent": "iommu-parent" in node.props,
            "hardware_emulated": False,
        }
    if not nodes["arm-io/ans"]["reg_windows"]:
        raise ValueError("Original Apple ANS register mapping missing")
    return {
        "source": "original Apple J490AP DeviceTree from HomeView 24V514",
        "device": "HomeAccessory17,1",
        "arm_io_range_child_base": hex(raw_ranges[0]),
        "arm_io_phys_base": hex(iobase),
        "arm_io_range_fields": [hex(v) for v in raw_ranges[:3]],
        "qemu_reference": "jprx/qemu-sptm bad6336f hw/arm/darwin.c: arm_io_ranges[1]",
        "nodes": nodes,
        "trace_targets": list(TRACE_TARGETS),
        "driver_binding_verified": False,
        "controller_emulation_implemented": False,
        "native_homeview_display_verified": False,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("raw_dtree")
    p.add_argument("--upstream", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()
    spec = importlib.util.spec_from_file_location("original_apple_dt", args.upstream)
    if not spec or not spec.loader:
        raise ValueError("Missing Apple DeviceTree decoder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    root = module.ADTNode()
    module.decode_node(Path(args.raw_dtree).read_bytes(), root)
    data = collect(root)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps({"device": data["device"], "mmio_base": data["arm_io_phys_base"],
                      "nodes": {k: len(v.get("reg_windows", []))
                                for k, v in data["nodes"].items()}}))


if __name__ == "__main__":
    main()
