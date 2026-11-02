#!/usr/bin/env python3
"""Source-backed J490 MMIO / interrupt contract from ORIGINAL Apple DeviceTree.

This is an address inventory for an Intel-hosted QEMU research machine, not
an ANS/DCP/NAND controller implementation. It does not copy firmware bytes.
The layout matches jprx/qemu-sptm's arm-io/ranges[1] + adt_io_reg.base.
"""
import argparse
import importlib.util
import hashlib
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
ANS_PROPERTIES = (
    "nvme-linear-sq", "nvme-num-sl", "nvme-queue-entries",
    "nvme-interrupt-idx", "nvme-secure-bar", "nvme-tl-wa",
    "iommu-parent", "namespaces", "iop-version",
    "role", "nvme-boot-min-nvmever",
)
# These are original Apple ADT values, not Linux values. Never substitute
# QEMU guessed capabilities for the detected hardware identity.


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


def parse_reg(value, path):
    if value is None:
        return [], False
    # Child SPI/I2C/Nub registers describe addresses on their parent bus, not
    # ARM physical MMIO windows. Upstream ADT decoder expresses 4/8-byte
    # values as u32:/u64: strings. Never translate them using arm-io/ranges.
    if path.count("/") >= 2:
        return [], True
    if not isinstance(value, bytes) or len(value) % 16:
        raise ValueError("Unsupported direct arm-io MMIO reg field: " + path)
    fields = decode_u64(value, "reg")
    return [(fields[i], fields[i+1]) for i in range(0, len(fields), 2)], False


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


def describe_original_adt_property(props, key):
    """Preserve type, original scalar and bounded opaque fingerprint only."""
    if key not in props:
        return {"present": False}
    value = props[key]
    if isinstance(value, str):
        if value.startswith(("u32:", "u64:")):
            field_type, raw = value.split(":", 1)
            try:
                num = int(raw, 0)
            except ValueError:
                raise ValueError("Malformed Apple integer property: " + key)
            if num < 0 or num >= (1 << (32 if field_type == "u32" else 64)):
                raise ValueError("Apple integer out of range: " + key)
            return {"present": True, "kind": field_type, "unsigned": num,
                    "hex": hex(num)}
        if len(value) > 128:
            raise ValueError("Oversize text Apple ADT property: " + key)
        return {"present": True, "kind": "text", "value": value}
    if isinstance(value, bytes):
        if len(value) == 4:
            number = struct.unpack("<I", value)[0]
            return {"present": True, "kind": "raw-u32", "unsigned": number,
                    "hex": hex(number)}
        if len(value) == 8:
            number = struct.unpack("<Q", value)[0]
            return {"present": True, "kind": "raw-u64", "unsigned": number,
                    "hex": hex(number)}
        return {"present": True, "kind": "opaque-bytes",
                "length": len(value),
                "sha256": hashlib.sha256(value).hexdigest()}
    if isinstance(value, bool):
        return {"present": True, "kind": "boolean", "value": value}
    if isinstance(value, int):
        return {"present": True, "kind": "number", "unsigned": value,
                "hex": hex(value)}
    raise ValueError("Unsupported Apple ADT property type: " + key)


def collect(root):
    iobase, raw_ranges = parse_ranges(root)
    nodes = {}
    for path in TARGETS:
        node = get_node(root, path)
        if node is None:
            nodes[path] = {"present": False}
            continue
        regs, parent_bus_register = parse_reg(node.props.get("reg"), path)
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
            "parent_bus_register_not_MMIO": parent_bus_register,
            "interrupts_raw": parse_irq(node.props.get("interrupts")),
            "has_iommu_parent": "iommu-parent" in node.props,
            "hardware_emulated": False,
        }
    if not nodes["arm-io/ans"]["reg_windows"]:
        raise ValueError("Original Apple ANS register mapping missing")
    ans_node = get_node(root, "arm-io/ans")
    original_caps = {key: describe_original_adt_property(ans_node.props, key)
                     for key in ANS_PROPERTIES}
    return {
        "source": "original Apple J490AP DeviceTree from HomeView 24V514",
        "device": "HomeAccessory17,1",
        "arm_io_range_child_base": hex(raw_ranges[0]),
        "arm_io_phys_base": hex(iobase),
        "arm_io_range_fields": [hex(v) for v in raw_ranges[:3]],
        "qemu_reference": "jprx/qemu-sptm bad6336f hw/arm/darwin.c: arm_io_ranges[1]",
        "nodes": nodes,
        "trace_targets": list(TRACE_TARGETS),
        "ANS_original_firmware_capabilities": original_caps,
        "ANS_device_stack_components_required_not_emulated": [
            "ASC_mailbox", "RTKit", "SART_DMA_authorization",
            "NVMe_admin_and_io_queue", "NVMMU_tag_translation",
            "controller_interrupts", "backing_storage_image",
        ],
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
