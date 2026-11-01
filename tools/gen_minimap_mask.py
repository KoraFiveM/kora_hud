#!/usr/bin/env python3
"""Generates assets/square_minimap_mask.png, the square radar mask kora_hud
loads at runtime (Config.hud.minimapLayout.shape = square).

Kora original: produced entirely by this script (pure python, zlib/struct, no
third-party artwork or textures), same licence as the kora_hud resource.

The image is 256x256 RGBA: white, fully opaque square with a soft alpha ramp
over the outer EDGE pixels so the clip is not aliased. Deterministic: running
it again yields a byte-identical file.

Usage: python3 tools/gen_minimap_mask.py [output.png]
"""
import os
import struct
import sys
import zlib

SIZE = 256
EDGE = 2  # pixels of soft alpha along each border


def alpha_at(x, y):
    d = min(x, y, SIZE - 1 - x, SIZE - 1 - y)  # distance to the nearest border
    if d >= EDGE:
        return 255
    return round(255 * (d + 1) / (EDGE + 1))


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def build():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter type: none
        for x in range(SIZE):
            rows += bytes((255, 255, 255, alpha_at(x, y)))
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "assets", "square_minimap_mask.png")
    with open(out, "wb") as f:
        f.write(build())
    print("wrote", os.path.normpath(out))
