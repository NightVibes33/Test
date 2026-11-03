#!/usr/bin/env python3
"""The HomeView boot path that lakr233/vphone-cli already proved.

Credit: https://github.com/lakr233/vphone-cli/blob/main/Research/Firmware/homeview_bringup.md
The working guest is not the J490 hardware kernel. It is the Apple TV HD
restore base, HomeView 27.2 userland from the OTA, and the cloudOS 26.4
vphone600 research kernel, whose display is paravirtual.
"""
import argparse
import json
from pathlib import Path

CREDIT = "lakr233/vphone-cli Research/Firmware/homeview_bringup.md"

# cloudOS 26.4 beta, the last image that still contains vphone600ap.
CLOUDOS_URL = (
    "https://updates.cdn-apple.com/private-cloud-compute/"
    "c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ada27273262b0b8b64"
)
CLOUDOS_BYTES = 1199454323

RESTORE_BASE_URL = (
    "https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-67287/"
    "F525C1FF-B49B-40AB-A5F4-A6F4A4847407/AppleTV5,3_26.6_23L773_Restore.ipsw"
)


def plan(macos_major, pvg_compiled):
    display = bool(pvg_compiled) and int(macos_major) < 27
    return {
        "credit": CREDIT,
        "guest_model": "HomeAccessory17,1",
        "userland_build": "24V514",
        "restore_base": {
            "device": "AppleTV5,3",
            "board": "J42dAP",
            "version": "26.6",
            "build": "23L773",
            "url": RESTORE_BASE_URL,
            "role": "filesystem the OTA userland replaces",
        },
        "boot_kernel": {
            "image": "cloudOS 26.4 (23E5207q)",
            "url": CLOUDOS_URL,
            "bytes": CLOUDOS_BYTES,
            "kernel": "kernelcache.research.vphone600",
            "device_tree": "Firmware/all_flash/DeviceTree.vphone600ap.im4p",
            "sptm": "Firmware/sptm.vresearch1.release.im4p",
            "txm": "Firmware/txm.iphoneos.research.im4p",
            "ramdisk": "094-39914-031.dmg",
            "trustcache": "Firmware/094-39914-031.dmg.trustcache",
        },
        "display": {
            "vphone_framebuffer": "1088x1088 via Virtualization.framework",
            "qemu_pvg_compiled": bool(pvg_compiled),
            "host_macos_major": int(macos_major),
            "qemu_can_present_pv_framebuffer": display,
            "blocker": None if display else (
                "macOS 27 obsoletes ParavirtualizedGraphics.framework PGTask_t, "
                "so qemu-sptm is built with --disable-pvg and its darwin machine "
                "has no display device"),
        },
        "sandbox_repairs_from_vphone": [
            "BreadBoard mach-lookup com.apple.backboard.display.services",
            "userprofilesd mach-lookup com.apple.mobile.keybagd.UserManager.xpc",
        ],
        "setup_bypass": "ForceNoBuddy only; SetupDone stays untouched",
        "j490_hardware_kernel_is_the_display_path": False,
        "breadboard_boot_proven": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--macos-major", type=int, required=True)
    parser.add_argument("--pvg-compiled", action="store_true")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = plan(args.macos_major, args.pvg_compiled)
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"pv_framebuffer": report["display"]["qemu_can_present_pv_framebuffer"]}))


if __name__ == "__main__":
    main()
