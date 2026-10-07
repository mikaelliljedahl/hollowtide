"""Campaign mode's route planner (tools/playtest/campaign_route.py): the objective order follows the
campaign graph solver's progression stages, every objective is reachable from the previous one with
the kit owned by then, flow-field hops descend to the objective, the route's solver curls into
Slipstream form only on a floor, the runner hands the route to the game, and Jev's compact state
carries the objective. Round 10: the route sweeps the 48-room world (every mini-boss fight and
optional pickup the route solver can reach, the Tidal Heart and the ending last), and builds in
under BUILD_LIMIT seconds. Run by tools/check_playtest_bridge.py (suite `playtest bridge`)."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "playtest"))

import campaign_route  # noqa: E402
import check_campaign_graph as graph  # noqa: E402
import jev_feedback  # noqa: E402
import jev_request  # noqa: E402
import run  # noqa: E402
from campaign_layout import load_rooms  # noqa: E402
from route_graph import RouteSolver  # noqa: E402

# Round 9's planner took over two minutes on the 48-room world; the limit guards against that
# class of regression, not against machine load. Round 13: the 72-objective route (depths cluster
# reachable) took 19.0 to 30.8 s of CPU on this laptop at load average 6 to 15 (another agent's
# Godot running), 14.5 s for 66 objectives on a quieter machine, so 20 s failed on load alone.
BUILD_LIMIT = 40.0


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
        began = time.monotonic()
        cls.route = campaign_route.build(cls.out)
        cls.seconds = time.monotonic() - began
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
        targets = [o["target"] for o in self.objectives if not o["optional"]]
        self.assertEqual(targets[0], "fringe_02.slipstream")
        self.assertEqual(targets[-1], "ending")
        bosses = set(self.world.bosses)
        self.assertEqual(set(targets[:-1]), collected | bosses)
        start = (*self.world.start, False, 0, 0)
        explored: dict[tuple, set] = {}
        for objective in self.objectives:
            kit = (tuple(objective["abilities"]), tuple(objective["flags"]))
            if kit not in explored:
                solver = graph.Solver(self.world, set(kit[0]), set(kit[1]), set(), breaks=False)
                explored[kit] = solver.explore([start])[0]
            seen = explored[kit]
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

    def test_build_is_fast(self):
        """Round 9 took over two minutes to build the 48-room route."""
        self.assertLess(self.seconds, BUILD_LIMIT)

    def test_the_sweep_takes_every_reachable_optional(self):
        """Every pickup, mini-boss and room is an objective or on a path to one, or unreachable
        for the route solver (no timed doors, no breaks) even with every ability and flag, or a
        trap it cannot leave; optional objectives carry a time budget."""
        taken = {o["target"] for o in self.objectives}
        for pickup_id, _kind in self.world.pickups.values():
            self.assertTrue(pickup_id in taken or pickup_id in self.route["unreached"], pickup_id)
        minis = [o for o in self.objectives if o["kind"] == "mini"]
        # Three since round 12: Lanternjaw's depths_08 lies past depths_01's south opening, which
        # the game's updraft never lets a body sink through (RouteSolver).
        self.assertGreaterEqual(len(minis), 3, [o["target"] for o in minis])
        for mini in self.world.minis:
            self.assertTrue(mini in taken or f"mini:{mini}" in self.route["unreached"], mini)
        for objective in minis:
            self.assertTrue(objective["optional"])
            self.assertEqual(objective["grants"], f"mini:{objective['target']}")
        every = {"missiles", "slipstream", "beam", "bombs", "ice_beam", "high_jump"}
        every |= {"pressure_seal", "wave_beam", "undertow_dash"}
        flags = {
            f"{prefix}:{boss}" for boss in self.world.bosses for prefix in ("boss", "regional")
        }
        flags |= {f"mini:{mini}" for mini in self.world.minis}
        solver = RouteSolver(self.world, every, flags, set(), breaks=False)
        seen, _edges = solver.explore([(*self.world.start, False, 0, 0)])
        for missing in self.route["unreached"]:
            if missing.startswith("room:"):
                # A room the solver only enters as a trap (it cannot leave again) is not swept.
                inside = [state for state in seen if state[0] == missing[5:]]
                escaped, _edges = solver.explore(inside)
                self.assertFalse([s for s in escaped if s[0] != missing[5:]], missing)
                continue
            if missing.startswith("mini:"):
                room, arena = self.world.minis[missing[5:]]
                cells = campaign_route._arena_cells(arena)
            else:
                room, x, y = next(k for k, v in self.world.pickups.items() if v[0] == missing)
                cells = [(x, y)]
            objective = campaign_route.Objective("pickup", missing, room, cells, "")
            self.assertFalse(campaign_route.targets(objective, seen), f"{missing} is reachable")
        for objective in self.objectives:
            self.assertEqual("seconds" in objective, objective["optional"], objective["target"])

    def test_mini_rewards_follow_their_fight(self):
        """A pickup behind a `mini:` gate comes after that fight (kiln_08's Bolt Quiver)."""
        order = [o["target"] for o in self.objectives]
        self.assertLess(order.index("emberkite"), order.index("kiln_08.missile_02"))
        quiver = self.objectives[order.index("kiln_08.missile_02")]
        self.assertIn("mini:emberkite", quiver["flags"])

    def test_only_a_mini_reward_needs_the_mini_flag(self):
        """r10-run1/run2 timed out on the optional Tollwing, and every later objective, the
        required ones too, listed `mini:tollwing`: nothing was ready and the run ended as
        `route_done` with 43 objectives open. Only an optional pickup behind a mini-boss reward
        gate lists a `mini:` flag."""
        for objective in self.objectives:
            minis = [flag for flag in objective["flags"] if flag.startswith("mini:")]
            if not objective["optional"] or objective["kind"] != "pickup":
                self.assertFalse(minis, f"{objective['index']} {objective['target']}")

    def test_last_boss_and_ending_come_last(self):
        kinds = [(o["kind"], o["target"]) for o in self.objectives]
        self.assertEqual(kinds[-2:], [("boss", "tidal_heart"), ("ending", "ending")])

    def test_minimum_kit_plans_required_items_only(self):
        minimum = campaign_route.plan(self.world, sweep=False)
        self.assertFalse([o.target for o in minimum if o.optional or o.kind == "mini"])
        required = [o["target"] for o in self.objectives if not o["optional"]]
        self.assertEqual(sorted(o.target for o in minimum), sorted(required))

    def test_each_objective_is_ready_with_the_kit_before_it(self):
        owned: set[str] = set()
        flags: set[str] = set()
        for objective in self.objectives:
            self.assertLessEqual(set(objective["abilities"]), owned, objective["target"])
            self.assertLessEqual(set(objective["flags"]), flags, objective["target"])
            if objective["kind"] == "pickup" and not objective["optional"]:
                owned.add(objective["grants"])
            elif objective["kind"] in ("boss", "mini"):
                flags.update(objective["grants"].split(","))
            if objective["kind"] == "boss":
                self.assertLessEqual(graph.BOSS_NEEDS[objective["target"]], owned)
            if objective["kind"] == "mini":
                self.assertLessEqual(graph.MINI_NEEDS, owned)

    def test_hops_descend_from_the_start_to_the_first_pickup(self):
        first = next(o for o in self.objectives if o["kind"] == "pickup")
        self.assertEqual(first["target"], "fringe_02.slipstream")
        field = self.field(first["index"])
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
        """Following the fields from the start reaches every objective in turn; after a fight
        play goes on from the planner's `rest` spot (the arena's return point when the solver
        walks there). The walk passes most of the 48 rooms."""
        position = f"{self.world.start[0]}:{self.world.start[1]}:{self.world.start[2]}:0"
        rooms: set[str] = set()
        for index in range(len(self.objectives)):
            field = self.field(index)
            if index:
                position = self.objectives[index - 1]["rest"]
            position = landed(field, position)
            self.assertTrue(position in field, f"objective {index} unreachable from {position}")
            steps, hop = field[position]
            for _hop in range(400):
                if steps == 0:
                    break
                rooms.update(cell[0] for cell in hop)
                last = hop[-1]
                position = f"{last[0]}:{last[1]}:{last[2]}:{last[3]}"
                if position not in field:
                    break  # the hop ends on the objective's cell in mid-air
                steps, hop = field[position]
            self.assertTrue(steps == 0 or position not in field, f"objective {index} not reached")
        # 39 since round 12: depths_05 to depths_10 lie past depths_01's updraft (RouteSolver).
        self.assertGreaterEqual(len(rooms), 39, sorted(set(self.world.rooms) - rooms))

    def test_route_solver_curls_only_on_a_floor(self):
        solver = RouteSolver(self.world, {"slipstream", "beam"}, set(), set(), breaks=False)
        seen, _edges = solver.explore([(*self.world.start, False, 0, 0)])
        airborne = [s for s in seen if not s[3] and not campaign_route.resting(solver, s)]
        self.assertTrue(airborne)
        for state in airborne[:400]:
            self.assertFalse(any(nxt[3] for nxt in solver.neighbours(state)), state)

    def test_route_solver_never_sinks_in_a_strong_updraft(self):
        # r12-full-s1b hung 1,400 s in the current over depths_01's south opening on a planned
        # drop into depths_05; the game's updraft only ever lifts a body inside it.
        solver = RouteSolver(self.world, {"slipstream", "beam"}, set(), set(), breaks=False)
        state = ("depths_01", 37, 30, False, 0, 0)
        self.assertTrue(solver._lifted(state))
        moves = solver.neighbours(state)
        self.assertTrue(moves)
        self.assertFalse([nxt for nxt in moves if nxt[0] == "depths_01" and nxt[2] > 30])
        self.assertNotIn("depths_05", [o["target"] for o in self.objectives])

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
        compact = jev_request.compact_state(state, {})
        self.assertIn("collect the Slipstream", compact["goal"])
        facts = compact["objective"]
        self.assertEqual(facts["progress"], "0 of 13 objectives done")
        self.assertEqual(facts["route"], "next door south:fringe_02, 1 room change(s) to go")
        self.assertEqual(facts["minutes_on_it"], 1.5)
        self.assertIn("harpoon socket", facts["gate_ahead"])
        for kind in ("go_to_objective", "go_to_door", "open_gate", "freeze", "fast_travel"):
            self.assertIn(kind, jev_request.RUBRIC)
            self.assertIn(kind, jev_feedback.GROUPS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
