"""Aggregate Hollowtide playtest agent reports (report.json per run) into cross-run findings.

python3 tools/playtest/aggregate.py <run-dir-or-report.json> ... [--out DIR]
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import jev_feedback

STUCK_SECONDS = 3.0


def load(paths: list[Path]) -> list[dict[str, Any]]:
    reports = []
    for path in paths:
        report = path / "report.json" if path.is_dir() else path
        if report.exists():
            reports.append(json.loads(report.read_text(encoding="utf-8")))
    return reports


def aggregate(reports: list[dict[str, Any]]) -> dict[str, Any]:
    runs = len(reports)
    jev_runs = [report["jev"] for report in reports if "jev" in report]
    killers: Counter[str] = Counter()
    damage: Counter[str] = Counter()
    ends: Counter[str] = Counter()
    stuck: Counter[str] = Counter()
    stuck_seconds: defaultdict[str, float] = defaultdict(float)
    fallbacks: Counter[str] = Counter()
    bosses: defaultdict[str, dict[str, Any]] = defaultdict(
        lambda: {"attempts": 0, "defeated": 0, "deaths_by_stage": Counter(), "damage": Counter()}
    )
    ambushes: defaultdict[str, dict[str, Any]] = defaultdict(
        lambda: {"fights": 0, "cleared": 0, "seconds": [], "damage": [], "outcomes": Counter()}
    )
    free_boss_damage: Counter[str] = Counter()
    for report in reports:
        data = report["telemetry"]
        stuck_here: set[str] = set()
        ends[report["meta"]["end_reason"]] += 1
        killers.update(death["killer"] for death in data["deaths"])
        damage.update(data["damage_by_source"])
        free_boss_damage.update(data.get("boss_damage_while_disengaged", {}))
        for episode in data["stuck"]:
            if episode["seconds"] >= STUCK_SECONDS:
                spot = f"{episode['room']} ({episode['cell'][0]}, {episode['cell'][1]})"
                stuck_here.add(spot)
                stuck_seconds[spot] += episode["seconds"]
        # A run counts once per spot, however many episodes it had there.
        stuck.update(stuck_here)
        for policy in data["decisions"].values():
            fallbacks.update(policy["fallbacks"])
        for attempt in data["bosses"]:
            entry = bosses[attempt["id"]]
            entry["attempts"] += 1
            entry["defeated"] += attempt["outcome"] == "defeated"
            if attempt["outcome"] == "died":
                entry["deaths_by_stage"][f"stage {attempt['stage_reached']}"] += 1
            entry["damage"].update(attempt["damage_by_source"])
        for fight in data["ambushes"]:
            entry = ambushes[fight["id"]]
            entry["fights"] += 1
            entry["outcomes"][fight["outcome"]] += 1
            if fight["outcome"] == "cleared":
                entry["cleared"] += 1
                entry["seconds"].append(fight["seconds"])
                entry["damage"].append(fight["damage_taken"])
    summary = {
        "runs": runs,
        "end_reasons": dict(ends),
        "killers": dict(killers),
        "damage_by_source": dict(damage),
        "bosses": {key: _plain(value) for key, value in bosses.items()},
        "ambushes": {key: _plain(value) for key, value in ambushes.items()},
        "stuck_spots": {spot: round(stuck_seconds[spot], 1) for spot in stuck},
        "stuck_runs": dict(stuck),
        "boss_damage_while_disengaged": dict(free_boss_damage),
        "fallbacks": dict(fallbacks),
        "findings": findings(
            runs, bosses, ambushes, killers, damage, stuck, stuck_seconds, fallbacks
        )
        + [
            f"{boss} took {amount} damage while the player was outside its arena."
            for boss, amount in sorted(free_boss_damage.items())
        ],
    }
    if jev_runs:
        stats = jev_feedback.merge_stats([run["stats"] for run in jev_runs])
        analysis = jev_feedback.merge_analyses([run["analysis"] for run in jev_runs])
        summary["jev"] = {
            "runs": len(jev_runs),
            "stats": stats,
            "derived": jev_feedback.derived(stats),
            "analysis": analysis,
            "findings": jev_feedback.describe(stats, analysis),
        }
    return summary


def findings(
    runs: int,
    bosses: dict[str, dict[str, Any]],
    ambushes: dict[str, dict[str, Any]],
    killers: Counter[str],
    damage: Counter[str],
    stuck: Counter[str],
    stuck_seconds: dict[str, float],
    fallbacks: Counter[str],
) -> list[str]:
    result = []
    for boss, entry in sorted(bosses.items()):
        line = f"{boss}: {entry['defeated']}/{entry['attempts']} attempts won over {runs} runs"
        if entry["deaths_by_stage"]:
            stage, count = _top(entry["deaths_by_stage"])
            line += f"; {stage} killed the agent {count}/{entry['attempts']} times"
        if entry["damage"]:
            source, amount = _top(entry["damage"])
            line += f"; most damage from {source} ({amount})"
        result.append(line + ".")
    for arena, entry in sorted(ambushes.items()):
        line = f"Ambush {arena}: cleared {entry['cleared']}/{entry['fights']} fights"
        if entry["seconds"]:
            mean_seconds = sum(entry["seconds"]) / len(entry["seconds"])
            mean_damage = sum(entry["damage"]) / len(entry["damage"])
            line += f", mean {mean_seconds:.1f} s and {mean_damage:.0f} damage per clear"
        result.append(line + ".")
    for killer, count in killers.most_common(3):
        result.append(f"{killer} killed the agent {count} times over {runs} runs.")
    if damage:
        source, amount = _top(damage)
        result.append(f"Most damage over all runs: {source} ({amount} of {sum(damage.values())}).")
    for spot, count in stuck.most_common(3):
        result.append(
            f"Stuck at {spot} in {count}/{runs} runs, {stuck_seconds[spot]:.1f} s in total."
        )
    for reason, count in sorted(fallbacks.items()):
        result.append(f"External policy fell back {count} times ({reason}).")
    return result or ["No deaths, stalls or failed fights over all runs."]


def to_markdown(summary: dict[str, Any]) -> str:
    lines = [f"# Playtest aggregate ({summary['runs']} runs)", "", "## Findings", ""]
    lines += [f"- {finding}" for finding in summary["findings"]]
    lines += ["", "## End reasons", "", "| Reason | Runs |", "|---|---|"]
    lines += [f"| {reason} | {count} |" for reason, count in sorted(summary["end_reasons"].items())]
    lines += ["", "## Damage by source", "", "| Source | Damage |", "|---|---|"]
    ranked = sorted(summary["damage_by_source"].items(), key=lambda item: (-item[1], item[0]))
    lines += [f"| {source} | {amount} |" for source, amount in ranked]
    text = "\n".join(lines) + "\n"
    if "jev" in summary:
        jev = summary["jev"]
        heading = f"## Jev policy ({jev['runs']} runs)"
        text += "\n" + jev_feedback.stats_markdown(jev["stats"], jev["analysis"], heading)
    return text


def write(summary: dict[str, Any], out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    (out / "aggregate.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    (out / "aggregate.md").write_text(to_markdown(summary), encoding="utf-8")


def _top(counts: Counter[str]) -> tuple[str, int]:
    return min(counts.items(), key=lambda item: (-item[1], item[0]))


def _plain(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        key: dict(value) if isinstance(value, Counter) else value for key, value in entry.items()
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--out", type=Path, help="directory for aggregate.json and aggregate.md")
    args = parser.parse_args()
    reports = load(args.paths)
    if not reports:
        print("no report.json found")
        return 1
    summary = aggregate(reports)
    write(summary, args.out or args.paths[0].parent)
    print("\n".join(summary["findings"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
