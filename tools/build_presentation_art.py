#!/usr/bin/env python3
"""Build audited player presentation, fixtures, roster repairs, and Flux refill."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "assets" / "sprites"
DEV = SPRITES / "devmode"
PROOFS = ROOT / "proofs" / "presentation_art"
SOURCE = ROOT / "tools" / "source_art"
DEV_SOURCE = SOURCE / "devmode"
SOURCES = {
    "player_run_hd.png": "4ea36728313f920fc4aae4bb2bf4e2fd7a44d32760a4384df0197e7ced30d6ef",
    "player_run_armed_hd.png": "b27038dc42afc918affa3f8269405aae5ab6cbc33c45aeb78cdb957622de7ad6",
    "dev_fixtures_hd.png": "c807a802d591d7b264f06f0bd16f315d37cc93eee9e04f4abc1545c5348ba7ab",
    "player_sprint_wall_hd.png": "784d98e70899e49f39382c515197aabc41fe3a7d0be949b6fb21405e7d4a3061",
    "enemy_roster_hd.png": "08b872fad041e380d5e0d868a1334dccf86c04102465f6f49f2743c0b138db44",
    "boss_roster_hd.png": "ee8ca8c0a82e5eb62621cf924678af9c2e946b5c330c896faa4678142778caec",
    "flux_systems_hd.png": "c3409e9362493a6595e9155c8f095cee0a51847e9f0b134d44c7252e0ae08753",
}
TIDAL_ALPHA_THRESHOLD = 12
TIDAL_MIN_TOP_PADDING = 32
TIDAL_MIN_SIDE_PADDING = 24
TIDAL_MAX_BOTTOM = 480
TIDAL_BASELINE_Y = 440
TIDAL_BASELINE_TOLERANCE = 24

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    if os.environ.get("HOLLOWTIDE_PRESENTATION_ART_BOOTSTRAP"):
        raise
    env = {**os.environ, "HOLLOWTIDE_PRESENTATION_ART_BOOTSTRAP": "1"}
    raise SystemExit(
        subprocess.run(
            ["uv", "run", "--with", "pillow==12.3.0", "python", __file__, *sys.argv[1:]],
            cwd=ROOT,
            env=env,
            check=False,
        ).returncode
    )

sys.path.insert(0, str(ROOT / "tools"))
import gen_sprites  # noqa: E402


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name, size, mode=None):
    path = (
        DEV_SOURCE / name
        if name
        in {
            "dev_fixtures_hd.png",
            "player_sprint_wall_hd.png",
            "enemy_roster_hd.png",
            "boss_roster_hd.png",
            "flux_systems_hd.png",
        }
        else SOURCE / name
    )
    if digest(path) != SOURCES[name]:
        raise ValueError(f"source hash mismatch: {path.relative_to(ROOT)}")
    with Image.open(path) as raw:
        if raw.size != size or (mode and raw.mode != mode):
            raise ValueError(f"unexpected source: {path.relative_to(ROOT)} {raw.mode} {raw.size}")
        return raw.convert("RGBA")


def bbox(image, threshold=12):
    return image.getchannel("A").point(lambda x: 255 if x >= threshold else 0).getbbox()


def components(image, threshold=32):
    alpha = image.getchannel("A")
    w, h = image.size
    seen = bytearray(w * h)
    px = alpha.load()
    result = []
    for y in range(h):
        for x in range(w):
            start = y * w + x
            if seen[start] or px[x, y] < threshold:
                continue
            seen[start] = 1
            q = deque([(x, y)])
            points = []
            left = right = x
            top = bottom = y
            while q:
                a, b = q.popleft()
                points.append((a, b))
                left = min(left, a)
                right = max(right, a)
                top = min(top, b)
                bottom = max(bottom, b)
                for ny in range(max(0, b - 1), min(h, b + 2)):
                    for nx in range(max(0, a - 1), min(w, a + 2)):
                        i = ny * w + nx
                        if not seen[i] and px[nx, ny] >= threshold:
                            seen[i] = 1
                            q.append((nx, ny))
            result.append((points, (left, top, right + 1, bottom + 1)))
    return result


def distance(a, b):
    return max(a[0] - b[2], b[0] - a[2], 0) ** 2 + max(a[1] - b[3], b[1] - a[3], 0) ** 2


def isolate(cell, radius=56):
    """Keep main cell-local body plus intentional nearby pieces; never bleed neighbor cells."""
    found = components(cell)
    if not found:
        raise ValueError("empty audited cell")
    anchor, anchor_box = max(found, key=lambda item: len(item[0]))
    keep = []
    for points, box in found:
        if points is anchor or distance(box, anchor_box) <= radius * radius:
            keep.extend(points)
    out = Image.new("RGBA", cell.size)
    src = cell.load()
    dst = out.load()
    for x, y in keep:
        dst[x, y] = src[x, y]
    return out, anchor_box, len(found), len(keep)


def component_center(box):
    return ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)


def component_in_cell(box, cell_box):
    x, y = component_center(box)
    return cell_box[0] <= x < cell_box[2] and cell_box[1] <= y < cell_box[3]


def intentional_parts(found, anchor, cell_box=None, radius=32):
    """Accept only compact, nearby detail; reject studio noise and neighboring rows."""
    anchor_points, anchor_box = anchor
    accepted = [anchor]
    rejected_boundary = 0
    for candidate in found:
        points, box = candidate
        if candidate is anchor:
            continue
        touches_row = cell_box and (box[1] <= cell_box[1] or box[3] >= cell_box[3])
        if touches_row:
            rejected_boundary += 1
            continue
        if cell_box and not component_in_cell(box, cell_box):
            continue
        if not (128 <= len(points) <= len(anchor_points) * 0.15):
            continue
        width, height = box[2] - box[0], box[3] - box[1]
        anchor_width, anchor_height = anchor_box[2] - anchor_box[0], anchor_box[3] - anchor_box[1]
        if width > anchor_width * 0.75 or height > anchor_height * 0.75:
            continue
        if distance(box, anchor_box) > radius * radius:
            continue
        accepted.append(candidate)
    return accepted, rejected_boundary


def masked_components(image, accepted, radius=4):
    """Preserve original RGBA inside 4px component support; zero all else."""
    support = Image.new("L", image.size)
    pixels = bytearray(image.width * image.height)
    for points, _ in accepted:
        for x, y in points:
            pixels[y * image.width + x] = 255
    support.frombytes(bytes(pixels))
    support = support.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    source = image.load()
    mask = support.load()
    bounds = [image.width, image.height, 0, 0]
    for _, box in accepted:
        bounds[0] = min(bounds[0], box[0])
        bounds[1] = min(bounds[1], box[1])
        bounds[2] = max(bounds[2], box[2])
        bounds[3] = max(bounds[3], box[3])
    left = max(0, bounds[0] - radius)
    top = max(0, bounds[1] - radius)
    right = min(image.width, bounds[2] + radius)
    bottom = min(image.height, bounds[3] + radius)
    result = Image.new("RGBA", (right - left, bottom - top))
    output = result.load()
    for y in range(top, bottom):
        for x in range(left, right):
            if mask[x, y]:
                output[x - left, y - top] = source[x, y]
    return result


def player_metrics(frame):
    """Frame-local alpha/noise facts used in manifest and deterministic gate."""
    alpha = frame.getchannel("A")
    results = {}
    for threshold in (8, 32):
        found = components(frame, threshold)
        anchor, anchor_box = max(found, key=lambda item: len(item[0]))
        significant = [
            (points, box) for points, box in found if len(points) >= max(16, len(anchor) // 100)
        ]
        support = Image.new("L", frame.size)
        values = bytearray(frame.width * frame.height)
        for points, _ in significant:
            for x, y in points:
                values[y * frame.width + x] = 255
        support.frombytes(bytes(values))
        support = support.filter(ImageFilter.MaxFilter(13))
        support_values = support.load()
        outside = sum(
            alpha.getpixel((x, y)) >= threshold and not support_values[x, y]
            for y in range(frame.height)
            for x in range(frame.width)
        )
        top_significant = [
            len(points) for points, box in significant if box[1] < 32 and anchor_box[1] >= 32
        ]
        results[str(threshold)] = {
            "components": len(found),
            "significant_components": len(significant),
            "main_area_px": len(anchor),
            "main_bbox_px": list(anchor_box),
            "top32_significant_px": sum(top_significant),
            "outside_6px_support_px": outside,
        }
    return results


def assert_player_frame(label, frame, exclusion_zones=()):
    metrics = player_metrics(frame)
    alpha = frame.getchannel("A")
    for threshold, values in metrics.items():
        if values["significant_components"] != 1:
            raise ValueError(f"{label}: fragmented alpha>={threshold} silhouette")
        if values["top32_significant_px"]:
            raise ValueError(f"{label}: detached top-row alpha>={threshold}")
        if values["outside_6px_support_px"] > 2:
            raise ValueError(f"{label}: alpha>={threshold} outside 6px support")
    for zone in exclusion_zones:
        if any(
            alpha.getpixel((x, y)) >= 8
            for x in range(zone[0], zone[2])
            for y in range(zone[1], zone[3])
        ):
            raise ValueError(f"{label}: source-audited fragment zone occupied {zone}")
    return metrics


def tidal_metrics(frame):
    """Measured non-destructive Tidal placement facts for manifest and gates."""
    alpha = frame.getchannel("A")
    visible = bbox(frame, TIDAL_ALPHA_THRESHOLD)
    if visible is None:
        raise ValueError("tidal_heart: empty alpha")
    found = components(frame, 32)
    anchor, _ = max(found, key=lambda item: len(item[0]))
    significant = [
        (points, box) for points, box in found if len(points) >= max(16, len(anchor) // 100)
    ]
    edge_fragment_pixels = sum(
        alpha.getpixel((x, y)) >= TIDAL_ALPHA_THRESHOLD
        for y in range(frame.height)
        for x in (
            *range(TIDAL_MIN_SIDE_PADDING),
            *range(frame.width - TIDAL_MIN_SIDE_PADDING, frame.width),
        )
    )
    return {
        "alpha_threshold": TIDAL_ALPHA_THRESHOLD,
        "visible_bbox_px": list(visible),
        "top_padding_px": visible[1],
        "bottom_padding_px": frame.height - visible[3],
        "left_padding_px": visible[0],
        "right_padding_px": frame.width - visible[2],
        "baseline_y_px": visible[3],
        "partial_alpha_pixels": sum(0 < value < 255 for value in alpha.get_flattened_data()),
        "alpha32_components": len(found),
        "significant_alpha32_components": len(significant),
        "edge_fragment_alpha12_pixels": edge_fragment_pixels,
    }


def tidal_invariant_errors(frame, metrics=None):
    metrics = metrics or tidal_metrics(frame)
    visible = metrics["visible_bbox_px"]
    errors = []
    if visible[1] < TIDAL_MIN_TOP_PADDING:
        errors.append(f"top padding {visible[1]} < {TIDAL_MIN_TOP_PADDING}")
    if visible[3] > TIDAL_MAX_BOTTOM:
        errors.append(f"bottom {visible[3]} > {TIDAL_MAX_BOTTOM}")
    if metrics["left_padding_px"] < TIDAL_MIN_SIDE_PADDING:
        errors.append(f"left padding {metrics['left_padding_px']} < {TIDAL_MIN_SIDE_PADDING}")
    if metrics["right_padding_px"] < TIDAL_MIN_SIDE_PADDING:
        errors.append(f"right padding {metrics['right_padding_px']} < {TIDAL_MIN_SIDE_PADDING}")
    if metrics["partial_alpha_pixels"] == 0:
        errors.append("partial alpha absent")
    if metrics["alpha32_components"] != 1 or metrics["significant_alpha32_components"] != 1:
        errors.append("detached alpha>=32 component")
    if metrics["edge_fragment_alpha12_pixels"]:
        errors.append("detached edge fragment")
    if abs(metrics["baseline_y_px"] - TIDAL_BASELINE_Y) > TIDAL_BASELINE_TOLERANCE:
        errors.append(
            f"baseline {metrics['baseline_y_px']} not comparable to grounded boss baseline"
        )
    return errors


def resize_place(art, canvas, anchor=(128, 240), scale=None, max_box=(224, 192), bbox_threshold=12):
    box = bbox(art, bbox_threshold)
    if box is None:
        raise ValueError("empty art")
    cropped = art.crop(box)
    if scale is None:
        scale = min(max_box[0] / cropped.width, max_box[1] / cropped.height)
    size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    if size[0] >= canvas[0] or size[1] >= canvas[1]:
        raise ValueError(f"clipping risk {size} in {canvas}")
    scaled = cropped.resize(size, Image.Resampling.LANCZOS)
    out = Image.new("RGBA", canvas)
    out.alpha_composite(scaled, (round(anchor[0] - size[0] / 2), round(anchor[1] - size[1] + 1)))
    return out, scale


def pack(frames):
    out = Image.new("RGBA", (sum(frame.width for frame in frames), frames[0].height))
    for i, frame in enumerate(frames):
        out.alpha_composite(frame, (i * frame.width, 0))
    return out


def grid(image, cols, rows, col, row):
    xs = [round(i * image.width / cols) for i in range(cols + 1)]
    ys = [round(i * image.height / rows) for i in range(rows + 1)]
    return image.crop((xs[col], ys[row], xs[col + 1], ys[row + 1])), [
        xs[col],
        ys[row],
        xs[col + 1],
        ys[row + 1],
    ]


def player_run(name):
    """Continuously matte chroma source, then retain only audited pose components."""
    source = load(name, (2172, 724), "RGB")
    matte = gen_sprites.chroma_matte(source)
    found = components(matte, 32)
    anchors = sorted(found, key=lambda item: len(item[0]), reverse=True)[:8]
    if len(anchors) != 8:
        raise ValueError(f"{name}: expected eight humanoid anchors")
    anchors.sort(key=lambda item: component_center(item[1])[0])
    arts = []
    audit = []
    for index, anchor in enumerate(anchors):
        accepted, _ = intentional_parts(found, anchor, radius=32)
        art = masked_components(matte, accepted)
        arts.append(art)
        audit.append(
            {
                "frame": index,
                "anchor_bbox_px": list(anchor[1]),
                "accepted_components": len(accepted),
                "rejected_components": len(found) - len(accepted),
            }
        )
    scale = min(192 / (bbox(art, 32)[3] - bbox(art, 32)[1]) for art in arts)
    frames = [resize_place(art, (256, 256), scale=scale)[0] for art in arts]
    metrics = [
        assert_player_frame(f"{name} frame {index}", frame) for index, frame in enumerate(frames)
    ]
    return pack(frames), {
        "common_scale": scale,
        "feet_y": [240] * 8,
        "pivot_px": [128, 240],
        "frames": 8,
        "source_components": audit,
        "frame_metrics": metrics,
        "status": "accepted",
    }


def sprint_and_wall():
    source = load("player_sprint_wall_hd.png", (1402, 1122), "RGBA")
    found = components(source, 32)
    mappings = {
        "player_sprint.png": [(i, 0) for i in range(5)] + [(i, 1) for i in range(3)],
        "player_sprint_armed.png": [(i, 2) for i in range(5)] + [(i, 3) for i in range(3)],
    }
    # Audited output regions where prior cell crops admitted feet/gun fragments
    # from adjoining source rows. These zones intentionally exclude body pixels.
    fragment_zones = {
        # Source-row leaks previously appeared above target body bounds. These
        # audited empty caps flank each affected lower-row output; component
        # metrics below catch any fragment in remaining upper-body space.
        "player_sprint.png": [
            ([0, 32, 32, 48], [224, 32, 256, 48]),
            ([0, 32, 32, 48], [224, 32, 256, 48]),
            ([0, 32, 32, 48], [224, 32, 256, 48]),
        ],
        "player_sprint_armed.png": [
            ([0, 32, 32, 48], [224, 32, 256, 48]),
            ([0, 32, 32, 48], [224, 32, 256, 48]),
            ([0, 32, 32, 48], [224, 32, 256, 48]),
        ],
    }
    outputs = {}
    records = {}
    for name, positions in mappings.items():
        arts = []
        cells = []
        for col, row in positions:
            _, cell_box = grid(source, 5, 4, col, row)
            in_cell = [item for item in found if component_in_cell(item[1], cell_box)]
            if not in_cell:
                raise ValueError(f"{name}: no humanoid anchor in source cell {(col, row)}")
            anchor = max(in_cell, key=lambda item: len(item[0]))
            accepted, rejected_boundary = intentional_parts(found, anchor, cell_box, radius=32)
            art = masked_components(source, accepted)
            arts.append(art)
            cells.append(
                {
                    "cell": [col, row],
                    "box_px": cell_box,
                    "anchor_bbox_px": list(anchor[1]),
                    "accepted_components": len(accepted),
                    "rejected_row_boundary_components": rejected_boundary,
                }
            )
        scale = min(
            192 / max(bbox(art, 32)[3] - bbox(art, 32)[1] for art in arts),
            224 / max(bbox(art, 32)[2] - bbox(art, 32)[0] for art in arts),
        )
        frames = [resize_place(art, (256, 256), scale=scale)[0] for art in arts]
        zones = [()] * 5 + fragment_zones[name]
        metrics = [
            assert_player_frame(f"{name} frame {index}", frame, zones[index])
            for index, frame in enumerate(frames)
        ]
        outputs[name] = pack(frames)
        records[name] = {
            "frames": 8,
            "common_scale": scale,
            "feet_y": [240] * 8,
            "pivot_px": [128, 240],
            "cells": cells,
            "fragment_exclusion_zones_px": zones,
            "frame_metrics": metrics,
            "status": "accepted",
        }
    # One scale/pivot for all four wall poses. Right-facing hands/shoulders make
    # contact readable; source has no wall plane, so none is invented.
    wall = []
    for armed, row in ((False, 1), (True, 3)):
        for kind, col in (("wall_slide", 3), ("wall_jump", 4)):
            cell, cell_box = grid(source, 5, 4, col, row)
            art, ab, count, _ = isolate(cell, 8)
            wall.append((armed, kind, cell_box, art, ab, count))
    wall_scale = min(
        208 / max(bbox(art)[3] - bbox(art)[1] for _, _, _, art, _, _ in wall),
        224 / max(bbox(art)[2] - bbox(art)[0] for _, _, _, art, _, _ in wall),
    )
    for armed, kind, cell_box, art, ab, count in wall:
        frame, _ = resize_place(art, (256, 256), anchor=(128, 224), scale=wall_scale)
        name = f"player_{kind}{'_armed' if armed else ''}.png"
        outputs[name] = frame
        records[name] = {
            "frames": 1,
            "common_scale": wall_scale,
            "pivot_px": [128, 240],
            "source_cell": [3 if kind == "wall_slide" else 4, 1 if not armed else 3],
            "source_box_px": cell_box,
            "components": count,
            "anchor_bbox_px": list(ab),
            "status": "accepted",
            "contact_read": "right-facing raised hand and shoulder retained; source has no painted wall plane",
        }
    return outputs, records


def fixtures():
    source = load("dev_fixtures_hd.png", (1774, 887), "RGBA")
    ids = [
        "passage_arch",
        "missile_gate",
        "wave_grate",
        "bomb_gate",
        "undertow_gate",
        "checkpoint_shrine",
        "refill_shrine",
        "flux_shrine",
    ]
    out = {}
    records = {}
    for index, name in enumerate(ids):
        col, row = index % 4, index // 4
        cell, box = grid(source, 4, 2, col, row)
        # Source alpha is coverage authority. Scale whole audited cell so no reservoir/gate piece is dropped.
        image = cell.resize((512, 512) if index < 5 else (256, 256), Image.Resampling.LANCZOS)
        out[f"devmode/{name}.png"] = image
        records[name] = {
            "cell": [col, row],
            "box_px": box,
            "output_px": list(image.size),
            "source_alpha_primary": True,
            "visible_bbox_px": list(bbox(image) or ()),
            "status": "accepted",
        }
    records["passage_arch"]["runtime_opening_target_px"] = 192
    records["passage_arch"]["opening_policy"] = (
        "source center remains transparent; no fill/debug bars added"
    )
    return out, records


def roster():
    enemy = load("enemy_roster_hd.png", (1536, 1024), "RGBA")
    boss = load("boss_roster_hd.png", (2172, 724), "RGBA")
    specs = {
        "vent_flyer": (enemy, 4, 2, 1, 0, (256, 256), (128, 144)),
        "hopper": (enemy, 4, 2, 2, 0, (256, 256), (128, 144)),
        # Keep the complete hanging crown inside the runtime frame. The old y=132
        # anchor cropped 51 pixels from the top of the source component.
        "frost_floater": (enemy, 4, 2, 1, 1, (256, 256), (128, 200)),
        "tidal_heart": (boss, 3, 1, 2, 0, (512, 512), (256, 296)),
    }
    out = {}
    records = {}
    for name, (src, cols, rows, col, row, size, anchor) in specs.items():
        cell, cell_box = grid(src, cols, rows, col, row)
        art, ab, count, kept = isolate(cell, 8)
        record = {
            "cell": [col, row],
            "box_px": cell_box,
            "anchor_component_bbox_px": list(ab),
            "components_found": count,
            "pixels_kept": kept,
            "status": "accepted",
        }
        if name == "tidal_heart":
            # Keep every non-zero source-alpha pixel in primary component. Selection
            # never rewrites alpha; detached left source fragment remains excluded.
            found = components(cell, 1)
            primary = max(found, key=lambda item: len(item[0]))
            art = masked_components(cell, [primary], radius=1)
            frame, scale = resize_place(
                art,
                size,
                anchor=(256, TIDAL_BASELINE_Y),
                max_box=(448, 400),
                bbox_threshold=1,
            )
            metrics = tidal_metrics(frame)
            errors = tidal_invariant_errors(frame, metrics)
            if errors:
                raise ValueError(f"tidal_heart: {'; '.join(errors)}")
            record.update(
                {
                    "anchor_component_bbox_px": list(primary[1]),
                    "components_found": len(found),
                    "pixels_kept": len(primary[0]),
                    "common_scale": scale,
                    "retention_policy": "complete primary alpha>0 component; detached components excluded",
                    "selection_alpha_threshold": 1,
                    "invariants": metrics,
                    "visible_bbox_px": metrics["visible_bbox_px"],
                }
            )
        else:
            frame, scale = resize_place(
                art, size, anchor=anchor, max_box=(size[0] - 48, size[1] - 72)
            )
            record.update(
                {
                    "common_scale": scale,
                    "visible_bbox_px": list(bbox(frame) or ()),
                }
            )
        out[f"devmode/{name}.png"] = frame
        records[name] = record
    return out, records


def refill():
    source = load("flux_systems_hd.png", (1536, 1024), "RGB").convert("RGB")
    # Reuse Flux pipeline matte. Exact cell-local crop remains audited there.
    import build_flux_art

    cell, _ = build_flux_art.soft_matte(source.crop((0, 768, 384, 1024)))
    art = cell.crop((164, 32, 236, 104))
    pixels = art.load()
    for y in range(art.height):
        for x in range(art.width):
            distance = ((x - 35.5) ** 2 + (y - 35.5) ** 2) ** 0.5
            red, green, blue, alpha = pixels[x, y]
            if distance >= 34:
                pixels[x, y] = (0, 0, 0, 0)
            elif distance > 30:
                pixels[x, y] = (red, green, blue, round(alpha * (34 - distance) / 4))
    frame, scale = resize_place(art, (128, 128), anchor=(64, 99), max_box=(72, 72))
    return {"devmode/flux_refill.png": frame}, {
        "source_cell": [0, 3],
        "source_cell_box_px": [0, 768, 384, 1024],
        "box_px": [164, 32, 236, 104],
        "common_scale": scale,
        "status": "accepted",
        "visible_bbox_px": list(bbox(frame) or ()),
    }


def proof_sheet(images, background, scale, title):
    names = list(images)
    cell = 280 * scale
    rows = (len(names) + 3) // 4
    out = Image.new("RGBA", (cell * 4, cell * rows + 32), (background))
    draw = ImageDraw.Draw(out)
    font = ImageFont.load_default()
    draw.text((8, 8), title, font=font, fill=(240, 244, 250, 255))
    for i, name in enumerate(names):
        image = images[name]
        preview = (
            image.resize((image.width * scale, image.height * scale), Image.Resampling.LANCZOS)
            if scale > 1
            else image
        )
        preview.thumbnail((cell - 24, cell - 52), Image.Resampling.LANCZOS)
        x = (i % 4) * cell + (cell - preview.width) // 2
        y = (i // 4) * cell + 38 + (cell - 42 - preview.height) // 2
        out.alpha_composite(preview, (x, y))
        draw.text(
            ((i % 4) * cell + 6, (i // 4) * cell + 22), name, font=font, fill=(240, 244, 250, 255)
        )
    return out


def player_proof_sheet(images, background, scale, title):
    """One frame per tile. Unlike strip thumbnails, 4x stays genuinely 4x."""
    cell = 280 * scale
    out = Image.new("RGBA", (cell * 4, cell * 2 + 32), background)
    draw = ImageDraw.Draw(out)
    font = ImageFont.load_default()
    draw.text((8, 8), title, font=font, fill=(240, 244, 250, 255))
    for index in range(8):
        frame = images.crop((index * 256, 0, (index + 1) * 256, 256))
        preview = frame.resize((256 * scale, 256 * scale), Image.Resampling.LANCZOS)
        x = (index % 4) * cell + (cell - preview.width) // 2
        y = (index // 4) * cell + 32 + (cell - preview.height) // 2
        out.alpha_composite(preview, (x, y))
        draw.text(
            ((index % 4) * cell + 6, (index // 4) * cell + 20),
            f"{title} frame {index}",
            font=font,
            fill=(240, 244, 250, 255),
        )
    return out


def visual_profiles(outputs=None):
    """Read staged outputs first so manifest never observes previous build state."""
    profiles = {}
    outputs = outputs or {}

    def visible(relative):
        staged = outputs.get(relative)
        if staged is not None:
            return bbox(staged.convert("RGBA"))
        with Image.open(SPRITES / relative) as image:
            return bbox(image.convert("RGBA"))

    normal = (
        "ceiling_diver",
        "vent_flyer",
        "hopper",
        "spitter",
        "armored_guard",
        "frost_floater",
        "energy_parasite",
        "shard_turret",
        "burrower",
        "grasshopper",
        "shooting_gargoyle",
        "lava_monster",
    )
    # crawler remains legacy 128px asset; profile derives its current visible bounds too.
    for name in ("crawler", *normal):
        relative = "crawler.png" if name == "crawler" else f"devmode/{name}.png"
        box = visible(relative)
        profiles[name] = {
            "desired_texture_scale": 1.0,
            # Moving frost_floater down inside its texture prevents source art
            # clipping; compensate here so its world-space silhouette stays put.
            "local_visual_offset_px": [
                0,
                -164 if name == "frost_floater" else (15 if name == "lava_monster" else -96),
            ],
            "nominal_visible_bounds_px": list(box or ()),
            "grounded": name
            in {
                "crawler",
                "hopper",
                "spitter",
                "armored_guard",
                "shard_turret",
                "burrower",
                "grasshopper",
            },
            "collider_note": "visual profile only; collision unchanged",
        }
    for name in ("stone_guardian", "furnace_mother", "tidal_heart"):
        box = visible(f"devmode/{name}.png")
        profiles[name] = {
            "desired_texture_scale": 1.0,
            "local_visual_offset_px": [0, -192],
            "nominal_visible_bounds_px": list(box or ()),
            "grounded": name in {"stone_guardian", "furnace_mother"},
            "collider_note": "visual profile only; collision unchanged",
        }
    return profiles


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=False, compress_level=9)


def build():
    runs = {
        "player_run.png": player_run("player_run_hd.png"),
        "player_run_armed.png": player_run("player_run_armed_hd.png"),
    }
    sprint, sprint_records = sprint_and_wall()
    fix, fix_records = fixtures()
    roster_out, roster_records = roster()
    refill_out, refill_record = refill()
    outputs = (
        {name: image for name, (image, _) in runs.items()} | sprint | fix | roster_out | refill_out
    )
    with tempfile.TemporaryDirectory(prefix=".presentation-art-", dir=ROOT) as temp:
        stage = Path(temp)
        for relative, image in outputs.items():
            save(image, stage / relative)
        entries = {}
        for relative, image in outputs.items():
            entries[f"res://assets/sprites/{relative}"] = {
                "sha256": digest(stage / relative),
                "size_px": list(image.size),
                "accepted": True,
            }
        manifest = {
            "schema_version": 2,
            "sources": {name: {"sha256": value} for name, value in SOURCES.items()},
            "player": {
                "run": runs["player_run.png"][1],
                "run_armed": runs["player_run_armed.png"][1],
                "sprint": sprint_records,
            },
            "fixtures": fix_records,
            "roster_repairs": roster_records,
            "flux_refill": refill_record,
            "outputs": entries,
            "rejected": {},
            "runtime_visual_profiles": visual_profiles(outputs),
            "runtime_wiring": {
                "player_poses": "res://scripts/player/player.gd",
                "enemy_boss_profiles": "res://scripts/enemies/effects/runtime_visual_profiles.gd",
                "enemy_loader": "res://scripts/enemies/combat_enemy.gd",
                "boss_loader": "res://scripts/enemies/boss.gd",
                "station_fixtures": "res://scripts/dev/dev_station_layout.gd",
                "passages": "res://scripts/dev/dev_passage.gd",
                "gates": "res://scripts/world/ability_gate.gd",
                "wave_grates": "res://scripts/world/wave_grate.gd",
            },
            "review": "native and 4x proof sheets required; technical acceptance only",
        }
        (stage / "devmode_art_manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n"
        )
        proof_images = {
            **{name: im for name, (im, _) in runs.items()},
            **sprint,
            **fix,
            **roster_out,
            **refill_out,
        }
        for label, color in {
            "dark": (11, 14, 20, 255),
            "light": (222, 229, 238, 255),
            "checker": (90, 90, 90, 255),
        }.items():
            save(
                proof_sheet(proof_images, color, 1, f"Presentation art {label} native"),
                stage / f"{label}_native.png",
            )
            save(
                proof_sheet(proof_images, color, 4, f"Presentation art {label} 4x"),
                stage / f"{label}_4x.png",
            )
            for name in (
                "player_run.png",
                "player_run_armed.png",
                "player_sprint.png",
                "player_sprint_armed.png",
            ):
                for scale in (1, 4):
                    save(
                        player_proof_sheet(
                            proof_images[name], color, scale, f"{name} {label} {scale}x"
                        ),
                        stage / f"{Path(name).stem}_{label}_{scale}x.png",
                    )
        # Named close-up/overlay proof retains source-cell audit context.
        save(
            proof_sheet(
                {
                    "tidal_before": grid(
                        load("boss_roster_hd.png", (2172, 724), "RGBA"), 3, 1, 2, 0
                    )[0],
                    "tidal_after": roster_out["devmode/tidal_heart.png"],
                },
                (11, 14, 20, 255),
                1,
                "Tidal connected-component repair",
            ),
            stage / "tidal_closeup.png",
        )
        for relative in outputs:
            dest = SPRITES / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            os.replace(stage / relative, dest)
        os.replace(stage / "devmode_art_manifest.json", DEV / "devmode_art_manifest.json")
        PROOFS.mkdir(parents=True, exist_ok=True)
        for path in stage.glob("*.png"):
            os.replace(path, PROOFS / path.name)
    print("PASS presentation-art: deterministic source-gated processing, manifests, proofs")


def check():
    manifest_path = DEV / "devmode_art_manifest.json"
    if not manifest_path.is_file():
        return ["missing devmode art manifest"]
    data = json.loads(manifest_path.read_text())
    errors = []
    for source, record in data.get("sources", {}).items():
        if record.get("sha256") != SOURCES.get(source):
            errors.append(f"source manifest hash mismatch: {source}")
    for path, entry in data.get("outputs", {}).items():
        file = ROOT / path.removeprefix("res://")
        if not file.is_file() or digest(file) != entry.get("sha256"):
            errors.append(f"output hash mismatch: {path}")
            continue
        with Image.open(file) as image:
            rgba = image.convert("RGBA")
            a = rgba.getchannel("A")
            if image.mode != "RGBA":
                errors.append(f"not RGBA: {path}")
            if any(
                a.getpixel(p) >= 16
                for p in ((0, 0), (a.width - 1, 0), (0, a.height - 1), (a.width - 1, a.height - 1))
            ):
                errors.append(f"opaque corner/matte: {path}")
            if not any(0 < x < 255 for x in a.get_flattened_data()):
                errors.append(f"no soft alpha: {path}")
    tidal_path = DEV / "tidal_heart.png"
    tidal_record = data.get("roster_repairs", {}).get("tidal_heart", {})
    if not tidal_path.is_file():
        errors.append("missing tidal_heart output")
    else:
        with Image.open(tidal_path) as image:
            metrics = tidal_metrics(image.convert("RGBA"))
        errors.extend(f"tidal_heart: {error}" for error in tidal_invariant_errors(None, metrics))
        if tidal_record.get("invariants") != metrics:
            errors.append("tidal_heart: manifest invariants mismatch")
    for label in ("dark", "light", "checker"):
        for scale in ("native", "4x"):
            if not (PROOFS / f"{label}_{scale}.png").is_file():
                errors.append(f"missing proof {label}_{scale}")
        for name in ("player_run", "player_run_armed", "player_sprint", "player_sprint_armed"):
            for scale in (1, 4):
                if not (PROOFS / f"{name}_{label}_{scale}x.png").is_file():
                    errors.append(f"missing player proof {name}_{label}_{scale}x")
    return errors


if __name__ == "__main__":
    errors = check() if "--check" in sys.argv else (build() or [])
    if errors:
        print("\n".join(f"FAIL {x}" for x in errors), file=sys.stderr)
        raise SystemExit(1)
    if "--check" in sys.argv:
        print("PASS presentation-art checks")
