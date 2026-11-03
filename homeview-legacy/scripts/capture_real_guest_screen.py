#!/usr/bin/env python3
"""Capture only a real video framebuffer exported by the qemu-sptm HMP monitor.

No constructed Apple logo, rendered fake HomeView scene, or host Linux console.
QEMU has no native Apple display controller at present; capture can fail.
"""
import json
import pathlib
import socket
import struct
import time
import zlib

def _valid_ppm(dest):
    if not dest.exists() or dest.stat().st_size < 4096:
        return False
    return dest.read_bytes()[:3] == b"P6\n"


def write_png(ppm_path, png_path):
    """Lossless conversion of a real QEMU screendump. No drawn pixels."""
    blob = pathlib.Path(ppm_path).read_bytes()
    if not blob.startswith(b"P6\n"):
        raise ValueError("screendump is not a binary P6 PPM")
    pos = 0
    tokens = []
    while len(tokens) < 4:
        while pos < len(blob) and blob[pos] in b" \t\r\n":
            pos += 1
        start = pos
        while pos < len(blob) and blob[pos] not in b" \t\r\n":
            pos += 1
        if pos == start:
            raise ValueError("invalid PPM header")
        tokens.append(blob[start:pos])
    if tokens[0] != b"P6" or tokens[3] != b"255":
        raise ValueError("unexpected QEMU framebuffer pixel format")
    width, height = int(tokens[1]), int(tokens[2])
    if not (64 <= width <= 8192 and 64 <= height <= 8192):
        raise ValueError("QEMU framebuffer dimensions invalid")
    pos += 1
    pixels = blob[pos:]
    if len(pixels) != width * height * 3:
        raise ValueError("PPM framebuffer payload length mismatch")
    pitch = width * 3
    filtered = b"".join(b"\x00" + pixels[i:i + pitch] for i in range(0, len(pixels), pitch))

    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(filtered, 6))
           + chunk(b"IEND", b""))
    pathname = pathlib.Path(png_path)
    pathname.write_bytes(png)
    return {"width": width, "height": height, "png_bytes": len(png)}


def capture(monitor, dest):
    monitor, dest = pathlib.Path(monitor), pathlib.Path(dest)
    result = {"source": "qemu-sptm live guest HMP screendump",
              "guest_framebuffer_captured": False,
              "apple_setup_or_breadboard_verified": False}
    if not monitor.exists():
        result["reason"] = "QEMU monitor socket not available"
        return result
    dest.unlink(missing_ok=True)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(5)
            conn.connect(str(monitor))
            try:
                conn.recv(4096)
            except socket.timeout:
                pass
            path = dest.resolve().as_posix()
            if any(char.isspace() for char in path):
                raise ValueError("path contains whitespace")
            conn.sendall(("screendump "+path+"\r\n").encode("ascii"))
            conn.settimeout(0.25)
            answer = bytearray()
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline and len(answer) < 8192:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    chunk = b""
                if chunk:
                    answer.extend(chunk)
                if _valid_ppm(dest):
                    break
                if not chunk:
                    time.sleep(0.05)
    except (OSError, ValueError) as err:
        result["reason"] = "HMP error: " + str(err)
        return result
    result["monitor_response"] = bytes(answer).decode("utf-8", "replace")[-1000:]
    result["apple_setup_or_breadboard_verified"] = False
    result["surface_is_apple_display_service"] = False
    if not _valid_ppm(dest):
        dest.unlink(missing_ok=True)
        result["guest_framebuffer_captured"] = False
        result["qemu_monitor_surface_captured"] = False
        result["reason"] = "Apple guest did not expose a QEMU RGB video surface"
        return result
    # A QEMU HMP surface can be the default parallel console. Keep the bytes,
    # and do not promote them to an Apple framebuffer or HomeView GUI.
    result["guest_framebuffer_captured"] = False
    result["qemu_monitor_surface_captured"] = True
    result["filename"] = dest.name
    result["reason"] = (
        "HMP screendump wrote a QEMU video surface. "
        "This is not an Apple framebuffer and not a HomeView GUI."
    )
    try:
        png = dest.with_suffix(".png")
        result["png"] = write_png(dest, png)
        result["png"]["filename"] = png.name
    except (OSError, ValueError) as err:
        result["png_error"] = str(err)
    return result
