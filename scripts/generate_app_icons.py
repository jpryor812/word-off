#!/usr/bin/env python3
"""Generate Worded app icon PNGs for AppIcon.appiconset."""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "Worded/Resources/Assets.xcassets/AppIcon.appiconset"

# Theme.swift palette
BG = (33, 82, 99)          # deep teal
TILE = (250, 235, 199)     # cream tile
TILE_EDGE = (184, 133, 71) # wood edge
TEXT = (71, 46, 20)        # tile letter
ACCENT = (242, 143, 48)    # orange highlight

SIZES = {
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-1024x1024@1x.png": 1024,
}


def write_png(path: Path, width: int, height: int, rgba_rows: list[list[tuple[int, int, int, int]]]) -> None:
    raw = b"".join(b"\x00" + bytes(pixel) for row in rgba_rows for pixel in row)
    compressed = zlib.compress(raw, 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(png)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(lerp(c1[0], c2[0], t)),
        int(lerp(c1[1], c2[1], t)),
        int(lerp(c1[2], c2[2], t)),
    )


def rounded_rect_mask(x: float, y: float, w: float, h: float, radius: float) -> bool:
    if x < 0 or y < 0 or x >= w or y >= h:
        return False
    r = min(radius, w / 2, h / 2)
    corners = (
        (r, r),
        (w - r, r),
        (r, h - r),
        (w - r, h - r),
    )
    for cx, cy in corners:
        if (x < cx and y < cy) or (x > w - cx and y < cy) or (x < cx and y > h - cy) or (x > w - cx and y > h - cy):
            dx = x - cx if x < cx else x - (w - cx) if x > w - cx else 0
            dy = y - cy if y < cy else y - (h - cy) if y > h - cy else 0
            if dx * dx + dy * dy > r * r:
                return False
    return True


def fill_w(pixels: list[list[tuple[int, int, int, int]]], size: int, color: tuple[int, int, int]) -> None:
    """Draw a bold block W centered in the icon."""
    thickness = max(2, round(size * 0.11))
    gap = max(1, round(size * 0.04))
    top = round(size * 0.30)
    bottom = round(size * 0.72)
    left = round(size * 0.24)
    right = size - left
    mid = size // 2
    leg = max(2, round(size * 0.14))

    def paint(x0: int, y0: int, x1: int, y1: int) -> None:
        for y in range(max(0, y0), min(size, y1)):
            for x in range(max(0, x0), min(size, x1)):
                pixels[y][x] = (*color, 255)

    # Outer legs
    paint(left, top, left + thickness, bottom)
    paint(right - thickness, top, right, bottom)
    # Inner legs
    paint(mid - leg, top + round((bottom - top) * 0.42), mid - leg + thickness, bottom)
    paint(mid + leg - thickness, top + round((bottom - top) * 0.42), mid + leg, bottom)
    # Top bar
    paint(left, top, right, top + thickness)
    # V dip
    paint(mid - thickness // 2, top + round((bottom - top) * 0.38), mid + thickness // 2 + 1, top + round((bottom - top) * 0.42) + gap)


def render_icon(size: int) -> list[list[tuple[int, int, int, int]]]:
    pixels = [([(0, 0, 0, 0)] * size) for _ in range(size)]
    outer_radius = size * 0.22
    tile_size = size * 0.62
    tile_x = (size - tile_size) / 2
    tile_y = (size - tile_size) / 2
    tile_radius = tile_size * 0.18

    for y in range(size):
        for x in range(size):
            fx, fy = x + 0.5, y + 0.5
            if not rounded_rect_mask(fx, fy, size, size, outer_radius):
                continue

            # Subtle radial gradient on background
            cx, cy = size / 2, size / 2
            dist = math.hypot(fx - cx, fy - cy) / (size * 0.7)
            bg = lerp_color(BG, (24, 62, 76), min(1.0, dist * 0.55))
            pixels[y][x] = (*bg, 255)

            tx, ty = fx - tile_x, fy - tile_y
            if rounded_rect_mask(tx, ty, tile_size, tile_size, tile_radius):
                edge_band = tile_size * 0.08
                if tx < edge_band or ty < edge_band or tx > tile_size - edge_band or ty > tile_size - edge_band:
                    pixels[y][x] = (*TILE_EDGE, 255)
                else:
                    pixels[y][x] = (*TILE, 255)

    fill_w(pixels, size, TEXT)

    # Orange accent dot (score pip) top-right of tile
    dot_r = max(1.5, size * 0.045)
    dot_cx = tile_x + tile_size * 0.78
    dot_cy = tile_y + tile_size * 0.22
    for y in range(size):
        for x in range(size):
            if math.hypot(x + 0.5 - dot_cx, y + 0.5 - dot_cy) <= dot_r:
                pixels[y][x] = (*ACCENT, 255)

    return pixels


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    for filename, px in SIZES.items():
        write_png(ICON_DIR / filename, px, px, render_icon(px))
        print(f"wrote {filename} ({px}x{px})")

    contents = {
        "images": [
            {"filename": "Icon-App-20x20@2x.png", "idiom": "iphone", "scale": "2x", "size": "20x20"},
            {"filename": "Icon-App-20x20@3x.png", "idiom": "iphone", "scale": "3x", "size": "20x20"},
            {"filename": "Icon-App-29x29@2x.png", "idiom": "iphone", "scale": "2x", "size": "29x29"},
            {"filename": "Icon-App-29x29@3x.png", "idiom": "iphone", "scale": "3x", "size": "29x29"},
            {"filename": "Icon-App-40x40@2x.png", "idiom": "iphone", "scale": "2x", "size": "40x40"},
            {"filename": "Icon-App-40x40@3x.png", "idiom": "iphone", "scale": "3x", "size": "40x40"},
            {"filename": "Icon-App-60x60@2x.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
            {"filename": "Icon-App-60x60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60"},
            {"filename": "Icon-App-1024x1024@1x.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (ICON_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")

    assets_root = ICON_DIR.parent
    (assets_root / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    print("done")


if __name__ == "__main__":
    main()
