#!/usr/bin/env python3
"""Build audited Phase 1 VFX and player-pose PNGs from supplied HD sheets.

Only source-hash-specific cells below are read. Output is staged, validated, then
atomically replaced. Matting keeps continuous source coverage and applies only
edge despill; it never keys against a single flat background colour.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont
from PIL import __version__ as PILLOW_VERSION

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "tools" / "source_art" / "devmode"
SPRITE_DIR = ROOT / "assets" / "sprites"
EFFECT_DIR = SPRITE_DIR / "effects"
MANIFEST_DIR = EFFECT_DIR / "manifests"
PROOF_DIR = ROOT / "proofs" / "phase1_vfx"

SOURCES = {
    "wave_core": {
        "file": "wave_core_hd.png",
        "hash": "71a0778c8620de4e27695a1e07b0f12ec06e348b92aad84c57a1ad1b3f8e672e",
        "size": [1774, 887],
        "grid": [4, 2],
    },
    "wave_interactions": {
        "file": "wave_interactions_hd.png",
        "hash": "bbe120cc20a1352f23a722bc3d94cdbde82b1f5c610765f82547c2fc8df0aad2",
        "size": [1448, 1086],
        "grid": [4, 3],
    },
    "beam_family": {
        "file": "beam_family_vfx_hd.png",
        "hash": "ad8c129ab1c5615185c96f4eb0ce1684bac33a74a5f9f8d04926d80484afe26e",
        "size": [1536, 1024],
        "grid": [4, 4],
    },
    "player_extra": {
        "file": "player_movement_extra_hd.png",
        "hash": "e979c7b6fbc72aec3b24585b0618c9143bff2c2c8b27b04ffdcd909c25e5e111",
        "size": [1536, 1024],
        "grid": [4, 2],
    },
}

# Exact source boxes audited against these immutable source hashes. Unequal 1774
# pixel wave columns intentionally use [0, 444, 887, 1330, 1774].
WAVE_CORE_BOXES = [
    (0, 0, 444, 444),
    (444, 0, 887, 444),
    (887, 0, 1330, 444),
    (1330, 0, 1774, 444),
    (0, 444, 444, 887),
    (444, 444, 887, 887),
    (887, 444, 1330, 887),
    (1330, 444, 1774, 887),
]
WAVE_MUZZLE_BOXES = [(index * 362, 0, (index + 1) * 362, 362) for index in range(4)]
WAVE_IMPACT_BOXES = [
    *((index * 362, 362, (index + 1) * 362, 724) for index in range(4)),
    *((index * 362, 724, (index + 1) * 362, 1086) for index in range(4)),
]
BASE_CORE_BOXES = [(index * 384, 0, (index + 1) * 384, 256) for index in range(4)]
BASE_IMPACT_BOXES = [(index * 384, 256, (index + 1) * 384, 512) for index in range(4)]
ICE_CORE_BOXES = [(index * 384, 512, (index + 1) * 384, 768) for index in range(4)]
ICE_IMPACT_BOXES = [(index * 384, 768, (index + 1) * 384, 1024) for index in range(4)]
PLAYER_BOXES = {
    "player_crouch.png": (0, 0, 384, 512),
    "player_crouch_armed.png": (384, 0, 768, 512),
    "player_crouch_shoot_horizontal.png": (768, 0, 1152, 512),
    "player_run_sprint.png": (1152, 0, 1536, 512),
    "player_run_sprint_armed.png": (0, 512, 384, 1024),
    "player_wall_slide.png": (384, 512, 768, 1024),
    "player_shoot_horizontal_air.png": (768, 512, 1152, 1024),
    "player_crouch_hurt.png": (1152, 512, 1536, 1024),
}

# Wall cell depicts back-facing loose pose, no readable wall contact. Do not
# publish runtime file: player code keeps existing fallback animation.
REJECTED_PLAYER = {
    "player_wall_slide.png": "Rejected: back-facing pose lacks wall plane/contact read; fallback remains safer.",
}
SUPERSEDED_RUNTIME_OUTPUTS = {
    "player_run_sprint.png": "replaced by authored eight-frame player_sprint.png",
    "player_run_sprint_armed.png": "replaced by authored eight-frame player_sprint_armed.png",
    "player_crouch_hurt.png": "runtime damage uses blink/knockback without a dedicated hurt pose",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_pillow():
    if PILLOW_VERSION != "12.3.0":
        raise RuntimeError(f"Pillow 12.3.0 required, found {PILLOW_VERSION}")


def source_image(source_id):
    spec = SOURCES[source_id]
    path = SOURCE_DIR / spec["file"]
    if not path.is_file():
        raise FileNotFoundError(f"Missing source: {path.relative_to(ROOT)}")
    if sha256(path) != spec["hash"]:
        raise ValueError(f"Source hash mismatch: {path.relative_to(ROOT)}")
    with Image.open(path) as image:
        if list(image.size) != spec["size"] or image.mode != "RGBA":
            raise ValueError(
                f"Invalid source: {path.relative_to(ROOT)} is {image.mode} {image.size}"
            )
        return image.copy()


def alpha_bbox(image, threshold=12):
    alpha = image.getchannel("A")
    return alpha.point(lambda value: 255 if value >= threshold else 0).getbbox()


def median_rgb(values):
    return tuple(median(channel) for channel in zip(*values, strict=True))


def corner_background(image, corner, span=24):
    width, height = image.size
    positions = {
        "tl": (0, 0),
        "tr": (width - span, 0),
        "bl": (0, height - span),
        "br": (width - span, height - span),
    }
    origin_x, origin_y = positions[corner]
    pixels = image.load()
    samples = []
    for y in range(origin_y, origin_y + span):
        for x in range(origin_x, origin_x + span):
            red, green, blue, alpha = pixels[x, y]
            if alpha <= 8:
                samples.append((red, green, blue))
    if len(samples) < span:
        samples = [pixels[origin_x + span // 2, origin_y + span // 2][:3]]
    return median_rgb(samples)


def smooth_background(image):
    """Per-cell bilinear low-frequency background from transparent border corners."""
    corners = [corner_background(image, corner) for corner in ("tl", "tr", "bl", "br")]
    width, height = image.size
    result = Image.new("RGB", image.size)
    data = []
    for y in range(height):
        vertical = y / max(1, height - 1)
        for x in range(width):
            horizontal = x / max(1, width - 1)
            top = [
                corners[0][index] * (1 - horizontal) + corners[1][index] * horizontal
                for index in range(3)
            ]
            bottom = [
                corners[2][index] * (1 - horizontal) + corners[3][index] * horizontal
                for index in range(3)
            ]
            data.append(
                tuple(
                    round(top[index] * (1 - vertical) + bottom[index] * vertical)
                    for index in range(3)
                )
            )
    result.putdata(data)
    return result


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def soft_matte(cell, profile):
    """Recover edge RGB from smooth background while retaining continuous alpha.

    Source alpha is primary coverage. Colour/luminance residual recovers thin
    low-alpha glow detail only. Dark player outlines retain source alpha even
    when their RGB residual against a navy background is small.
    """
    background = smooth_background(cell)
    source = cell.load()
    bg = background.load()
    pixels = []
    for y in range(cell.height):
        for x in range(cell.width):
            red, green, blue, alpha8 = source[x, y]
            back_red, back_green, back_blue = bg[x, y]
            alpha = alpha8 / 255.0
            residual = (
                max(abs(red - back_red), abs(green - back_green), abs(blue - back_blue)) / 255.0
            )
            luminance = (
                abs(
                    (red * 0.2126 + green * 0.7152 + blue * 0.0722)
                    - (back_red * 0.2126 + back_green * 0.7152 + back_blue * 0.0722)
                )
                / 255.0
            )
            recovered = smoothstep((max(residual, luminance) - 0.028) / 0.22)
            # VFX keeps faint glow. Player recovery stays constrained to source
            # alpha so gradient noise cannot create a rectangular halo.
            # Only recover where source already signals an edge. This excludes
            # smooth background curvature from becoming translucent rectangles.
            edge_proximity = smoothstep(alpha / 0.03)
            if profile == "vfx":
                coverage = max(alpha, recovered * 0.32 * edge_proximity)
            else:
                coverage = max(alpha, min(alpha + 0.04, recovered * 0.10 * edge_proximity))
            if coverage <= 0.001:
                pixels.append((0, 0, 0, 0))
                continue
            # Edge-only despill. High-coverage original RGB remains intact.
            if coverage < 0.92:
                recovery_alpha = max(coverage, 0.08)
                clean = [
                    max(0.0, min(255.0, (value - (1.0 - coverage) * back) / recovery_alpha))
                    for value, back in zip(
                        (red, green, blue), (back_red, back_green, back_blue), strict=True
                    )
                ]
            else:
                clean = [red, green, blue]
            pixels.append((*[round(value) for value in clean], round(coverage * 255)))
    output = Image.new("RGBA", cell.size)
    output.putdata(pixels)
    return output


def crop_art(source, box, profile):
    cell = source.crop(box)
    matted = soft_matte(cell, profile)
    bbox = alpha_bbox(matted)
    if bbox is None:
        raise ValueError(f"No visible art in audited cell {box}")
    return matted.crop(bbox), bbox


def fit_art(art, canvas_size, max_size, anchor, source_anchor=None, scale=None):
    if scale is None:
        scale = min(max_size[0] / art.width, max_size[1] / art.height)
    size = (max(1, round(art.width * scale)), max(1, round(art.height * scale)))
    resized = art.resize(size, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", canvas_size)
    if source_anchor is None:
        left = round(anchor[0] - resized.width / 2)
        top = round(anchor[1] - resized.height / 2)
    else:
        left = round(anchor[0] - source_anchor[0] * scale)
        top = round(anchor[1] - source_anchor[1] * scale)
    if (
        left < 0
        or top < 0
        or left + resized.width > canvas_size[0]
        or top + resized.height > canvas_size[1]
    ):
        raise ValueError(f"Clipped art {size} on {canvas_size} at {(left, top)}")
    output.alpha_composite(resized, (left, top))
    return output


def pack_strip(frames, frame_size):
    strip = Image.new("RGBA", (frame_size[0] * len(frames), frame_size[1]))
    for index, frame in enumerate(frames):
        if frame.size != frame_size:
            raise ValueError(f"Unexpected frame size {frame.size}; expected {frame_size}")
        strip.alpha_composite(frame, (index * frame_size[0], 0))
    return strip


def build_effect(source, boxes, frame_size, max_size, name, boxes_record):
    arts = []
    for box in boxes:
        art, visible = crop_art(source, box, "vfx")
        arts.append((art, visible))
    widths = [art.width for art, _ in arts]
    heights = [art.height for art, _ in arts]
    # One sequence-wide scale: deliberate pose/impact evolution stays visible,
    # but individual crops never inflate and pump.
    scale = min(max_size[0] / max(widths), max_size[1] / max(heights))
    frames = [
        fit_art(art, frame_size, max_size, (frame_size[0] / 2, frame_size[1] / 2), scale=scale)
        for art, _ in arts
    ]
    boxes_record[name] = {
        "audited_boxes_px": [list(box) for box in boxes],
        "visible_boxes_px": [list(box) for _, box in arts],
        "common_scale": scale,
    }
    return pack_strip(frames, frame_size)


def player_support_x(image):
    alpha = image.getchannel("A")
    bbox = alpha_bbox(image)
    if bbox is None:
        raise ValueError("Player art empty")
    band_top = max(bbox[1], bbox[3] - max(24, image.height // 12))
    points = [
        (x, y)
        for y in range(band_top, bbox[3])
        for x in range(bbox[0], bbox[2])
        if alpha.getpixel((x, y)) >= 96
    ]
    if not points:
        raise ValueError("Player art has no opaque support")
    return median(x for x, _ in points), bbox[3]


def build_players(source, boxes_record):
    cropped = {}
    for name, box in PLAYER_BOXES.items():
        art, visible = crop_art(source, box, "player")
        cropped[name] = (art, visible)
    # Full running bodies provide 192px reference. One common scale applies to
    # every accepted pose; crouch/air variation survives unaltered.
    references = [
        cropped["player_run_sprint.png"][0].height,
        cropped["player_run_sprint_armed.png"][0].height,
    ]
    scale = 192 / median(references)
    outputs = {}
    for name, (art, visible) in cropped.items():
        support_x, support_y = player_support_x(art)
        # Canvas centre is horizontal root for every pose. Bottommost support
        # selects baseline only: sprint's leading foot must not shift whole body.
        output = fit_art(art, (256, 256), (256, 256), (128, 240), (art.width / 2, support_y), scale)
        opaque_box = alpha_bbox(output, 96)
        if opaque_box is None:
            raise ValueError(f"No opaque player silhouette after placement: {name}")
        baseline_delta = 241 - opaque_box[3]
        if abs(baseline_delta) > 3:
            raise ValueError(f"Unexpected player baseline correction {baseline_delta}: {name}")
        if baseline_delta:
            corrected = Image.new("RGBA", (256, 256))
            corrected.alpha_composite(output, (0, baseline_delta))
            output = corrected
        boxes_record[name] = {
            "audited_box_px": list(PLAYER_BOXES[name]),
            "visible_box_px": list(visible),
            "support_source_px": [support_x, support_y],
            "common_scale": scale,
            "status": "rejected" if name in REJECTED_PLAYER else "accepted",
        }
        if name not in REJECTED_PLAYER:
            outputs[name] = output
    return outputs, scale


def save_png(image, path):
    if image.mode != "RGBA":
        raise ValueError(f"{path}: non-RGBA output")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def font():
    return ImageFont.load_default()


def contact_sheet(images, background, scale, title):
    names = list(images)
    columns = 4
    native_w = max(image.width for image in images.values())
    native_h = max(image.height for image in images.values())
    cell_w = native_w * scale + 20
    cell_h = native_h * scale + 36
    rows = (len(names) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h + 24), background)
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 6), title, fill=(240, 244, 250, 255), font=font())
    for index, name in enumerate(names):
        image = images[name]
        preview = (
            image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
            if scale > 1
            else image
        )
        x = (index % columns) * cell_w + (cell_w - preview.width) // 2
        y = (index // columns) * cell_h + 24 + 18
        sheet.alpha_composite(preview, (x, y))
        draw.text(
            ((index % columns) * cell_w + 6, (index // columns) * cell_h + 24),
            name.replace(".png", ""),
            fill=(235, 240, 248, 255),
            font=font(),
        )
    return sheet


def verify_image(name, image, frame_size, count):
    errors = []
    if image.mode != "RGBA" or image.size != (frame_size[0] * count, frame_size[1]):
        errors.append(f"{name}: wrong dimensions/mode {image.mode} {image.size}")
    alpha = image.getchannel("A")
    values = alpha.get_flattened_data()
    if not any(0 < value < 255 for value in values):
        errors.append(f"{name}: no partial alpha")
    for index in range(count):
        frame = alpha.crop((index * frame_size[0], 0, (index + 1) * frame_size[0], frame_size[1]))
        bbox = alpha_bbox(Image.merge("RGBA", (frame, frame, frame, frame)))
        if bbox is None:
            errors.append(f"{name}: empty frame {index}")
            continue
        corners = [
            frame.getpixel(point)
            for point in (
                (0, 0),
                (frame.width - 1, 0),
                (0, frame.height - 1),
                (frame.width - 1, frame.height - 1),
            )
        ]
        if any(value >= 16 for value in corners):
            errors.append(f"{name}: opaque corner frame {index}")
    return errors


def build():
    require_pillow()
    sources = {source_id: source_image(source_id) for source_id in SOURCES}
    boxes_record = {}
    outputs = {
        "effects/wave_core.png": build_effect(
            sources["wave_core"], WAVE_CORE_BOXES, (96, 64), (88, 58), "wave_core", boxes_record
        ),
        "effects/wave_muzzle.png": build_effect(
            sources["wave_interactions"],
            WAVE_MUZZLE_BOXES,
            (128, 128),
            (112, 104),
            "wave_muzzle",
            boxes_record,
        ),
        "effects/wave_impact.png": build_effect(
            sources["wave_interactions"],
            WAVE_IMPACT_BOXES,
            (128, 128),
            (110, 110),
            "wave_impact",
            boxes_record,
        ),
        "effects/base_core.png": build_effect(
            sources["beam_family"], BASE_CORE_BOXES, (96, 64), (88, 58), "base_core", boxes_record
        ),
        "effects/base_impact.png": build_effect(
            sources["beam_family"],
            BASE_IMPACT_BOXES,
            (128, 128),
            (110, 110),
            "base_impact",
            boxes_record,
        ),
        "effects/ice_core.png": build_effect(
            sources["beam_family"], ICE_CORE_BOXES, (96, 64), (88, 58), "ice_core", boxes_record
        ),
        "effects/ice_impact.png": build_effect(
            sources["beam_family"],
            ICE_IMPACT_BOXES,
            (128, 128),
            (110, 110),
            "ice_impact",
            boxes_record,
        ),
    }
    player_outputs, player_scale = build_players(sources["player_extra"], boxes_record)
    outputs.update(player_outputs)

    errors = []
    for name, image in outputs.items():
        if name.startswith("effects/"):
            frame_size = (96, 64) if name.endswith("_core.png") else (128, 128)
            errors.extend(verify_image(name, image, frame_size, image.width // frame_size[0]))
        else:
            errors.extend(verify_image(name, image, (256, 256), 1))
    if errors:
        raise ValueError("; ".join(errors))

    effect_images = {
        name.removeprefix("effects/"): image
        for name, image in outputs.items()
        if name.startswith("effects/")
    }
    player_images = {
        name: image for name, image in outputs.items() if not name.startswith("effects/")
    }
    proof_images = {**effect_images, **player_images}
    backgrounds = {
        "dark": (11, 14, 20, 255),
        "light": (222, 229, 238, 255),
        "cave": (25, 34, 48, 255),
    }

    manifest = {
        "schema_version": 1,
        "pillow": PILLOW_VERSION,
        "sources": {
            source_id: {
                "path": f"res://tools/source_art/devmode/{spec['file']}",
                "sha256": spec["hash"],
                "size_px": spec["size"],
                "grid": spec["grid"],
            }
            for source_id, spec in SOURCES.items()
        },
        "matting": "per-cell bilinear low-frequency RGB background estimated from transparent border corners; source alpha primary; residual/luminance recovery; edge-only despill; no chroma key, thresholded alpha, or palette conversion",
        "audited_cells": boxes_record,
        "runtime_outputs": {},
        "review": {
            "accepted_frames": {
                "wave_core": [f"frame_{index}" for index in range(8)],
                "wave_muzzle": [f"frame_{index}" for index in range(4)],
                "wave_impact": [f"frame_{index}" for index in range(8)],
                "base_core": [f"frame_{index}" for index in range(4)],
                "base_impact": [f"frame_{index}" for index in range(4)],
                "ice_core": [f"frame_{index}" for index in range(4)],
                "ice_impact": [f"frame_{index}" for index in range(4)],
                "player": sorted(player_outputs),
            },
            "wave_core_frame_7": "Accepted: source contraction visually closes into similarly compact frame_0 under one sequence-wide scale; no isolated tiny loop pop.",
            "rejected_frames": REJECTED_PLAYER,
            "human_visual_approval": False,
            "pending": [
                "real-level gameplay timing",
                "normal-camera cave contrast",
                "user visual acceptance",
            ],
        },
        "rejected": REJECTED_PLAYER,
        "player_anchor": {
            "canvas_px": [256, 256],
            "support_row": 240,
            "reference_height_px": 192,
            "common_scale": player_scale,
        },
        "proofs": {
            name: [
                f"res://proofs/phase1_vfx/{name}_native.png",
                f"res://proofs/phase1_vfx/{name}_4x.png",
            ]
            for name in backgrounds
        },
    }

    with tempfile.TemporaryDirectory(prefix=".phase1-vfx-", dir=ROOT) as temp_name:
        stage = Path(temp_name)
        for name, image in outputs.items():
            save_png(image, stage / "sprites" / name)
        for background_name, color in backgrounds.items():
            save_png(
                contact_sheet(proof_images, color, 1, f"Phase 1 VFX — {background_name} — native"),
                stage / "proofs" / f"{background_name}_native.png",
            )
            save_png(
                contact_sheet(proof_images, color, 4, f"Phase 1 VFX — {background_name} — 4x"),
                stage / "proofs" / f"{background_name}_4x.png",
            )
        for name in outputs:
            staged = stage / "sprites" / name
            entry = {
                "size_px": list(Image.open(staged).size),
                "sha256": sha256(staged),
                "frames": Image.open(staged).width // (96 if name.endswith("_core.png") else 128)
                if name.startswith("effects/")
                else 1,
            }
            if name in SUPERSEDED_RUNTIME_OUTPUTS:
                entry["delivery_status"] = "superseded"
                entry["status_reason"] = SUPERSEDED_RUNTIME_OUTPUTS[name]
            else:
                entry["delivery_status"] = "runtime"
                if name.startswith("effects/"):
                    entry["runtime_owner"] = (
                        "res://scripts/combat/beam_fx_muzzle.gd"
                        if name.endswith("wave_muzzle.png")
                        else "res://scripts/combat/beam_fx_impact.gd"
                        if name.endswith("impact.png")
                        else "res://scripts/combat/beam_shot.gd"
                    )
                else:
                    entry["runtime_owner"] = "res://scripts/player/player.gd"
            manifest["runtime_outputs"][f"res://assets/sprites/{name}"] = entry
        manifest_path = stage / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

        for name in outputs:
            destination = SPRITE_DIR / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / "sprites" / name, destination)
        MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
        os.replace(manifest_path, MANIFEST_DIR / "phase1_vfx.json")
        PROOF_DIR.mkdir(parents=True, exist_ok=True)
        for background_name in backgrounds:
            for suffix in ("native", "4x"):
                os.replace(
                    stage / "proofs" / f"{background_name}_{suffix}.png",
                    PROOF_DIR / f"{background_name}_{suffix}.png",
                )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Build into owned runtime paths; retained for command symmetry.",
    )
    parser.parse_args()
    build()
    print("PASS phase1-vfx: outputs, alpha, anchors, manifests, and proofs written")


if __name__ == "__main__":
    main()
