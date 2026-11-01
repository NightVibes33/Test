#!/usr/bin/env python3
"""Capture only a real video framebuffer exported by the qemu-sptm HMP monitor.

No constructed Apple logo, rendered fake HomeView scene, or host Linux console.
QEMU has no native Apple display controller at present; capture can fail.
"""
import json
import pathlib
import socket

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
            answer = bytearray()
            while len(answer) < 8192:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                answer.extend(chunk)
                if b"(qemu)" in chunk:
                    break
    except (OSError, ValueError) as err:
        result["reason"] = "HMP error: " + str(err)
        return result
    result["monitor_response"] = bytes(answer).decode("utf-8", "replace")[-1000:]
    if not dest.exists() or not dest.read_bytes()[:3] == b"P6\n" or dest.stat().st_size < 4096:
        dest.unlink(missing_ok=True)
        result["reason"] = "Apple guest did not expose a QEMU RGB video surface"
        return result
    result["guest_framebuffer_captured"] = True
    result["filename"] = dest.name
    result["reason"] = "Live guest framebuffer present; Hello/BreadBoard content not independently verified"
    return result
