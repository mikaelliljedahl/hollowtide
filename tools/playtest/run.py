"""Run the Hollowtide playtest agent over one or more seeds and aggregate the reports.

    python3 tools/playtest/run.py --room fringe_03 --kit beam --seeds 1,2,3
    python3 tools/playtest/run.py --room vaults_03 --spawn 6,14 --kit beam,missiles,missile_tank:2 \\
        --policy external --backend passthrough --windowed --shots 5
    python3 tools/playtest/run.py --room fringe_03 --kit beam --seeds 1 --policy external \\
        --backend jev          # hosted Jev; needs TYPESAFE_API_KEY in the environment
    python3 tools/playtest/run.py --campaign --seeds 1 --out <dir>   # new game to the ending

Each run launches Godot with res://tools/playtest_agent.tscn in --test-mode with its own save root
and its own user:// directory under the run's output folder, so the player's real save and
settings.cfg are never touched. Reports go to --out (default: a new directory under
the system temp dir, never the repo). See docs/features/playtest-agent.md.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import aggregate
import campaign_route
import jev_backend
import jev_feedback
from policy_server import BACKENDS, Backend, PolicyServer

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from godot_env import isolated_env  # noqa: E402

SCENE = "res://tools/playtest_agent.tscn"
LOG_LIMIT = 4 * 1024 * 1024  # Godot output kept per run; the rest is dropped.
CAMPAIGN_SECONDS = 2700.0  # campaign mode's default game-time cap (45 minutes)
CAMPAIGN_MAX_DEATHS = 1000  # deaths do not end a campaign run; the time cap does
# The game writes heartbeat.txt every 20 s of wall time (tools/playtest_agent.gd; piped stdout is
# block-buffered); this much silence means the process froze (a script loop, a lost scene) and it
# is killed.
SILENCE_LIMIT = 120.0


def _heartbeat(out: Path, started: float) -> float:
    """Monotonic time of the game's last heartbeat file write, or `started` before the first."""
    try:
        age = time.time() - (out / "heartbeat.txt").stat().st_mtime
    except OSError:
        return started
    return max(started, time.monotonic() - age)


def break_specs() -> str:
    """Sequence-break start cells from tools/campaign_breaks.py, as the agent's --playtest-breaks."""
    from campaign_breaks import BREAKS

    return ";".join(f"{b.break_id}:{b.room}:{b.start[0]}:{b.start[1]}" for b in BREAKS)


def build_command(args: argparse.Namespace, seed: int, out: Path, port: int) -> list[str]:
    command = [*shlex.split(args.godot), "--path", str(ROOT)]
    if args.windowed:
        command += ["--windowed", "--resolution", "1920x1080"]
    else:
        command += ["--headless", "--fixed-fps", "60"]
    command += [
        SCENE,
        "--",
        "--test-mode",
        f"--test-save-root={out / 'saves'}",
        f"--playtest-room={args.room}",
        f"--playtest-kit={args.kit}",
        f"--playtest-seed={seed}",
        f"--playtest-seconds={args.seconds}",
        f"--playtest-policy={args.policy}",
        f"--playtest-out={out}",
        f"--playtest-run-id={out.name}",
        f"--playtest-goal={args.goal}",
        f"--playtest-max-deaths={args.max_deaths}",
        f"--playtest-timeout-ms={args.timeout_ms}",
        f"--playtest-breaks={break_specs()}",
        f"--playtest-shots={args.shots}",
    ]
    if getattr(args, "trial", None):
        command.append(f"--playtest-trial={args.trial}")
    if getattr(args, "route", None):
        command.append(f"--playtest-campaign={args.route}")
    if args.spawn:
        command.append(f"--playtest-spawn={args.spawn}")
    if port:
        command.append(f"--playtest-port={port}")
    return command


def child_env(out: Path) -> dict[str, str]:
    """Godot's environment: user:// (settings.cfg, logs) under the run's own HOME, never the
    player's (tools/godot_env.py); the Jev key stays with the Python backend."""
    env = isolated_env(out / "home")
    env.pop(jev_backend.KEY_ENV, None)
    return env


def make_backend(args: argparse.Namespace) -> Backend:
    if args.backend != jev_backend.JevBackend.name:
        return BACKENDS[args.backend]()
    config = jev_backend.JevConfig(
        base_url=args.jev_base_url,
        model=args.jev_model,
        timeout_ms=args.jev_timeout_ms,
        min_confidence=args.jev_min_confidence,
        max_hz=args.jev_hz,
        budget_usd=args.jev_budget_usd,
    )
    return jev_backend.JevBackend(config)


def run_one(args: argparse.Namespace, seed: int, base: Path) -> tuple[Path, Backend | None]:
    label = args.backend if args.policy == "external" else args.policy
    out = base / f"{'campaign' if args.campaign else args.room}-{label}-s{seed}"
    (out / "saves").mkdir(parents=True, exist_ok=True)
    server = None
    backend = None
    if args.policy == "external":
        backend = make_backend(args)
        server = PolicyServer(backend).start()
    command = build_command(args, seed, out, server.port if server else 0)
    wall_limit = getattr(args, "wall_limit", None) or args.seconds * 4 + 120
    with (out / "godot.log").open("wb") as log:
        process = subprocess.Popen(
            command, cwd=ROOT, env=child_env(out), stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        # A game that stops ending (paused tree, hung scene) must not outlive its run.
        killed: list[str] = []
        last_line = [time.monotonic()]
        started = time.monotonic()
        done = threading.Event()

        def watch() -> None:
            while not done.wait(5.0):
                now = time.monotonic()
                if now - started > wall_limit:
                    killed.append(f"wall limit {wall_limit:.0f} s")
                elif now - max(last_line[0], _heartbeat(out, started)) > SILENCE_LIMIT:
                    killed.append(f"no output for {SILENCE_LIMIT:.0f} s")
                else:
                    continue
                process.kill()
                return

        watchdog = threading.Thread(target=watch, daemon=True)
        watchdog.start()
        assert process.stdout is not None
        written = 0
        for line in process.stdout:
            last_line[0] = time.monotonic()
            if written < LOG_LIMIT:
                log.write(line)
                log.flush()
                written += len(line)
            if line.startswith(b"PLAYTEST REPORT") or line.startswith(b"  - "):
                sys.stdout.write(line.decode("utf-8", "replace"))
        process.wait()
        done.set()
        watchdog.join()
    if killed:
        print(f"run {out.name}: killed by the runner ({killed[0]})")
    if server:
        server.join(timeout=5)
        for error in server.stats.backend_errors[:3]:
            print(f"backend {args.backend}: {error}")
    if process.returncode != 0:
        print(f"run {out.name}: Godot exited {process.returncode}; see {out / 'godot.log'}")
    if isinstance(backend, jev_backend.JevBackend):
        jev = jev_feedback.apply(out, backend)
        for finding in jev["findings"] if jev else []:
            print(f"  - {finding}")
    return out, backend


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--room", help="campaign room id (required unless --trial or --campaign)")
    parser.add_argument(
        "--campaign",
        action="store_true",
        help="play a new game from the start room to the ending along the solver's route",
    )
    parser.add_argument(
        "--trial", choices=["gauntlet", "boss_rush"], help="play a Trial on its fixed kit"
    )
    parser.add_argument(
        "--minimum-kit",
        action="store_true",
        help="campaign: plan the required items only, no nearby Bolt Quivers or energy tanks",
    )
    parser.add_argument("--kit", default="", help="abilities and pickups, kind:count repeats")
    parser.add_argument("--spawn", default="", help="feet cell x,y in room tiles")
    parser.add_argument("--seeds", default="1", help="comma-separated seeds, one run each")
    parser.add_argument("--seconds", type=float, help="game seconds per run (90; campaign 2700)")
    parser.add_argument(
        "--policy", choices=["heuristic", "random", "external"], default="heuristic"
    )
    parser.add_argument(
        "--backend", choices=sorted([*BACKENDS, jev_backend.JevBackend.name]), default="passthrough"
    )
    parser.add_argument("--goal", default="auto", choices=["auto", "ambush", "boss", "none"])
    parser.add_argument("--max-deaths", type=int, help="deaths that end a run (3; campaign 1000)")
    parser.add_argument("--timeout-ms", type=int, default=1000)
    parser.add_argument("--windowed", action="store_true", help="real-time window (screenshots)")
    parser.add_argument("--shots", type=float, default=0.0, help="screenshot every N seconds")
    parser.add_argument(
        "--jev-base-url",
        default=os.environ.get(jev_backend.BASE_URL_ENV, jev_backend.DEFAULT_BASE_URL),
        help="System One server; a local /v1/systemone shim works too (env TYPESAFE_BASE_URL)",
    )
    parser.add_argument("--jev-model", default=jev_backend.DEFAULT_MODEL)
    parser.add_argument("--jev-timeout-ms", type=int, default=800, help="per request, no retry")
    parser.add_argument(
        "--jev-min-confidence", type=float, default=0.35, help="below it, use the heuristic"
    )
    parser.add_argument("--jev-hz", type=float, default=5.0, help="max Jev calls per game second")
    parser.add_argument(
        "--jev-budget-usd",
        type=float,
        help="estimated spend per run after which the heuristic's hint is played (skip:budget)",
    )
    parser.add_argument(
        "--wall-limit", type=float, help="wall seconds before the run is killed (seconds * 4 + 120)"
    )
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--out", type=Path, help="output directory (default: under the temp dir)")
    args = parser.parse_args()
    args.route = None
    if args.campaign:
        if args.trial or args.room or args.kit or args.spawn:
            parser.error("--campaign starts a new game: no --room, --trial, --kit or --spawn")
        args.room = "fringe_01"
        args.goal = "none"
    elif args.trial:
        args.room = f"trials_{args.trial}"
    elif not args.room:
        parser.error("--room is required unless --trial or --campaign is given")
    if args.seconds is None:
        args.seconds = CAMPAIGN_SECONDS if args.campaign else 90.0
    if args.max_deaths is None:
        args.max_deaths = CAMPAIGN_MAX_DEATHS if args.campaign else 3
    if args.backend == jev_backend.JevBackend.name:
        if args.policy != "external":
            parser.error("--backend jev needs --policy external")
        try:
            jev_backend.require_key()
        except jev_backend.JevConfigError as error:
            print(f"error: {error}")
            return 2
        # The game must wait longer than one Jev request, or every slow answer becomes a timeout.
        args.timeout_ms = max(args.timeout_ms, args.jev_timeout_ms + 700)

    stamp = time.strftime("%Y%m%d-%H%M%S")
    base = args.out or Path(tempfile.gettempdir()) / "hollowtide-playtest" / stamp
    if args.campaign:
        args.route = base / "route"
        route = campaign_route.build(args.route, not args.minimum_kit)
        print(f"route: {len(route['objectives'])} objectives in {args.route}")
    runs = []
    for seed in (int(seed) for seed in args.seeds.split(",") if seed.strip()):
        out, backend = run_one(args, seed, base)
        runs.append(out)
        fatal = getattr(backend, "fatal", None)
        if fatal:
            print(f"jev stopped the runs: {fatal['message']} (HTTP {fatal['status']})")
            break
    reports = aggregate.load(runs)
    if not reports:
        print("no run produced a report")
        return 1
    summary = aggregate.aggregate(reports)
    aggregate.write(summary, base)
    print(f"\nAGGREGATE {base / 'aggregate.md'} ({len(reports)}/{len(runs)} runs reported)")
    for finding in summary["findings"] + summary.get("jev", {}).get("findings", []):
        print(f"  - {finding}")
    return 0 if len(reports) == len(runs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
