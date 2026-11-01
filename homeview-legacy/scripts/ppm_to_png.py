#!/usr/bin/env python3
"""Convert an actual QEMU HMP screendump P6 framebuffer into an unmodified PNG.

No compositing, synthetic HomeView UI, overlays, or generated pixels.
"""
import json
import pathlib
import struct
import sys
import zlib

def png_chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))

def convert(ppm_path, png_path):
    blob = pathlib.Path(ppm_path).read_bytes()
    if not blob.startswith(b"P6\n"):
        raise ValueError("screendump is not a binary P6 PPM")
    # PPM produced by QEMU: P6, dimensions, maxval 255, raw RGB pixels.
    pos = 0
    tokens = []
    while len(tokens) < 4:
        while pos < len(blob) and blob[pos] in b" \t\r\n":
            pos += 1
        if pos < len(blob) and blob[pos] == 35:  # comment
            pos = blob.index(b"\n", pos) + 1
            continue
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
    if pos >= len(blob) or blob[pos] not in b" \t\r\n":
        raise ValueError("PPM pixel separator missing")
    pos += 1
    pixels = blob[pos:]
    if len(pixels) != width * height * 3:
        raise ValueError("PPM framebuffer payload length mismatch")
    pitch = width * 3
    filtered = b"".join(b"\x00" + pixels[i:i+pitch] for i in range(0, len(pixels), pitch))
    png = (b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(filtered, 6))
        + png_chunk(b"IEND", b""))
    pathname = pathlib.Path(png_path)
    pathname.parent.mkdir(parents=True, exist_ok=True)
    pathname.write_bytes(png)
    report = {
      "source": "QEMU HMP screendump of virtual x86 VGA framebuffer",
      "image_path": pathname.name,
      "width": width,
      "height": height,
      "actual_guest": "Ubuntu Linux x86_64 research host",
      "genuine_apple_homeview_breadboard": False,
      "homeview_visual_proof": False,
      "screen_is_synthetic": False
    }
    pathname.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: ppm_to_png.py qemu.ppm screenshot.png")
    convert(sys.argv[1], sys.argv[2])
