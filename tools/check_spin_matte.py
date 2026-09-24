#!/usr/bin/env python3
"""Regression checks for noisy magenta spin-source matting."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import build_devmode_art  # noqa: E402

SOURCE_NAMES = {
    "player_spin": "player_spin_hd_v2.png",
    "player_spin_armed": "player_spin_armed_hd_v3.png",
}
SPIN_BLANK_ROWS = 128


def open_original(path: Path) -> Image.Image:
    with Image.open(path) as source:
        return build_devmode_art.chroma_matte(source)


def detect_spin_frames(image: Image.Image) -> list[tuple[int, int, int, int] | None]:
    boxes = []
    for index in range(8):
        left = round(index * image.width / 8)
        right = round((index + 1) * image.width / 8)
        frame = image.crop((left, 0, right, image.height))
        boxes.append(build_devmode_art.visible_bbox(frame))
    return boxes


def fail(message: str) -> None:
    raise AssertionError(message)


def check_real_sources() -> None:
    for name, source_name in SOURCE_NAMES.items():
        source = open_original(build_devmode_art.DEFAULT_SOURCE / source_name)
        alpha = source.getchannel("A")
        blank = alpha.crop((0, 0, alpha.width, SPIN_BLANK_ROWS))
        if any(value for value in blank.get_flattened_data()):
            fail(f"{name}: blank top rows received alpha")
        box = build_devmode_art.visible_bbox(source)
        if box is None or box[1] < SPIN_BLANK_ROWS:
            fail(f"{name}: alpha bbox includes source background noise: {box}")
        if name == "player_spin_armed" and not any(
            0 < value < 255 for value in alpha.get_flattened_data()
        ):
            fail(f"{name}: matte lost all soft alpha")
        # Approved unarmed v2 source uses hard alpha; synthetic pixels below
        # still prove matte recovery preserves fractional edges.
        boxes = detect_spin_frames(source)
        if len(boxes) != 8 or any(
            box is None or box[2] <= box[0] or box[3] <= box[1] for box in boxes
        ):
            fail(f"{name}: incomplete pose detection: {boxes}")

    armed = Image.open(ROOT / "assets" / "sprites" / "player_spin_armed.png")
    for index in range(8):
        frame = armed.crop((index * 256, 0, (index + 1) * 256, 256))
        glow_pixels = sum(
            1
            for red, green, blue, alpha in frame.get_flattened_data()
            if (alpha >= 128 and green > 70 and blue > 120 and blue > red * 1.7)
        )
        if glow_pixels == 0:
            fail(f"armed frame {index}: gun/glow missing")


def check_synthetic_pixels() -> None:
    image = Image.new("RGB", (128, 128), (255, 0, 255))
    draw = ImageDraw.Draw(image)
    opaque = {
        "skin": (232, 184, 148),
        "hair": (45, 30, 25),
        "outfit": (45, 70, 110),
    }
    draw.rectangle((40, 40, 49, 49), fill=opaque["skin"])
    draw.rectangle((60, 40, 69, 49), fill=opaque["hair"])
    draw.rectangle((80, 40, 89, 49), fill=opaque["outfit"])
    # Half-covered neutral edge, blended against magenta. It must remain a
    # fractional edge, not become either a hard mask or a green pixel.
    foreground = (40, 60, 80)
    background = (255, 0, 255)
    image.putpixel(
        (64, 80),
        tuple(
            round(0.5 * value + 0.5 * background[index]) for index, value in enumerate(foreground)
        ),
    )

    matte = build_devmode_art.chroma_matte(image)
    for label, point in zip(opaque, ((44, 44), (64, 44), (84, 44)), strict=True):
        pixel = matte.getpixel(point)
        if pixel[:3] != opaque[label] or pixel[3] != 255:
            fail(f"opaque {label} changed: {pixel}")
    edge = matte.getpixel((64, 80))
    if not 0 < edge[3] < 255:
        fail(f"soft edge became binary alpha: {edge}")
    if max(abs(edge[channel] - foreground[channel]) for channel in range(3)) > 18:
        fail(f"soft edge un-premultiplied incorrectly: {edge}")
    if edge[1] > edge[0] + 4 or edge[1] > edge[2] + 4:
        fail(f"soft edge has green spill: {edge}")


def main() -> int:
    check_real_sources()
    check_synthetic_pixels()
    print("PASS spin matte: noisy blank regions removed, soft alpha and armed guns retained")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
