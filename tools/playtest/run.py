"""Run the Hollowtide playtest agent over one or more seeds and aggregate the reports.

    python3 tools/playtest/run.py --room fringe_03 --kit beam --seeds 1,2,3
    python3 tools/playtest/run.py --room vaults_03 --spawn 6,14 --kit beam,missiles,missile_tank:2 \\
        --policy external --backend passthrough --windowed --shots 5
    python3 tools/playtest/run.py --room fringe_03 --kit beam --seeds 1 --policy external \\
        --backend jev          # hosted Jev; needs TYPESAFE_API_KEY in the environment

Each run launches Godot with res://tools/playtest_agent.tscn in --test-mode with its own save root,
so the player's real save is never touched. Reports go to --out (default: a new directory under
the system temp dir, never the repo). See docs/features/playtest-agent.md.
"""

from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import aggregate
import jev_backend
import jev_feedback
from policy_server import BACKENDS, Backend, PolicyServer

ROOT = Path(__file__).resolve().parents[2]
SCENE = "res://tools/playtest_agent.tscn"
LOG_LIMIT = 4 * 1024 * 1024  # Godot output kept per run; the rest is dropped.


def break_specs() -> str:
    """Sequence-break start cells from tools/campaign_breaks.py, as the agent's --playtest-breaks."""
    sys.path.insert(0, str(ROOT / "tools"))
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
    if args.spawn:
        command.append(f"--playtest-spawn={args.spawn}")
    if port:
        command.append(f"--playtest-port={port}")
    return command


def make_backend(args: argparse.Namespace) -> Backend:
    if args.backend != jev_backend.JevBackend.name:
        return BACKENDS[args.backend]()
    config = jev_backend.JevConfig(
        base_url=args.jev_base_url,
        model=args.jev_model,
        timeout_ms=args.jev_timeout_ms,
        min_confidence=args.jev_min_confidence,
        max_hz=args.jev_hz,
    )
    return jev_backend.JevBackend(config)


def run_one(args: argparse.Namespace, seed: int, base: Path) -> tuple[Path, Backend | None]:
    label = args.backend if args.policy == "external" else args.policy
    out = base / f"{args.room}-{label}-s{seed}"
    (out / "saves").mkdir(parents=True, exist_ok=True)
    server = None
    backend = None
    if args.policy == "external":
        backend = make_backend(args)
        server = PolicyServer(backend).start()
    command = build_command(args, seed, out, server.port if server else 0)
    with (out / "godot.log").open("wb") as log:
        process = subprocess.Popen(
            command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        assert process.stdout is not None
        written = 0
        for line in process.stdout:
            if written < LOG_LIMIT:
                log.write(line)
                written += len(line)
            if line.startswith(b"PLAYTEST REPORT") or line.startswith(b"  - "):
                sys.stdout.write(line.decode("utf-8", "replace"))
        process.wait(timeout=args.seconds * 4 + 120)
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
    parser.add_argument("--room", required=True)
    parser.add_argument("--kit", default="", help="abilities and pickups, kind:count repeats")
    parser.add_argument("--spawn", default="", help="feet cell x,y in room tiles")
    parser.add_argument("--seeds", default="1", help="comma-separated seeds, one run each")
    parser.add_argument("--seconds", type=float, default=90.0, help="game seconds per run")
    parser.add_argument(
        "--policy", choices=["heuristic", "random", "external"], default="heuristic"
    )
    parser.add_argument(
        "--backend", choices=sorted([*BACKENDS, jev_backend.JevBackend.name]), default="passthrough"
    )
    parser.add_argument("--goal", default="auto", choices=["auto", "ambush", "boss", "none"])
    parser.add_argument("--max-deaths", type=int, default=3)
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
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--out", type=Path, help="output directory (default: under the temp dir)")
    args = parser.parse_args()
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
