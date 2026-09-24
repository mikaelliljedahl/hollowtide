"""Jev-derived playtest feedback: decision stats, confusion hotspots, danger peaks against damage
actually taken, and disagreement with the heuristic. Works on one run's decision records and
merges across runs for the aggregate. See docs/features/playtest-agent.md ("Jev feedback").
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

# $0.042 per million input tokens, output tokens free (docs.typesafe.ai/models via
# .agent-reports/jev-research.md). An estimate: the price can change.
PRICE_PER_INPUT_TOKEN = 0.042 / 1_000_000
HOTSPOT_TILES = 3
SPLIT_MARGIN = 0.15
DANGER_HIGH = 1.34
DANGER_LOW = 0.67
HIT_WINDOW = 1.5
TOP = 3
GROUPS = {
    "shoot": "attack",
    "harpoon": "attack",
    "approach": "close in",
    "retreat": "evade",
    "jump_over": "evade",
    "dash_through": "evade",
    "wall_jump": "evade",
    "go_to_exit": "travel",
    "go_to_ambush": "travel",
    "pick_up": "travel",
    "idle": "wait",
    "jump": "jump",
}


def action_name(key: str) -> str:
    """Readable action without enemy ids: `shoot`, `jump:left`, `go_to_exit:west`."""
    parts = key.split(":")
    if parts[0] in ("jump", "go_to_exit") and len(parts) > 1:
        return f"{parts[0]}:{parts[1]}"
    return parts[0]


def conflicting(first: str, second: str) -> bool:
    a, b = first.split(":"), second.split(":")
    if GROUPS.get(a[0], a[0]) != GROUPS.get(b[0], b[0]):
        return True
    return a[0] == b[0] == "jump" and a[1:2] != b[1:2]


# --- Stats ------------------------------------------------------------------------------------


def stats(records: list[dict[str, Any]], fatal: dict[str, Any] | None = None) -> dict[str, Any]:
    sources = Counter(record["source"] for record in records)
    return {
        "decisions": len(records),
        "calls": sum(1 for record in records if "latency_ms" in record),
        "answered": sources.get("jev", 0),
        "fallbacks": sum(n for source, n in sources.items() if source.startswith("fallback:")),
        "skipped": sum(n for source, n in sources.items() if source.startswith("skip:")),
        "sources": dict(sources),
        "latencies_ms": [record["latency_ms"] for record in records if "latency_ms" in record],
        "input_tokens": sum(record.get("input_tokens", 0) for record in records),
        "output_tokens": sum(record.get("output_tokens", 0) for record in records),
        "models": sorted({record["model"] for record in records if record.get("model")}),
        "fatal": fatal,
    }


def merge_stats(parts: list[dict[str, Any]]) -> dict[str, Any]:
    merged = stats([])
    for part in parts:
        for name in ("decisions", "calls", "answered", "fallbacks", "skipped"):
            merged[name] += part[name]
        merged["input_tokens"] += part["input_tokens"]
        merged["output_tokens"] += part["output_tokens"]
        merged["latencies_ms"] += part["latencies_ms"]
        merged["sources"] = dict(Counter(merged["sources"]) + Counter(part["sources"]))
        merged["models"] = sorted(set(merged["models"]) | set(part["models"]))
        merged["fatal"] = merged["fatal"] or part["fatal"]
    return merged


def derived(summary: dict[str, Any]) -> dict[str, Any]:
    latencies = sorted(summary["latencies_ms"])
    acted = summary["decisions"] - summary["skipped"]
    return {
        "mean_latency_ms": round(sum(latencies) / len(latencies), 1) if latencies else None,
        "p95_latency_ms": latencies[min(len(latencies) - 1, int(0.95 * len(latencies)))]
        if latencies
        else None,
        "fallback_rate": round(summary["fallbacks"] / acted, 3) if acted else None,
        "cost_usd_estimate": round(summary["input_tokens"] * PRICE_PER_INPUT_TOKEN, 5),
    }


# --- Analysis ---------------------------------------------------------------------------------


def analyze(
    records: list[dict[str, Any]], hits: list[dict[str, Any]], min_confidence: float
) -> dict[str, Any]:
    return {
        "hotspots": _hotspots(records, min_confidence),
        "danger": _danger(records, hits),
        "disagreement": _disagreement(records),
    }


def _hotspots(records: list[dict[str, Any]], min_confidence: float) -> dict[str, Any]:
    spots: dict[str, Any] = {}
    for record in records:
        probabilities = record.get("probabilities")
        if not probabilities or not record.get("cell") or not record.get("room"):
            continue
        cell = [
            (record["cell"][i] // HOTSPOT_TILES) * HOTSPOT_TILES + HOTSPOT_TILES // 2
            for i in (0, 1)
        ]
        spot = spots.setdefault(
            f"{record['room']}|{cell[0]}|{cell[1]}",
            {
                "room": record["room"],
                "cell": cell,
                "calls": 0,
                "confused": 0,
                "confidence": 0.0,
                "pairs": {},
                "context": {},
            },
        )
        spot["calls"] += 1
        spot["confidence"] += record["confidence"]
        ranked = sorted(probabilities.items(), key=lambda item: -item[1])
        top, second = ranked[0], ranked[1] if len(ranked) > 1 else (ranked[0][0], 0.0)
        split = top[1] - second[1] < SPLIT_MARGIN and conflicting(top[0], second[0])
        if record["confidence"] < min_confidence or split:
            spot["confused"] += 1
            pair = " vs ".join(sorted({action_name(top[0]), action_name(second[0])}))
            spot["pairs"][pair] = spot["pairs"].get(pair, 0) + 1
            context = record.get("boss_attack") or record.get("threat") or "no enemy"
            spot["context"][context] = spot["context"].get(context, 0) + 1
    return spots


def _danger(records: list[dict[str, Any]], hits: list[dict[str, Any]]) -> dict[str, Any]:
    rated = sorted(
        (record for record in records if record.get("danger") is not None),
        key=lambda record: record["t"],
    )
    by_source: dict[str, dict[str, int]] = {}
    for hit in hits:
        entry = by_source.setdefault(
            hit["source"], {"hits": 0, "rated": 0, "warned": 0, "surprise": 0, "damage": 0}
        )
        entry["hits"] += 1
        entry["damage"] += int(hit.get("amount", 0))
        window = [r["danger"] for r in rated if hit["t"] - HIT_WINDOW <= r["t"] <= hit["t"]]
        if not window:
            continue
        entry["rated"] += 1
        peak = max(window)
        if peak >= DANGER_HIGH:
            entry["warned"] += 1
        elif peak < DANGER_LOW:
            entry["surprise"] += 1
    peaks: dict[str, dict[str, int]] = {}
    for record in rated:
        if record["danger"] < DANGER_HIGH:
            continue
        context = record.get("boss_attack") or record.get("threat") or "no enemy"
        entry = peaks.setdefault(context, {"high": 0, "avoided": 0})
        entry["high"] += 1
        entry["avoided"] += not any(
            record["t"] < hit["t"] <= record["t"] + HIT_WINDOW for hit in hits
        )
    return {"hits": by_source, "peaks": peaks}


def _disagreement(records: list[dict[str, Any]]) -> dict[str, Any]:
    pairs: Counter[str] = Counter()
    answered = differ = 0
    for record in records:
        if "choice" not in record:
            continue
        answered += 1
        if action_name(record["choice"]) != action_name(record["hint"]):
            differ += 1
            context = record.get("boss_attack") or record.get("threat") or "no enemy"
            pairs[
                f"{action_name(record['choice'])} instead of {action_name(record['hint'])}"
                f" near {context}"
            ] += 1
    return {"answered": answered, "differ": differ, "pairs": dict(pairs)}


def merge_analyses(parts: list[dict[str, Any]]) -> dict[str, Any]:
    merged: dict[str, Any] = {"hotspots": {}, "danger": {"hits": {}, "peaks": {}}}
    merged["disagreement"] = {"answered": 0, "differ": 0, "pairs": {}}
    for part in parts:
        _add(merged, part)
    return merged


def _add(into: dict[str, Any], other: dict[str, Any]) -> None:
    for key, value in other.items():
        if isinstance(value, dict):
            _add(into.setdefault(key, {}), value)
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            into[key] = into.get(key, 0) + value
        else:
            into.setdefault(key, value)


# --- Findings ---------------------------------------------------------------------------------


def describe(summary: dict[str, Any], analysis: dict[str, Any]) -> list[str]:
    lines = []
    if summary["fatal"]:
        fatal = summary["fatal"]
        status = f"HTTP {fatal['status']}" if fatal["status"] else "not started"
        lines.append(f"Jev rejected the run ({status}): {fatal['message']}")
    lines += _hotspot_lines(analysis["hotspots"])
    lines += _danger_lines(analysis["danger"])
    lines += _disagreement_lines(analysis["disagreement"])
    return lines or ["Jev answered no decision, so there is no Jev feedback for this run."]


def _top(counts: dict[str, int]) -> str:
    name, count = min(counts.items(), key=lambda item: (-item[1], item[0]))
    return f"{name} ({count}x)"


def _hotspot_lines(spots: dict[str, Any]) -> list[str]:
    ranked = sorted(
        (spot for spot in spots.values() if spot["confused"] >= 2),
        key=lambda spot: (-spot["confused"], spot["room"], spot["cell"]),
    )
    lines = []
    for spot in ranked[:TOP]:
        mean = spot["confidence"] / spot["calls"]
        lines.append(
            f"Confusion hotspot {spot['room']} around cell ({spot['cell'][0]}, {spot['cell'][1]}):"
            f" {spot['confused']} of {spot['calls']} Jev decisions were unsure or split"
            f" (mean confidence {mean:.2f}), most often {_top(spot['pairs'])}, with"
            f" {_top(spot['context'])} in play. The right move is not legible here: give the"
            " threat a distinct wind-up, a safe spot or more room to act, or accept it as"
            " intended pressure."
        )
    return lines


def _danger_lines(danger: dict[str, Any]) -> list[str]:
    lines = []
    unrated = 0
    for source, entry in sorted(danger["hits"].items(), key=lambda item: -item[1]["damage"]):
        unrated += entry["hits"] - entry["rated"]
        if entry["surprise"]:
            lines.append(
                f"Unreadable hits from {source}: {entry['surprise']} of {entry['rated']} rated"
                f" hits came while Jev rated danger low in the {HIT_WINDOW} s before. Nothing in"
                " the state warned of it (no wind-up flag, close threat or incoming shot):"
                " lengthen or strengthen its telegraph, or make it visible earlier."
            )
        if entry["warned"]:
            lines.append(
                f"Readable but not avoided: {entry['warned']} of {entry['rated']} rated hits from"
                f" {source} followed a high danger rating. The threat reads, yet the agent could"
                " not dodge it: check that a safe response exists and that its window is fair."
            )
    for context, entry in sorted(danger["peaks"].items(), key=lambda item: -item[1]["high"]):
        if entry["high"] < 2:
            continue
        share = entry["avoided"] / entry["high"]
        verdict = (
            "a fair, dodgeable telegraph"
            if share >= 0.7
            else "seen coming but often not escaped; widen the dodge window or the safe area"
        )
        lines.append(
            f"Danger peaks near {context}: Jev rated danger high {entry['high']} times and"
            f" {entry['avoided']} passed without damage within {HIT_WINDOW} s: {verdict}."
        )
    if unrated:
        lines.append(
            f"{unrated} hits had no Jev danger rating in the {HIT_WINDOW} s before (skipped or"
            " fallback decisions); they are not judged above."
        )
    return lines


def _disagreement_lines(entry: dict[str, Any]) -> list[str]:
    if not entry["answered"]:
        return []
    share = entry["differ"] / entry["answered"]
    line = (
        f"Jev disagreed with the heuristic in {entry['differ']} of {entry['answered']} answered"
        f" decisions ({share:.0%})"
    )
    if entry["pairs"]:
        line += f"; most often {_top(entry['pairs'])}"
    return [
        line + ". Where one alternative dominates, compare damage between the jev and heuristic"
        " runs before changing the heuristic or the encounter."
    ]


def stats_markdown(summary: dict[str, Any], analysis: dict[str, Any], heading: str) -> str:
    extra = derived(summary)
    reasons = ", ".join(
        f"{source.removeprefix('fallback:')} {count}"
        for source, count in sorted(summary["sources"].items())
        if source.startswith("fallback:")
    )
    rows = [
        ("Model", ", ".join(summary["models"]) or "none answered"),
        ("Decisions", summary["decisions"]),
        ("Requests sent", summary["calls"]),
        ("Answered by Jev", summary["answered"]),
        ("Skipped (rate cap)", summary["skipped"]),
        ("Fallback rate", _pct(extra["fallback_rate"]) + (f" ({reasons})" if reasons else "")),
        ("Mean latency", _ms(extra["mean_latency_ms"])),
        ("p95 latency", _ms(extra["p95_latency_ms"])),
        ("Input tokens", summary["input_tokens"]),
        ("Output tokens", summary["output_tokens"]),
        ("Cost (estimate)", f"${extra['cost_usd_estimate']:.4f} at $0.042 per million input"),
    ]
    lines = [heading, "", "| Measure | Value |", "|---|---|"]
    lines += [f"| {name} | {value} |" for name, value in rows]
    lines += ["", "Jev findings (Jev reads the structured state, not the screen):", ""]
    lines += [f"- {line}" for line in describe(summary, analysis)]
    return "\n".join(lines) + "\n"


def _pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.0%}"


def _ms(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.0f} ms"


# --- Files ------------------------------------------------------------------------------------


def apply(out: Path, backend: Any) -> dict[str, Any] | None:
    """Folds the backend's records into the run's decisions.jsonl, report.json and report.md."""
    report_path = out / "report.json"
    if not report_path.exists():
        return None
    report = json.loads(report_path.read_text(encoding="utf-8"))
    summary = stats(backend.records, backend.fatal)
    analysis = analyze(
        backend.records, report["telemetry"].get("hits", []), backend.config.min_confidence
    )
    report["jev"] = {
        "config": {
            "base_url": backend.config.base_url,
            "model": backend.config.model,
            "timeout_ms": backend.config.timeout_ms,
            "min_confidence": backend.config.min_confidence,
            "max_hz": backend.config.max_hz,
        },
        "stats": summary,
        "derived": derived(summary),
        "analysis": analysis,
        "findings": describe(summary, analysis),
    }
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    with (out / "report.md").open("a", encoding="utf-8") as markdown:
        markdown.write("\n" + stats_markdown(summary, analysis, "## Jev policy"))
    _merge_decisions(out / "decisions.jsonl", backend.records)
    if backend.request_sample is not None:
        (out / "jev_request_sample.json").write_text(
            json.dumps(backend.request_sample, indent=2) + "\n", encoding="utf-8"
        )
    return report["jev"]


def _merge_decisions(path: Path, records: list[dict[str, Any]]) -> None:
    if not path.exists():
        return
    by_tick = {record["tick"]: record for record in records}
    lines = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        entry = json.loads(raw)
        record = by_tick.get(entry.get("tick"))
        if record is not None:
            entry["jev"] = {k: v for k, v in record.items() if k not in ("tick", "t", "room")}
        lines.append(json.dumps(entry))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
