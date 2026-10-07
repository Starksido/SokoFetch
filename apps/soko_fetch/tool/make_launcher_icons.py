"""
Draw the legacy (pre-Android 8) launcher PNGs: an orange rounded square with
the white shopping bag (U-shaped handle cut into it), same geometry as SokoMark in
lib/core/ui/brand.dart and drawable/ic_launcher_foreground.xml.

    python tool/make_launcher_icons.py

Pure Python (no Pillow); edges are smoothed by 4x4 supersampling.
"""
import math
import os
import struct
import zlib

ORANGE = (0xF2, 0x6B, 0x1D)
WHITE = (0xFF, 0xFF, 0xFF)
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
RES = os.path.join(os.path.dirname(__file__), "..", "android", "app", "src", "main", "res")
SS = 4  # Supersampling per axis


def in_rrect(x, y, l, t, r, b, rad):
    if not (l <= x <= r and t <= y <= b):
        return False
    cx = min(max(x, l + rad), r - rad)
    cy = min(max(y, t + rad), b - rad)
    return (x - cx) ** 2 + (y - cy) ** 2 <= rad ** 2


def colour_at(u, v):
    """None outside the icon, else the colour at unit coordinates (u, v)."""
    if not in_rrect(u, v, 0.0, 0.0, 1.0, 1.0, 0.22):
        return None
    if not in_rrect(u, v, 0.22, 0.30, 0.78, 0.80, 0.07):
        return ORANGE
    # Inside the white bag: the handle is a U cut into it, with round ends
    dx, dy = u - 0.5, v - 0.40
    if dy >= 0 and abs(math.hypot(dx, dy) - 0.12) <= 0.0275:
        return ORANGE
    for ex in (0.38, 0.62):
        if math.hypot(u - ex, v - 0.40) <= 0.045:
            return ORANGE
    return WHITE


def render(size):
    rows = []
    for py in range(size):
        row = bytearray([0])
        for px in range(size):
            r = g = b = a = 0
            for sy in range(SS):
                for sx in range(SS):
                    c = colour_at((px + (sx + 0.5) / SS) / size, (py + (sy + 0.5) / SS) / size)
                    if c is not None:
                        r += c[0]; g += c[1]; b += c[2]; a += 255
            n = SS * SS
            cover = a // n
            if cover:
                k = a // 255  # Samples inside
                row += bytes((r // k, g // k, b // k, cover))
            else:
                row += bytes((0, 0, 0, 0))
        rows.append(bytes(row))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
            + chunk(b"IEND", b""))


for density, px in SIZES.items():
    path = os.path.join(RES, f"mipmap-{density}", "ic_launcher.png")
    with open(path, "wb") as f:
        f.write(render(px))
    print(f"{density:8} {px:4}px  {os.path.relpath(path)}")
