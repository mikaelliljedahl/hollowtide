#!/usr/bin/env python3
"""Build the extra dev-mode enemy sprites from their supplied HD original.

Only ``enemies_extra_hd.png`` is processed (shard turret and burrower). Pickup icons
are delivered directly as finished 128 px originals and are not generated here.
The shared matte helpers are also used by ``tools/check_spin_matte.py``.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import tempfile
from pathlib import Path
from statistics import median

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "tools" / "source_art" / "devmode"
DEFAULT_OUTPUT = ROOT / "assets" / "sprites"
DEV_OUTPUT = DEFAULT_OUTPUT / "devmode"

EXTRA_ENEMY_SOURCE = "enemies_extra_hd.png"
SOURCE_HASHES = {
    EXTRA_ENEMY_SOURCE: "bbdd5a0ef62d00170198f3441a2fc5dade7930462687c118e69a92c3326cc54b",
}
EXTRA_ENEMY_IDS = ("shard_turret", "burrower")
EXTRA_ENEMY_CELLS = {
    "shard_turret": (0, 0, 887, 887),
    "burrower": (887, 0, 1774, 887),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def key_dominance(red: int, green: int, blue: int) -> float:
    return (min(red, blue) - green) / 255.0


def border_key_stats(image: Image.Image, border: int = 20) -> tuple[float, float]:
    pixels = image.convert("RGB")
    values = []
    for y in range(pixels.height):
        for x in range(pixels.width):
            if (
                x < border
                or x >= pixels.width - border
                or y < border
                or y >= pixels.height - border
            ):
                values.append(key_dominance(*pixels.getpixel((x, y))))
    return min(values), median(values)


def chroma_matte(image: Image.Image) -> Image.Image:
    """Continuous magenta matte with source-colour recovery and soft alpha."""
    if image.mode == "RGBA":
        return image.copy()
    source = image.convert("RGB")
    background_floor, background_reference = border_key_stats(source)
    foreground_ceiling = min(0.1, background_reference - 0.25)
    key_span = max(background_reference - foreground_ceiling, 1.0 / 255.0)
    pixels = []
    for red8, green8, blue8 in source.get_flattened_data():
        red, green, blue = red8 / 255.0, green8 / 255.0, blue8 / 255.0
        key = key_dominance(red8, green8, blue8)
        coverage = (
            smoothstep((background_reference - key) / key_span) if key < background_floor else 0.0
        )
        if coverage <= 0.0:
            pixels.append((0, 0, 0, 0))
            continue
        foreground = [
            (red - (1.0 - coverage)) / coverage,
            green / coverage,
            (blue - (1.0 - coverage)) / coverage,
        ]
        if coverage < 1.0:
            spill = max(0.0, min(foreground[0], foreground[2]) - foreground[1])
            foreground[0] -= spill
            foreground[2] -= spill
        pixels.append(
            tuple(round(255 * min(1.0, max(0.0, value))) for value in foreground)
            + (round(255 * coverage),)
        )
    result = Image.new("RGBA", source.size)
    result.putdata(pixels)
    return result


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").getbbox()


def crop_visible(
    image: Image.Image, cell: tuple[int, int, int, int]
) -> tuple[Image.Image, tuple[int, int, int, int]]:
    cell_image = image.crop(cell)
    local_bbox = visible_bbox(cell_image)
    if local_bbox is None:
        raise ValueError(f"empty reviewed cell {cell}")
    return cell_image.crop(local_bbox), (
        cell[0] + local_bbox[0],
        cell[1] + local_bbox[1],
        cell[0] + local_bbox[2],
        cell[1] + local_bbox[3],
    )


def fit_centered(
    art: Image.Image, size: tuple[int, int], max_size: tuple[int, int], center: tuple[int, int]
) -> Image.Image:
    scale = min(max_size[0] / art.width, max_size[1] / art.height)
    if scale <= 0:
        raise ValueError("non-positive art scale")
    resized = art.resize(
        (max(1, round(art.width * scale)), max(1, round(art.height * scale))),
        Image.Resampling.LANCZOS,
    )
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    x = round(center[0] - resized.width / 2)
    y = round(center[1] - resized.height / 2)
    if x < 1 or y < 1 or x + resized.width > size[0] - 1 or y + resized.height > size[1] - 1:
        raise ValueError(f"art {resized.size} has insufficient transparent margin in {size}")
    result.alpha_composite(resized, (x, y))
    return result


def load_source(source_dir: Path, filename: str, expected_size: tuple[int, int]) -> Image.Image:
    path = source_dir / filename
    if not path.is_file():
        raise FileNotFoundError(f"missing source {path.relative_to(ROOT)}")
    if sha256(path) != SOURCE_HASHES[filename]:
        raise ValueError(f"source hash changed: {path.relative_to(ROOT)}")
    with Image.open(path) as image:
        if image.size != expected_size or image.mode != "RGB":
            raise ValueError(
                f"{filename}: expected RGB {expected_size}, got {image.mode} {image.size}"
            )
        return image.copy()


def save_png(image: Image.Image, path: Path) -> None:
    if image.mode != "RGBA":
        raise ValueError(f"{path}: output must be RGBA")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def build(source_dir: Path, output_root: Path) -> None:
    enemies = chroma_matte(load_source(source_dir, EXTRA_ENEMY_SOURCE, (1774, 887)))
    outputs = {}
    for enemy_id in EXTRA_ENEMY_IDS:
        art, _bbox = crop_visible(enemies, EXTRA_ENEMY_CELLS[enemy_id])
        outputs[enemy_id] = fit_centered(art, (256, 256), (224, 192), (128, 144))
    destination = output_root / "devmode"
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".devmode-art-", dir=destination) as temp_name:
        stage = Path(temp_name)
        for enemy_id, image in outputs.items():
            save_png(image, stage / f"{enemy_id}.png")
        for enemy_id in outputs:
            os.replace(stage / f"{enemy_id}.png", destination / f"{enemy_id}.png")
    print("Generated extra dev-mode enemy sprites")


def check(source_dir: Path, output_root: Path) -> list[str]:
    errors = []
    path = source_dir / EXTRA_ENEMY_SOURCE
    if not path.is_file():
        errors.append(f"missing source {path.relative_to(ROOT)}")
    elif sha256(path) != SOURCE_HASHES[path.name]:
        errors.append(f"source hash changed: {path.relative_to(ROOT)}")
    for name in EXTRA_ENEMY_IDS:
        output = output_root / "devmode" / f"{name}.png"
        if not output.is_file():
            errors.append(f"missing output {output.relative_to(ROOT)}")
            continue
        with Image.open(output) as image:
            if image.size != (256, 256) or image.mode != "RGBA":
                errors.append(f"{output.relative_to(ROOT)}: expected 256x256 RGBA")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--verify", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.check or args.verify:
            errors = check(args.source_dir, args.output_root)
            if errors:
                for error in errors:
                    print(f"FAIL: {error}", file=sys.stderr)
                return 1
            print("PASS: devmode art source/output checks")
            return 0
        build(args.source_dir, args.output_root)
        return 0
    except (OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
