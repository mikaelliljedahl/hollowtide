"""Jev critic: rates every room, ambush and boss fight of a finished playtest run.

After the run, each segment (one room's traversal, one arena, one boss) becomes a compact summary
built in code from the run's report.json and decisions.jsonl: time, deaths, damage by source,
boss attacks seen against attacks escaped, stuck time, retries, and Jev's own confidence and
danger while it played there. One POST per segment asks five Scores (difficulty, fairness,
readability, pacing, fun) and one Choice (the main problem). The answers keep every probability
and confidence; the scorecard combines them with weights kept here (composite scoring), so a new
weighting never needs a new request. Standard library only; the key handling is
jev_backend.Client's. Contract: docs/features/playtest-agent.md ("Jev critic").
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median
from typing import Any

import jev_backend
from jev_feedback import DANGER_HIGH, DANGER_LOW, HIT_WINDOW, PRICE_PER_INPUT_TOKEN

RATINGS_JSON = "ratings.json"
RATINGS_MD = "ratings.md"
DEFAULT_BUDGET_USD = 0.05
TIMEOUT_MS = 5000
# Question id -> (short level names in order, the Score levels Jev reads).
SCORES: dict[str, tuple[list[str], str, list[str]]] = {
    "difficulty": (
        ["too easy", "fair", "too hard"],
        "How hard was this for the player, judged from `segment`?",
        [
            "too easy: no pressure; nothing here tested the player",
            "fair: some damage or a retry, but the player overcame it at a steady rate",
            "too hard: repeated deaths, heavy damage or many retries before getting through",
        ],
    ),
    "fairness": (
        ["no", "partly", "yes"],
        "Was the damage taken here avoidable with good play? No damage taken counts as yes.",
        [
            "no: most damage came from attacks or hazards the player had no fair chance to escape",
            "partly: some hits were avoidable, others gave the player little chance",
            "yes: the damage was avoidable with good play, or no damage was taken",
        ],
    ),
    "readability": (
        ["unclear", "some unclear", "clear"],
        "Did threats announce themselves before they hurt the player?",
        [
            "unclear: damage mostly arrived while the player's danger estimate was low",
            "some unclear: a few hits came without warning, most were foreseen",
            "clear: hits came when danger was already rated high, or there were no hits",
        ],
    ),
    "pacing": (
        ["boring", "good", "hectic"],
        "How did the time spent here feel for its content?",
        [
            "boring: long for what happened, with stuck time, retries or backtracking",
            "good: time in proportion to the challenge; steady progress",
            "hectic: a short burst of dense damage and threats with no room to breathe",
        ],
    ),
    "fun": (
        ["low", "medium", "high"],
        "How much fun would a human player likely have had here?",
        [
            "low: frustrating (deaths, stuck, unavoidable damage) or empty",
            "medium: fine but unremarkable",
            "high: a tense challenge that was overcome cleanly",
        ],
    ),
}
PROBLEMS = {
    "none": "No real problem stands out.",
    "unfair_hit": "The player took damage that could not reasonably be avoided.",
    "unclear_warning": "Threats hurt the player before they were readable.",
    "too_long": "It dragged: far more time than its content warrants.",
    "too_short": "Over before it could become interesting.",
    "navigation_confusing": "The player got stuck or lost finding the way.",
    "too_hard": "Too many deaths or too much damage to get through.",
    "too_easy": "No challenge at all.",
}
PROBLEM_QUESTION = "main_problem"
# Composite weights (sum 1); a dimension's goodness is in 0..1 (see goodness()).
WEIGHTS = {"difficulty": 0.25, "fairness": 0.25, "readability": 0.2, "pacing": 0.15, "fun": 0.15}
ACTIONABLE = ("unfair_hit", "unclear_warning", "too_long", "too_hard", "navigation_confusing")
FLAG_PROBABILITY = 0.4
WINDOW_SLACK = 0.1
KIND_WORDS = {
    "room": "moving through a room (fights inside arenas and boss fights are rated separately)",
    "ambush": "a sealed arena: waves of enemies; the doors open when every wave is cleared",
    "boss": "a boss fight",
}


# --- Segments ---------------------------------------------------------------------------------


def load_run(out: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    report = json.loads((out / "report.json").read_text(encoding="utf-8"))
    records = []
    decisions = out / "decisions.jsonl"
    if decisions.exists():
        for raw in decisions.read_text(encoding="utf-8").splitlines():
            if raw.strip():
                entry = json.loads(raw)
                jev = entry.get("jev") or {}
                records.append(
                    {
                        "t": float(entry.get("t", 0.0)),
                        "room": ((entry.get("state") or {}).get("room") or {}).get("id"),
                        "source": jev.get("source", ""),
                        "confidence": jev.get("confidence"),
                        "danger": jev.get("danger"),
                    }
                )
    return report, records


def segments(report: dict[str, Any], records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every boss fight, arena and room of the run in play order, one entry per id."""
    telemetry = report["telemetry"]
    hits = telemetry.get("hits", [])
    fights: list[dict[str, Any]] = []
    for kind, entries in (("boss", telemetry.get("bosses", [])), ("ambush", telemetry["ambushes"])):
        grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for entry in entries:
            grouped[entry["id"]].append(entry)
        fights += [_fight(kind, tries, hits, records) for tries in grouped.values()]
    windows = [w for fight in fights for w in fight.pop("windows")]
    rooms = [
        _room(room, seconds, report, windows, records)
        for room, seconds in telemetry.get("room_seconds", {}).items()
    ]
    medians = {
        kind: median([s["facts"]["seconds"] for s in group])
        for kind in ("room", "ambush", "boss")
        if (group := [s for s in rooms + fights if s["kind"] == kind])
    }
    everything = sorted(rooms + fights, key=lambda s: s["first_t"])
    for entry in everything:
        entry["facts"]["median_seconds_for_this_kind_in_run"] = round(medians[entry["kind"]], 1)
    return everything


def _in(t: float, windows: list[tuple[float, float]]) -> bool:
    return any(start <= t <= end for start, end in windows)


def _fight(
    kind: str,
    tries: list[dict[str, Any]],
    hits: list[dict[str, Any]],
    records: list[dict[str, Any]],
) -> dict[str, Any]:
    first = tries[0]
    room = first["room"]
    # Reports from before the critic carry no start time; their fight then spans nothing.
    # `seconds` is rounded to 0.1 s, so the death that ends a try can land just past its end.
    windows = [
        (float(e["t"]), float(e["t"]) + float(e["seconds"]) + WINDOW_SLACK)
        for e in tries
        if "t" in e
    ]
    fight_hits = [h for h in hits if h["room"] == room and _in(float(h["t"]), windows)]
    facts: dict[str, Any] = {
        "seconds": round(sum(float(e["seconds"]) for e in tries), 1),
        "attempts": len(tries),
        "retries": len(tries) - 1,
        "outcomes": [e["outcome"] for e in tries],
        "deaths": sum(1 for e in tries if e["outcome"] == "died"),
        "damage_taken": sum(_fight_damage(e) for e in tries),
        "damage_by_source": _by_source(fight_hits),
        "hits": len(fight_hits),
    }
    if kind == "boss":
        # The boss recorder attributes its own damage; the hit list needs the fight window.
        totals: Counter[str] = Counter()
        for entry in tries:
            totals.update(entry.get("damage_by_source", {}))
        facts["damage_by_source"] = dict(totals.most_common())
    if kind == "ambush":
        facts["waves"] = first.get("waves")
        facts["best_wave_reached"] = max(int(e.get("wave_reached", 0)) for e in tries)
    else:
        facts["best_stage_reached"] = max(int(e.get("stage_reached", 0)) for e in tries)
        facts["attacks"] = _attacks(tries)
    facts["jev_play"] = _jev_play(records, room, windows, fight_hits)
    return {
        "kind": kind,
        "id": first["id"],
        "room": room,
        "first_t": windows[0][0] if windows else float("inf"),
        "facts": facts,
        "windows": [(room, w) for w in windows],
    }


def _fight_damage(entry: dict[str, Any]) -> int:
    if "damage_taken" in entry:
        return int(entry["damage_taken"])
    return sum(int(v) for v in entry.get("damage_by_source", {}).values())


def _attacks(tries: list[dict[str, Any]]) -> dict[str, dict[str, int]]:
    seen: Counter[str] = Counter()
    landed: Counter[str] = Counter()
    for entry in tries:
        seen.update(entry.get("attacks", {}))
        landed.update(entry.get("attacks_landed", {}))
    return {
        name: {"seen": count, "landed": landed[name], "escaped": max(0, count - landed[name])}
        for name, count in sorted(seen.items())
    }


def _room(
    room: str,
    seconds: float,
    report: dict[str, Any],
    windows: list[tuple[str, tuple[float, float]]],
    records: list[dict[str, Any]],
) -> dict[str, Any]:
    telemetry = report["telemetry"]
    campaign = report.get("campaign") or {}
    fights = [w for r, w in windows if r == room]
    outside = [h for h in telemetry.get("hits", []) if h["room"] == room]
    outside = [h for h in outside if not _in(float(h["t"]), fights)]
    deaths = [d for d in telemetry.get("deaths", []) if d["room"] == room]
    deaths = [d for d in deaths if not _in(float(d["t"]), fights)]
    visits = [v for v in campaign.get("rooms_visited", []) if v["room"] == room]
    failed = [
        a for a in campaign.get("attempts", []) if a.get("room") == room and a["outcome"] != "done"
    ]
    fight_seconds = sum(end - start - WINDOW_SLACK for start, end in fights)
    facts = {
        "seconds": round(max(0.0, float(seconds) - fight_seconds), 1),
        "visits": max(1, len(visits)),
        "retries": len(failed),
        "deaths": len(deaths),
        "damage_taken": sum(h["amount"] for h in outside),
        "damage_by_source": _by_source(outside),
        "hits": len(outside),
        "stuck_seconds": round(
            sum(float(s["seconds"]) for s in telemetry.get("stuck", []) if s["room"] == room), 1
        ),
        "jev_play": _jev_play(records, room, None, outside, exclude=fights),
    }
    first_t = min([float(v["t"]) for v in visits] or [0.0])
    return {"kind": "room", "id": room, "room": room, "first_t": first_t, "facts": facts}


def _by_source(hits: list[dict[str, Any]]) -> dict[str, int]:
    totals: Counter[str] = Counter()
    for hit in hits:
        totals[hit["source"]] += int(hit["amount"])
    return dict(totals.most_common())


def _jev_play(
    records: list[dict[str, Any]],
    room: str,
    windows: list[tuple[float, float]] | None,
    hits: list[dict[str, Any]],
    exclude: list[tuple[float, float]] | None = None,
) -> dict[str, Any]:
    """Jev's own view while it played the segment: confidence, danger, and hits it foresaw."""
    mine = [r for r in records if r["room"] == room]
    if windows is not None:
        mine = [r for r in mine if _in(r["t"], windows)]
    if exclude:
        mine = [r for r in mine if not _in(r["t"], exclude)]
    answered = [r for r in mine if r["confidence"] is not None]
    dangers = [float(r["danger"]) for r in answered if r["danger"] is not None]
    foreseen = unforeseen = 0
    for hit in hits:
        before = [
            r
            for r in answered
            if r["danger"] is not None and 0.0 <= float(hit["t"]) - r["t"] <= HIT_WINDOW
        ]
        if not before:
            continue
        if max(float(r["danger"]) for r in before) >= DANGER_LOW:
            foreseen += 1
        else:
            unforeseen += 1
    return {
        "decisions": len(mine),
        "mean_confidence": _mean([float(r["confidence"]) for r in answered]),
        "low_confidence_share": _share(mine, lambda r: r["source"] == "fallback:low_confidence"),
        "mean_danger_0_to_2": _mean(dangers),
        "high_danger_share": round(sum(d >= DANGER_HIGH for d in dangers) / len(dangers), 2)
        if dangers
        else None,
        "hits_foreseen": foreseen,
        "hits_not_foreseen": unforeseen,
    }


def _mean(values: list[float]) -> float | None:
    return round(sum(values) / len(values), 2) if values else None


def _share(items: list[dict[str, Any]], test: Any) -> float | None:
    return round(sum(1 for item in items if test(item)) / len(items), 2) if items else None


# --- Request and answer -----------------------------------------------------------------------


def build_request(model: str, segment: dict[str, Any]) -> dict[str, Any]:
    state = {
        "segment": {
            "kind": KIND_WORDS[segment["kind"]],
            "name": segment["id"],
            "room": segment["room"],
            **segment["facts"],
        },
        "player": (
            "An AI playtester that plays through real game inputs; `jev_play` is its own view"
            " while it played here (danger 0 = safe, 2 = about to be hit)."
        ),
    }
    questions: dict[str, Any] = {
        qid: {"type": "score", "instructions": text, "criteria": levels}
        for qid, (_, text, levels) in SCORES.items()
    }
    questions[PROBLEM_QUESTION] = {
        "type": "choice",
        "instructions": "Which single problem best describes this part of the game?",
        "criteria": PROBLEMS,
    }
    return {"model": model, "state": state, "questions": questions}


def parse_answer(answer: dict[str, Any]) -> dict[str, Any]:
    """Typed ratings from a /v1/systemone answer; raises KeyError/ValueError on a bad shape."""
    answers = answer["answers"]
    ratings: dict[str, Any] = {}
    for qid, (names, _, _) in SCORES.items():
        entry = answers[qid]
        probabilities = {
            names[int(index)]: round(float(p), 4) for index, p in entry["probabilities"].items()
        }
        score = float(entry["score"])
        if not 0.0 <= score <= len(names) - 1:
            raise ValueError(f"{qid} score {score} is outside 0..{len(names) - 1}")
        ratings[qid] = {
            "level": max(probabilities, key=probabilities.__getitem__),
            "score": round(score, 3),
            "confidence": round(float(entry["confidence"]), 3),
            "probabilities": probabilities,
        }
    problem = answers[PROBLEM_QUESTION]
    if problem["choice"] not in PROBLEMS:
        raise ValueError(f"main problem {problem['choice']!r} is not an option")
    ratings[PROBLEM_QUESTION] = {
        "choice": problem["choice"],
        "confidence": round(float(problem["confidence"]), 3),
        "probabilities": {k: round(float(v), 4) for k, v in problem["probabilities"].items()},
    }
    return ratings


def goodness(ratings: dict[str, Any]) -> dict[str, float]:
    """Each dimension on 0..1 where 1 is what the design wants, plus their weighted overall."""
    values = {
        "difficulty": ratings["difficulty"]["probabilities"].get("fair", 0.0),
        "fairness": ratings["fairness"]["score"] / 2.0,
        "readability": ratings["readability"]["score"] / 2.0,
        "pacing": ratings["pacing"]["probabilities"].get("good", 0.0),
        "fun": ratings["fun"]["score"] / 2.0,
    }
    values["overall"] = sum(values[k] * w for k, w in WEIGHTS.items())
    return {k: round(v, 3) for k, v in values.items()}


def flags(ratings: dict[str, Any]) -> list[str]:
    """Actionable complaints: a level or problem Jev puts at least FLAG_PROBABILITY on."""
    found = []
    checks = (
        ("too hard", ratings["difficulty"]["probabilities"].get("too hard", 0.0)),
        ("unfair", ratings["fairness"]["probabilities"].get("no", 0.0)),
        ("unclear", ratings["readability"]["probabilities"].get("unclear", 0.0)),
        ("boring", ratings["pacing"]["probabilities"].get("boring", 0.0)),
    )
    found += [name for name, p in checks if p >= FLAG_PROBABILITY]
    problem = ratings[PROBLEM_QUESTION]
    if problem["choice"] in ACTIONABLE and problem["confidence"] >= FLAG_PROBABILITY:
        found.append(problem["choice"])
    return found


# --- Running ----------------------------------------------------------------------------------


def rate_run(
    out: Path,
    base_url: str = jev_backend.DEFAULT_BASE_URL,
    model: str = jev_backend.DEFAULT_MODEL,
    budget_usd: float = DEFAULT_BUDGET_USD,
) -> dict[str, Any]:
    """Rates every segment of the run in `out`; writes ratings.json and ratings.md there."""
    jev_backend.require_key()
    report, records = load_run(out)
    client = jev_backend.Client(base_url, TIMEOUT_MS / 1000.0)
    rated: list[dict[str, Any]] = []
    tokens = 0
    try:
        for segment in segments(report, records):
            entry = {k: segment[k] for k in ("kind", "id", "room", "facts")}
            if tokens * PRICE_PER_INPUT_TOKEN >= budget_usd:
                entry["error"] = "skipped: critic budget spent"
            else:
                tokens += _ask(client, build_request(model, segment), entry)
            rated.append(entry)
    finally:
        client.close()
    result = {
        "run": report["meta"].get("run_id"),
        "model": model,
        "input_tokens": tokens,
        "cost_usd_estimate": round(tokens * PRICE_PER_INPUT_TOKEN, 5),
        "segments": rated,
        "scorecard": scorecard(rated),
    }
    (out / RATINGS_JSON).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (out / RATINGS_MD).write_text(to_markdown(result), encoding="utf-8")
    return result


def _ask(client: jev_backend.Client, request: dict[str, Any], entry: dict[str, Any]) -> int:
    body = json.dumps(request, separators=(",", ":")).encode("utf-8")
    try:
        status, _, payload = client.post(body)
    except (OSError, http.client.HTTPException) as error:
        entry["error"] = jev_backend.scrub(f"{type(error).__name__}: {error}")
        return 0
    if status != 200:
        entry["error"] = f"HTTP {status}: {jev_backend.scrub(payload.decode('utf-8', 'replace'))}"
        return 0
    try:
        answer = json.loads(payload)
        entry["ratings"] = parse_answer(answer)
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        entry["error"] = jev_backend.scrub(f"bad answer: {error}")
        return 0
    entry["goodness"] = goodness(entry["ratings"])
    entry["flags"] = flags(entry["ratings"])
    return int((answer.get("usage") or {}).get("input_tokens", 0))


def scorecard(rated: list[dict[str, Any]]) -> dict[str, Any]:
    scored = [entry for entry in rated if "goodness" in entry]
    card: dict[str, Any] = {"rated": len(scored), "failed": len(rated) - len(scored)}
    for kind in ("all", "room", "ambush", "boss"):
        group = [e for e in scored if kind == "all" or e["kind"] == kind]
        if group:
            card[kind] = {
                key: round(sum(e["goodness"][key] for e in group) / len(group), 3)
                for key in (*WEIGHTS, "overall")
            }
    card["levels"] = {
        qid: dict(Counter(e["ratings"][qid]["level"] for e in scored)) for qid in SCORES
    }
    card["main_problems"] = dict(Counter(e["ratings"][PROBLEM_QUESTION]["choice"] for e in scored))
    card["worst"] = [
        {"kind": e["kind"], "id": e["id"], "overall": e["goodness"]["overall"], "flags": e["flags"]}
        for e in sorted(scored, key=lambda e: e["goodness"]["overall"])[:5]
    ]
    return card


def to_markdown(result: dict[str, Any]) -> str:
    card = result["scorecard"]
    lines = [
        f"# Jev ratings: {result['run']}",
        "",
        f"{card['rated']} segments rated, {card['failed']} failed; "
        f"{result['input_tokens']} input tokens (${result['cost_usd_estimate']:.4f}).",
        "",
        "| Group | Difficulty | Fairness | Readability | Pacing | Fun | Overall |",
        "|---|---|---|---|---|---|---|",
    ]
    for kind in ("all", "room", "ambush", "boss"):
        if kind in card:
            row = card[kind]
            cells = " | ".join(f"{row[key]:.2f}" for key in (*WEIGHTS, "overall"))
            lines.append(f"| {kind} | {cells} |")
    lines += [
        "",
        "Goodness 0..1: P(fair) difficulty, fairness and readability and fun scores / 2,"
        " P(good) pacing.",
        "",
        "| Kind | Id | Time s | Deaths | Damage | Difficulty | Fairness | Readability | Pacing"
        " | Fun | Main problem | Overall | Flags |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for entry in result["segments"]:
        facts = entry["facts"]
        head = (
            f"| {entry['kind']} | {entry['id']} | {facts['seconds']} | {facts['deaths']}"
            f" | {facts['damage_taken']} |"
        )
        if "ratings" not in entry:
            lines.append(f"{head} {entry.get('error', 'not rated')} ||||||||")
            continue
        ratings = entry["ratings"]
        cells = [
            f"{ratings[q]['level']} ({ratings[q]['probabilities'][ratings[q]['level']]:.2f},"
            f" c{ratings[q]['confidence']:.2f})"
            for q in SCORES
        ]
        problem = ratings[PROBLEM_QUESTION]
        cells.append(f"{problem['choice']} (c{problem['confidence']:.2f})")
        cells.append(f"{entry['goodness']['overall']:.2f}")
        cells.append(", ".join(entry["flags"]) or "-")
        lines.append(f"{head} {' | '.join(cells)} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path, help="run directories with report.json")
    parser.add_argument(
        "--jev-base-url",
        default=os.environ.get(jev_backend.BASE_URL_ENV, jev_backend.DEFAULT_BASE_URL),
    )
    parser.add_argument("--jev-model", default=jev_backend.DEFAULT_MODEL)
    parser.add_argument("--budget-usd", type=float, default=DEFAULT_BUDGET_USD)
    args = parser.parse_args()
    try:
        for out in args.runs:
            result = rate_run(out, args.jev_base_url, args.jev_model, args.budget_usd)
            print(f"{out / RATINGS_MD}: {result['scorecard'].get('all', {})}")
    except jev_backend.JevConfigError as error:
        print(f"error: {error}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
