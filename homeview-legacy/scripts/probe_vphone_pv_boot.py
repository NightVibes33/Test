#!/usr/bin/env python3
"""Boot the vphone600 research kernel in qemu-sptm.

The kernel, device tree, and ramdisk come from the cloudOS 26.4 image that
lakr233/vphone-cli pairs with HomeView. This does not implement
Virtualization.framework graphics and does not claim a BreadBoard frame.
"""
import json
import os
import pathlib
import subprocess
import select
import sys
import time

from boot_evidence import classify
from capture_real_guest_screen import capture
from vphone_homeview_path import plan


def main():
    root = pathlib.Path(os.environ["RUNNER_TEMP"]) / "hv-vphone"
    out = pathlib.Path("out")
    out.mkdir(parents=True, exist_ok=True)
    machine = pathlib.Path("emulator/build/qemu-system-aarch64").resolve()
    required = {
        "bootkc": root / "bootkc",
        "dtree": root / "dtree",
        "sptm": root / "sptm",
        "txm": root / "txm",
        "ramdisk": root / "ramdisk.dmg",
        "tc": root / "ramdisk.tc",
    }
    missing = [name for name, path in required.items() if not path.is_file() or path.stat().st_size < 64]
    report = plan(27, False)
    report["variant"] = "vphone600-research-kernel"
    report["missing_components"] = missing
    if missing or not machine.is_file():
        report["boot_attempted"] = False
        report["reason"] = "missing " + ",".join(missing or ["qemu"])
        (out / "homeview-vphone-pv-result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"attempted": False, "missing": missing}))
        return 2
    serial_path = out / "native-homeview-vphone600-serial.log"
    debug_path = out / "qemu-vphone600.log"
    monitor = out / "monitor-vphone600.sock"
    screen = out / "native-homeview-guest-frame-vphone600.ppm"
    argv = [
        str(machine), "-M", "darwin",
        "-bootkc", str(required["bootkc"]),
        "-dtree", str(required["dtree"]),
        "-sptm", str(required["sptm"]),
        "-txm", str(required["txm"]),
        "-tc", str(required["tc"]),
        "-ramdisk", str(required["ramdisk"]),
        "-args", "rd=md0 serial=3 -v -noprogress wdt=-1 cpus=1",
        "-m", "8G",
        "-display", "none", "-serial", "stdio",
        "-monitor", "unix:" + str(monitor) + ",server=on,wait=off",
        "-d", "guest_errors,unimp", "-D", str(debug_path),
    ]
    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    chunks = bytearray()
    screen_result = None
    deadline = time.monotonic() + 150
    try:
        os.set_blocking(proc.stdout.fileno(), False)
        while time.monotonic() < deadline:
            ready, _, _ = select.select([proc.stdout], [], [], 0.35)
            if ready:
                try:
                    chunk = os.read(proc.stdout.fileno(), 65536)
                except BlockingIOError:
                    chunk = b""
                if chunk:
                    chunks.extend(chunk)
            if proc.poll() is not None:
                break
            text = bytes(chunks).decode("utf-8", "replace")
            if "BreadBoard" in text and screen_result is None:
                screen_result = capture(monitor, screen)
        else:
            report["qemu_timed_out"] = True
    finally:
        if proc.poll() is None:
            late = capture(monitor, screen)
            if late.get("qemu_monitor_surface_captured"):
                screen_result = late
            proc.terminate()
        try:
            rest, _ = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            rest, _ = proc.communicate(timeout=5)
        chunks.extend(rest or b"")
        monitor.unlink(missing_ok=True)
    output = bytes(chunks).decode("utf-8", "replace")
    serial_path.write_text(output[-250000:], encoding="utf-8")
    evidence = classify(output)
    report.update({
        "boot_attempted": True,
        "qemu_exit_status": proc.returncode,
        "breadboard_process_seen": "BreadBoard" in output,
        "backboardd_seen": "backboardd" in output,
        "apple_framebuffer_blocker_observed": evidence.get("framebuffer_missing_count", 0) > 0,
        "qemu_real_framebuffer_probe": screen_result or {
            "guest_framebuffer_captured": False,
            "apple_setup_or_breadboard_verified": False,
        },
        "breadboard_boot_proven": False,
        "serial_excerpt": output[-2000:],
    })
    (out / "homeview-vphone-pv-result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "breadboard_seen": report["breadboard_process_seen"],
        "framebuffer": report["qemu_real_framebuffer_probe"].get("guest_framebuffer_captured"),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
