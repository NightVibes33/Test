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

# Short path: QEMU's HMP readline redraws and can drop a long workspace path.
STAGE = pathlib.Path("/tmp/hv-screendump.ppm")


def _valid_ppm(dest):
    dest = pathlib.Path(dest)
    if not dest.is_file() or dest.stat().st_size < 4096:
        return False
    return dest.read_bytes()[:3] == b"P6\n"


def wait_for_ppm(path, timeout=8.0):
    """Wait until a screendump is a stable P6 file. Does not invent pixels."""
    path = pathlib.Path(path)
    deadline = time.monotonic() + timeout
    last = -1
    stable = 0
    while time.monotonic() < deadline:
        if path.is_file():
            size = path.stat().st_size
            if size >= 4096 and size == last and path.read_bytes()[:3] == b"P6\n":
                stable += 1
                if stable >= 2:
                    return True
            else:
                stable = 0
            last = size
        time.sleep(0.15)
    return _valid_ppm(path)


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


def publish_surface(dest, monitor_response=""):
    """Keep a real screendump. Never label it as an Apple framebuffer."""
    dest = pathlib.Path(dest)
    result = {
        "source": "qemu-sptm live guest HMP screendump",
        "guest_framebuffer_captured": False,
        "apple_setup_or_breadboard_verified": False,
        "surface_is_apple_display_service": False,
        "qemu_monitor_surface_captured": False,
        "monitor_response": monitor_response[-1000:],
    }
    if not _valid_ppm(dest):
        result["reason"] = "Apple guest did not expose a QEMU RGB video surface"
        return result
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


def capture(monitor, dest):
    monitor, dest = pathlib.Path(monitor), pathlib.Path(dest)
    if _valid_ppm(dest):
        return publish_surface(dest, "existing screendump kept")
    if not monitor.exists():
        return publish_surface(dest, "QEMU monitor socket not available")
    stage = STAGE
    if not _valid_ppm(stage):
        stage.unlink(missing_ok=True)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(5)
            conn.connect(str(monitor))
            try:
                conn.recv(4096)
            except socket.timeout:
                pass
            path = stage.as_posix()
            if any(char.isspace() for char in path):
                raise ValueError("path contains whitespace")
            conn.sendall(("screendump " + path + "\n").encode("ascii"))
            conn.settimeout(0.25)
            answer = bytearray()
            deadline = time.monotonic() + 8.0
            while time.monotonic() < deadline and len(answer) < 16384:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    chunk = b""
                if chunk:
                    answer.extend(chunk)
                if _valid_ppm(stage):
                    break
                time.sleep(0.1)
            if _valid_ppm(stage):
                wait_for_ppm(stage, timeout=1.5)
    except (OSError, ValueError) as err:
        return publish_surface(dest, "HMP error: " + str(err))
    if _valid_ppm(stage):
        dest.write_bytes(stage.read_bytes())
    return publish_surface(dest, bytes(answer).decode("utf-8", "replace"))
