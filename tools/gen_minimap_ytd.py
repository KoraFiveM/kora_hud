#!/usr/bin/env python3
"""Generates stream/kora_hud_squaremap.ytd, the square radar mask texture
dictionary kora_hud streams for Config.hud.minimapLayout.shape = 'square'.

Kora original: the texture is produced entirely by this script (pure python,
zlib/struct only, no third-party artwork) and is the same licence as kora_hud.

Why a streamed .ytd and not a PNG: the radar mask (radarmasksm / radarmask1g
in platform:/textures/graphics) is sampled by the minimap renderer from a
streamed texture dictionary, and the renderer reads the mask from the COLOUR
channels (black = clipped, grey = visible, alpha is 255 everywhere). A runtime
texture built from a PNG whose RGB is white everywhere masks nothing.

Output: an RSC7 (version 13) texture dictionary with one 512x396 DXT5 texture
named 'radarmasksm'. Inside the texture, the visible area is a solid
rectangle at RECT (pixels, inclusive), GREY on black; the rectangle is
placed where the stock mask's visible area sits, so the stock-relative
minimap_mask component rects in client/minimap.lua line up with it.

Deterministic: running it again yields a byte-identical file.
Usage: python3 tools/gen_minimap_ytd.py [output.ytd]
"""
import os
import struct
import sys
import zlib

WIDTH, HEIGHT = 512, 396
RECT = (20, 63, 334, 299)  # x0, y0, x1, y1 inclusive: the visible square area
GREY = (23 << 11) | (46 << 5) | 23  # RGB565 grey ~(189, 186, 189): the visible area
TEXTURE_NAME = b'radarmasksm'

SYSTEM_SIZE = 0x2000       # one 8 KiB system page
GRAPHICS_SIZE = 0x40000    # one 256 KiB graphics page
SYSTEM_FLAGS = 0x00020000
GRAPHICS_FLAGS = 0xD0020005
PAD = 0xCD                 # RAGE fills unused resource bytes with 0xCD
SYS_BASE, GFX_BASE = 0x50000000, 0x60000000

DICT_VFT = 0x650890B2      # pgDictionary<grcTexture> type tag on PC
TEX_VFT = 0xB6F0EE97       # grcTexturePC type tag


def joaat(text):
    h = 0
    for c in text.lower():
        h = (h + c) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h ^= h >> 6
    h = (h + (h << 3)) & 0xFFFFFFFF
    h ^= h >> 11
    return (h + (h << 15)) & 0xFFFFFFFF


def visible(x, y):
    x0, y0, x1, y1 = RECT
    return x0 <= x <= x1 and y0 <= y <= y1


def dxt5():
    """Two-colour DXT5: alpha block always 255, colour index 0 = grey, 1 = black."""
    grey = GREY
    out = bytearray()
    for by in range(0, HEIGHT, 4):
        for bx in range(0, WIDTH, 4):
            bits = 0
            for py in range(4):
                for px in range(4):
                    if not visible(bx + px, by + py):
                        bits |= 1 << (2 * (py * 4 + px))
            if bits == 0x55555555:   # fully black block
                colour = struct.pack('<HHI', 0, 0, 0)
            else:
                colour = struct.pack('<HHI', grey, 0, bits)
            out += b'\xff\xff' + b'\x00' * 6 + colour
    return bytes(out)


def system_page():
    s = bytearray(b'\x00' * 0xE0) + bytearray([PAD]) * (SYSTEM_SIZE - 0xE0)
    p = lambda off: SYS_BASE + off
    # pgDictionary at 0x00
    struct.pack_into('<IIQ', s, 0x00, DICT_VFT, 0, p(0xD0))       # vft, pagemap
    struct.pack_into('<Q', s, 0x18, 1)
    struct.pack_into('<QHH', s, 0x20, p(0x110), 1, 1)              # hashes
    struct.pack_into('<QHH', s, 0x30, p(0x100), 1, 1)              # textures
    # grcTexturePC at 0x40
    struct.pack_into('<I', s, 0x40, TEX_VFT)
    struct.pack_into('<Q', s, 0x68, p(0xF0))                       # name
    struct.pack_into('<HH', s, 0x70, 1, 0x80)                      # refcount, usage
    struct.pack_into('<I', s, 0x80, 0x20032001)
    struct.pack_into('<HHHH', s, 0x90, WIDTH, HEIGHT, 1, WIDTH)    # w, h, depth, stride
    s[0x98:0x9C] = b'DXT5'
    s[0x9D] = 1                                                    # mip levels
    struct.pack_into('<Q', s, 0xB0, GFX_BASE)                      # pixel data
    s[0xD8:0xDA] = b'\x01\x01'                                     # page map: 1 sys, 1 gfx
    name = TEXTURE_NAME + b'\x00'
    s[0xF0:0xF0 + len(name)] = name
    struct.pack_into('<Q', s, 0x100, p(0x40))
    struct.pack_into('<I', s, 0x110, joaat(TEXTURE_NAME))
    return bytes(s)


def build(pixels=None):
    pixels = dxt5() if pixels is None else pixels
    gfx = pixels + bytes([PAD]) * (GRAPHICS_SIZE - len(pixels))
    body = system_page() + gfx
    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = comp.compress(body) + comp.flush()
    return struct.pack('<4sIII', b'RSC7', 13, SYSTEM_FLAGS, GRAPHICS_FLAGS) + data, body


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'stream', 'kora_hud_squaremap.ytd')
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'wb') as f:
        f.write(build()[0])
    print('wrote', os.path.normpath(out))
