#!/usr/bin/env python3
"""Build coherent original fire-jet and steam-vent animation strips."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/source_art/devmode/industrial_hazards.svg"
OUTPUT = ROOT / "assets/environment/vfx"
PROOF = ROOT / "proofs/industrial_hazards"
MANIFEST = ROOT / "assets/environment/manifests/industrial_hazards.json"


def sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    PROOF.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="hollowtide-industrial-hazards-") as temp_name:
        raster = Path(temp_name) / "hazards.png"
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
                str(raster),
            ],
            cwd=ROOT,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "industrial hazard SVG render failed")
        with Image.open(raster) as loaded:
            atlas = loaded.convert("RGBA")
    if atlas.size != (1024, 512):
        raise ValueError(f"unexpected industrial hazard atlas size {atlas.size}")
    outputs = {}
    for name, box in {
        "industrial_fire": (0, 0, 1024, 256),
        "industrial_steam": (0, 256, 1024, 512),
    }.items():
        strip = atlas.crop(box)
        path = OUTPUT / f"{name}.png"
        strip.save(path, format="PNG", optimize=False, compress_level=9)
        outputs[name] = {
            "path": f"res://assets/environment/vfx/{name}.png",
            "size_px": [1024, 256],
            "frame_size_px": [256, 256],
            "frames": 4,
            "anchor_y": 250,
            "sha256": sha256(path),
            "runtime_owner": "res://scripts/dev/dev_hazard.gd",
            "status": "runtime",
        }
    proof = Image.new("RGBA", atlas.size, (8, 12, 16, 255))
    proof.alpha_composite(atlas)
    proof_path = PROOF / "industrial_hazards_dark.png"
    proof_path.parent.mkdir(parents=True, exist_ok=True)
    proof.save(proof_path, format="PNG", optimize=False, compress_level=9)
    manifest = {
        "schema_version": 1,
        "source": {
            "path": "res://tools/source_art/devmode/industrial_hazards.svg",
            "sha256": sha256(SOURCE),
            "size_px": [1024, 512],
            "authorship": "original Hollowtide vector art; no external or private-reference assets",
        },
        "outputs": outputs,
        "supersedes": [
            "res://assets/environment/vfx/fire_small.png",
            "res://assets/environment/vfx/fire_vent.png",
            "res://assets/environment/vfx/steam_embers.png",
        ],
        "proof": {
            "path": "res://proofs/industrial_hazards/industrial_hazards_dark.png",
            "sha256": sha256(proof_path),
            "size_px": [1024, 512],
        },
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS industrial hazards: coherent fire/steam strips, manifest, and proof")


if __name__ == "__main__":
    main()
