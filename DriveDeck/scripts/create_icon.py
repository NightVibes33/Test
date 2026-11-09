#!/usr/bin/env python3
"""Generate a 1024px original DriveDeck app icon without external packages."""
import math
import os
import struct
import sys
import zlib

SIZE = 1024

def rounded(x, y, left, top, right, bottom, radius):
    if x < left or x >= right or y < top or y >= bottom:
        return False
    cx = max(left + radius, min(x, right - radius))
    cy = max(top + radius, min(y, bottom - radius))
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

def pixel(x, y):
    t = y / (SIZE - 1)
    side = x / (SIZE - 1)
    r = int(57 + 41 * t + 13 * side)
    g = int(113 - 42 * t - 16 * side)
    b = int(246 - 8 * t)
    # Original dash-screen glyph: white bezel, violet glass, and play arrow.
    frame = rounded(x, y, 150, 222, 874, 711, 94)
    glass = rounded(x, y, 200, 272, 824, 660, 54)
    if frame:
        r, g, b = 250, 252, 255
    if glass:
        r, g, b = 32, 28, 98
    # Broad white broadcast arcs rising from the lower-left of the display.
    if glass:
        dx, dy = x - 280, y - 608
        dist = math.hypot(dx, dy)
        if x >= 280 and y <= 608 and (abs(dist - 111) < 14 or abs(dist - 178) < 14):
            r, g, b = 255, 255, 255
        if math.hypot(x - 280, y - 608) < 19:
            r, g, b = 255, 255, 255
        # Play triangle to the right of the cast waves.
        if 555 <= x <= 711 and abs(y - 470) < (x - 555) * 0.56:
            r, g, b = 255, 255, 255
    # Display stand and curved console base.
    if 479 <= x <= 545 and 708 <= y <= 821:
        r, g, b = 252, 252, 255
    dx = (x - 512) / 365
    dy = (y - 850) / 69
    if dy * dy + dx * dx <= 1.0 and 814 <= y <= 853:
        r, g, b = 247, 249, 255
    return bytes((min(255, r), max(0, g), b, 255))

def chunk(kind, payload):
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)

def main(out):
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            rows.extend(pixel(x, y))
    header = b"\x89PNG\r\n\x1a\n"
    png = header + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as fp:
        fp.write(png)
    print("Generated DriveDeck icon", out, len(png), "bytes")

if __name__ == "__main__":
    main(sys.argv[1])
