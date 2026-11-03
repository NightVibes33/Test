#!/usr/bin/env python3
"""Empirical HomeView J490 QEMU boot variants, original Apple payloads only.

Uses a real XNU boot log. Never claims a graphical/usable HomeView result.
"""
import json
import os
import pathlib
import re
import subprocess
import select
import time
from boot_evidence import classify
from capture_real_guest_screen import capture
import sys

def run_variant(machine, firmware, name, device_tree, ramdisk, trustcache, dest):
    dest.mkdir(parents=True, exist_ok=True)
    debug = dest / ("qemu-" + name + ".log")
    serial = dest / ("native-homeview-" + name + "-serial.log")
    monitor = dest / ("monitor-" + name + ".sock")
    screendump = dest / ("native-homeview-guest-frame-" + name + ".ppm")
    pc_trace = dest / ("homeview-tcg-pc-" + name + ".log")
    argv = [
        str(machine), "-M", "darwin", "-bootkc", str(firmware / "bootkc"),
        "-dtree", str(device_tree), "-sptm", str(firmware / "sptm"),
        "-txm", str(firmware / "txm"), "-tc", str(trustcache),
        "-ramdisk", str(ramdisk),
        "-args", "rd=md0 serial=3 -v -noprogress wdt=-1 wlan-olyhal-abort cpus=1",
        "-m", "2G", "-display", "none", "-serial", "stdio",
        "-monitor", "unix:"+str(monitor)+",server=on,wait=off",
        "-d", "guest_errors,unimp", "-D", str(debug)
    ]
    answer = {
        "variant": name, "real_homeview_firmware": True,
        "boot_reached_userspace": False,
        "breadboard_gui_rendered": False,
        "homeview_setup_gui_rendered": False
    }
    # Preserve real guest serial output; stop when repeated missing NAND and
    # framebuffer messages make further waiting non-informative.
    env = os.environ.copy()
    # Only the first J490 boot uses the new MMIO diagnostics; control cases
    # retain the original upstream QEMU hardware behavior.
    if name in ("software-update-dock-removed-control",
                "software-update-dock-removed-pumpkin",
                "software-update-ans-binding-probe"):
        env["HOMEVIEW_MMIO_TRACE"] = "1"
    # Only the ANS diagnostic uses all original physical register windows.
    if name == "software-update-ans-binding-probe":
        env["HOMEVIEW_MMIO_ALL_WINDOWS"] = "1"
        env["HOMEVIEW_MMIO_FULL_ANS"] = "1"
    if name == "software-update-ans-binding-probe":
        path = os.environ.get("HOMEVIEW_TCG_PC_PLUGIN")
        classes_path = dest / "homeview-original-iokit-cpp-methods.json"
        # Only exact VAs from the original Apple kernelcache; no KASLR guesses.
        if path and pathlib.Path(path).is_file() and classes_path.is_file():
            from disassemble_ans2_vtables import select_targets
            classes = json.loads(classes_path.read_text())
            addresses = [x["address"] for x in select_targets(classes)]
            fingerprint_args = []
            disassembly = dest / "homeview-original-ans2-vtable-disassembly.json"
            if disassembly.is_file():
                from original_pc_signatures import plugin_args
                fingerprint_args = plugin_args(json.loads(disassembly.read_text()))
            if addresses or fingerprint_args:
                plugin = pathlib.Path(path).resolve()
                options = ["addr=" + address for address in addresses]
                options.extend(fingerprint_args)
                argv.extend(["-plugin", str(plugin) + "," + ",".join(options)])
                answer["experimental_original_code_fingerprints"] = len(fingerprint_args)
                env["HOMEVIEW_TCG_PC_TRACE_FILE"] = str(pc_trace.resolve())
                answer["pc_trace_artifact"] = pc_trace.name
                # qemu_plugin_outs uses CPU_LOG_PLUGIN, which is filtered
                # unless -d plugin is enabled in the ANS experiment.
                argv[argv.index("-d") + 1] += ",plugin"
                answer["experimental_guest_PC_trace_targets"] = addresses
        answer["guest_PC_trace_is_not_controller_start_proof"] = True
    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    chunks = bytearray()
    screen_result = None
    stop_reason = None
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
                stop_reason = "emulator exited"
                break
            recent = bytes(chunks[-120000:]).decode("utf-8", "replace")
            snapshot = classify(recent)
            if screen_result is None and snapshot["apple_restore_userspace_started"]:
                screen_result = capture(monitor, screendump)
            if (snapshot["apple_restore_userspace_started"]
                and snapshot["nand_service_wait_count"] >= 3
                and snapshot["framebuffer_missing_count"] >= 3):
                stop_reason = "Apple restore userspace blocked: no NAND or framebuffer"
                break
            if (snapshot["first_kernel_panic"]
                and "Nested panic count exceeds limit" in recent):
                stop_reason = "XNU nested kernel panic"
                break
        else:
            stop_reason = "150-second observation limit"
            answer["qemu_timed_out"] = True
    finally:
        if proc.poll() is None:
            late = capture(monitor, screendump)
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
    answer["experimental_multi_window_ANS_trace"] = name == "software-update-ans-binding-probe"
    answer["experimental_full_primary_ANS_window"] = name == "software-update-ans-binding-probe"
    answer["qemu_exit_status"] = proc.returncode
    # Preserve trace independently of the QEMU -d plugin filtering/debug file.
    if "pc_trace_artifact" in answer:
        trace_text = pc_trace.read_text(errors="replace") if pc_trace.is_file() else ""
        answer["pc_trace_initialized"] = "HOMEVIEW_PC_TRACE initialized" in trace_text
        answer["pc_trace_file_bytes"] = len(trace_text.encode("utf-8"))
        answer["pc_trace_fingerprint_hits"] = trace_text.count("HOMEVIEW_PC_TRACE fingerprint_hit ")
        answer["pc_trace_exact_pc_hits"] = trace_text.count("HOMEVIEW_PC_TRACE hit ")
        active_negative = "classification=no_hit_instrumentation_active" in trace_text
        answer["pc_trace_instrumentation_active"] = (
            "exec_callback_fired" in trace_text or "instrumentation_active=true" in trace_text)
        answer["pc_trace_no_hit_inconclusive"] = (
            not answer["pc_trace_initialized"]
            or "candidate_budget_exhausted=true" in trace_text
            or "candidate_allocation_failed=true" in trace_text
            or "classification=no_exec_callbacks_inconclusive" in trace_text
            or (
                not (answer["pc_trace_fingerprint_hits"] or answer["pc_trace_exact_pc_hits"])
                and not active_negative))
    answer["observation_stop_reason"] = stop_reason
    answer["experimental_ans_dcp_mmio_trace"] = name in (
        "software-update-dock-removed-control",
        "software-update-dock-removed-pumpkin",
        "software-update-ans-binding-probe")
    answer["qemu_real_framebuffer_probe"] = screen_result or {
        "guest_framebuffer_captured": False,
        "apple_setup_or_breadboard_verified": False,
        "reason": "No Apple restore boot stage observed"
    }
    serial.write_text(output[-250000:], encoding="utf-8")
    answer["serial_bytes"] = len(output.encode("utf-8"))
    # Native Apple bootstrapper logs use com.apple.xpc.launchd|, not launchd[PID].
    # Preserve restore/userspace evidence without claiming regular HomeView ran.
    answer.update(classify(output))
    answer["bootloader_banner_seen"] = "iBoot version: qemu-sptm" in output
    answer["image4_initialized"] = "Darwin Image4 Extension Version" in output
    answer["iokit_started"] = "IOService" in output or "AppleARMBacklight" in output
    answer["xnu_executed"] = ("Darwin Image4 Extension Version" in output and answer["iokit_started"])
    answer["first_panic"] = next((line.strip() for line in output.splitlines()
                                 if line.startswith("panic(cpu ")), None)
    answer["dock_driver_started"] = "AppleDockConnectAIC::start()" in output
    answer["launchd_seen"] = answer["apple_launchd_pid1_started"]
    # This success gate is for REGULAR HomeView, not the OTA restore ramdisk.
    answer["boot_reached_userspace"] = bool(
        answer["normal_homeview_os_booted"] and not answer["first_panic"]
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
        ("software-update-dock-removed-control", root / "dtree", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("software-update-dock-removed-pumpkin", root / "dtree.pumpkin", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("software-update-ans-binding-probe", root / "dtree.ans-probe", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("software-update-dock-neutralized", root / "dtree.neutralized", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("baseline-software-update", root / "dtree.baseline", root / "ramdisk-su.dmg", root / "ramdisk-su.tc"),
        ("baseline-restore", root / "dtree.baseline", root / "ramdisk.dmg", root / "ramdisk.tc"),
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
    pair = {
        "control": "software-update-dock-removed-control",
        "experimental": "software-update-dock-removed-pumpkin",
        "only_adt_difference_verified_by": "homeview-pumpkin-pair-verification.json",
        "comparison_complete": all(name in {a["variant"] for a in attempts}
                                   for name in ("software-update-dock-removed-control",
                                                "software-update-dock-removed-pumpkin")),
        "guest_MobileGestalt_return_observed": False,
        "device_tree_hint_is_getter_source_proven": False,
    }
    result = {
        "target": "HomeAccessory17,1 / J490", "build": "HomeView 27.2 (24V514)",
        "pumpkin_matched_pair": pair,
        "real_homeview_firmware": True,
        "native_breadboard_rendered": False, "native_setup_rendered": False,
        "boot_reached_userspace": any(x["boot_reached_userspace"] for x in attempts),
        "attempts": attempts, "best_evidence_variant": preferred["variant"],
        "genuine_apple_restore_userspace_observed": any(
            x["apple_restore_userspace_started"] for x in attempts
        ),
        "apple_nand_service_blocker_observed": any(
            x["nand_service_wait_count"] > 0 for x in attempts
        ),
        "apple_framebuffer_blocker_observed": any(
            x["framebuffer_missing_count"] > 0 for x in attempts
        ),
        "native_homeview_hello_verified": False,
        "native_homeview_breadboard_verified": False,
    }
    (output_dir / "native-homeview-kernel-result.json").write_text(json.dumps(result, indent=2) + "\n")
    if not result["boot_reached_userspace"]:
        print("ORIGINAL_HOMEVIEW_USERSPACE_NOT_REACHED; inspected native serial and panic reports.", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
