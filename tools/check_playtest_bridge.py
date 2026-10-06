#!/usr/bin/env python3
"""Python side of the playtest agent (tools/playtest/): the policy server speaks the wire format of
docs/features/playtest-agent.md, a failing backend yields a null key instead of killing the run,
the runner always passes --test-mode, the aggregate derives cross-run findings, and the jev
backend talks to a local stub /v1/systemone server (no network): request shape, answer parsing,
timeout and low-confidence fallbacks, a missing key, and no API key in any written file. Campaign
mode's route planner is tested in tools/check_playtest_campaign.py, whose cases run here too."""

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
import jev_request  # noqa: E402
import run  # noqa: E402
from check_playtest_campaign import CampaignRouteTest, JevObjectiveTest  # noqa: E402, F401
from check_playtest_feedback import JevFeedbackTest, report  # noqa: E402, F401
from policy_server import HeuristicPassthrough, PolicyServer  # noqa: E402

CANDIDATES = [{"key": "idle", "kind": "idle", "label": "stand still"}]


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
    def test_godot_gets_its_own_home_and_no_key(self):
        with tempfile.TemporaryDirectory() as scratch:
            out = Path(scratch) / "run"
            saved = os.environ.get(jev_backend.KEY_ENV)
            os.environ[jev_backend.KEY_ENV] = "placeholder"
            try:
                env = run.child_env(out)
            finally:
                if saved is None:
                    os.environ.pop(jev_backend.KEY_ENV)
                else:
                    os.environ[jev_backend.KEY_ENV] = saved
            home = (out / "home").resolve()
            for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME"):
                self.assertTrue(Path(env[key]).is_relative_to(home), key)
            self.assertNotIn(jev_backend.KEY_ENV, env)

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

    def test_degraded_jev_run_is_left_out(self):
        """r10's runs fell back 92-97% during a hosted outage and were reported as Jev runs."""
        healthy = report("defeated", 4, "stone_guardian:rockfall", 7.0)
        healthy["jev"] = self.jev_run([{"source": "jev"}] * 9 + [{"source": "fallback:timeout"}])
        outage = report("died", 3, "stone_guardian:fault_slam", 6.0)
        outage["jev"] = self.jev_run([{"source": "fallback:http_503"}] * 9)
        summary = aggregate.aggregate([healthy, outage])
        self.assertIn("1 of 2 runs", summary["degraded"])
        self.assertEqual(summary["jev"]["stats"]["decisions"], 10)
        lines = aggregate.to_markdown(summary).split("\n")
        self.assertTrue(lines[2].startswith("**RUN DEGRADED"))
        summary = aggregate.aggregate([outage])
        self.assertEqual(summary["jev"]["findings"], [])
        self.assertIn("RUN DEGRADED", jev_feedback.describe(outage["jev"]["stats"], {})[0])

    @staticmethod
    def jev_run(records: list[dict]) -> dict:
        stats = jev_feedback.stats(records)
        return {"stats": stats, "analysis": jev_feedback.analyze(records, [], 0.35)}


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
                if stub.mode == "overloaded":
                    self._reply(529, {"error": "system_overloaded"}, {"Retry-After": "10"})
                    return
                if stub.mode == "unavailable":
                    self._reply(503, {"error": "no healthy upstream"})
                    return
                if stub.mode == "reject":
                    # A hostile server echoing the credential back must not get it into a report.
                    self._reply(401, {"error": f"bad key {self.headers['Authorization']}"})
                    return
                keys = list(body["questions"]["action"]["criteria"])
                self._reply(200, jev_answer(keys[2], stub.confidence, keys))

            def _reply(self, status: int, payload: dict, headers: dict | None = None) -> None:
                data = json.dumps(payload).encode()
                try:
                    self.send_response(status)
                    for name, value in (headers or {}).items():
                        self.send_header(name, value)
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
        # Jev's answer is kept between calls instead of the hint ("retreat").
        self.assertEqual(self.decide(3.1), "shoot:e2:forward")
        self.assertEqual(self.backend.records[1]["source"], "skip:rate")
        self.assertTrue(self.backend.records[1]["held"])
        self.assertEqual(len(self.stub.requests), 1)

    def test_rate_skip_plays_the_hint_after_a_fallback(self):
        self.stub.confidence = 0.2
        self.decide(3.0)
        self.assertEqual(self.decide(3.1), "retreat")
        self.assertNotIn("held", self.backend.records[1])

    def test_budget_stops_the_calls(self):
        self.backend.config.budget_usd = 1e-9
        self.decide(3.0)
        self.assertEqual(self.decide(4.0), "retreat")
        self.assertEqual(self.backend.records[1]["source"], "skip:budget")
        self.assertEqual(len(self.stub.requests), 1)

    def test_timeout_falls_back_to_the_hint(self):
        self.stub.mode = "slow"
        started = time.monotonic()
        self.assertEqual(self.decide(), "retreat")
        self.assertLess(time.monotonic() - started, 0.55)
        self.assertEqual(self.backend.records[0]["source"], "fallback:timeout")

    def test_overload_cools_down_in_game_time(self):
        """r10-run1: a 529's 10 s cooldown ran on the wall clock while the headless game ran
        ahead, so one 529 blanked 120-200 game seconds; the cooldown is game time now."""
        self.stub.mode = "overloaded"
        self.decide(1.0)
        self.stub.mode = "ok"
        self.decide(5.0)
        self.assertEqual(self.backend.records[1]["source"], "fallback:cooldown")
        self.assertEqual(self.decide(11.5), "shoot:e2:forward")
        self.assertEqual(len(self.stub.requests), 2)

    def test_unavailable_backs_off(self):
        """r10: 634 requests went into a seven-minute 503 outage, one per decision; a 503 now
        backs off 1 s, then 2 s, and an answer resets it."""
        self.stub.mode = "unavailable"
        for t in (1.0, 1.5, 2.1, 3.5, 4.2):
            self.decide(t)
        sources = [record["source"] for record in self.backend.records]
        self.assertEqual(
            sources,
            [
                "fallback:http_503",
                "fallback:cooldown",
                "fallback:http_503",
                "fallback:cooldown",
                "fallback:http_503",
            ],
        )
        self.stub.mode = "ok"
        self.assertEqual(self.decide(8.5), "shoot:e2:forward")
        self.assertEqual(self.backend._failures, 0)

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


class JevRoundThreeStateTest(unittest.TestCase):
    """Round 3: Jev sees the boss shell and its opener, the bolts, touching hazards and refills."""

    def state(self) -> dict:
        state = json.loads(json.dumps(GAME_STATE))
        state["kit"].update(beam="ice", beams=["base", "ice", "wave"], missiles=0, max_missiles=35)
        opener = {"beam": "wave", "via": "grate", "owned": True, "point_rel": [300, -320]}
        boss = dict(state["enemies"][0], id="e1", type="tidal_heart", is_boss=True, hurt_by=[])
        boss.update(stage=3, attack="", attack_state="idle", open=False, opener=opener)
        boss["switch_to"] = "wave"
        state["enemies"] = [boss]
        state["hazards"] = [
            {"kind": "lava", "rel": [64, 0], "size": [256, 64], "gap": 0, "state": ""},
            {"kind": "stalactite", "rel": [0, -900], "size": [96, 128], "gap": 700, "state": ""},
        ]
        state["refills"] = [{"kind": "missilerefill", "restores": ["harpoons"], "rel": [600, 0]}]
        return state

    def test_compact_state_carries_shell_bolts_hazards_and_refills(self):
        compact = jev_request.compact_state(self.state(), {})
        threat = compact["threats"][0]
        self.assertEqual(
            threat["shell"], "closed; an Echo (wave) shot through the grate in front of it opens it"
        )
        self.assertEqual(threat["hurt_by_bolt"], "Echo (wave)")
        self.assertEqual(compact["facts"]["boss_shell"], threat["shell"])
        self.assertEqual(compact["player"]["bolt"], "Snare (ice)")
        self.assertEqual(len(compact["player"]["bolts_owned"]), 3)
        # Only the lava is within four tiles; it touches the player.
        self.assertEqual(compact["hazards"], [{"kind": "lava", "where": "right", "touching": True}])
        self.assertEqual(compact["facts"]["refill_here_for"], "harpoons")

    def test_spent_opening_reads_closed_without_an_opener(self):
        state = self.state()
        state["enemies"][0]["opening"] = False
        self.assertEqual(
            jev_request.compact_state(state, {})["threats"][0]["shell"],
            "closed; nothing hurts it until it recovers after its next attack",
        )

    def test_new_kinds_have_rubric_groups_and_legality(self):
        for kind in (
            "jump_shoot",
            "open_boss",
            "select_beam",
            "pulse",
            "go_to_refill",
            "duck",
            "dodge",
        ):
            self.assertIn(kind, jev_request.RUBRIC)
            self.assertIn(kind, jev_feedback.GROUPS)
        candidates = [
            {"key": "idle", "kind": "idle", "label": "stand still"},
            {"key": "pulse:e1", "kind": "pulse", "label": "roll in and drop a pulse"},
            {"key": "select_beam:wave", "kind": "select_beam", "label": "switch to Echo"},
        ]
        kept = jev_request.legal(candidates, self.state(), "idle")
        self.assertEqual([c["key"] for c in kept], ["idle", "select_beam:wave"])
        request = jev_request.build_request("jev-test", self.state(), kept, {})
        self.assertIn(
            "equipped bolt", request["questions"]["action"]["criteria"]["select_beam:wave"]
        )

    def test_no_useless_bolt_shots(self):
        state = self.state()
        mimic = dict(state["enemies"][0], id="e63", type="mimic", is_boss=False, frozen=True)
        mimic["hurt_by"] = ["ice", "missile", "bomb"]
        state["enemies"] = [mimic]
        candidates = [
            {"key": "shoot:e63:up", "kind": "shoot", "label": "fire the crossbow up at mimic"},
            {"key": "go_to_objective", "kind": "go_to_objective", "label": "follow the route"},
        ]
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(keys, ["go_to_objective"])
        mimic["frozen"] = False
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(keys, ["shoot:e63:up", "go_to_objective"])
        # An armored guard only the Resonance Pulse hurts: no bolt shot at it.
        mimic.update(type="armored_guard", hurt_by=["bomb"], frozen=False)
        state["kit"]["beam"] = "base"
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(keys, ["go_to_objective"])
        # A closed boss no bolt hurts (its opener is open_boss): no body shot; an open one keeps it.
        mimic.update(type="tidal_heart", is_boss=True, hurt_by=[])
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(keys, ["go_to_objective"])
        mimic["hurt_by"] = ["beam", "missile"]
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(keys, ["shoot:e63:up", "go_to_objective"])

    def test_empty_quiver_at_a_boss_takes_the_refill_run(self):
        # t4-min-s1b: 1,880 approaches at a shut Tidal Heart with the Harpoon refill offered.
        state = self.state()
        candidates = [
            {"key": "approach:e1", "kind": "approach", "label": "move to firing range"},
            {"key": "retreat", "kind": "retreat", "label": "run away from tidal_heart"},
            {"key": "go_to_refill:missilerefill", "kind": "go_to_refill", "label": "refill"},
        ]
        hint = "go_to_refill:missilerefill"
        keys = [c["key"] for c in jev_request.legal(candidates, state, hint)]
        self.assertEqual(keys, ["retreat", hint])
        self.assertIn("empty", jev_request.compact_state(state, {})["facts"]["quiver"])
        # No refill run offered, or Harpoons left: the approach stays.
        keys = [c["key"] for c in jev_request.legal(candidates[:2], state, "retreat")]
        self.assertEqual(keys, ["approach:e1", "retreat"])
        state["kit"]["missiles"] = 5
        keys = [c["key"] for c in jev_request.legal(candidates, state, hint)]
        self.assertEqual(keys, ["approach:e1", "retreat", hint])
        self.assertNotIn("quiver", jev_request.compact_state(state, {})["facts"])

    def test_passing_a_boss_that_is_not_the_goal(self):
        # r12-full-s1: after the Tollwing objective timed out, later objectives led through its
        # arena and Jev idled and shot there for over 1,000 s with an empty quiver.
        state = self.state()
        state["enemies"][0].update(type="tollwing", stage=2)
        state["goal"] = {"kind": "visit", "target": "nexus_05", "room": "nexus_05"}
        candidates = [
            {"key": "idle", "kind": "idle", "label": "stand still"},
            {"key": "go_to_objective", "kind": "go_to_objective", "label": "follow the route"},
            {"key": "dodge:swoop", "kind": "dodge", "label": "run into the pocket"},
            {"key": "approach:e1", "kind": "approach", "label": "move to firing range"},
            {"key": "select_beam:base", "kind": "select_beam", "label": "switch"},
        ]
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(keys, ["go_to_objective", "dodge:swoop"])
        # Its own objective, or no route move offered: the fight moves stay.
        state["goal"] = {"kind": "mini", "target": "tollwing", "room": "nexus_09"}
        keys = [c["key"] for c in jev_request.legal(candidates, state, "go_to_objective")]
        self.assertEqual(len(keys), 5)
        state["goal"] = {"kind": "visit", "target": "nexus_05", "room": "nexus_05"}
        keys = [c["key"] for c in jev_request.legal(candidates[2:], state, "dodge:swoop")]
        self.assertEqual(len(keys), 3)

    def test_no_route_out_of_a_running_arena(self):
        # r6-min-s1: the route led up out of the fringe_03 beam trial and the arena aborted.
        state = self.state()
        state["enemies"] = []
        state["ambush"] = {"state": "fighting", "wave": 1, "waves": 2, "alive": 2, "inside": True}
        candidates = [
            {"key": "go_to_objective", "kind": "go_to_objective", "label": "follow the route"},
            {"key": "go_to_door:west:fringe_02", "kind": "go_to_door", "label": "door"},
            {"key": "approach:e3", "kind": "approach", "label": "approach enemy e3 (hopper)"},
        ]
        keys = [c["key"] for c in jev_request.legal(candidates, state, "approach:e3")]
        self.assertEqual(keys, ["approach:e3"])
        state["ambush"]["state"] = "cleared"
        keys = [c["key"] for c in jev_request.legal(candidates, state, "approach:e3")]
        self.assertEqual(len(keys), 3)

    def test_crouch_shot_is_explained_and_legal_on_the_ground(self):
        self.assertIn("crouch_shot", jev_request.RUBRIC)
        self.assertEqual(jev_feedback.GROUPS["crouch_shot"], "attack")
        state = self.state()
        guard = dict(state["enemies"][0], id="e7", type="armored_guard", is_boss=False, low=True)
        guard["hurt_by"] = ["missile", "bomb"]
        state["enemies"] = [guard]
        state["kit"].update(beam="base", missiles=5)
        self.assertTrue(jev_request.compact_state(state, {})["threats"][0]["below_standing_shot"])
        candidates = [
            {"key": "crouch_shot:e7:harpoon", "kind": "crouch_shot", "label": "crouch and fire"},
            {"key": "approach:e7", "kind": "approach", "label": "approach enemy e7"},
        ]
        keys = [c["key"] for c in jev_request.legal(candidates, state, "approach:e7")]
        self.assertEqual(keys, ["crouch_shot:e7:harpoon", "approach:e7"])
        state["kit"]["missiles"] = 0
        keys = [c["key"] for c in jev_request.legal(candidates, state, "approach:e7")]
        self.assertEqual(keys, ["approach:e7"])
        state["kit"]["missiles"] = 5
        state["player"]["grounded"] = False
        keys = [c["key"] for c in jev_request.legal(candidates, state, "approach:e7")]
        self.assertEqual(keys, ["approach:e7"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
