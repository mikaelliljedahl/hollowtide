"""Campaign route for the playtest agent's campaign mode (docs/features/playtest-agent.md).

    python3 tools/playtest/campaign_route.py --out <dir>

Plans the progression order with the campaign graph solver (tools/check_campaign_graph.py): from
the start with an empty kit it repeatedly takes the nearest objective the solver can reach with the
kit owned at that moment (a required pickup, a boss, finally the ending), exactly the order in which
the solver's stages unlock the world, but one objective at a time. Intended sequence breaks and
timed doors are left out: they are skilled or optional moves, and the campaign finishes without
them (the graph check's "no-breaks" run).

For every objective it writes a flow field over the solver's movement graph at that point: for each
resting state (feet on a floor or a frozen floater, not mid-jump) the number of solver steps to the
objective and the cells to the next resting state on a shortest path. The agent follows it through
inputs (tools/playtest_nav.gd); the planner only picks the goal. Output: `route.json` (objectives
and their order) and `field_<n>.json` per objective, read by tools/playtest_route.gd.
"""

from __future__ import annotations

import argparse
import heapq
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from campaign_layout import load_rooms  # noqa: E402
from check_campaign_graph import (  # noqa: E402
    BOSS_NEEDS,
    OPTIONAL_KINDS,
    REGIONAL,
    REQUIRED_MISSILE_TANK,
    Solver,
    World,
    covered_cells,
)

FORMAT = 1
# Solver steps a resting state may lie from its next resting state before the path is cut there
# (a long fall is one hop; a hop never needs more).
MAX_HOP_STEPS = 64
# Extra cost per solver step in Slipstream form, per change of form, and per step on a lava basin.
BALL_COST = 3
TOGGLE_COST = 2
LAVA_COST = 20

State = tuple[str, int, int, bool, int, int]


@dataclass
class Objective:
    kind: str  # "pickup", "boss" or "ending"
    target: str  # pickup id, boss id or "ending"
    room: str
    cells: list[tuple[int, int]]
    grants: str  # ability id, flag list or ""
    abilities: list[str] = field(default_factory=list)  # owned when the objective starts
    flags: list[str] = field(default_factory=list)
    steps: int = 0  # solver steps from the previous objective


def required_pickups(world: World) -> dict[str, tuple[str, str, int, int]]:
    """pickup id -> (kind, room, x, y) for pickups the campaign cannot finish without."""
    result = {}
    for (room_id, x, y), (pickup_id, kind) in world.pickups.items():
        if kind in OPTIONAL_KINDS:
            continue
        if kind == "missile_tank" and pickup_id != REQUIRED_MISSILE_TANK:
            continue
        result[pickup_id] = (kind, room_id, x, y)
    return result


def _candidates(world: World, abilities: set[str], flags: set[str], taken: set[str]):
    for pickup_id, (kind, room_id, x, y) in sorted(required_pickups(world).items()):
        if pickup_id not in taken:
            ability = "missiles" if kind == "missile_tank" else kind
            yield Objective("pickup", pickup_id, room_id, [(x, y)], ability)
    for boss, (room_id, (ax, ay, aw, ah)) in sorted(world.bosses.items()):
        flag = f"boss:{boss}"
        if flag in flags or not BOSS_NEEDS[boss] <= abilities:
            continue
        cells = [(x, y) for y in range(ay, ay + ah) for x in range(ax, ax + aw)]
        grants = [flag] + ([f"regional:{boss}"] if boss in REGIONAL else [])
        yield Objective("boss", boss, room_id, cells, ",".join(grants))
    if "boss:tidal_heart" in flags:
        room_id = sorted(world.endings)[0][0]
        cells = sorted((x, y) for room, x, y in world.endings if room == room_id)
        yield Objective("ending", "ending", room_id, cells, "")


def targets(objective: Objective, states) -> set[State]:
    wanted = {(objective.room, x, y) for x, y in objective.cells}
    return {state for state in states if wanted.intersection(covered_cells(state))}


class RouteSolver(Solver):
    """The graph check's solver, minus a move the game does not allow: the player curls into
    Slipstream form only standing on a floor (scripts/player/player.gd, _handle_slip_input)."""

    def neighbours(self, state):
        result = super().neighbours(state)
        if state[3] or resting(self, state):
            return result
        return [nxt for nxt in result if not nxt[3]]


def solver_for(world: World, abilities: set[str], flags: set[str]) -> Solver:
    return RouteSolver(world, set(abilities), set(flags), set(), crumble_gone=True, breaks=False)


def step_cost(solver: Solver, state: State, nxt: State) -> int:
    """Solver steps weighted the way a player moves: Slipstream form only where it is needed (it
    cannot shoot), and never along a lava basin when there is another way."""
    cost = 1
    if nxt[3]:
        cost += BALL_COST
    if nxt[3] != state[3]:
        cost += TOGGLE_COST
    room = solver.world.rooms[nxt[0]]
    if solver.lava(room, nxt[1], nxt[2] + 1) or solver.lava(room, nxt[1], nxt[2]):
        cost += LAVA_COST
    return cost


def forward_distances(solver: Solver, starts: list[State]) -> dict[State, int]:
    distance = {state: 0 for state in starts}
    queue = [(0, state) for state in starts]
    while queue:
        cost, state = heapq.heappop(queue)
        if cost > distance[state]:
            continue
        for nxt in solver.neighbours(state):
            if not solver.inside(nxt):
                continue
            total = cost + step_cost(solver, state, nxt)
            if total < distance.get(nxt, total + 1):
                distance[nxt] = total
                heapq.heappush(queue, (total, nxt))
    return distance


def plan(world: World) -> list[Objective]:
    """Objectives in play order: each time the nearest one the current kit can reach."""
    abilities: set[str] = set()
    flags: set[str] = set()
    taken: set[str] = set()
    start: State = (*world.start, False, 0, 0)
    position = [start]
    order: list[Objective] = []
    while True:
        solver = solver_for(world, abilities, flags)
        distance = forward_distances(solver, position)
        best: tuple[int, Objective, State] | None = None
        for objective in _candidates(world, abilities, flags, taken):
            reached = targets(objective, distance)
            if not reached:
                continue
            state = min(reached, key=lambda s: (distance[s], s))
            if best is None or distance[state] < best[0]:
                best = (distance[state], objective, state)
        if best is None:
            break
        steps, objective, state = best
        objective.abilities = sorted(abilities)
        objective.flags = sorted(flags)
        objective.steps = steps
        order.append(objective)
        if objective.kind == "ending":
            break
        taken.add(objective.target)
        if objective.kind == "pickup":
            abilities.add(objective.grants)
        else:
            flags.update(objective.grants.split(","))
        position = [state]
    return order


def resting(solver: Solver, state: State) -> bool:
    room_id, x, y, _ball, up, side = state
    return up == 0 and side == 0 and solver.platform(solver.world.rooms[room_id], x, y + 1)


def flow_field(world: World, objective: Objective) -> dict[str, list]:
    """'room:x:y:b' -> [steps, hop] for every resting state that can reach the objective, where
    hop is the list of [room, x, y, ball, rising] cells up to the next resting state, which may lie
    in the next room."""
    solver = solver_for(world, set(objective.abilities), set(objective.flags))
    start: State = (*world.start, False, 0, 0)
    seen, edges = solver.explore([start])
    goal = targets(objective, seen)
    distance = {state: 0 for state in goal}
    queue = [(0, state) for state in goal]
    while queue:
        cost, state = heapq.heappop(queue)
        if cost > distance[state]:
            continue
        for previous in edges.get(state, []):
            total = cost + step_cost(solver, previous, state)
            if total < distance.get(previous, total + 1):
                distance[previous] = total
                heapq.heappush(queue, (total, previous))
    result: dict[str, list] = {}
    for state, steps in distance.items():
        if not resting(solver, state):
            continue
        result[key(state)] = [steps, hop(solver, state, distance)]
    return result


def hop(solver: Solver, state: State, distance: dict[State, int]) -> list[list]:
    cells: list[list] = []
    current = state
    for _ in range(MAX_HOP_STEPS):
        if distance[current] == 0:
            break
        here = current
        options = [
            n
            for n in solver.neighbours(here)
            if n in distance and distance[n] + step_cost(solver, here, n) == distance[here]
        ]
        # Deterministic, and prefer staying on the ground over starting a jump when both are
        # shortest.
        current = min(options, key=lambda n: (n[4] > 0 or n[5] > 0, n))
        cells.append([current[0], current[1], current[2], int(current[3]), int(current[4] > 0)])
        if resting(solver, current):
            break
    return cells


def key(state: State) -> str:
    return f"{state[0]}:{state[1]}:{state[2]}:{int(state[3])}"


def build(out: Path) -> dict:
    world = World(load_rooms())
    order = plan(world)
    out.mkdir(parents=True, exist_ok=True)
    objectives = []
    for index, objective in enumerate(order):
        name = f"field_{index}.json"
        field_data = flow_field(world, objective)
        (out / name).write_text(json.dumps(field_data, separators=(",", ":")), encoding="utf-8")
        objectives.append(
            {
                "index": index,
                "kind": objective.kind,
                "target": objective.target,
                "room": objective.room,
                "cells": [list(cell) for cell in objective.cells[:64]],
                "grants": objective.grants,
                "abilities": objective.abilities,
                "flags": objective.flags,
                "steps": objective.steps,
                "field": name,
                "states": len(field_data),
            }
        )
    route = {"format": FORMAT, "start": list(world.start), "objectives": objectives}
    (out / "route.json").write_text(json.dumps(route, indent=1), encoding="utf-8")
    return route


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path, required=True, help="directory for route.json")
    args = parser.parse_args()
    route = build(args.out)
    for objective in route["objectives"]:
        print(
            f"{objective['index']:2d} {objective['kind']:7s} {objective['target']:26s} "
            f"{objective['room']:10s} {objective['steps']:5d} steps, {objective['states']} states"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
