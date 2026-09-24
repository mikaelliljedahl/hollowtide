#!/usr/bin/env python3
"""Render the three original Phase 1 expansion enemies from authored SVG."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/source_art/devmode/f1_new_enemies.svg"
OUTPUT = ROOT / "assets/sprites/devmode"
PROOF = ROOT / "proofs/new_enemies"
MANIFEST = OUTPUT / "f1_new_enemy_manifest.json"
IDS = ("grasshopper", "shooting_gargoyle", "lava_monster")


def sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_source(destination: Path):
    result = subprocess.run(
        [
            "magick",
            "-background",
            "none",
            "-density",
            "96",
            str(SOURCE),
            "-define",
            "png:exclude-chunk=date,time",
            str(destination),
        ],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "ImageMagick SVG render failed")


def main():
    if not SOURCE.is_file():
        raise FileNotFoundError(SOURCE)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PROOF.mkdir(parents=True, exist_ok=True)
    records = {}
    proof = Image.new("RGBA", (1536, 512), (10, 15, 20, 255))
    with tempfile.TemporaryDirectory(prefix="hollowtide-new-enemies-") as temp_name:
        rendered_path = Path(temp_name) / "source.png"
        render_source(rendered_path)
        with Image.open(rendered_path) as loaded:
            source = loaded.convert("RGBA")
        if source.size != (1536, 512):
            raise ValueError(f"unexpected SVG raster size {source.size}")
        for index, runtime_id in enumerate(IDS):
            cell = source.crop((index * 512, 0, (index + 1) * 512, 512))
            scaled = cell.resize((236, 236), Image.Resampling.LANCZOS)
            frame = Image.new("RGBA", (256, 256))
            frame.alpha_composite(scaled, (10, 10))
            alpha_box = frame.getchannel("A").getbbox()
            if (
                alpha_box is None
                or min(alpha_box[0], alpha_box[1], 256 - alpha_box[2], 256 - alpha_box[3]) < 7
            ):
                raise ValueError(
                    f"{runtime_id}: silhouette lacks safe transparent margin: {alpha_box}"
                )
            path = OUTPUT / f"{runtime_id}.png"
            frame.save(path, format="PNG", optimize=False, compress_level=9)
            proof.alpha_composite(
                frame.resize((512, 512), Image.Resampling.LANCZOS), (index * 512, 0)
            )
            records[runtime_id] = {
                "path": f"res://assets/sprites/devmode/{runtime_id}.png",
                "size_px": [256, 256],
                "sha256": sha256(path),
                "visible_bbox_px": list(alpha_box),
                "runtime_owner": "res://scripts/enemies/combat_enemy.gd",
                "status": "runtime",
            }
    proof_path = PROOF / "catalog_dark_2x.png"
    proof.save(proof_path, format="PNG", optimize=False, compress_level=9)
    manifest = {
        "schema_version": 1,
        "source": {
            "path": "res://tools/source_art/devmode/f1_new_enemies.svg",
            "sha256": sha256(SOURCE),
            "size_px": [1536, 512],
            "authorship": "original Hollowtide vector source; no external or private-reference assets",
        },
        "outputs": records,
        "proof": {
            "path": "res://proofs/new_enemies/catalog_dark_2x.png",
            "sha256": sha256(proof_path),
            "size_px": [1536, 512],
        },
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS new enemy art: three original silhouettes, safe alpha, manifest, and proof")


if __name__ == "__main__":
    main()
