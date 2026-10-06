#!/usr/bin/env python3
"""Jev critic (tools/playtest/jev_critic.py) against a local stub /v1/systemone (no network):
segments cut from a run's report, the rating request's shape, answer parsing into named levels,
the scorecard, a bad answer or a rejection recorded per segment, the budget stop, and no API key
in any written file."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent / "playtest"))

import jev_backend  # noqa: E402
import jev_critic  # noqa: E402
import jev_feedback  # noqa: E402

FAKE_KEY = "ts-test-critic-key-0123456789"


def report() -> dict:
    """fringe_03 with an arena from t=20 to t=40, vaults_03 with a boss fought twice."""
    hits = [
        {
            "t": 12.0,
            "room": "fringe_03",
            "cell": [1, 1],
            "source": "hazard:stalactite",
            "amount": 18,
        },
        {"t": 25.0, "room": "fringe_03", "cell": [2, 1], "source": "bat", "amount": 10},
        {"t": 30.0, "room": "fringe_03", "cell": [2, 1], "source": "hopper", "amount": 12},
        {"t": 71.0, "room": "vaults_03", "cell": [5, 5], "source": "sg:slam", "amount": 30},
    ]
    return {
        "meta": {"run_id": "campaign-jev-s1"},
        "telemetry": {
            "hits": hits,
            "deaths": [{"t": 72.04, "room": "vaults_03", "killer": "sg:slam"}],
            "room_seconds": {"fringe_03": 50.0, "vaults_03": 70.0},
            "stuck": [
                {"room": "fringe_03", "cell": [1, 1], "t": 5.0, "seconds": 4.0},
                {"room": "fringe_03", "cell": [2, 1], "t": 26.0, "seconds": 6.0},
            ],
            "ambushes": [
                {
                    "id": "fringe_03.ambush.a",
                    "room": "fringe_03",
                    "t": 20.0,
                    "outcome": "cleared",
                    "seconds": 20.0,
                    "wave_reached": 2,
                    "waves": 2,
                    "damage_taken": 22,
                }
            ],
            "bosses": [
                {
                    "id": "stone_guardian",
                    "room": "vaults_03",
                    "t": 62.0,
                    "outcome": "died",
                    "seconds": 10.0,
                    "stage_reached": 2,
                    "attacks": {"fault_slam": 3, "rockfall": 1},
                    "attacks_landed": {"fault_slam": 1},
                    "damage_by_source": {"sg:slam": 30},
                },
                {
                    "id": "stone_guardian",
                    "room": "vaults_03",
                    "t": 90.0,
                    "outcome": "defeated",
                    "seconds": 30.0,
                    "stage_reached": 4,
                    "attacks": {"fault_slam": 4},
                    "attacks_landed": {},
                    "damage_by_source": {},
                },
            ],
        },
        "campaign": {
            "rooms_visited": [{"room": "fringe_03", "t": 1.0}, {"room": "vaults_03", "t": 55.0}],
            "attempts": [
                {"room": "fringe_03", "outcome": "done"},
                {"room": "vaults_03", "outcome": "died"},
            ],
        },
    }


# Jev saw danger coming before the t=12 hit, not before the t=71 one.
RECORDS = [
    {"t": 11.5, "room": "fringe_03", "source": "jev", "confidence": 0.8, "danger": 1.5},
    {"t": 24.5, "room": "fringe_03", "source": "jev", "confidence": 0.6, "danger": 1.0},
    {
        "t": 70.5,
        "room": "vaults_03",
        "source": "fallback:low_confidence",
        "confidence": 0.2,
        "danger": 0.1,
    },
]


def answer(problem: str = "unfair_hit", score: float = 0.4) -> dict:
    scores = {
        qid: {
            "type": "score",
            "score": score,
            "confidence": 0.5,
            "probabilities": {"0": 0.6, "1": 0.4, "2": 0.0},
        }
        for qid in jev_critic.SCORES
    }
    options = list(jev_critic.PROBLEMS)
    probabilities = {option: (0.72 if option == problem else 0.04) for option in options}
    scores[jev_critic.PROBLEM_QUESTION] = {
        "type": "choice",
        "choice": problem,
        "confidence": 0.68,
        "probabilities": probabilities,
    }
    return {"model": "jev-test", "answers": scores, "usage": {"input_tokens": 900}}


class Stub:
    """A local /v1/systemone that records requests and answers with `reply(request)`."""

    def __init__(self) -> None:
        self.requests: list[dict] = []
        self.status = 200
        # Statuses for the next requests, in order, before `status` applies again.
        self.statuses: list[int] = []
        self.reply = lambda body: answer()
        stub = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                stub.requests.append(body)
                status = stub.statuses.pop(0) if stub.statuses else stub.status
                payload = (
                    stub.reply(body)
                    if status == 200
                    else {"error": f"bad key {self.headers['Authorization']}"}
                )
                data = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args) -> None:
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()


class SegmentTest(unittest.TestCase):
    def setUp(self):
        self.cut = {(s["kind"], s["id"]): s for s in jev_critic.segments(report(), RECORDS)}

    def test_play_order_and_kinds(self):
        order = [(s["kind"], s["id"]) for s in jev_critic.segments(report(), RECORDS)]
        self.assertEqual(
            order,
            [
                ("room", "fringe_03"),
                ("ambush", "fringe_03.ambush.a"),
                ("room", "vaults_03"),
                ("boss", "stone_guardian"),
            ],
        )

    def test_room_leaves_its_fights_out(self):
        room = self.cut[("room", "fringe_03")]["facts"]
        self.assertEqual(room["seconds"], 30.0)
        self.assertEqual(room["damage_by_source"], {"hazard:stalactite": 18})
        self.assertEqual(room["stuck_seconds"], 4.0)
        self.assertEqual(room["retries"], 0)
        self.assertEqual(self.cut[("room", "vaults_03")]["facts"]["retries"], 1)
        self.assertEqual(self.cut[("room", "vaults_03")]["facts"]["deaths"], 0)

    def test_ambush_takes_the_hits_in_its_window(self):
        ambush = self.cut[("ambush", "fringe_03.ambush.a")]["facts"]
        self.assertEqual(ambush["damage_by_source"], {"hopper": 12, "bat": 10})
        self.assertEqual(ambush["damage_taken"], 22)
        self.assertEqual(ambush["best_wave_reached"], 2)
        self.assertEqual(ambush["stuck_seconds"], 6.0)

    def test_boss_attacks_seen_against_escaped(self):
        boss = self.cut[("boss", "stone_guardian")]["facts"]
        self.assertEqual(boss["attempts"], 2)
        self.assertEqual(boss["retries"], 1)
        self.assertEqual(boss["deaths"], 1)
        self.assertEqual(boss["attacks"]["fault_slam"], {"seen": 7, "landed": 1, "escaped": 6})
        self.assertEqual(boss["attacks"]["rockfall"], {"seen": 1, "landed": 0, "escaped": 1})

    def test_jev_play_counts_foreseen_hits(self):
        room = self.cut[("room", "fringe_03")]["facts"]["jev_play"]
        self.assertEqual((room["hits_foreseen"], room["hits_not_foreseen"]), (1, 0))
        boss = self.cut[("boss", "stone_guardian")]["facts"]["jev_play"]
        self.assertEqual((boss["hits_foreseen"], boss["hits_not_foreseen"]), (0, 1))
        self.assertEqual(boss["low_confidence_share"], 1.0)

    def test_request_shape(self):
        request = jev_critic.build_request("jev-test", self.cut[("boss", "stone_guardian")])
        questions = request["questions"]
        self.assertEqual(request["model"], "jev-test")
        for qid in ("difficulty", "fairness", "readability", "pacing", "fun"):
            self.assertEqual(questions[qid]["type"], "score")
            self.assertEqual(len(questions[qid]["criteria"]), 3)
        problem = questions[jev_critic.PROBLEM_QUESTION]
        self.assertEqual(problem["type"], "choice")
        self.assertEqual(
            set(problem["criteria"]),
            {
                "none",
                "unfair_hit",
                "unclear_warning",
                "too_long",
                "too_short",
                "navigation_confusing",
                "too_hard",
                "too_easy",
            },
        )
        self.assertEqual(request["state"]["segment"]["name"], "stone_guardian")
        self.assertIn("attacks", request["state"]["segment"])


class StayTest(unittest.TestCase):
    """r10-run2 kiln_02: 56.2 s in the room over five stays (a 25 s first pass with a 12.4 s
    ambush, three 3.75 s walks back from Cinder Warden deaths, an 18.4 s return), rated as one
    43.8 s visit, too_long. The first traversal is rated; the rest are their own facts."""

    def test_a_room_is_rated_on_its_first_traversal(self):
        run = report()
        entries = [("kiln_02", 0.0, "move"), ("kiln_03", 25.0, "move")]
        for start in (100.0, 200.0, 300.0):
            entries += [("kiln_02", start, "respawn"), ("kiln_03", start + 3.75, "move")]
        entries += [("kiln_02", 400.0, "move"), ("kiln_06", 418.4, "move")]
        run["campaign"]["room_entries"] = [
            {"room": room, "t": t, "cause": cause} for room, t, cause in entries
        ]
        run["telemetry"]["seconds"] = 430.0
        run["telemetry"]["room_seconds"] = {"kiln_02": 56.2}
        run["telemetry"]["ambushes"] = [
            dict(run["telemetry"]["ambushes"][0], id="kiln_02.ambush", room="kiln_02", t=8.0)
        ]
        run["telemetry"]["ambushes"][0]["seconds"] = 12.4
        run["telemetry"]["bosses"] = []
        cut = {(s["kind"], s["id"]): s for s in jev_critic.segments(run, [])}
        room = cut[("room", "kiln_02")]["facts"]
        self.assertAlmostEqual(room["seconds"], 12.6, places=1)
        self.assertEqual(room["visits"], 5)
        self.assertAlmostEqual(room["respawn_walk_seconds"], 11.2, delta=0.1)
        self.assertAlmostEqual(room["revisit_seconds"], 18.4, places=1)


class RateRunTest(unittest.TestCase):
    def setUp(self):
        self.stub = Stub()
        self.env = mock.patch.dict(os.environ, {jev_backend.KEY_ENV: FAKE_KEY})
        self.env.start()
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name)
        (self.out / "report.json").write_text(json.dumps(report()), encoding="utf-8")

    def tearDown(self):
        self.env.stop()
        self.stub.stop()
        self.tmp.cleanup()

    def rate(self, budget: float = 1.0) -> dict:
        return jev_critic.rate_run(self.out, self.stub.url, "jev-test", budget)

    def test_ratings_parse_into_named_levels(self):
        result = self.rate()
        self.assertEqual(len(self.stub.requests), 4)
        first = result["segments"][0]
        difficulty = first["ratings"]["difficulty"]
        self.assertEqual(difficulty["level"], "too easy")
        self.assertEqual(
            difficulty["probabilities"], {"too easy": 0.6, "fair": 0.4, "too hard": 0.0}
        )
        self.assertEqual(first["ratings"]["main_problem"]["choice"], "unfair_hit")
        self.assertIn("unfair", first["flags"])
        self.assertIn("unfair_hit", first["flags"])
        self.assertAlmostEqual(first["goodness"]["fairness"], 0.2)
        self.assertEqual(result["input_tokens"], 3600)
        self.assertEqual(result["scorecard"]["rated"], 4)
        self.assertEqual(result["scorecard"]["main_problems"], {"unfair_hit": 4})
        self.assertTrue((self.out / jev_critic.RATINGS_MD).exists())

    def test_bad_answers_are_recorded_not_fatal(self):
        replies = iter([answer(score=2.5), answer(problem="lag"), answer(), answer()])
        self.stub.reply = lambda body: next(replies)
        result = self.rate()
        errors = [entry.get("error", "") for entry in result["segments"]]
        self.assertIn("outside", errors[0])
        self.assertIn("not an option", errors[1])
        self.assertEqual(result["scorecard"]["rated"], 2)
        self.assertEqual(result["scorecard"]["failed"], 2)

    def test_rejection_never_writes_the_key(self):
        self.stub.status = 401
        result = self.rate()
        self.assertTrue(all(e["error"].startswith("HTTP 401") for e in result["segments"]))
        for path in self.out.iterdir():
            self.assertNotIn(FAKE_KEY, path.read_text(encoding="utf-8"), path.name)

    def test_budget_stops_the_rest(self):
        result = self.rate(budget=0.9 * 900 * jev_critic.PRICE_PER_INPUT_TOKEN)
        self.assertEqual(len(self.stub.requests), 1)
        self.assertEqual(result["segments"][1]["error"], "skipped: critic budget spent")

    def test_outage_is_retried(self):
        """r10: one 503 or 529 lost a segment for good (9 of 13 in run3)."""
        self.stub.statuses = [503, 529]
        with mock.patch.object(jev_critic, "RETRY_WAITS", (0.0, 0.0, 0.0)):
            result = self.rate()
        self.assertEqual(result["scorecard"]["rated"], 4)
        self.assertEqual(result["segments"][0]["retries"], 2)

    def test_readability_needs_rated_hits(self):
        """r10-run2: 10 of 11 segments rated "unclear" had damage but no answered Jev rating
        near any hit (the outage); readability is left out there, not inferred."""
        result = self.rate()
        room = result["segments"][0]
        self.assertGreater(room["facts"]["damage_taken"], 0)
        self.assertEqual(room["unjudged"], ["readability"])
        self.assertNotIn("unclear", room["flags"])
        self.assertNotIn("readability", room["goodness"])
        self.assertIn(jev_critic.UNJUDGED, (self.out / jev_critic.RATINGS_MD).read_text())

    def test_degraded_run_is_marked(self):
        run = report()
        run["jev"] = {"stats": jev_feedback.stats([{"source": "fallback:http_503"}] * 9)}
        (self.out / "report.json").write_text(json.dumps(run), encoding="utf-8")
        result = self.rate()
        self.assertIn("RUN DEGRADED", result["degraded"])
        text = (self.out / jev_critic.RATINGS_MD).read_text()
        self.assertTrue(text.split("\n")[2].startswith("**RUN DEGRADED"))

    def test_missing_key_refuses(self):
        with mock.patch.dict(os.environ, {jev_backend.KEY_ENV: ""}):
            with self.assertRaises(jev_backend.JevConfigError):
                self.rate()
        self.assertEqual(self.stub.requests, [])


if __name__ == "__main__":
    unittest.main(verbosity=1)
