#!/usr/bin/env python3
"""Prove pinned QEMU loads the read-only HomeView plugin before Apple OTA fetch.

-M none does not execute Apple firmware and cannot prove a guest PC hit.
This checks actual dynamic plugin loading, API version, and -d plugin logging.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

MARKER = "HOMEVIEW_PC_TRACE initialized targets=1 read_only=true"
TEST_PC = "0xfffffff009b0dabc"


def command(qemu, plugin, logfile):
    return [
        str(qemu), "-M", "none", "-S", "-display", "none",
        "-monitor", "none", "-serial", "none",
        "-plugin", str(plugin) + ",addr=" + TEST_PC,
        "-d", "plugin", "-D", str(logfile),
    ]


def verify(qemu, plugin, timeout=7, runner=subprocess.Popen):
    qemu, plugin = Path(qemu), Path(plugin)
    if not qemu.is_file() or not plugin.is_file():
        raise ValueError("QEMU executable or compiled TCG plugin is missing")
    with tempfile.TemporaryDirectory(prefix="homeview-tcg-smoke-") as temp:
        log = Path(temp) / "qemu-plugin.log"
        argv = command(qemu, plugin, log)
        proc = runner(argv, stdin=subprocess.DEVNULL,
                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        expired = False
        try:
            output, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            expired = True
            proc.terminate()
            try:
                output, _ = proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                output, _ = proc.communicate(timeout=3)
        text = (log.read_text(errors="replace") if log.is_file() else "")
        if output:
            text += "\n" + output.decode("utf-8", "replace")
        if MARKER not in text:
            raise RuntimeError(
                "QEMU did not initialize the real API v7 HomeView plugin: "
                + "\n".join(text.splitlines()[-20:])[:1600])
        if not expired and proc.returncode not in (None, 0):
            raise RuntimeError("QEMU exited with error after plugin initialization")
        return {
            "qemu_plugin_dynamic_load_verified": True,
            "QEMU_plugin_logging_mask_active": True,
            "test_executed_Apple_instructions": False,
            "test_established_controller_start": False,
            "guest_firmware_used": False,
            "test_program_counter": TEST_PC,
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qemu", required=True)
    parser.add_argument("--plugin", required=True)
    args = parser.parse_args()
    result = verify(args.qemu, args.plugin)
    print("HOMEVIEW_TCG_PLUGIN_SMOKE_PASSED:", result)


if __name__ == "__main__":
    main()
