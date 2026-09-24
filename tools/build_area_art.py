#!/usr/bin/env python3
"""Build the per-area environment art used by scripts/world/cave_visuals.gd.

Inputs (per area) live in assets/environment/source/<area>/ (ignored by Godot via .gdignore):
  fill.png, top.png, bottom.png, side.png          terrain material (see art brief env_terrain)
  far.png, mid.png                                 parallax layers (see art brief env_bg)
  props.png                                        decor sprites (see art brief env_props)
fill.png is required; other missing inputs are skipped (the runtime has fallbacks). Outputs go to assets/environment/areas/<area>/ together with area.json.

Run: uv run --with pillow==12.3.0 --with numpy python tools/build_area_art.py [area ...]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/environment/source"
OUT = ROOT / "assets/environment/areas"
AREAS = ("fringe", "nexus", "vaults", "kiln", "depths")

# Strip geometry (px, runtime space). Must match cave_visuals.gd.
FILL_SIZE = 512
STRIP_WIDTH = 1024
TOP_HEIGHT = 128
TOP_LINE = 32  # walk line inside the top strip
BOTTOM_HEIGHT = 160
BOTTOM_LINE = 48  # underside line inside the bottom strip
SIDE_WIDTH = 128
SIDE_LINE = 96  # wall face line inside the (right-facing) side strip
SIDE_HEIGHT = 1024
CAP_WIDTH = 32

# Source band geometry requested in the art brief (1536x1024 strips, 1024x1536 side).
SRC_TOP_LINE = 448
SRC_BOTTOM_LINE = 576
SRC_SIDE_LINE = 576

AREA_STYLE = {
    "fringe": {
        "far_modulate": (0.66, 0.7, 0.74),
        "mid_modulate": (0.42, 0.47, 0.52),
        "tint": (0.62, 0.72, 0.8),
        "crust": (79, 107, 58),
        "hang": (60, 52, 40),
        "glow": None,
        "fog": (0.36, 0.5, 0.58),
        "far_parallax": 0.18,
        "mid_parallax": 0.42,
        "particles": "drip",
    },
    "nexus": {
        "far_modulate": (0.62, 0.68, 0.7),
        "mid_modulate": (0.4, 0.47, 0.5),
        "tint": (0.5, 0.66, 0.7),
        "crust": (60, 110, 115),
        "hang": (70, 150, 150),
        "glow": (89, 217, 207),
        "fog": (0.2, 0.55, 0.55),
        "far_parallax": 0.14,
        "mid_parallax": 0.38,
        "particles": "mist",
    },
    "vaults": {
        "far_modulate": (0.44, 0.48, 0.54),
        "mid_modulate": (0.4, 0.44, 0.5),
        "tint": (0.9, 0.95, 1.0),
        "crust": (220, 234, 242),
        "hang": (200, 225, 240),
        "glow": None,
        "fog": (0.7, 0.82, 0.9),
        "far_parallax": 0.12,
        "mid_parallax": 0.34,
        "particles": "snow",
    },
    "kiln": {
        "far_modulate": (0.6, 0.56, 0.54),
        "mid_modulate": (0.42, 0.36, 0.34),
        "tint": (0.55, 0.42, 0.38),
        "crust": (70, 44, 34),
        "hang": (40, 26, 22),
        "glow": (255, 106, 31),
        "fog": (0.9, 0.42, 0.18),
        "far_parallax": 0.12,
        "mid_parallax": 0.34,
        "particles": "embers",
    },
    "depths": {
        "far_modulate": (0.8, 0.8, 0.86),
        "mid_modulate": (0.6, 0.6, 0.7),
        "tint": (0.36, 0.4, 0.55),
        "crust": (40, 44, 70),
        "hang": (30, 34, 60),
        "glow": (122, 92, 255),
        "fog": (0.3, 0.26, 0.6),
        "far_parallax": 0.1,
        "mid_parallax": 0.3,
        "particles": "motes",
    },
}


def _seed(area: str, salt: int) -> int:
    return (sum(ord(c) * (i + 7) for i, c in enumerate(area)) * 7919 + salt * 104729) % (2**32)


def _noise1d(length: int, rng: np.random.Generator, scale: int, amp: float) -> np.ndarray:
    """Smooth periodic 1D noise (wraps at `length`)."""
    points = max(4, length // scale)
    ctrl = rng.uniform(-1.0, 1.0, points)
    x = np.arange(length) / length * points
    i0 = np.floor(x).astype(int) % points
    i1 = (i0 + 1) % points
    t = x - np.floor(x)
    t = t * t * (3 - 2 * t)
    return (ctrl[i0] * (1 - t) + ctrl[i1] * t) * amp


def _fractal1d(length: int, rng: np.random.Generator, amp: float) -> np.ndarray:
    return (
        _noise1d(length, rng, 128, amp)
        + _noise1d(length, rng, 48, amp * 0.5)
        + _noise1d(length, rng, 16, amp * 0.25)
    )


def _seamless(img: Image.Image, axis: str = "both", blend: float = 0.25) -> Image.Image:
    """Cross-fade opposite edges so the image wraps without a visible seam."""
    arr = np.asarray(img.convert("RGBA")).astype(np.float32)
    h, w = arr.shape[:2]
    if axis in ("both", "x"):
        n = int(w * blend)
        rolled = np.roll(arr, w // 2, axis=1)
        ramp = np.clip(np.abs(np.arange(w) - w / 2) / n - (w / 2 - n) / n, 0, 1)
        ramp = ramp[None, :, None]
        arr = arr * (1 - ramp) + rolled * ramp
        # after mixing, edges come from the rolled centre, which is continuous across the wrap
    if axis in ("both", "y"):
        n = int(h * blend)
        rolled = np.roll(arr, h // 2, axis=0)
        ramp = np.clip(np.abs(np.arange(h) - h / 2) / n - (h / 2 - n) / n, 0, 1)
        ramp = ramp[:, None, None]
        arr = arr * (1 - ramp) + rolled * ramp
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def _key_magenta(img: Image.Image) -> Image.Image:
    """Turn a flat #FF00FF key into alpha with soft edges and despill."""
    arr = np.asarray(img.convert("RGBA")).astype(np.float32)
    if arr[..., 3].min() < 250:
        return img.convert("RGBA")  # already transparent
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    magenta = np.clip(((r + b) * 0.5 - g) / 255.0, 0, 1)
    close = np.clip((magenta - 0.55) / 0.35, 0, 1)
    alpha = 1.0 - close
    # despill: remove magenta cast from partially keyed pixels
    spill = np.minimum(r, b) - g
    fix = np.clip(spill, 0, None) * (1 - alpha)
    arr[..., 0] -= fix
    arr[..., 2] -= fix
    arr[..., 3] = alpha * 255
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def _load_source(area: str, name: str) -> Image.Image | None:
    path = SOURCE / area / f"{name}.png"
    if not path.exists():
        return None
    return Image.open(path)


# ---------------------------------------------------------------- material


def build_fill(area: str) -> Image.Image:
    src = _load_source(area, "fill")
    if src is None:
        raise SystemExit(f"missing source art: assets/environment/source/{area}/fill.png")
    src = src.convert("RGBA").resize((FILL_SIZE, FILL_SIZE), Image.LANCZOS)
    return _seamless(src, blend=0.12)


def _placeholder_top(area: str, fill: Image.Image) -> Image.Image:
    style = AREA_STYLE[area]
    rng = np.random.default_rng(_seed(area, 1))
    body = np.asarray(fill.resize((FILL_SIZE, FILL_SIZE))).astype(np.float32)
    body = np.tile(body, (1, STRIP_WIDTH // FILL_SIZE, 1))[:TOP_HEIGHT]
    out = body.copy()
    edge = TOP_LINE + _fractal1d(STRIP_WIDTH, rng, 4.0)
    tuft = TOP_LINE - np.clip(_fractal1d(STRIP_WIDTH, rng, 14.0), 0, None) - 2
    ys = np.arange(TOP_HEIGHT)[:, None]
    solid = ys >= edge[None, :]
    crust = (ys >= tuft[None, :]) & (ys < edge[None, :] + 10)
    col = np.array(style["crust"], dtype=np.float32)
    out[..., :3] = np.where(crust[..., None], out[..., :3] * 0.35 + col * 0.65, out[..., :3])
    # lip highlight
    lip = (ys >= edge[None, :]) & (ys < edge[None, :] + 4)
    out[..., :3] = np.where(lip[..., None], np.minimum(out[..., :3] * 1.5 + 30, 255), out[..., :3])
    fade = np.clip((TOP_HEIGHT - 8 - ys) / 40.0, 0, 1)
    alpha = np.where(solid | crust, 1.0, 0.0) * fade
    out[..., 3] = alpha * 255
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def build_top(area: str, fill: Image.Image) -> Image.Image:
    src = _load_source(area, "top")
    if src is None:
        return _placeholder_top(area, fill)
    src = _key_magenta(src)
    scale = 0.5
    w = int(src.width * scale)
    src = src.resize((w, int(src.height * scale)), Image.LANCZOS)
    top = int(SRC_TOP_LINE * scale) - TOP_LINE
    band = src.crop((0, top, w, top + TOP_HEIGHT))
    band = _fade_rows(band, TOP_HEIGHT - 40, TOP_HEIGHT - 4)
    band = _seamless(band, "x", 0.1).resize((STRIP_WIDTH, TOP_HEIGHT), Image.LANCZOS)
    return band


def _fade_rows(img: Image.Image, start: int, end: int, reverse: bool = False) -> Image.Image:
    arr = np.asarray(img.convert("RGBA")).astype(np.float32)
    ys = np.arange(arr.shape[0])
    f = np.clip((end - ys) / max(1, end - start), 0, 1)
    if reverse:
        f = np.clip((ys - start) / max(1, end - start), 0, 1)
    arr[..., 3] *= f[:, None]
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def _placeholder_bottom(area: str, fill: Image.Image) -> Image.Image:
    style = AREA_STYLE[area]
    rng = np.random.default_rng(_seed(area, 2))
    body = np.asarray(fill).astype(np.float32)
    body = np.tile(body, (1, STRIP_WIDTH // FILL_SIZE, 1))[:BOTTOM_HEIGHT]
    out = body.copy() * np.array([0.7, 0.7, 0.7, 1.0])
    edge = BOTTOM_LINE + _fractal1d(STRIP_WIDTH, rng, 5.0)
    hang = np.zeros(STRIP_WIDTH)
    x = 0
    while x < STRIP_WIDTH:
        width = int(rng.integers(10, 26))
        length = float(rng.uniform(10, 70)) if rng.random() < 0.55 else float(rng.uniform(4, 14))
        xs = np.arange(width)
        profile = length * np.sqrt(np.clip(1 - ((xs - width / 2) / (width / 2)) ** 2, 0, 1))
        for i, value in enumerate(profile):
            hang[(x + i) % STRIP_WIDTH] = max(hang[(x + i) % STRIP_WIDTH], value)
        x += width + int(rng.integers(8, 60))
    ys = np.arange(BOTTOM_HEIGHT)[:, None]
    solid = ys <= edge[None, :]
    drip = (ys > edge[None, :]) & (ys <= edge[None, :] + hang[None, :])
    col = np.array(style["hang"], dtype=np.float32)
    out[..., :3] = np.where(drip[..., None], out[..., :3] * 0.4 + col * 0.6, out[..., :3])
    fade = np.clip((ys - 0) / 16.0, 0, 1)
    out[..., 3] = np.where(solid | drip, 255.0, 0.0) * fade
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def build_bottom(area: str, fill: Image.Image) -> Image.Image:
    src = _load_source(area, "bottom")
    if src is None:
        return _placeholder_bottom(area, fill)
    src = _key_magenta(src)
    scale = 0.5
    w = int(src.width * scale)
    src = src.resize((w, int(src.height * scale)), Image.LANCZOS)
    top = int(SRC_BOTTOM_LINE * scale) - BOTTOM_LINE
    band = src.crop((0, top, w, top + BOTTOM_HEIGHT))
    band = _fade_rows(band, 0, 16, reverse=True)
    band = _seamless(band, "x", 0.1).resize((STRIP_WIDTH, BOTTOM_HEIGHT), Image.LANCZOS)
    return band


def _placeholder_side(area: str, fill: Image.Image) -> Image.Image:
    style = AREA_STYLE[area]
    rng = np.random.default_rng(_seed(area, 3))
    body = np.asarray(fill).astype(np.float32)
    body = np.tile(body, (SIDE_HEIGHT // FILL_SIZE, 1, 1))[:, :SIDE_WIDTH]
    out = body.copy()
    edge = SIDE_LINE + _fractal1d(SIDE_HEIGHT, rng, 6.0)
    xs = np.arange(SIDE_WIDTH)[None, :]
    solid = xs <= edge[:, None]
    rim = solid & (xs > edge[:, None] - 5)
    out[..., :3] = np.where(rim[..., None], np.minimum(out[..., :3] * 1.35 + 18, 255), out[..., :3])
    shade = np.clip((edge[:, None] - xs) / 60.0, 0, 1)
    out[..., :3] *= (1 - 0.35 * shade)[..., None]
    fade = np.clip(xs / 24.0, 0, 1)
    out[..., 3] = np.where(solid, 255.0, 0.0) * fade
    _ = style
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def build_side(area: str, fill: Image.Image) -> Image.Image:
    src = _load_source(area, "side")
    if src is None:
        return _placeholder_side(area, fill)
    src = _key_magenta(src)
    scale = 0.5
    src = src.resize((int(src.width * scale), int(src.height * scale)), Image.LANCZOS)
    left = int(SRC_SIDE_LINE * scale) - SIDE_LINE
    band = src.crop((left, 0, left + SIDE_WIDTH, src.height))
    arr = np.asarray(band).astype(np.float32)
    arr[..., 3] *= np.clip(np.arange(SIDE_WIDTH) / 24.0, 0, 1)[None, :]
    band = Image.fromarray(arr.astype(np.uint8), "RGBA")
    band = _seamless(band, "y", 0.1).resize((SIDE_WIDTH, SIDE_HEIGHT), Image.LANCZOS)
    return band


def make_cap(strip: Image.Image, left: bool) -> Image.Image:
    """End cap for a horizontal strip: CAP_WIDTH px of overhang past the run end, fading out."""
    width = CAP_WIDTH
    x0 = 0 if left else strip.width - width
    crop = np.asarray(strip.crop((x0, 0, x0 + width, strip.height))).astype(np.float32)
    xs = np.arange(width)
    ramp = xs / width if left else (width - 1 - xs) / width
    # rounded falloff: deeper rows fall off sooner so the end reads as a rounded rock nose
    ys = np.arange(strip.height)[:, None] / strip.height
    curve = np.clip(ramp[None, :] * 1.6 - ys * 0.6, 0, 1) ** 1.5
    crop[..., 3] *= curve
    return Image.fromarray(crop.astype(np.uint8), "RGBA")


# ---------------------------------------------------------------- backgrounds


def build_background(area: str, name: str) -> Image.Image | None:
    src = _load_source(area, name)
    if src is None:
        return None
    img = _key_magenta(src) if name == "mid" else src.convert("RGBA")
    if name == "mid":
        img = _drop_specks(img, 6000)
        for box in MID_ERASE.get(area, ()):
            arr = np.asarray(img).copy()
            arr[box[1] : box[3], box[0] : box[2], 3] = 0
            img = Image.fromarray(arr, "RGBA")
        # Delivered mids have empty (erased) side bands; crop to content and re-seam by crossfade.
        cols = np.where((np.asarray(img)[..., 3] > 20).sum(axis=0) > 0)[0]
        if cols[0] > 8 or cols[-1] < img.width - 9:
            img = img.crop((int(cols[0]) + 2, 0, int(cols[-1]) - 1, img.height))
            img = _seamless(img, "x", 0.1)
    target_h = 1536
    scale = target_h / img.height
    # Sources are delivered horizontally seamless; only resample.
    return img.resize((int(img.width * scale), target_h), Image.LANCZOS)


# Hand-picked stray blobs in delivered mid layers (source pixel boxes x0, y0, x1, y1).
MID_ERASE = {"kiln": ((515, 270, 615, 470),)}


def _drop_specks(img: Image.Image, max_area: int) -> Image.Image:
    """Erase small isolated alpha islands (stray blobs) that would float in the open band."""
    arr = np.asarray(img).copy()
    small = Image.fromarray(((arr[..., 3] > 10) * 255).astype(np.uint8)).resize(
        (img.width // 4, img.height // 4), Image.NEAREST
    )
    mask = np.asarray(small) > 0
    seen = np.zeros(mask.shape, dtype=bool)
    h, w = mask.shape
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            stack = [(y, x)]
            seen[y, x] = True
            pixels = []
            touches_edge = False
            while stack:
                cy, cx = stack.pop()
                pixels.append((cy, cx))
                touches_edge |= cy in (0, h - 1)
                for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, (cx + 1) % w), (cy, (cx - 1) % w)):
                    if 0 <= ny < h and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if not touches_edge and len(pixels) * 16 < max_area:
                for cy, cx in pixels:
                    arr[cy * 4 : cy * 4 + 4, cx * 4 : cx * 4 + 4, 3] = 0
    return Image.fromarray(arr, "RGBA")


def edge_colors(img: Image.Image) -> tuple[list[float], list[float]]:
    arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    top = arr[:24].reshape(-1, 3).mean(axis=0)
    bottom = arr[-24:].reshape(-1, 3).mean(axis=0)
    return [round(float(v), 4) for v in top], [round(float(v), 4) for v in bottom]


# ---------------------------------------------------------------- props


def _component_mask(m: np.ndarray, labels: np.ndarray, box: tuple) -> np.ndarray:
    x0, y0, x1, y1 = box
    sub = labels[y0:y1, x0:x1]
    ids, counts = np.unique(sub[sub > 0], return_counts=True)
    main = ids[np.argmax(counts)]
    return sub == main


def build_props(area: str) -> list[dict]:
    """Slice a props sheet into individual sprites via connected alpha components."""
    src = _load_source(area, "props")
    out_dir = OUT / area
    for old in out_dir.glob(f"{area}_prop_*.png"):
        old.unlink()
    if src is None:
        return []
    img = _key_magenta(src)
    alpha = np.asarray(img)[..., 3]
    mask = Image.fromarray(((alpha > 24) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))
    m = np.asarray(mask) > 0
    labels = np.zeros(m.shape, dtype=np.int32)
    boxes = []
    current = 0
    h, w = m.shape
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            if m[y, x] and labels[y, x] == 0:
                current += 1
                stack = [(y, x)]
                labels[y, x] = current
                x0 = x1 = x
                y0 = y1 = y
                while stack:
                    cy, cx = stack.pop()
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and labels[ny, nx] == 0:
                            labels[ny, nx] = current
                            stack.append((ny, nx))
                if (x1 - x0) > 40 and (y1 - y0) > 40:
                    boxes.append((x0, y0, x1 + 1, y1 + 1))
    entries = []
    boxes.sort(key=lambda b: ((b[1] + b[3]) // 2 > h // 2, b[0]))
    arr = np.asarray(img).copy()
    arr[..., 3] = np.where(arr[..., 3] < 20, 0, arr[..., 3])
    for index, box in enumerate(boxes):
        # Keep only this component's pixels so faint haze or neighbours never form a visible box.
        x0, y0, x1, y1 = box
        crop_arr = arr[y0:y1, x0:x1].copy()
        component = _component_mask(m, labels, box)
        crop_arr[..., 3] = np.where(component, crop_arr[..., 3], 0)
        crop = Image.fromarray(crop_arr, "RGBA")
        a = np.asarray(crop)[..., 3]
        rows = np.where(a.max(axis=1) > 24)[0]
        # hanging props touch the top of their box with a wide row; standing ones the bottom
        top_width = (a[: max(3, len(rows) // 12)] > 24).sum()
        bottom_width = (a[-max(3, len(rows) // 12) :] > 24).sum()
        kind = "hang" if box[1] < h * 0.42 and top_width >= bottom_width else "stand"
        kind = FIXTURE_PROPS.get(area, {}).get(index, kind)
        name = f"{area}_prop_{index:02d}.png"
        crop.save(out_dir / name)
        entries.append(
            {
                "path": f"res://assets/environment/areas/{area}/{name}",
                "kind": kind,
                "size_px": [crop.width, crop.height],
            }
        )
    return entries


# Props that are hazard fixtures, not random decor (index in the sliced, row-sorted sheet).
# Props with a special role. "spare" props are never auto-placed: the glowing orb cluster and the
# broken ring read as pickups/portals, so decoration could be mistaken for something interactive.
FIXTURE_PROPS = {
    "kiln": {2: "vent_fire", 3: "vent_steam"},
    "depths": {5: "spare"},
    "nexus": {6: "spare"},
}
FLUID_TOP = 400  # source row just above the surface glow (surface at 448)
FLUID_BOTTOM = 720


def build_fluid(area: str) -> dict | None:
    src = _load_source(area, "fluid")
    target = OUT / area / f"{area}_fluid.png"
    if src is None:
        if target.exists():
            target.unlink()
        return None
    img = _key_magenta(src).crop((0, FLUID_TOP, src.width, FLUID_BOTTOM))
    img = img.resize((img.width // 2, img.height // 2), Image.LANCZOS)
    img.save(target)
    return {
        "path": f"res://assets/environment/areas/{area}/{area}_fluid.png",
        "surface_y": (448 - FLUID_TOP) // 2,
    }


# ---------------------------------------------------------------- main


def build_area(area: str) -> None:
    out_dir = OUT / area
    out_dir.mkdir(parents=True, exist_ok=True)
    style = AREA_STYLE[area]
    fill = build_fill(area)
    fill.convert("RGB").save(out_dir / f"{area}_fill.png")
    top = build_top(area, fill)
    top.save(out_dir / f"{area}_top.png")
    make_cap(top, True).save(out_dir / f"{area}_top_cap_l.png")
    make_cap(top, False).save(out_dir / f"{area}_top_cap_r.png")
    bottom = build_bottom(area, fill)
    bottom.save(out_dir / f"{area}_bottom.png")
    make_cap(bottom, True).save(out_dir / f"{area}_bottom_cap_l.png")
    make_cap(bottom, False).save(out_dir / f"{area}_bottom_cap_r.png")
    side = build_side(area, fill)
    side.save(out_dir / f"{area}_side_r.png")
    side.transpose(Image.FLIP_LEFT_RIGHT).save(out_dir / f"{area}_side_l.png")
    manifest: dict = {
        "area_id": area,
        "tint": list(style["tint"]),
        "fog": list(style["fog"]),
        "glow": [c / 255 for c in style["glow"]] if style["glow"] else None,
        "particles": style["particles"],
        "far_parallax": style["far_parallax"],
        "far_modulate": list(style["far_modulate"]),
        "mid_modulate": list(style["mid_modulate"]),
        "mid_parallax": style["mid_parallax"],
        "material": {
            "fill": f"res://assets/environment/areas/{area}/{area}_fill.png",
            "top": f"res://assets/environment/areas/{area}/{area}_top.png",
            "top_cap_l": f"res://assets/environment/areas/{area}/{area}_top_cap_l.png",
            "top_cap_r": f"res://assets/environment/areas/{area}/{area}_top_cap_r.png",
            "bottom": f"res://assets/environment/areas/{area}/{area}_bottom.png",
            "bottom_cap_l": f"res://assets/environment/areas/{area}/{area}_bottom_cap_l.png",
            "bottom_cap_r": f"res://assets/environment/areas/{area}/{area}_bottom_cap_r.png",
            "side_l": f"res://assets/environment/areas/{area}/{area}_side_l.png",
            "side_r": f"res://assets/environment/areas/{area}/{area}_side_r.png",
        },
        "strip": {
            "top_height": TOP_HEIGHT,
            "top_line": TOP_LINE,
            "bottom_height": BOTTOM_HEIGHT,
            "bottom_line": BOTTOM_LINE,
            "side_width": SIDE_WIDTH,
            "side_line": SIDE_LINE,
            "cap_width": CAP_WIDTH,
        },
        "background": {},
        "props": build_props(area),
        "fluid": build_fluid(area),
    }
    for layer in ("far", "mid"):
        img = build_background(area, layer)
        target = out_dir / f"{area}_{layer}.png"
        if img is None:
            if target.exists():
                target.unlink()
            continue
        img.save(target)
        top_color, bottom_color = edge_colors(img)
        manifest["background"][layer] = {
            "path": f"res://assets/environment/areas/{area}/{area}_{layer}.png",
            "top_color": top_color,
            "bottom_color": bottom_color,
        }
    (out_dir / "area.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"built {area}")


def main() -> None:
    areas = sys.argv[1:] or list(AREAS)
    for area in areas:
        build_area(area)


if __name__ == "__main__":
    main()
