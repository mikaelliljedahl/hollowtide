#!/usr/bin/env python3
"""Render the Tide Socket and Tide Glyph pickup icons (original procedural art).

Run with Pillow, as the other art builders do:
    uv run --quiet --with pillow==12.3.0 python tools/build_tide_art.py

Writes single-frame 128 px RGBA icons to assets/sprites/tide/<kind>.png, the paths registered in
scripts/progression/content_catalog.gd. The socket is a hexagonal frame around a tide line; each
glyph is a slate tablet whose rim colour marks its family and whose rune marks its effect. Shapes
are drawn at 4x and downsampled for smooth edges.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/sprites/tide"
SIZE = 128
SCALE = 4
S = SIZE * SCALE

TEAL = (127, 227, 214)
AMBER = (242, 196, 109)
CORAL = (236, 122, 98)
PULSE = (255, 176, 84)
SLATE_TOP = (38, 58, 66)
SLATE_BOTTOM = (14, 24, 30)

# Rune strokes per glyph in a 0..1 tablet-local box: polylines ("line") or filled polygons ("fill").
GLYPHS: dict[str, tuple[tuple[int, int, int], list[tuple[str, list[tuple[float, float]]]]]] = {
    "quickstring": (
        AMBER,
        [
            ("line", [(0.22, 0.70), (0.52, 0.30)]),
            ("line", [(0.40, 0.76), (0.70, 0.36)]),
            ("line", [(0.58, 0.82), (0.84, 0.46)]),
            ("line", [(0.46, 0.22), (0.70, 0.22), (0.70, 0.46)]),
        ],
    ),
    "farcast": (
        AMBER,
        [
            ("line", [(0.16, 0.52), (0.84, 0.52)]),
            ("line", [(0.64, 0.36), (0.84, 0.52), (0.64, 0.68)]),
            ("fill", [(0.20, 0.30), (0.26, 0.24), (0.32, 0.30), (0.26, 0.36)]),
            ("fill", [(0.20, 0.74), (0.26, 0.68), (0.32, 0.74), (0.26, 0.80)]),
        ],
    ),
    "heavy_barb": (
        AMBER,
        [
            ("line", [(0.50, 0.86), (0.50, 0.30)]),
            ("fill", [(0.50, 0.12), (0.72, 0.42), (0.50, 0.34), (0.28, 0.42)]),
            ("line", [(0.36, 0.86), (0.64, 0.86)]),
        ],
    ),
    "brine_hide": (
        TEAL,
        [
            ("line", [(0.22, 0.34), (0.50, 0.20), (0.78, 0.34)]),
            ("line", [(0.22, 0.54), (0.50, 0.40), (0.78, 0.54)]),
            ("line", [(0.22, 0.74), (0.50, 0.60), (0.78, 0.74)]),
        ],
    ),
    "ebb_mend": (
        TEAL,
        [
            ("line", [(0.14, 0.70), (0.30, 0.60), (0.46, 0.70), (0.62, 0.60), (0.78, 0.70)]),
            ("line", [(0.50, 0.18), (0.50, 0.46)]),
            ("line", [(0.36, 0.32), (0.64, 0.32)]),
        ],
    ),
    "deep_pulse": (
        PULSE,
        [
            ("line", [(0.50, 0.14), (0.82, 0.50), (0.50, 0.86), (0.18, 0.50), (0.50, 0.14)]),
            ("line", [(0.50, 0.32), (0.66, 0.50), (0.50, 0.68), (0.34, 0.50), (0.50, 0.32)]),
            ("fill", [(0.50, 0.44), (0.56, 0.50), (0.50, 0.56), (0.44, 0.50)]),
        ],
    ),
    "spring_tide": (
        CORAL,
        [
            ("line", [(0.14, 0.78), (0.32, 0.62), (0.50, 0.78), (0.68, 0.62), (0.86, 0.78)]),
            ("line", [(0.50, 0.56), (0.50, 0.16)]),
            ("line", [(0.32, 0.32), (0.50, 0.14), (0.68, 0.32)]),
        ],
    ),
}


def _px(point: tuple[float, float], box: tuple[float, float, float, float]) -> tuple[float, float]:
    left, top, right, bottom = box
    return (left + point[0] * (right - left), top + point[1] * (bottom - top))


def _glow(layer: Image.Image, radius: float, strength: float) -> Image.Image:
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    alpha = blurred.getchannel("A").point(lambda value: min(255, int(value * strength)))
    blurred.putalpha(alpha)
    return blurred


def _finish(canvas: Image.Image, path: Path) -> None:
    canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(path)


def _hexagon(center: tuple[float, float], radius: float) -> list[tuple[float, float]]:
    cx, cy = center
    offsets = [(1.0, 0.0), (0.5, 0.866), (-0.5, 0.866), (-1.0, 0.0), (-0.5, -0.866), (0.5, -0.866)]
    return [(cx + dx * radius, cy + dy * radius) for dx, dy in offsets]


def render_socket(path: Path) -> None:
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    strokes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(strokes)
    center = (S / 2, S / 2)
    outer = _hexagon(center, S * 0.40)
    inner = _hexagon(center, S * 0.29)
    fill = ImageDraw.Draw(canvas)
    fill.polygon(outer, fill=(*SLATE_BOTTOM, 235))
    fill.polygon(inner, fill=(*SLATE_TOP, 245))
    draw.line([*outer, outer[0]], fill=(*TEAL, 255), width=int(S * 0.045), joint="curve")
    draw.line([*inner, inner[0]], fill=(*TEAL, 150), width=int(S * 0.018), joint="curve")
    wave = [
        _px(point, (S * 0.30, S * 0.40, S * 0.70, S * 0.60))
        for point in [(0.0, 0.6), (0.25, 0.2), (0.5, 0.6), (0.75, 0.2), (1.0, 0.6)]
    ]
    draw.line(wave, fill=(*TEAL, 255), width=int(S * 0.03), joint="curve")
    canvas = Image.alpha_composite(_glow(strokes, S * 0.03, 1.6), canvas)
    canvas = Image.alpha_composite(canvas, strokes)
    _finish(canvas, path)


def render_glyph(glyph_id: str, path: Path) -> None:
    color, runes = GLYPHS[glyph_id]
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Tablet: slightly wider at the top, cut corners (an octagonal slate, not a round token).
    left, top, right, bottom = S * 0.22, S * 0.10, S * 0.78, S * 0.90
    cut = S * 0.07
    tablet = [
        (left + cut, top),
        (right - cut, top),
        (right + S * 0.02, top + cut),
        (right - S * 0.02, bottom - cut),
        (right - cut - S * 0.02, bottom),
        (left + cut + S * 0.02, bottom),
        (left + S * 0.02, bottom - cut),
        (left - S * 0.02, top + cut),
    ]
    gradient = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad_draw = ImageDraw.Draw(gradient)
    for row in range(S):
        t = row / S
        shade = tuple(int(a + (b - a) * t) for a, b in zip(SLATE_TOP, SLATE_BOTTOM))
        grad_draw.line([(0, row), (S, row)], fill=(*shade, 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(tablet, fill=240)
    canvas.paste(gradient, (0, 0), mask)
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).line([*tablet, tablet[0]], fill=(*color, 210), width=int(S * 0.025))
    strokes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(strokes)
    rune_box = (left + S * 0.06, top + S * 0.08, right - S * 0.06, bottom - S * 0.08)
    for kind, points in runes:
        mapped = [_px(point, rune_box) for point in points]
        if kind == "fill":
            draw.polygon(mapped, fill=(*color, 255))
        else:
            draw.line(mapped, fill=(*color, 255), width=int(S * 0.045), joint="curve")
            radius = S * 0.0225
            for x, y in (mapped[0], mapped[-1]):
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*color, 255))
    canvas = Image.alpha_composite(_glow(rim, S * 0.025, 1.2), canvas)
    canvas = Image.alpha_composite(canvas, rim)
    canvas = Image.alpha_composite(canvas, _glow(strokes, S * 0.03, 1.8))
    canvas = Image.alpha_composite(canvas, strokes)
    _finish(canvas, path)


def main() -> int:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    render_socket(OUTPUT / "tide_socket.png")
    for glyph_id in GLYPHS:
        render_glyph(glyph_id, OUTPUT / f"glyph_{glyph_id}.png")
    print(f"build_tide_art: wrote {1 + len(GLYPHS)} icons to {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
