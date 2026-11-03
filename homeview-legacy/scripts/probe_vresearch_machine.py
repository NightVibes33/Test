#!/usr/bin/env python3
"""Boot OpenAVB on qemu-vphone -M vresearch101 and record the display result.

The ROMs are the open-source OpenAVB and OpenSEP images shipped by
lakr233/vphone-cli (owngoal-dev/OpenAVB and owngoal-dev/OpenSEP). No Apple
firmware is loaded. The root drive is a blank image on the Apple virtio-blk
root function (backend id root-pci). It is not the HomeView payload volume.

gfx-device=none is the only display this binary has when it was built
without reims-vgpu. vram.reg in DeviceTree.vphone600ap is 0/0, so a
screendump of this run is not a BreadBoard frame.
"""
import hashlib
import json
import os
import pathlib
import socket
import subprocess
import time

OPENAVB_SHA256 = "bbcabe73fd39fb92b96fbb4c661c1a15b0f9e5d9411468f7954c4f433911cb9c"
OPENSEP_SHA256 = "92690b9c7e900ec0054271dbbc0444ee2d8567c8d41d3a2e491ba011e2b08b12"
OPENAVB_URL = (
    "https://github.com/Lakr233/vphone-cli/raw/main/"
    "VPhoneExecutable/VPhoneVirtualization/Resources/OpenAVB/OpenAVB.bin"
)
OPENSEP_URL = (
    "https://github.com/Lakr233/vphone-cli/raw/main/"
    "VPhoneExecutable/VPhoneVirtualization/Resources/OpenSEP/OpenSEP.bin"
)


def qemu_argv(qemu, bios, sep_rom, aux, root, serial, debug, monitor):
    machine = ",".join((
        "vresearch101",
        "gfx-device=none",
        "ecid=1",
        "sep-rom=" + str(sep_rom),
    ))
    locking = "file.locking=off"
    return [
        str(qemu),
        "-machine", machine,
        "-accel", "tcg,tb-size=64",
        "-smp", "1,maxcpus=2",
        "-m", "4G",
        "-bios", str(bios),
        "-drive", f"file={aux},if=pflash,format=raw,offset=16384,{locking}",
        "-drive", f"file={root},if=pflash,format=raw,{locking}",
        "-drive", f"file={root},if=none,id=root-pci,format=raw,{locking}",
        "-drive", f"file={aux},if=none,id=aux-pci,format=raw,offset=16384,{locking}",
        "-display", "none",
        "-serial", "file:" + str(serial),
        "-monitor", "unix:" + str(monitor) + ",server=on,wait=off",
        "-d", "guest_errors,unimp",
        "-D", str(debug),
    ]


def interpret(serial_text, qemu_text, returncode, ran_seconds, screendump_reply):
    lived = ran_seconds >= 3 and returncode is None
    reply = screendump_reply or ""
    captured = "screendump_wrote_ppm" in reply and "BreadBoard" not in reply
    # A ppm from gfx-device=none is not a guest framebuffer. Never treat it
    # as one, and never treat serial text as pixels.
    return {
        "machine": "vresearch101",
        "credit": [
            "lakr233/vphone-cli OpenAVB and OpenSEP",
            "owngoal-dev/OpenAVB",
            "owngoal-dev/OpenSEP",
            "YahiaAngelo/qemu-vphone",
        ],
        "gfx_device": "none",
        "linear_bootloader_framebuffer": False,
        "root_disk_backend": "vmapple-virtio-blk-pci variant=root id=root-pci",
        "attached_disk_is_homeview_root": False,
        "attached_disk_note": (
            "Blank 64MiB image. The 13.9GB payload APFS was an extracted "
            "file tree, larger than the ramdisk slot and the Actions cache, "
            "and is not a restored vphone Disk.img."
        ),
        "machine_stayed_up": lived,
        "qemu_returncode": returncode,
        "ran_seconds": round(ran_seconds, 3),
        "serial_bytes": len(serial_text),
        "serial_excerpt": serial_text[:2000],
        "qemu_excerpt": qemu_text[:2000],
        "screendump_reply": reply[:500],
        "guest_framebuffer_captured": False,
        "breadboard_boot_proven": False,
        "display_wall": (
            "gfx-device=none has no scanout. BreadBoard pixels need "
            "apple-gfx-mmio linked to reims-vgpu and a restored system "
            "disk, which this smoke does not have."
        ) if lived or returncode == 0 else "QEMU did not stay up",
        "ppm_was_written": captured,
    }


def _sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _screendump(monitor, ppm):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(3)
    try:
        sock.connect(str(monitor))
        greeting = sock.recv(256)
        sock.sendall(b"screendump " + str(ppm).encode() + b"\n")
        reply = sock.recv(1024)
    except OSError as exc:
        return "monitor_connect_failed: " + str(exc)
    finally:
        sock.close()
    text = (greeting + reply).decode("utf-8", "replace").replace("\r", "")
    if ppm.is_file() and ppm.stat().st_size > 16:
        return "screendump_wrote_ppm " + text
    return text


def _blank(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as handle:
        handle.truncate(64 * 1024 * 1024)


def main():
    out = pathlib.Path(os.environ.get("VRESEARCH_OUT", "out"))
    out.mkdir(parents=True, exist_ok=True)
    qemu = pathlib.Path(os.environ["VRESEARCH_QEMU"])
    bios = pathlib.Path(os.environ["VRESEARCH_BIOS"])
    sep = pathlib.Path(os.environ["VRESEARCH_SEP"])
    report = {
        "boot_attempted": False,
        "breadboard_boot_proven": False,
        "guest_framebuffer_captured": False,
        "linear_bootloader_framebuffer": False,
    }
    hashes = {
        "openavb": _sha256(bios) if bios.is_file() else None,
        "opensep": _sha256(sep) if sep.is_file() else None,
    }
    report["rom_sha256"] = hashes
    report["rom_sha256_expected"] = {
        "openavb": OPENAVB_SHA256,
        "opensep": OPENSEP_SHA256,
    }
    if hashes["openavb"] != OPENAVB_SHA256 or hashes["opensep"] != OPENSEP_SHA256:
        report["reason"] = "open ROM hash mismatch or missing file"
        (out / "homeview-vresearch-boot.json").write_text(
            json.dumps(report, indent=2) + "\n")
        print(json.dumps({"attempted": False, "reason": report["reason"]}))
        return 1
    if not qemu.is_file():
        report["reason"] = "qemu binary missing"
        (out / "homeview-vresearch-boot.json").write_text(
            json.dumps(report, indent=2) + "\n")
        print(json.dumps({"attempted": False, "reason": report["reason"]}))
        return 1
    aux = out / "vresearch-aux.img"
    root = out / "vresearch-root.img"
    _blank(aux)
    _blank(root)
    serial = out / "vresearch-serial.log"
    debug = out / "vresearch-qemu.log"
    monitor = out / "vresearch-monitor.sock"
    ppm = out / "vresearch-screendump.ppm"
    argv = qemu_argv(qemu, bios, sep, aux, root, serial, debug, monitor)
    started = time.monotonic()
    proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    reply = ""
    try:
        time.sleep(8)
        if proc.poll() is None:
            reply = _screendump(monitor, ppm)
        deadline = started + 25
        while time.monotonic() < deadline and proc.poll() is None:
            time.sleep(0.5)
        stayed = proc.poll() is None
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    ran = time.monotonic() - started
    serial_text = serial.read_text("utf-8", "replace") if serial.is_file() else ""
    qemu_text = debug.read_text("utf-8", "replace") if debug.is_file() else ""
    code = None if stayed else proc.returncode
    report.update(interpret(serial_text, qemu_text, code, ran, reply))
    report["boot_attempted"] = True
    report["guest_framebuffer_captured"] = False
    report["breadboard_boot_proven"] = False
    (out / "homeview-vresearch-boot.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({
        "attempted": True,
        "stayed_up": report["machine_stayed_up"],
        "serial_bytes": report["serial_bytes"],
        "framebuffer": False,
    }))
    return 0 if report["machine_stayed_up"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
