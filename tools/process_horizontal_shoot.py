#!/usr/bin/env python3
"""Process horizontal firing pose into one runtime sprite frame."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import build_devmode_art  # noqa: E402

SOURCE = ROOT / "tools/source_art/devmode/player_shoot_right_hd.png"
OUTPUT = ROOT / "assets/sprites/player_shoot_horizontal.png"
FRAME_SIZE = (256, 256)
BODY_HEIGHT = 192
FEET_ROW = 240
ALPHA_THRESHOLD = 128
FOOT_BAND_HEIGHT = 36
# Blue-green barrel-tip pixel measured in supplied source image.
SOURCE_MUZZLE = (955, 281)


def opaque_bbox(image: Image.Image, threshold: int = ALPHA_THRESHOLD):
    bbox = build_devmode_art.visible_bbox(image, threshold)
    if bbox is None:
        raise ValueError("source has no opaque artwork")
    return bbox


def foot_midpoint(image: Image.Image, body_box: tuple[int, int, int, int]):
    alpha = image.getchannel("A")
    left, _, right, bottom = body_box
    top = max(body_box[1], bottom - FOOT_BAND_HEIGHT)
    points = [
        (x, y)
        for y in range(top, bottom)
        for x in range(left, right)
        if alpha.getpixel((x, y)) >= ALPHA_THRESHOLD
    ]
    if not points:
        raise ValueError("source feet/support band has no opaque pixels")
    foot_box = (min(x for x, _ in points), top, max(x for x, _ in points) + 1, bottom)
    return (foot_box[0] + foot_box[2] - 1) / 2, foot_box


def atomic_save(image: Image.Image, path: Path):
    temporary = path.with_name(f".{path.name}.tmp")
    try:
        image.save(temporary, format="PNG", optimize=False, compress_level=9)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def process():
    source = build_devmode_art.open_original(SOURCE)
    body_box = opaque_bbox(source, 24)
    body_height = body_box[3] - body_box[1]
    scale = BODY_HEIGHT / body_height
    foot_x, foot_box = foot_midpoint(source, body_box)
    cropped = source.crop(body_box)
    resized = cropped.resize(
        (round(cropped.width * scale), round(cropped.height * scale)),
        Image.Resampling.LANCZOS,
    )

    top = FEET_ROW - resized.height + 1
    foot_x_in_resized = (foot_x - body_box[0]) * resized.width / cropped.width
    left = round(128 - foot_x_in_resized)
    output = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    output.alpha_composite(resized, (left, top))

    # Resolve integer rounding from measured output feet, not sprite-bbox centering.
    output_foot_points = [
        (x, y)
        for y in range(FEET_ROW - FOOT_BAND_HEIGHT, FEET_ROW + 1)
        for x in range(FRAME_SIZE[0])
        if output.getchannel("A").getpixel((x, y)) >= ALPHA_THRESHOLD
    ]
    if not output_foot_points:
        raise ValueError("processed feet/support band has no opaque pixels")
    output_foot_min = min(x for x, _ in output_foot_points)
    output_foot_max = max(x for x, _ in output_foot_points)
    output_foot_mid = (output_foot_min + output_foot_max) / 2
    left += round(128 - output_foot_mid)
    output = Image.new("RGBA", FRAME_SIZE, (0, 0, 0, 0))
    output.alpha_composite(resized, (left, top))

    source_muzzle_x, source_muzzle_y = SOURCE_MUZZLE
    muzzle_x = left + round((source_muzzle_x - body_box[0]) * resized.width / cropped.width)
    muzzle_y = top + round((source_muzzle_y - body_box[1]) * resized.height / cropped.height)
    if not (0 <= muzzle_x < FRAME_SIZE[0] and 0 <= muzzle_y < FRAME_SIZE[1]):
        raise ValueError(f"muzzle point outside frame: {(muzzle_x, muzzle_y)}")

    atomic_save(output, OUTPUT)
    final_box = opaque_bbox(output, 24)
    alpha_values = list(output.getchannel("A").get_flattened_data())
    if output.size != FRAME_SIZE or output.mode != "RGBA":
        raise ValueError(f"runtime output contract failed: {output.size} {output.mode}")
    if final_box[1] != 49 or final_box[3] != FEET_ROW + 1:
        raise ValueError(f"body/foot alignment failed: {final_box}")
    if not any(0 < alpha < 255 for alpha in alpha_values):
        raise ValueError("soft alpha missing")
    if (muzzle_x, muzzle_y) == (128, 240):
        raise ValueError("muzzle collapsed onto feet root")

    return {
        "source": str(SOURCE.relative_to(ROOT)),
        "output": str(OUTPUT.relative_to(ROOT)),
        "source_body_bbox_alpha24": list(body_box),
        "source_foot_bbox_alpha128_band": list(foot_box),
        "source_foot_midpoint_x": foot_x,
        "scale": scale,
        "runtime_bbox_alpha24": list(final_box),
        "runtime_feet_root": [128, FEET_ROW],
        "source_muzzle_blue_barrel_tip": list(SOURCE_MUZZLE),
        "runtime_muzzle": [muzzle_x, muzzle_y],
        "muzzle_locator": "rightmost blue-green barrel-tip highlight in source weapon ROI; mapped through crop/scale/placement",
        "runtime_frame_center": [128, 128],
        "alpha": "RGBA continuous soft alpha; full color; no quantization",
    }


def main():
    print(json.dumps(process(), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
