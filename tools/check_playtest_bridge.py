#!/usr/bin/env python3
"""Python side of the playtest agent (tools/playtest/): the policy server speaks the wire format of
docs/features/playtest-agent.md, a failing backend yields a null key instead of killing the run,
the runner always passes --test-mode, the aggregate derives cross-run findings, and the jev
backend talks to a local stub /v1/systemone server (no network): request shape, answer parsing,
timeout and low-confidence fallbacks, a missing key, and no API key in any written file."""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent / "playtest"))

import aggregate  # noqa: E402
import jev_backend  # noqa: E402
import jev_feedback  # noqa: E402
import run  # noqa: E402
from policy_server import HeuristicPassthrough, PolicyServer  # noqa: E402

CANDIDATES = [{"key": "idle", "kind": "idle", "label": "stand still"}]


def report(boss_outcome: str, stage: int, killer: str, ambush_seconds: float) -> dict:
    return {
        "meta": {"end_reason": "time"},
        "telemetry": {
            "deaths": [{"killer": killer}] if boss_outcome == "died" else [],
            "damage_by_source": {killer: 40},
            "stuck": [{"room": "fringe_03", "cell": [30, 14], "seconds": 6.0}],
            "decisions": {"external": {"fallbacks": {"timeout": 2}}},
            "bosses": [
                {
                    "id": "stone_guardian",
                    "outcome": boss_outcome,
                    "stage_reached": stage,
                    "damage_by_source": {killer: 40},
                }
            ],
            "ambushes": [
                {
                    "id": "fringe_03.ambush.beam_trial",
                    "outcome": "cleared",
                    "seconds": ambush_seconds,
                    "damage_taken": 10,
                }
            ],
        },
    }


class Broken(HeuristicPassthrough):
    def decide(self, state, candidates, hint):
        raise RuntimeError("model unavailable")


class PolicyServerTest(unittest.TestCase):
    def talk(self, backend) -> tuple[list[dict], PolicyServer]:
        server = PolicyServer(backend, accept_timeout=5).start()
        replies = []
        with socket.create_connection(("127.0.0.1", server.port), timeout=5) as client:
            stream = client.makefile("rwb")
            for message in (
                {"type": "hello", "protocol": 1, "run_id": "t"},
                {
                    "type": "decide",
                    "tick": 3,
                    "state": {},
                    "candidates": CANDIDATES,
                    "hint": "idle",
                },
                {"type": "bye", "summary": {"end_reason": "time"}},
            ):
                stream.write((json.dumps(message) + "\n").encode())
                stream.flush()
                if message["type"] == "decide":
                    replies.append(json.loads(stream.readline()))
        server.join(timeout=5)
        return replies, server

    def test_passthrough_round_trip(self):
        replies, server = self.talk(HeuristicPassthrough())
        self.assertEqual(replies, [{"type": "action", "tick": 3, "key": "idle"}])
        self.assertEqual(server.stats.decisions, 1)
        self.assertEqual(server.stats.bye, {"end_reason": "time"})

    def test_backend_failure_sends_null_key(self):
        replies, server = self.talk(Broken())
        self.assertIsNone(replies[0]["key"])
        self.assertIn("model unavailable", server.stats.backend_errors[0])


class RunnerTest(unittest.TestCase):
    def test_command_is_an_argument_vector_in_test_mode(self):
        args = argparse.Namespace(
            godot="godot",
            windowed=False,
            room="fringe_03",
            kit="beam",
            seconds=30.0,
            policy="external",
            goal="auto",
            max_deaths=3,
            timeout_ms=500,
            shots=0.0,
            spawn="",
        )
        command = run.build_command(args, 2, Path("/tmp/x y/run"), 4242)
        self.assertIn("--test-mode", command)
        self.assertIn("--test-save-root=/tmp/x y/run/saves", command)
        self.assertIn("--playtest-port=4242", command)
        breaks = next(arg for arg in command if arg.startswith("--playtest-breaks="))
        self.assertIn("breach_ledge:fringe_01:", breaks)


class AggregateTest(unittest.TestCase):
    def test_cross_run_findings(self):
        summary = aggregate.aggregate(
            [
                report("died", 3, "stone_guardian:fault_slam", 6.0),
                report("died", 3, "stone_guardian:fault_slam", 8.0),
                report("defeated", 4, "stone_guardian:rockfall", 7.0),
            ]
        )
        text = "\n".join(summary["findings"])
        self.assertIn("stone_guardian: 1/3 attempts won over 3 runs", text)
        self.assertIn("stage 3 killed the agent 2/3 times", text)
        self.assertIn("most damage from stone_guardian:fault_slam (80)", text)
        self.assertIn("cleared 3/3 fights, mean 7.0 s", text)
        self.assertIn("Stuck at fringe_03 (30, 14) in 3/3 runs, 18.0 s in total.", text)
        self.assertIn("fell back 6 times (timeout)", text)
        self.assertTrue(aggregate.to_markdown(summary).startswith("# Playtest aggregate (3 runs)"))


FAKE_KEY = "ts-test-key-4f1c9a"
GAME_STATE = {
    "tick": 7,
    "t": 3.0,
    "room": {"id": "fringe_03", "area": "fringe", "size": [1920, 1088]},
    "player": {
        "pos": [640, 896],
        "cell": [10, 13],
        "vel": [0, 0],
        "health": 60,
        "max_health": 100,
        "grounded": True,
        "on_wall": False,
        "facing": 1,
        "form": "standing",
        "dash_ready": False,
    },
    "kit": {"abilities": ["beam"], "beam": "base", "missiles": 0, "max_missiles": 0},
    "enemies": [
        {
            "id": "e2",
            "type": "hopper",
            "rel": [192, 0],
            "dist": 192,
            "health": 20,
            "max_health": 20,
            "is_boss": False,
            "telegraph": True,
            "ambush": True,
            "hurt_by": ["beam"],
            "visible": True,
        }
    ],
    "projectiles": [{"rel": [-256, -64], "vel": [300, 0], "style": "spit"}],
    "ambush": {
        "id": "fringe_03.ambush.beam_trial",
        "state": "fighting",
        "wave": 1,
        "waves": 3,
        "alive": 2,
        "trigger_rel": [0, 0],
        "inside": True,
    },
    "exits": [],
    "pickups": [],
    "hazards": [],
}
GAME_CANDIDATES = [
    {"key": "idle", "kind": "idle", "label": "stand still"},
    {"key": "retreat", "kind": "retreat", "label": "run away from hopper"},
    {"key": "shoot:e2:forward", "kind": "shoot", "label": "fire the crossbow forward at hopper"},
    {"key": "harpoon:e2:forward", "kind": "harpoon", "label": "fire a harpoon forward at hopper"},
    {"key": "dash_through", "kind": "dash_through", "label": "dash into the incoming spit shot"},
    {"key": "jump:left", "kind": "jump", "label": "jump left"},
]


def jev_answer(choice: str, confidence: float, keys: list[str]) -> dict:
    rest = (1.0 - confidence) / max(1, len(keys) - 1)
    probabilities = {key: (confidence if key == choice else rest) for key in keys}
    return {
        "model": "jev-1.13.0",
        "answers": {
            "action": {
                "type": "choice",
                "choice": choice,
                "probabilities": probabilities,
                "confidence": confidence,
            },
            "danger": {"type": "score", "score": 1.8, "confidence": 0.7},
            "unsure": {"type": "noul", "noul": 0.1},
        },
        "usage": {"input_tokens": 700, "output_tokens": 30},
    }


class StubJev:
    """A local /v1/systemone on 127.0.0.1 that records requests and answers per `mode`."""

    def __init__(self) -> None:
        self.mode = "ok"
        self.confidence = 0.8
        self.requests: list[dict] = []
        stub = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                stub.requests.append(
                    {"path": self.path, "headers": dict(self.headers.items()), "body": body}
                )
                if stub.mode == "slow":
                    time.sleep(0.6)
                if stub.mode == "reject":
                    # A hostile server echoing the credential back must not get it into a report.
                    self._reply(401, {"error": f"bad key {self.headers['Authorization']}"})
                    return
                keys = list(body["questions"]["action"]["criteria"])
                self._reply(200, jev_answer(keys[2], stub.confidence, keys))

            def _reply(self, status: int, payload: dict) -> None:
                data = json.dumps(payload).encode()
                try:
                    self.send_response(status)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                except OSError:
                    pass  # The client gave up (the timeout test).

            def log_message(self, *args) -> None:
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()


class JevBackendTest(unittest.TestCase):
    def setUp(self):
        self.stub = StubJev()
        self.env = mock.patch.dict(os.environ, {jev_backend.KEY_ENV: FAKE_KEY})
        self.env.start()
        self.backend = jev_backend.JevBackend(
            jev_backend.JevConfig(base_url=self.stub.url, model="jev-test", timeout_ms=300)
        )

    def tearDown(self):
        self.backend.close({})
        self.env.stop()
        self.stub.stop()

    def decide(self, t: float = 3.0) -> str:
        return self.backend.decide(dict(GAME_STATE, t=t), GAME_CANDIDATES, "retreat")

    def test_request_shape_and_answer(self):
        self.backend.start({})
        key = self.decide()
        request = self.stub.requests[0]
        self.assertEqual(request["path"], "/v1/systemone")
        self.assertEqual(request["headers"]["Authorization"], f"Bearer {FAKE_KEY}")
        body = request["body"]
        self.assertEqual(body["model"], "jev-test")
        questions = body["questions"]
        self.assertEqual(
            {name: q["type"] for name, q in questions.items()},
            {"action": "choice", "danger": "score", "unsure": "noul"},
        )
        # No harpoons left and the dash is not ready: both are removed before sending.
        self.assertEqual(
            list(questions["action"]["criteria"]),
            ["idle", "retreat", "shoot:e2:forward", "jump:left"],
        )
        self.assertIn("run away from hopper", questions["action"]["criteria"]["retreat"])
        self.assertEqual(len(questions["danger"]["criteria"]), 3)
        state = body["state"]
        self.assertEqual(state["threats"][0]["dx_tiles"], 3)
        self.assertEqual(state["threats"][0]["range"], "close")
        self.assertTrue(state["facts"]["threat_winding_up"])
        self.assertTrue(state["facts"]["shot_incoming"])
        self.assertTrue(state["facts"]["in_arena"])
        self.assertEqual(state["player"]["health_pct"], 60)
        self.assertNotIn("pos", state["player"])
        self.assertEqual(key, "shoot:e2:forward")
        record = self.backend.records[0]
        self.assertEqual(record["source"], "jev")
        self.assertEqual(record["removed"], ["dash_through", "harpoon:e2:forward"])
        self.assertAlmostEqual(sum(record["probabilities"].values()), 1.0, places=3)
        self.assertEqual((record["danger"], record["unsure"]), (1.8, 0.1))
        self.assertEqual((record["input_tokens"], record["model"]), (700, "jev-1.13.0"))
        self.assertGreater(record["latency_ms"], 0)

    def test_rate_cap_skips_between_calls(self):
        self.decide(3.0)
        self.assertEqual(self.decide(3.1), "retreat")
        self.assertEqual(self.backend.records[1]["source"], "skip:rate")
        self.assertEqual(len(self.stub.requests), 1)

    def test_timeout_falls_back_to_the_hint(self):
        self.stub.mode = "slow"
        started = time.monotonic()
        self.assertEqual(self.decide(), "retreat")
        self.assertLess(time.monotonic() - started, 0.55)
        self.assertEqual(self.backend.records[0]["source"], "fallback:timeout")

    def test_low_confidence_falls_back_to_the_hint(self):
        self.stub.confidence = 0.2
        self.assertEqual(self.decide(), "retreat")
        record = self.backend.records[0]
        self.assertEqual(record["source"], "fallback:low_confidence")
        self.assertEqual(record["choice"], "shoot:e2:forward")

    def test_missing_key_names_the_variable_only(self):
        os.environ.pop(jev_backend.KEY_ENV)
        with self.assertRaises(jev_backend.JevConfigError) as caught:
            self.backend.start({})
        self.assertIn(jev_backend.KEY_ENV, str(caught.exception))
        self.assertNotIn(FAKE_KEY, str(caught.exception))
        self.assertEqual(self.decide(), "retreat")
        self.assertEqual(self.backend.records[0]["source"], "fallback:missing_key")
        self.assertEqual(self.stub.requests, [])
        self.assertEqual(self.decide(9.0), "retreat")  # Disabled: no further request.
        self.assertEqual(self.backend.records[1]["source"], "fallback:disabled")

    def test_rejection_stops_and_no_file_holds_the_key(self):
        self.decide(1.0)
        self.stub.mode = "reject"
        self.decide(2.0)
        self.decide(3.0)
        self.assertEqual(len(self.stub.requests), 2)
        self.assertEqual(self.backend.fatal["status"], 401)
        self.assertNotIn(FAKE_KEY, json.dumps(self.backend.fatal))
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / "report.md").write_text("# Playtest run\n", encoding="utf-8")
            hits = [{"t": 2.5, "room": "fringe_03", "cell": [10, 13], "source": "hopper"}]
            (out / "report.json").write_text(
                json.dumps({"meta": {}, "telemetry": {"hits": hits}}), encoding="utf-8"
            )
            lines = [json.dumps({"tick": 7, "key": "retreat"}), json.dumps({"tick": 8})]
            (out / "decisions.jsonl").write_text("\n".join(lines), encoding="utf-8")
            jev_feedback.apply(out, self.backend)
            written = {path.name: path.read_text() for path in out.iterdir()}
        self.assertEqual(
            sorted(written),
            ["decisions.jsonl", "jev_request_sample.json", "report.json", "report.md"],
        )
        for name, text in written.items():
            self.assertNotIn(FAKE_KEY, text, name)
        self.assertIn("Bearer [redacted]", written["jev_request_sample.json"])
        self.assertIn("Jev rejected the run (HTTP 401)", written["report.md"])
        self.assertIn('"jev": {', written["decisions.jsonl"])


class JevFeedbackTest(unittest.TestCase):
    def record(self, t, cell, probabilities, confidence, danger, hint="shoot:e1:forward"):
        choice = max(probabilities, key=probabilities.get)
        return {
            "tick": int(t * 10),
            "t": t,
            "room": "vaults_03",
            "cell": cell,
            "hint": hint,
            "threat": "stone_guardian",
            "boss_attack": "boulder_volley",
            "source": "jev" if confidence >= 0.35 else "fallback:low_confidence",
            "choice": choice,
            "key": choice,
            "confidence": confidence,
            "probabilities": probabilities,
            "danger": danger,
            "latency_ms": 200.0,
            "input_tokens": 1000,
        }

    def test_findings_are_design_actionable(self):
        split = {"retreat": 0.4, "harpoon:e1:forward": 0.35, "idle": 0.25}
        records = [
            self.record(1.0, [12, 9], split, 0.3, 0.2),
            self.record(1.5, [13, 10], split, 0.3, 0.3),
            self.record(4.0, [20, 9], {"shoot:e1:forward": 0.9, "idle": 0.1}, 0.9, 1.9),
            self.record(6.0, [20, 9], {"shoot:e1:forward": 0.9, "idle": 0.1}, 0.9, 1.8),
        ]
        hits = [{"t": 2.0, "source": "stone_guardian:boulder_volley", "amount": 12}]
        summary = jev_feedback.stats(records)
        analysis = jev_feedback.analyze(records, hits, 0.35)
        text = "\n".join(jev_feedback.describe(summary, analysis))
        self.assertIn("Confusion hotspot vaults_03 around cell (13, 10): 2 of 2", text)
        self.assertIn("harpoon vs retreat (2x)", text)
        self.assertIn("Unreadable hits from stone_guardian:boulder_volley: 1 of 1", text)
        self.assertIn("rated danger high 2 times and 2 passed without damage", text)
        self.assertIn("disagreed with the heuristic in 2 of 4", text)
        extra = jev_feedback.derived(summary)
        self.assertEqual((extra["fallback_rate"], extra["mean_latency_ms"]), (0.5, 200.0))
        self.assertAlmostEqual(extra["cost_usd_estimate"], 0.00017)
        merged = aggregate.aggregate(
            [
                dict(report("defeated", 4, "x", 7.0), jev={"stats": summary, "analysis": analysis}),
                dict(report("defeated", 4, "x", 7.0), jev={"stats": summary, "analysis": analysis}),
            ]
        )
        self.assertIn("4 of 4 Jev decisions", "\n".join(merged["jev"]["findings"]))
        self.assertIn("## Jev policy (2 runs)", aggregate.to_markdown(merged))


if __name__ == "__main__":
    unittest.main(verbosity=2)
