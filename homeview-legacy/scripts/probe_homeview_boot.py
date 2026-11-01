#!/usr/bin/env python3
"""Empirical HomeView J490 QEMU boot variants, original Apple payloads only.

Uses a real XNU boot log. Never claims a graphical/usable HomeView result.
"""
import json
import os
import pathlib
import re
import subprocess
import sys

def run_variant(machine, firmware, name, device_tree, ramdisk, trustcache, dest):
    dest.mkdir(parents=True, exist_ok=True)
    debug = dest / ("qemu-" + name + ".log")
    serial = dest / ("native-homeview-" + name + "-serial.log")
    argv = [
        str(machine), "-M", "darwin", "-bootkc", str(firmware / "bootkc"),
        "-dtree", str(device_tree), "-sptm", str(firmware / "sptm"),
        "-txm", str(firmware / "txm"), "-tc", str(trustcache),
        "-ramdisk", str(ramdisk),
        "-args", "rd=md0 serial=3 -v -noprogress wdt=-1 wlan-olyhal-abort cpus=1",
        "-m", "2G", "-nographic", "-serial", "mon:stdio",
        "-d", "guest_errors,unimp", "-D", str(debug)
    ]
    answer = {
        "variant": name, "real_homeview_firmware": True,
        "boot_reached_userspace": False,
        "breadboard_gui_rendered": False,
        "homeview_setup_gui_rendered": False
    }
    try:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=150)
        output = proc.stdout.decode("utf-8", "replace")
        answer["qemu_exit_status"] = proc.returncode
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or b"").decode("utf-8", "replace")
        answer["qemu_timed_out"] = True
    serial.write_text(output[-250000:], encoding="utf-8")
    answer["serial_bytes"] = len(output.encode("utf-8"))
    answer["bootloader_banner_seen"] = "iBoot version: qemu-sptm" in output
    answer["image4_initialized"] = "Darwin Image4 Extension Version" in output
    answer["iokit_started"] = "IOService" in output or "AppleARMBacklight" in output
    answer["xnu_executed"] = ("Darwin Image4 Extension Version" in output and answer["iokit_started"])
    answer["first_panic"] = next((line.strip() for line in output.splitlines()
                                 if line.startswith("panic(cpu ")), None)
    answer["dock_driver_started"] = "AppleDockConnectAIC::start()" in output
    answer["launchd_seen"] = bool(re.search(r"(?:launchd\[\d+\]|launchd:)", output, re.I))
    answer["boot_reached_userspace"] = bool(
        answer["xnu_executed"] and answer["launchd_seen"] and not answer["first_panic"]
    )
    answer["serial_path"] = serial.name
    answer["debug_log"] = debug.name
    answer["serial_excerpt"] = output[-3000:]
    (dest / ("homeview-" + name + "-result.json")).write_text(json.dumps(answer, indent=2) + "\n")
    print(json.dumps({k:v for k,v in answer.items() if k != "serial_excerpt"}, indent=2), flush=True)
    return answer

def main():
    root = pathlib.Path(os.environ["RUNNER_TEMP"]) / "hv-firmware"
    output_dir = pathlib.Path("out")
    machine = pathlib.Path("emulator/build/qemu-system-aarch64").resolve()
    attempts = []
    for name, path, ramdisk, trustcache in [
        ("baseline-restore", root / "dtree.baseline", root / "ramdisk.dmg", root / "ramdisk.tc"),
        ("baseline-software-update", root / "dtree.baseline", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("software-update-dock-removed", root / "dtree", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("software-update-dock-neutralized", root / "dtree.neutralized", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
    ]:
        if not path.exists() or not path.stat().st_size:
            raise SystemExit("Missing real device-tree variant " + str(path))
        for required in (ramdisk, trustcache):
            if not required.exists() or not required.stat().st_size:
                raise SystemExit("Missing original Apple software-update or restore image " + str(required))
        attempts.append(run_variant(machine, root, name, path, ramdisk, trustcache, output_dir))
        if attempts[-1]["boot_reached_userspace"]:
            break
    preferred = max(attempts, key=lambda x:(
        x["boot_reached_userspace"], x["xnu_executed"], bool(x["serial_bytes"])
    ))
    result = {
        "target": "HomeAccessory17,1 / J490", "build": "HomeView 27.2 (24V514)",
        "real_homeview_firmware": True,
        "native_breadboard_rendered": False, "native_setup_rendered": False,
        "boot_reached_userspace": any(x["boot_reached_userspace"] for x in attempts),
        "attempts": attempts, "best_evidence_variant": preferred["variant"],
    }
    (output_dir / "native-homeview-kernel-result.json").write_text(json.dumps(result, indent=2) + "\n")
    if not result["boot_reached_userspace"]:
        print("ORIGINAL_HOMEVIEW_USERSPACE_NOT_REACHED; inspected native serial and panic reports.", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
