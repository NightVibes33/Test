#!/usr/bin/env python3
"""Device map of DeviceTree.vphone600ap, for a QEMU machine that is not `darwin`.

`reg` values in this tree are arm-io child addresses. `ranges` is
child 0, parent 0x10000000, size 0x70000000, so the guest physical
address is `reg + 0x10000000`. Those physical addresses are the ones
YahiaAngelo/qemu-vphone hardcodes in `-M vresearch101`.

Prior art, credited, not invented here:
- lakr233/vphone-cli, same board under Virtualization.framework.
- YahiaAngelo/qemu-vphone `-M vresearch101` and vphone-linux.
- QEMU `vmapple-virtio-blk-pci` (root/aux).
"""
import argparse
import json
from pathlib import Path

ARM_IO_PARENT = 0x10000000

# name, compatible, (base, size) child regs, interrupt INTIDs
DEVICES = (
    ("uart0", "arm,pl011", ((0x10010000, 0x10000),), ()),
    ("pl031-rtc", "ARM,pl031", ((0x10050000, 0x1000),), ()),
    ("pl061-buttons", "ARM,pl061", ((0x10060000, 0x1000),), (0x25,)),
    ("pvpanic", "qemu,pvpanic-mmio", ((0x10070000, 0x2),), ()),
    ("gfx", "paravirtualizedgraphics,gpu", ((0x20200000, 0x10000),), (0x31,)),
    ("iosurface-mapper", "paravirtualizedgraphics,iosurface",
     ((0x20210000, 0x10000),), (0x30,)),
    ("aes", "aes,s8000", ((0x20220000, 0x4000), (0x20230000, 0x4000)), (0x32,)),
    ("avp-rtc", "avp,rtc", ((0x20240000, 0x1000),), (0x33,)),
    ("sep", "iop-sep,vpiop", ((0x20250000, 0x10000),), (0x34, 0x35)),
    ("avp-ctrr", "avp,ctrr", ((0x20260000, 0x10000),), ()),
    ("pcie", "pcie,vmapple1", ((0x30000000, 0x10000000),), ()),
)

# First window's guest physical address in hw/vmapple/vresearch101.c.
VRESEARCH101_PHYS = {
    "uart0": 0x20010000,
    "pl031-rtc": 0x20050000,
    "pl061-buttons": 0x20060000,
    "pvpanic": 0x20070000,
    "gfx": 0x30200000,
    "iosurface-mapper": 0x30210000,
    "aes": 0x30220000,
    "avp-rtc": 0x30240000,
    "sep": 0x30250000,
    "avp-ctrr": 0x30260000,
    "pcie": 0x40000000,
}

GIC_CHILD = (
    {"base": 0x0, "size": 0x10000},
    {"base": 0x10000, "size": 0x400000},
    {"base": 0xFFF0000, "size": 0x10000},
)


def _window(base, size):
    return {
        "child_base": base,
        "guest_physical": base + ARM_IO_PARENT,
        "size": size,
    }


def _device(name, compat, regs, intids):
    return {
        "name": name,
        "compatible": compat,
        "windows": [_window(base, size) for base, size in regs],
        "interrupt_intids": list(intids),
        "spi": [value - 32 for value in intids],
        "vresearch101_first_phys": VRESEARCH101_PHYS[name],
    }


def board():
    devices = [_device(*item) for item in DEVICES]
    gic_regions = [_window(item["base"], item["size"]) for item in GIC_CHILD]
    return {
        "machine_name": "vresearch101",
        "not_the_darwin_machine": True,
        "interrupt_controller": "arm-io/gic",
        "darwin_aic_present": False,
        "arm_io": {
            "compatible": "arm-io,vmapple1",
            "device_type": "vresearch1-io",
            "ranges": {"child": 0, "parent": ARM_IO_PARENT, "size": 0x70000000},
        },
        "gic": {
            "compatible": ["gic,vmapple1", "ARM,gicv3"],
            "regions": gic_regions,
        },
        "devices": devices,
        "addresses_match_vresearch101": all(
            item["windows"][0]["guest_physical"] == item["vresearch101_first_phys"]
            for item in devices
        ) and [region["guest_physical"] for region in gic_regions] == [
            0x10000000, 0x10010000, 0x1FFF0000
        ],
        "root_disk": {
            "controller": "pcie,vmapple1",
            "guest_driver": "vmapple-virtio-blk-pci variant=root",
            "qemu_backend_id": "root-pci",
            "generic_virtio_mmio_is_the_binding": False,
        },
        "display": {
            "compatible": "paravirtualizedgraphics,gpu",
            "guest_physical": 0x30200000,
            "vram_reg_base": 0,
            "vram_reg_size": 0,
            "linear_bootloader_framebuffer": False,
            "reason": (
                "vram.reg is 0/0. chosen display-scale, display-rotation, "
                "display-corner-radius and display-boot-rotation are 0. "
                "gfx is paravirtualizedgraphics,gpu at guest physical "
                "0x30200000. There is no iBoot linear framebuffer to hand "
                "over. On Linux the host side is apple-gfx-mmio plus "
                "reims-vgpu (--enable-pvg against libreims_vgpu, not Apple's "
                "ParavirtualizedGraphics.framework). gfx-device=none maps "
                "the window as unimplemented and has nothing to screendump."
            ),
        },
        "prior_art": [
            "lakr233/vphone-cli Research/Firmware/homeview_bringup.md",
            "YahiaAngelo/qemu-vphone machine vresearch101",
            "YahiaAngelo/vphone-linux docs/ARCHITECTURE.md",
            "owngoal-dev/OpenAVB and owngoal-dev/OpenSEP",
            "QEMU hw/vmapple vmapple-virtio-blk-pci",
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    Path(args.output).write_text(json.dumps(board(), indent=2) + "\n")
    print(json.dumps({
        "devices": len(DEVICES),
        "linear_fb": False,
        "matches_vresearch101": board()["addresses_match_vresearch101"],
    }))


if __name__ == "__main__":
    main()
