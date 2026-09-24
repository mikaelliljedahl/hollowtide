#!/usr/bin/env python3
"""Build Flux pickup and VFX assets from audited Flux systems source sheet.

Run with ``python3 tools/build_flux_art.py``. Pillow bootstraps through uv when
not installed locally. Only SHA-gated source cells listed below are read.
"""

import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/source_art/devmode/flux_systems_hd.png"
SOURCE_HASH = "c3409e9362493a6595e9155c8f095cee0a51847e9f0b134d44c7252e0ae08753"
SOURCE_SIZE = (1536, 1024)
SPRITES = ROOT / "assets/sprites"
EFFECTS = SPRITES / "effects"
MANIFEST = EFFECTS / "manifests/flux_vfx.json"
PROOFS = ROOT / "proofs/flux_vfx"

try:
    from PIL import Image, ImageDraw, ImageFont
    from PIL import __version__ as PILLOW_VERSION
except ImportError as error:
    if os.environ.get("HOLLOWTIDE_FLUX_ART_UV_REEXEC") == "1":
        raise RuntimeError(f"Pillow import failed after bootstrap: {error}") from error
    environment = {**os.environ, "HOLLOWTIDE_FLUX_ART_UV_REEXEC": "1"}
    result = subprocess.run(
        ["uv", "run", "--with", "pillow==12.3.0", "python", str(Path(__file__).resolve())],
        cwd=ROOT,
        env=environment,
        check=False,
        timeout=300,
    )
    raise SystemExit(result.returncode)

# Source uses strict 384x256 row-major cells. These boxes are immutable for
# SOURCE_HASH. First row holds four pickups, then aura, burst, scan sequences.
PICKUPS = {
    "flux_shield.png": (0, 0, 384, 256),
    "burst_beam.png": (384, 0, 768, 256),
    "echo_scan.png": (768, 0, 1152, 256),
    "flux_tank.png": (1152, 0, 1536, 256),
}
# Source row 3, column 0 is Echo Scan's first pulse. This narrow crop retains
# central mint mote and its nearest ring only; outer scan rings and stone shards
# remain excluded so runtime refill reads as consumable, not scan hardware.
REFILL_SOURCE_CELL = (0, 768, 384, 1024)
REFILL_SOURCE_BOX = (164, 32, 236, 104)
SEQUENCES = {
    "flux_shield_aura.png": [(index * 384, 256, (index + 1) * 384, 512) for index in range(4)],
    "flux_burst.png": [(index * 384, 512, (index + 1) * 384, 768) for index in range(4)],
    "echo_scan_pulse.png": [(index * 384, 768, (index + 1) * 384, 1024) for index in range(4)],
}
OUTPUTS = {
    "devmode/flux_shield.png": ((128, 128), 1),
    "devmode/burst_beam.png": ((128, 128), 1),
    "devmode/echo_scan.png": ((128, 128), 1),
    "devmode/flux_tank.png": ((128, 128), 1),
    "devmode/flux_refill.png": ((128, 128), 1),
    "effects/flux_shield_aura.png": ((256, 256), 4),
    "effects/flux_burst.png": ((160, 96), 4),
    "effects/echo_scan_pulse.png": ((256, 256), 4),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def median_rgb(values):
    return tuple(round(median(channel)) for channel in zip(*values, strict=True))


def corner_background(cell, corner, span=28):
    width, height = cell.size
    positions = {
        "tl": (0, 0),
        "tr": (width - span, 0),
        "bl": (0, height - span),
        "br": (width - span, height - span),
    }
    start_x, start_y = positions[corner]
    pixels = cell.load()
    return median_rgb(
        [
            pixels[x, y]
            for y in range(start_y, start_y + span)
            for x in range(start_x, start_x + span)
        ]
    )


def smooth_background(cell):
    """Bilinear near-black field from border/corner background estimates."""
    corners = [corner_background(cell, name) for name in ("tl", "tr", "bl", "br")]
    width, height = cell.size
    background = Image.new("RGB", cell.size)
    data = []
    for y in range(height):
        vertical = y / max(1, height - 1)
        for x in range(width):
            horizontal = x / max(1, width - 1)
            data.append(
                tuple(
                    round(
                        (corners[0][channel] * (1 - horizontal) + corners[1][channel] * horizontal)
                        * (1 - vertical)
                        + (
                            corners[2][channel] * (1 - horizontal)
                            + corners[3][channel] * horizontal
                        )
                        * vertical
                    )
                    for channel in range(3)
                )
            )
    background.putdata(data)
    return background, corners


def soft_matte(cell):
    """Separate residual, luminance, and chroma from smooth near-black matte.

    No alpha thresholding: coverage stays continuous. Despill/unpremultiplication
    runs only below high coverage, retaining opaque dark stone and source colour.
    """
    background, corners = smooth_background(cell)
    source = cell.load()
    matte = background.load()
    pixels = []
    for y in range(cell.height):
        for x in range(cell.width):
            red, green, blue = source[x, y]
            back_red, back_green, back_blue = matte[x, y]
            residual = (
                max(abs(red - back_red), abs(green - back_green), abs(blue - back_blue)) / 255
            )
            luminance = (
                abs(
                    (red * 0.2126 + green * 0.7152 + blue * 0.0722)
                    - (back_red * 0.2126 + back_green * 0.7152 + back_blue * 0.0722)
                )
                / 255
            )
            chroma = abs((red - green) - (back_red - back_green)) + abs(
                (green - blue) - (back_green - back_blue)
            )
            chroma /= 510
            signal = max(residual, luminance, chroma)
            # 5% residual clears source-sheet near-black texture without an alpha
            # threshold. Art coverage still follows one continuous soft curve.
            coverage = smoothstep((signal - 0.05) / 0.16)
            if coverage <= 0.0005:
                pixels.append((0, 0, 0, 0))
                continue
            if coverage < 0.92:
                clean = [
                    max(0, min(255, round((value - (1 - coverage) * back) / max(coverage, 0.07))))
                    for value, back in zip(
                        (red, green, blue), (back_red, back_green, back_blue), strict=True
                    )
                ]
            else:
                clean = [red, green, blue]
            pixels.append((*clean, round(coverage * 255)))
    result = Image.new("RGBA", cell.size)
    result.putdata(pixels)
    return result, corners


def alpha_bbox(image, threshold=12):
    return image.getchannel("A").point(lambda value: 255 if value >= threshold else 0).getbbox()


def crop_visible(image):
    bbox = alpha_bbox(image)
    if bbox is None:
        raise ValueError("audited cell has no visible art")
    return image.crop(bbox), bbox


def composite_scaled(image, canvas_size, source_anchor, target_anchor, scale):
    size = (round(image.width * scale), round(image.height * scale))
    resized = image.resize(size, Image.Resampling.LANCZOS)
    left = round(target_anchor[0] - source_anchor[0] * scale)
    top = round(target_anchor[1] - source_anchor[1] * scale)
    canvas = Image.new("RGBA", canvas_size)
    canvas.alpha_composite(resized, (left, top))
    return canvas


def centered_icon(cell, scale, maximum_size=112):
    art, bbox = crop_visible(cell)
    resized = art.resize(
        (round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS
    )
    if resized.width > maximum_size or resized.height > maximum_size:
        raise ValueError(f"icon clipping risk: {resized.size}")
    output = Image.new("RGBA", (128, 128))
    output.alpha_composite(resized, ((128 - resized.width) // 2, (128 - resized.height) // 2))
    return output, bbox


def pack(frames):
    width, height = frames[0].size
    result = Image.new("RGBA", (width * len(frames), height))
    for index, frame in enumerate(frames):
        result.alpha_composite(frame, (index * width, 0))
    return result


def frame_metrics(frame):
    alpha = frame.getchannel("A")
    bbox = alpha_bbox(frame, 12)
    if bbox is None:
        raise ValueError("empty output frame")
    points = [
        (x, y, alpha.getpixel((x, y)))
        for y in range(frame.height)
        for x in range(frame.width)
        if alpha.getpixel((x, y)) >= 96
    ]
    total = sum(value for _, _, value in points)
    center = [round(sum(point[axis] * point[2] for point in points) / total, 3) for axis in (0, 1)]
    return {"visible_bbox_px": list(bbox), "opaque_weighted_center_px": center}


def verify_frame(name, frame):
    alpha = frame.getchannel("A")
    values = list(alpha.get_flattened_data())
    if not any(0 < value < 255 for value in values):
        raise ValueError(f"{name}: alpha lacks soft edge")
    if any(
        alpha.getpixel(point) >= 8
        for point in (
            (0, 0),
            (frame.width - 1, 0),
            (0, frame.height - 1),
            (frame.width - 1, frame.height - 1),
        )
    ):
        raise ValueError(f"{name}: non-transparent corner")
    if sum(value >= 250 for value in values) / len(values) > 0.62:
        raise ValueError(f"{name}: opaque matte risk")


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def contact_sheet(images, color, scale, title):
    labels = list(images)
    columns = 2
    preview_sizes = [(image.width * scale, image.height * scale) for image in images.values()]
    cell_width = max(width for width, _ in preview_sizes) + 24
    cell_height = max(height for _, height in preview_sizes) + 36
    rows = (len(labels) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_width, rows * cell_height + 26), color)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    draw.text((8, 7), title, font=font, fill=(240, 244, 250, 255))
    for index, label in enumerate(labels):
        image = images[label]
        preview = (
            image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
            if scale > 1
            else image
        )
        cell_x = (index % columns) * cell_width
        cell_y = (index // columns) * cell_height + 26
        draw.text(
            (cell_x + 6, cell_y + 3),
            label.removesuffix(".png"),
            font=font,
            fill=(240, 244, 250, 255),
        )
        sheet.alpha_composite(preview, (cell_x + (cell_width - preview.width) // 2, cell_y + 18))
    return sheet


def build():
    if PILLOW_VERSION != "12.3.0":
        raise RuntimeError(f"Pillow 12.3.0 required, found {PILLOW_VERSION}")
    if sha256(SOURCE) != SOURCE_HASH:
        raise ValueError("source hash mismatch")
    with Image.open(SOURCE) as loaded:
        if loaded.mode != "RGB" or loaded.size != SOURCE_SIZE:
            raise ValueError(f"source must be RGB {SOURCE_SIZE}, got {loaded.mode} {loaded.size}")
        source = loaded.copy()

    matted_pickups = {}
    matted_sequences = {}
    audited = {"pickups": {}, "sequences": {}}
    for name, box in PICKUPS.items():
        matted, corners = soft_matte(source.crop(box))
        matted_pickups[name] = matted
        audited["pickups"][name] = {"box_px": list(box), "background_corners_rgb": corners}
    for name, boxes in SEQUENCES.items():
        frames = []
        records = []
        for box in boxes:
            matted, corners = soft_matte(source.crop(box))
            frames.append(matted)
            records.append({"box_px": list(box), "background_corners_rgb": corners})
        matted_sequences[name] = frames
        audited["sequences"][name] = records

    refill_cell, refill_corners = soft_matte(source.crop(REFILL_SOURCE_CELL))
    refill = refill_cell.crop(REFILL_SOURCE_BOX)
    # Cell has compact mote/ring centered in a dark scan field. Keep that
    # source-derived circular motif only; soft radial edge rejects square matte
    # corners and outer Echo-scan hardware without repainting source art.
    refill_pixels = refill.load()
    for y in range(refill.height):
        for x in range(refill.width):
            distance = ((x - 35.5) ** 2 + (y - 35.5) ** 2) ** 0.5
            red, green, blue, alpha = refill_pixels[x, y]
            if distance >= 34:
                refill_pixels[x, y] = (0, 0, 0, 0)
            elif distance > 30:
                refill_pixels[x, y] = (red, green, blue, round(alpha * (34 - distance) / 4))
    refill_art, refill_visible_box = crop_visible(refill)
    audited["pickups"]["flux_refill.png"] = {
        "source_cell_box_px": list(REFILL_SOURCE_CELL),
        "box_px": list(REFILL_SOURCE_BOX),
        "background_corners_rgb": refill_corners,
        "visible_box_px": list(refill_visible_box),
        "selection": "bright central energy mote plus compact nearest ring; excludes outer scan expansion and stone fragments",
    }

    icon_arts = [crop_visible(image)[0] for image in matted_pickups.values()]
    icon_scale = min(
        112 / max(image.width for image in icon_arts),
        112 / max(image.height for image in icon_arts),
    )
    outputs = {}
    for name, image in matted_pickups.items():
        output, bbox = centered_icon(image, icon_scale)
        outputs[f"devmode/{name}"] = output
        audited["pickups"][name]["visible_box_px"] = list(bbox)
    refill_scale = min(72 / refill_art.width, 72 / refill_art.height)
    refill_output, _ = centered_icon(refill, refill_scale, maximum_size=72)
    outputs["devmode/flux_refill.png"] = refill_output
    # Fixed source-cell centers map to fixed runtime anchors. One scale per strip.
    aura_scale = 0.64
    # Whole 384x256 source cell fits within 160x96 at this one shared scale.
    # It preserves late-frame debris rather than clipping bottom-edge evolution.
    burst_scale = 0.34
    scan_scale = 0.64
    sequence_specs = {
        "flux_shield_aura.png": ((256, 256), (192, 128), (128, 128), aura_scale),
        "flux_burst.png": ((160, 96), (192, 128), (80, 48), burst_scale),
        "echo_scan_pulse.png": ((256, 256), (192, 128), (128, 128), scan_scale),
    }
    for name, frames in matted_sequences.items():
        canvas_size, source_anchor, target_anchor, scale = sequence_specs[name]
        output_frames = [
            composite_scaled(frame, canvas_size, source_anchor, target_anchor, scale)
            for frame in frames
        ]
        for index, frame in enumerate(output_frames):
            verify_frame(f"{name} frame {index}", frame)
        outputs[f"effects/{name}"] = pack(output_frames)

    for name, image in outputs.items():
        frame_size, count = OUTPUTS[name]
        if image.size != (frame_size[0] * count, frame_size[1]):
            raise ValueError(f"{name}: wrong output size {image.size}")
        for index in range(count):
            verify_frame(
                name,
                image.crop((index * frame_size[0], 0, (index + 1) * frame_size[0], frame_size[1])),
            )

    proof_images = {
        path.removeprefix("devmode/").removeprefix("effects/"): image
        for path, image in outputs.items()
    }
    with tempfile.TemporaryDirectory(prefix=".flux-art-", dir=ROOT) as temporary:
        stage = Path(temporary)
        for relative, image in outputs.items():
            save(image, stage / "sprites" / relative)
        manifest = {
            "schema_version": 1,
            "pillow": PILLOW_VERSION,
            "source": {
                "path": "res://tools/source_art/devmode/flux_systems_hd.png",
                "sha256": SOURCE_HASH,
                "size_px": list(SOURCE_SIZE),
                "mode": "RGB",
                "grid": [4, 4],
                "cell_size_px": [384, 256],
            },
            "matting": "per-cell bilinear near-black background estimated from 28px border corners; continuous residual, luminance, and chroma coverage; edge-only despill; no chroma key, binary alpha, palette conversion, or independent frame scaling",
            "audited_cells": audited,
            "placement": {
                "icons": {
                    "canvas_px": [128, 128],
                    "common_scale": icon_scale,
                    "center_px": [64, 64],
                },
                "flux_refill": {
                    "canvas_px": [128, 128],
                    "center_px": [64, 64],
                    "maximum_visible_span_px": 72,
                    "common_scale": refill_scale,
                    "source_cell": [0, 3],
                },
                "flux_shield_aura": {
                    "frame_px": [256, 256],
                    "frames": 4,
                    "source_anchor_px": [192, 128],
                    "frame_source_anchor_px": [[192, 128]] * 4,
                    "anchor_px": [128, 128],
                    "frame_anchor_px": [[128, 128]] * 4,
                    "common_scale": aura_scale,
                },
                "flux_burst": {
                    "frame_px": [160, 96],
                    "frames": 4,
                    "source_anchor_px": [192, 128],
                    "frame_source_anchor_px": [[192, 128]] * 4,
                    "physics_kernel_center_px": [80, 48],
                    "frame_anchor_px": [[80, 48]] * 4,
                    "common_scale": burst_scale,
                    "nose_contract_max_x": 159,
                },
                "echo_scan_pulse": {
                    "frame_px": [256, 256],
                    "frames": 4,
                    "source_anchor_px": [192, 128],
                    "frame_source_anchor_px": [[192, 128]] * 4,
                    "anchor_px": [128, 128],
                    "frame_anchor_px": [[128, 128]] * 4,
                    "common_scale": scan_scale,
                    "expansion": "monotonic",
                },
            },
            "runtime_wiring": {
                "pickup_catalog": "res://scripts/progression/content_catalog.gd",
                "player_runtime": "res://scripts/player/player_flux_runtime.gd",
                "shield_scene": "res://scenes/effects/flux/flux_shield_aura.tscn",
                "burst_scene": "res://scenes/combat/flux_burst_projectile.tscn",
                "echo_scene": "res://scenes/effects/flux/echo_scan_pulse.tscn",
            },
            "runtime_outputs": {},
            "proofs": {
                background: [
                    f"res://proofs/flux_vfx/{background}_native.png",
                    f"res://proofs/flux_vfx/{background}_4x.png",
                ]
                for background in ("dark", "light", "cave")
            },
            "review": {
                "human_visual_approval": False,
                "accepted": "Technical alpha, framing, common-scale, and anchor gate passed; source-derived art needs game-camera approval.",
                "pending": [
                    "runtime wiring",
                    "normal-camera cave contrast",
                    "gameplay timing",
                    "human visual approval",
                ],
            },
        }
        for relative, image in outputs.items():
            frame_size, count = OUTPUTS[relative]
            frames = [
                image.crop((index * frame_size[0], 0, (index + 1) * frame_size[0], frame_size[1]))
                for index in range(count)
            ]
            manifest["runtime_outputs"][f"res://assets/sprites/{relative}"] = {
                "size_px": list(image.size),
                "frame_size_px": list(frame_size),
                "frames": count,
                "sha256": sha256(stage / "sprites" / relative),
                "frame_metrics": [frame_metrics(frame) for frame in frames],
            }
        for background, color in {
            "dark": (11, 14, 20, 255),
            "light": (222, 229, 238, 255),
            "cave": (25, 34, 48, 255),
        }.items():
            save(
                contact_sheet(proof_images, color, 1, f"Flux VFX — {background} — native"),
                stage / "proofs" / f"{background}_native.png",
            )
            save(
                contact_sheet(proof_images, color, 4, f"Flux VFX — {background} — 4x"),
                stage / "proofs" / f"{background}_4x.png",
            )
        manifest_path = stage / "flux_vfx.json"
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        for relative in outputs:
            destination = SPRITES / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / "sprites" / relative, destination)
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        os.replace(manifest_path, MANIFEST)
        PROOFS.mkdir(parents=True, exist_ok=True)
        for background in ("dark", "light", "cave"):
            for scale in ("native", "4x"):
                os.replace(
                    stage / "proofs" / f"{background}_{scale}.png",
                    PROOFS / f"{background}_{scale}.png",
                )
    print("PASS flux-art: SHA-gated extraction, soft matte, outputs, manifest, proofs")


if __name__ == "__main__":
    build()
