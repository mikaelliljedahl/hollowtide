#!/usr/bin/env python3
"""Run Hollowtide's regression suites in parallel.

Usage:
    python3 tools/run_godot_check.py            # all suites
    python3 tools/run_godot_check.py walljump   # suites whose name contains a filter
    python3 tools/run_godot_check.py --list

Register a suite by adding one line to SUITES. Godot suites get an isolated save root and
user:// directory, so they can run side by side. A suite fails on a non-zero exit, a timeout,
a Godot `SCRIPT ERROR`, or leaked objects/resources at shutdown.
"""

from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FAILURE = re.compile(r"SCRIPT ERROR|ObjectDB instances leaked|resources? still in use", re.I)
PILLOW = ("uv", "run", "--quiet", "--with", "pillow==12.3.0", "python")


@dataclass(frozen=True)
class Suite:
    name: str
    target: str  # res:// path (.tscn scene or .gd script) or a tools/*.py script
    dev: bool = False  # pass --dev-mode to Godot
    pillow: bool = False  # python script needs Pillow
    timeout: float = 120.0
    # Run the simulation as fast as the machine allows with a fixed 60 Hz step instead of real
    # time: faster, and scripted-input tests no longer depend on machine load.
    fixed_fps: bool = True


# One line per suite. Keep behaviour tests; hash/wording/evidence checks are not wanted (D15).
SUITES = [
    # Movement, world and progression
    Suite("level route", "tools/check_level.py"),
    Suite("walljump", "tools/check_walljump.tscn"),
    Suite("slipstream", "tools/check_slipstream.tscn"),
    Suite("player controls", "tools/check_player_controls.tscn"),
    Suite("player upgrades", "tools/check_player_upgrades.tscn"),
    Suite("updraft glide", "tools/check_updraft_glide.tscn"),
    Suite("pressure seal", "tools/check_pressure_seal.tscn"),
    Suite("crouch ground hit", "tools/check_crouch_ground_hit.tscn"),
    Suite("progression", "tools/check_progression.gd"),
    Suite("pickup catalog", "tools/check_pickup_catalog.tscn", dev=True),
    Suite("phase1 catalog", "tools/check_phase1_catalog.py"),
    Suite("flux state", "tools/check_flux_state.gd"),
    Suite("flux runtime", "tools/check_flux_runtime.tscn", dev=True),
    Suite("dev world", "tools/check_dev_world.gd"),
    Suite("dev world dev", "tools/check_dev_world.gd", dev=True),
    Suite("passages", "tools/check_passages.tscn", dev=True),
    Suite("area routing", "tools/check_area_routing.tscn", dev=True),
    Suite("environment kits", "tools/check_environment_kits.tscn", dev=True),
    Suite("area visuals", "tools/check_area_visuals.tscn"),
    Suite("campaign graph", "tools/check_campaign_graph.py"),
    Suite("campaign moves", "tools/check_campaign_moves.tscn"),
    Suite("campaign moves kd", "tools/check_campaign_moves_kd.tscn", timeout=300.0),
    Suite("campaign map", "tools/check_campaign_map.tscn"),
    Suite("campaign flow", "tools/check_campaign_flow.tscn"),
    Suite("playability", "tools/check_playability_repair.tscn", dev=True),
    # Save and respawn
    Suite("world persistence", "tools/check_world_persistence.tscn", dev=True),
    Suite("respawn", "tools/check_respawn.tscn"),
    Suite("respawn dev", "tools/check_respawn.tscn", dev=True),
    # Combat
    Suite("combat devmode", "tools/check_combat_devmode.tscn", dev=True),
    Suite("combat integration", "tools/check_combat_integration.tscn"),
    # Checks real-time audio playback state, so it runs in real time.
    Suite("combat feedback", "tools/check_combat_feedback.tscn", fixed_fps=False),
    Suite("combat presentation", "tools/check_combat_presentation.tscn"),
    Suite("beam family", "tools/check_beam_family.tscn"),
    Suite("arsenal", "tools/check_arsenal.tscn"),
    Suite("surprise enemies", "tools/check_surprise_enemies.tscn"),
    Suite("worldfx", "tools/check_worldfx.tscn"),
    Suite("worldfx layout", "tools/check_worldfx_layout.py"),
    Suite("ambush rules", "tools/check_ambush_rules.tscn"),
    Suite("ambush campaign", "tools/check_ambush_campaign.tscn"),
    Suite("ambush rules dev", "tools/check_ambush_rules.tscn", dev=True),
    Suite("weapon visual", "tools/check_weapon_visual.tscn"),
    Suite("crossbow", "tools/check_crossbow.tscn"),
    Suite("crawler", "tools/check_crawler_surface.tscn", dev=True),
    Suite("upgrade feedback", "tools/check_upgrade_feedback.tscn"),
    # UI
    Suite("start/help", "tools/check_start_help.gd"),
    # Assets and audio
    Suite("spin matte", "tools/check_spin_matte.py", pillow=True),
    Suite("audio feedback", "tools/check_audio_feedback.py"),
    Suite("audio catalog", "tools/check_audio_catalog.py", timeout=180.0),
]


def command_for(suite: Suite, godot: list[str], save_root: Path) -> list[str]:
    if suite.target.endswith(".py"):
        python = list(PILLOW) if suite.pillow else [sys.executable]
        return [*python, suite.target]
    target = f"res://{suite.target}"
    command = [*godot, "--headless", "--path", str(ROOT)]
    if suite.fixed_fps:
        command += ["--fixed-fps", "60"]
    command += [target] if target.endswith(".tscn") else ["--script", target]
    command += ["--", "--test-mode", f"--test-save-root={save_root}"]
    if suite.dev:
        command.append("--dev-mode")
    return command


def run(suite: Suite, godot: list[str], scratch: Path) -> tuple[Suite, bool, float, str]:
    base = scratch / re.sub(r"[^a-z0-9]+", "-", suite.name.lower()).strip("-")
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONUNBUFFERED="1")
    for key, sub in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config")):
        (base / sub).mkdir(parents=True, exist_ok=True)
        env[key] = str(base / sub)
    (base / "saves").mkdir(exist_ok=True)
    command = command_for(suite, godot, base / "saves")
    started = time.monotonic()
    try:
        done = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            timeout=suite.timeout,
            check=False,
        )
        output = done.stdout + done.stderr
        ok = done.returncode == 0 and not FAILURE.search(output)
        if done.returncode != 0:
            output += f"\nexit={done.returncode}"
    except subprocess.TimeoutExpired as error:
        output = f"{error.stdout or ''}{error.stderr or ''}\nTIMEOUT after {suite.timeout:.0f}s"
        ok = False
    return suite, ok, time.monotonic() - started, f"$ {shlex.join(command)}\n{output}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("filters", nargs="*", help="only suites whose name contains a filter")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--jobs", "-j", type=int, default=max(2, (os.cpu_count() or 4) // 2))
    parser.add_argument("--list", action="store_true", help="list suites and exit")
    parser.add_argument("--verbose", "-v", action="store_true", help="show passing output too")
    args = parser.parse_args()

    if args.list:
        for suite in SUITES:
            print(f"{suite.name:24} {suite.target}")
        return 0
    selected = [
        suite
        for suite in SUITES
        if not args.filters or any(f.lower() in suite.name.lower() for f in args.filters)
    ]
    if not selected:
        print(f"no suite matches {args.filters}")
        return 1
    missing = [suite for suite in selected if not (ROOT / suite.target).exists()]
    runnable = [suite for suite in selected if suite not in missing]

    started = time.monotonic()
    failures = []
    godot = shlex.split(args.godot)
    with tempfile.TemporaryDirectory(prefix="hollowtide-check-") as scratch:
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            # Start the slowest suites first; report in list order.
            jobs = {
                suite: pool.submit(run, suite, godot, Path(scratch))
                for suite in sorted(runnable, key=lambda suite: -suite.timeout)
            }
            for job in (jobs[suite] for suite in runnable):
                suite, ok, seconds, output = job.result()
                print(f"{'PASS' if ok else 'FAIL'}  {suite.name:24} {seconds:5.1f}s", flush=True)
                if not ok or args.verbose:
                    print(output.rstrip() + "\n", flush=True)
                if not ok:
                    failures.append(suite.name)
    for suite in missing:
        print(f"FAIL  {suite.name:24} missing {suite.target} (remove it from SUITES?)")
        failures.append(suite.name)
    total = time.monotonic() - started
    if failures:
        print(f"\n{len(failures)}/{len(selected)} failed in {total:.0f}s: {', '.join(failures)}")
        return 1
    print(f"\nall {len(selected)} suites passed in {total:.0f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
