#!/usr/bin/env python3
"""Classify ORIGINAL Apple HomeView QEMU serial output without overstating boot.

Restoration launchd (PID 1) != regular HomeView BreadBoard / Setup Assistant.
No screenshot or device capability is inferred from a serial transcript.
"""
import json
import pathlib
import re
import sys

STAGES = ("no_serial_output", "apple_bootloader", "xnu_kernel",
          "apfs_ramdisk", "apple_restore_userspace")

def classify(serial):
    bootloader = "iBoot version: qemu-sptm" in serial
    image4 = "Darwin Image4 Extension Version" in serial
    xnu = image4 and ("BSD root:" in serial or "IOService" in serial)
    apfs = xnu and "apfs_vfsop_mountroot:" in serial
    pid1 = (
        "Darwin Bootstrapper Version" in serial
        and bool(re.search(r"com\.apple\.xpc\.launchd\|.*launchd logging initialized.*pid:\s*1", serial))
    )
    restore = pid1 and "Restore environment starting." in serial
    nand = serial.count("Waiting for NAND service to publish")
    framebuffer = serial.count("unable to get framebuffer")
    framebuffer_halted = "giving up trying to create framebuffer" in serial
    progress = [float(v) for v in re.findall(
        r"ramrod_display_set_granular_progress_forced:\s*([0-9]+(?:\.[0-9]+)?)", serial
    )]
    panics = [x.strip() for x in serial.splitlines() if x.startswith("panic(cpu ")]
    if restore:
        stage = STAGES[4]
    elif apfs:
        stage = STAGES[3]
    elif xnu:
        stage = STAGES[2]
    elif bootloader:
        stage = STAGES[1]
    else:
        stage = STAGES[0]
    blockers = []
    if nand:
        blockers.append("Apple NAND service absent or not publishing")
    if framebuffer:
        blockers.append("Apple display framebuffer unavailable")
    if panics:
        blockers.append("XNU kernel panic")
    return {
        "stage": stage,
        "apple_iboot_emulator_started": bootloader,
        "xnu_started": xnu,
        "apfs_root_attempted": apfs,
        "apple_launchd_pid1_started": pid1,
        "apple_restore_userspace_started": restore,
        "apple_restore_patchd_seen": restore and "patchd:" in serial,
        "apple_restore_ramrod_seen": restore and "ramrod_display_set_" in serial,
        "nand_service_wait_count": nand,
        "framebuffer_missing_count": framebuffer,
        "framebuffer_creation_abandoned": framebuffer_halted,
        "restore_progress_max_percent": max(progress) if progress else None,
        "first_kernel_panic": panics[0] if panics else None,
        "blockers": blockers,
        "normal_homeview_os_booted": False,
        "native_apple_hello_display_verified": False,
        "native_breadboard_display_verified": False,
    }

def main():
    if len(sys.argv) != 3:
        sys.exit("usage: boot_evidence.py serial.log assessment.json")
    data=classify(pathlib.Path(sys.argv[1]).read_text(errors="replace"))
    pathlib.Path(sys.argv[2]).write_text(json.dumps(data,indent=2)+"\n")
    print(json.dumps(data,indent=2))

if __name__ == "__main__":
    main()
