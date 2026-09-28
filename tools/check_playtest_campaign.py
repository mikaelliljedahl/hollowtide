"""Campaign mode's route planner (tools/playtest/campaign_route.py): the objective order follows the
campaign graph solver's progression stages, every objective is reachable from the previous one with
the kit owned by then, flow-field hops descend to the objective, the route's solver curls into
Slipstream form only on a floor, the runner hands the route to the game, and Jev's compact state
carries the objective. Run by tools/check_playtest_bridge.py (suite `playtest bridge`)."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "playtest"))

import campaign_route  # noqa: E402
import check_campaign_graph as graph  # noqa: E402
import jev_backend  # noqa: E402
import jev_feedback  # noqa: E402
import run  # noqa: E402
from campaign_layout import load_rooms  # noqa: E402


def landed(field: dict, key: str) -> str:
    """`key`, or the first resting spot straight below it (a pickup taken in mid-air)."""
    room, x, y, ball = key.split(":")
    for drop in range(12):
        probe = f"{room}:{x}:{int(y) + drop}:{ball}"
        if probe in field:
            return probe
    return key


class CampaignRouteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.world = graph.World(load_rooms())
        cls.temp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.temp.name)
        cls.route = campaign_route.build(cls.out)
        cls.objectives = cls.route["objectives"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def field(self, index: int) -> dict:
        return json.loads((self.out / self.objectives[index]["field"]).read_text(encoding="utf-8"))

    def test_order_follows_the_solver_stages(self):
        """Same objectives as the solver's no-optional progression, each one reachable by the
        graph check's own solver with exactly the kit and flags the route owns before it."""
        _errors, _stages, collected = graph.progress(self.world, {}, True, "route", True, False)
        targets = [objective["target"] for objective in self.objectives]
        self.assertEqual(targets[0], "fringe_02.slipstream")
        self.assertEqual(targets[-1], "ending")
        bosses = set(self.world.bosses)
        self.assertEqual(set(targets[:-1]), collected | bosses)
        start = (*self.world.start, False, 0, 0)
        for objective in self.objectives:
            solver = graph.Solver(
                self.world,
                set(objective["abilities"]),
                set(objective["flags"]),
                set(),
                breaks=False,
            )
            seen, _edges = solver.explore([start])
            reached = campaign_route.targets(
                campaign_route.Objective(
                    objective["kind"],
                    objective["target"],
                    objective["room"],
                    [tuple(cell) for cell in objective["cells"]],
                    objective["grants"],
                ),
                seen,
            )
            self.assertTrue(reached, f"{objective['target']} unreachable with its kit")

    def test_each_objective_is_ready_with_the_kit_before_it(self):
        owned: set[str] = set()
        flags: set[str] = set()
        for objective in self.objectives:
            self.assertLessEqual(set(objective["abilities"]), owned, objective["target"])
            self.assertLessEqual(set(objective["flags"]), flags, objective["target"])
            if objective["kind"] == "pickup":
                owned.add(objective["grants"])
            elif objective["kind"] == "boss":
                flags.update(objective["grants"].split(","))
            if objective["kind"] == "boss":
                self.assertLessEqual(graph.BOSS_NEEDS[objective["target"]], owned)

    def test_hops_descend_from_the_start_to_the_first_pickup(self):
        field = self.field(0)
        start = self.world.start
        key = f"{start[0]}:{start[1]}:{start[2]}:0"
        self.assertIn(key, field)
        steps = field[key][0]
        for _hop in range(200):
            steps, hop = field[key]
            if steps == 0:
                break
            last = hop[-1]
            key = f"{last[0]}:{last[1]}:{last[2]}:{last[3]}"
            self.assertIn(key, field, f"hop from {key} lands off the field")
            self.assertLess(field[key][0], steps)
        self.assertEqual(field[key][0], 0)
        self.assertEqual(key.split(":")[0], "fringe_02")

    def test_every_objective_starts_on_its_own_field(self):
        position = f"{self.world.start[0]}:{self.world.start[1]}:{self.world.start[2]}:0"
        for index in range(len(self.objectives)):
            field = self.field(index)
            position = landed(field, position)
            self.assertIn(position, field, f"objective {index} cannot be reached from {position}")
            steps, hop = field[position]
            for _hop in range(400):
                if steps == 0:
                    break
                last = hop[-1]
                position = f"{last[0]}:{last[1]}:{last[2]}:{last[3]}"
                if position not in field:
                    break  # the hop ends on the objective's cell in mid-air
                steps, hop = field[position]
            self.assertTrue(steps == 0 or position not in field, f"objective {index} not reached")

    def test_route_solver_curls_only_on_a_floor(self):
        solver = campaign_route.solver_for(self.world, {"slipstream", "beam"}, set())
        seen, _edges = solver.explore([(*self.world.start, False, 0, 0)])
        airborne = [s for s in seen if not s[3] and not campaign_route.resting(solver, s)]
        self.assertTrue(airborne)
        for state in airborne[:400]:
            self.assertFalse(any(nxt[3] for nxt in solver.neighbours(state)), state)

    def test_runner_hands_the_route_to_the_game(self):
        args = argparse.Namespace(
            godot="godot",
            windowed=False,
            room="fringe_01",
            kit="",
            seconds=2700.0,
            policy="heuristic",
            goal="none",
            max_deaths=1000,
            timeout_ms=1000,
            shots=0.0,
            spawn="",
            trial=None,
            route=self.out,
        )
        command = run.build_command(args, 1, self.out / "run", 0)
        self.assertIn("--test-mode", command)
        self.assertIn(f"--playtest-campaign={self.out}", command)


class JevObjectiveTest(unittest.TestCase):
    def test_compact_state_carries_the_objective(self):
        goal = {
            "objective": "collect the Slipstream in fringe_02",
            "kind": "pickup",
            "done": 0,
            "count": 13,
            "doors": ["south:fringe_02"],
            "heading": "down and right",
            "route_status": "on_field",
            "seconds_on_objective": 90.0,
            "gate_ahead": {"name": "harpoon socket", "opens_with": "missiles", "owned": True},
        }
        state = {
            "player": {
                "health": 100,
                "max_health": 100,
                "grounded": True,
                "on_wall": False,
                "facing": 1,
                "form": "standing",
                "dash_ready": False,
            },
            "kit": {"missiles": 0, "beam": "base", "beams": ["base"]},
            "enemies": [],
            "projectiles": [],
            "hazards": [],
            "refills": [],
            "ambush": None,
            "goal": goal,
        }
        compact = jev_backend.compact_state(state, {})
        self.assertIn("collect the Slipstream", compact["goal"])
        facts = compact["objective"]
        self.assertEqual(facts["progress"], "0 of 13 objectives done")
        self.assertEqual(facts["route"], "next door south:fringe_02, 1 room change(s) to go")
        self.assertEqual(facts["minutes_on_it"], 1.5)
        self.assertIn("harpoon socket", facts["gate_ahead"])
        for kind in ("go_to_objective", "go_to_door", "open_gate", "freeze", "fast_travel"):
            self.assertIn(kind, jev_backend.RUBRIC)
            self.assertIn(kind, jev_feedback.GROUPS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
