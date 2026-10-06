"""Campaign route for the playtest agent's campaign mode (docs/features/playtest-agent.md).

    python3 tools/playtest/campaign_route.py --out <dir> [--minimum-kit]

Plans the play order with the campaign graph solver (tools/check_campaign_graph.py): from the start
with an empty kit it repeatedly takes the nearest objective the solver can reach with the kit owned
at that moment. The full route is a sweep of the whole world: every required pickup and boss, every
mini-boss (a fight sets `mini:<id>` and opens its reward gate), every optional pickup (Bolt
Quivers, Heart Pearls, the Long Beam, Tide Sockets and Glyphs) and a visit to every room no other
objective's path crosses, with the Tidal Heart and then the ending last. Optional objectives are
`optional`: the agent leaves one behind after its time budget (`seconds`). `--minimum-kit` plans
the required items and bosses only. Intended sequence breaks and timed doors are left out: they are
skilled moves, and the campaign finishes without them (the graph check's "no-breaks" run). What the
route cannot reach is listed in `unreached`.

For every objective it writes a flow field over the solver's movement graph at that point: for each
resting state (feet on a floor or a frozen floater, not mid-jump) the number of solver steps to the
objective and the cells to the next resting state on a shortest path. The agent follows it through
inputs (tools/playtest_nav.gd); the planner only picks the goal. Output: `route.json` (objectives
and their order) and `field_<n>.json` per objective, read by tools/playtest_route.gd. The movement
graph is cached per room across kits (tools/playtest/route_graph.py).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "playtest"))

from campaign_layout import load_rooms  # noqa: E402
from check_campaign_graph import (  # noqa: E402
    BOSS_NEEDS,
    MINI_NEEDS,
    OPTIONAL_KINDS,
    REGIONAL,
    REQUIRED_MISSILE_TANK,
    World,
    covered_cells,
)
from route_graph import UNREACHED, Kit, RouteGraph, resting  # noqa: E402

FORMAT = 1
# Solver steps a resting state may lie from its next resting state before the path is cut there
# (a long fall is one hop; a hop never needs more).
MAX_HOP_STEPS = 64
# The boss whose flag opens the ending; the sweep fights it only when nothing else is left.
FINAL_BOSS = "tidal_heart"
# A room visit is taken on the way when it lies within this many weighted steps, else only once
# no pickup or fight is left.
VISIT_DETOUR = 60
# Game seconds an optional objective gets: a base plus a share per weighted solver step from the
# previous objective, within these bounds; a mini-boss gets the most (walk in plus a ~30 s fight).
OPTIONAL_SECONDS = 60.0
SECONDS_PER_STEP = 0.5
OPTIONAL_MIN_SECONDS = 120.0
OPTIONAL_MAX_SECONDS = 300.0

State = tuple[str, int, int, bool, int, int]


@dataclass
class Objective:
    kind: str  # "pickup", "boss", "mini", "visit" or "ending"
    target: str  # pickup id, boss or mini-boss id, room id (visit) or "ending"
    room: str
    cells: list[tuple[int, int]]
    grants: str  # ability id, flag list or ""
    abilities: list[str] = field(default_factory=list)  # owned when the objective starts
    flags: list[str] = field(default_factory=list)
    steps: int = 0  # weighted solver steps from the previous objective
    optional: bool = False  # not needed to finish
    final: bool = False  # only once nothing else is reachable (the last boss, the ending)
    rest: State | None = None  # where the plan goes on from once it is reached
    path: list[State] = field(default_factory=list)  # the planned states to it


def required_pickups(world: World) -> dict[str, tuple[str, str, int, int]]:
    """pickup id -> (kind, room, x, y) for pickups the campaign cannot finish without."""
    result = {}
    for (room_id, x, y), (pickup_id, kind) in world.pickups.items():
        if not is_optional_pickup(pickup_id, kind):
            result[pickup_id] = (kind, room_id, x, y)
    return result


def is_optional_pickup(pickup_id: str, kind: str) -> bool:
    return kind in OPTIONAL_KINDS or (kind == "missile_tank" and pickup_id != REQUIRED_MISSILE_TANK)


def _arena_cells(rect: tuple[int, int, int, int]) -> list[tuple[int, int]]:
    ax, ay, aw, ah = rect
    return [(x, y) for y in range(ay, ay + ah) for x in range(ax, ax + aw)]


def candidates(
    world: World, abilities: set[str], flags: set[str], taken: set[str], sweep: bool, seen: set[str]
):
    """Objectives not yet taken whose kit is owned (reachability is the search's job); `seen`
    holds the rooms the route has crossed (the ending's room is visited by the ending)."""
    for (room_id, x, y), (pickup_id, kind) in sorted(world.pickups.items()):
        if pickup_id in taken:
            continue
        optional = is_optional_pickup(pickup_id, kind)
        if optional and not sweep:
            continue
        grants = "missiles" if kind == "missile_tank" else kind
        yield Objective("pickup", pickup_id, room_id, [(x, y)], grants, optional=optional)
    for boss, (room_id, arena) in sorted(world.bosses.items()):
        flag = f"boss:{boss}"
        if flag in flags or not BOSS_NEEDS[boss] <= abilities:
            continue
        grants = [flag] + ([f"regional:{boss}"] if boss in REGIONAL else [])
        cells = _arena_cells(arena)
        yield Objective("boss", boss, room_id, cells, ",".join(grants), final=boss == FINAL_BOSS)
    for mini, (room_id, arena) in sorted(world.minis.items()) if sweep else ():
        flag = f"mini:{mini}"
        if flag in flags or mini in taken or not MINI_NEEDS <= abilities:
            continue
        yield Objective("mini", mini, room_id, _arena_cells(arena), flag, optional=True)
    ending_rooms = {room for room, _x, _y in world.endings}
    for room_id, room in sorted(world.rooms.items()) if sweep else ():
        if room_id not in seen and room_id not in taken and room_id not in ending_rooms:
            cells = [(x, y) for y in range(room.height) for x in range(room.width)]
            yield Objective("visit", room_id, room_id, cells, "", optional=True)
    if f"boss:{FINAL_BOSS}" in flags:
        room_id = sorted(world.endings)[0][0]
        cells = sorted((x, y) for room, x, y in world.endings if room == room_id)
        yield Objective("ending", "ending", room_id, cells, "", final=True)


def targets(objective: Objective, states) -> set[State]:
    wanted = {(objective.room, x, y) for x, y in objective.cells}
    return {state for state in states if wanted.intersection(covered_cells(state))}


def _nearest(kit: Kit, position: State, offered: list[Objective]):
    """(steps, objective, path) for the objective to play next, or None: the nearest pickup or
    fight, or a room visit within VISIT_DETOUR; else the nearest visit; else a `final` one."""
    tiers = (
        [o for o in offered if not o.final],
        [o for o in offered if o.kind == "visit"],
        [o for o in offered if o.final],
    )
    for number, tier in enumerate(tiers):
        by_cell: dict[tuple[str, int, int], Objective] = {}
        for objective in tier:
            for x, y in objective.cells:
                by_cell.setdefault((objective.room, x, y), objective)
        found: list[Objective] = []

        def wanted(state: State, steps: int) -> bool:
            for cell in covered_cells(state):
                hit = by_cell.get(cell)
                if hit is not None and (number or hit.kind != "visit" or steps <= VISIT_DETOUR):
                    found.append(hit)
                    return True
            return False

        reached = kit.nearest(position, wanted) if tier else None
        if reached is not None:
            return reached[0], found[-1], reached[1]
    return None


def plan(
    world: World,
    sweep: bool = True,
    graph: RouteGraph | None = None,
    taken_hook: Callable[[int, Objective, Kit, Kit | None], None] | None = None,
) -> list[Objective]:
    """Objectives in play order (see `_nearest`). An optional objective after which nothing is
    reachable is a trap of the solver's (a door it drops through into a sealed notch): it is
    dropped and the plan goes on from before it. `taken_hook(index, objective, kit, base)` runs
    for each objective as it joins the order, with the kit's graph reached from the start and
    `base`, the same kit without the mini-boss flags (None when they change no move).

    A mini-boss fight is optional: the agent may leave it after its time budget, its `mini:` flag
    unset and its reward gate shut. So the flags won there (`won`) open the way for the planner's
    search, but an objective lists them only when it cannot be reached without them (the reward
    behind the gate); every other objective, and every required one, lists boss flags only.
    r10-run1 and run2 timed out on the Tollwing, and every later objective, the required ones
    included, listed `mini:tollwing`: nothing was ready and the run ended as `route_done`."""
    graph = graph or RouteGraph(world)
    start: State = (*world.start, False, 0, 0)
    abilities: set[str] = set()
    flags: set[str] = set()
    won: set[str] = set()
    kits: dict[frozenset[str], Kit] = {}
    taken: set[str] = set()
    position = start
    seen = {position[0]}
    trapped: set[str] = set()
    order: list[Objective] = []
    history: list[tuple] = []
    kit: Kit | None = None
    while True:
        if kit is None or kit.key != graph.moves_key(abilities, flags | won):
            kit = _reached(graph, kits, abilities, flags | won, start)
        searcher = kit
        if position not in kit.index:
            # A frozen floater can shut a spot the previous kit stood on.
            searcher = graph.kit(abilities, flags | won)
            searcher.reach(position)
        offered = list(candidates(world, abilities, flags | won, taken | trapped, sweep, seen))
        best = _nearest(searcher, position, offered)
        if best is None:
            if order and order[-1].optional:
                trapped.add(order.pop().target)
                abilities, flags, won, taken, seen, position = history.pop()
                continue
            break
        steps, objective, path = best
        objective.path = path
        history.append((set(abilities), set(flags), set(won), set(taken), set(seen), position))
        seen.update(state[0] for state in path)
        base = None
        if graph.moves_key(abilities, flags) != kit.key:
            base = _reached(graph, kits, abilities, flags, start)
        # Only the kits in use stay (each holds the whole world's states).
        for stale in set(kits) - {kit.key, base.key if base else kit.key}:
            del kits[stale]
        objective.abilities = sorted(abilities)
        needs_won = base is not None and not base.covering(objective.room, set(objective.cells))
        objective.flags = sorted(flags | won if needs_won else flags)
        objective.steps = steps
        order.append(objective)
        if taken_hook is not None:
            taken_hook(len(order) - 1, objective, kit, base)
        if objective.kind == "ending":
            break
        taken.add(objective.target)
        position = path[-1]
        if objective.kind == "boss":
            flags.update(objective.grants.split(","))
            position = _after_fight(world, searcher, objective, position)
        elif objective.kind == "mini":
            won.add(objective.grants)
            position = _after_fight(world, searcher, objective, position)
        elif not objective.optional:
            abilities.add(objective.grants)
        # A pickup grabbed in a jump or a room entered mid-air: go on from where she lands.
        landing = searcher.nearest(position, lambda state, _steps: resting(searcher.solver, state))
        if landing is not None:
            position = landing[1][-1]
        objective.rest = position
    return order


def _reached(
    graph: RouteGraph, kits: dict[frozenset[str], Kit], abilities: set[str], flags: set[str], start
) -> Kit:
    """The kit for `abilities` and `flags`, reached from `start`, built once per moves key."""
    found = kits.get(graph.moves_key(abilities, flags))
    if found is None:
        found = kits[graph.moves_key(abilities, flags)] = graph.kit(abilities, flags)
        found.reach(start)
    return found


def _after_fight(world: World, kit: Kit, objective: Objective, entered: State) -> State:
    """Where the next objective starts after a fight: the arena's return point (where the game
    puts the checkpoint), standing, when the solver gets there from where she entered; else that
    entry (the first arena cell is often the door, in mid-air)."""
    room = world.rooms[objective.room]
    for entry in room.legend.values():
        if entry.kind in ("boss", "miniboss") and entry.args[0] == objective.target:
            spot = entry.options.get("return")
            if spot is None:
                break
            x, y = (int(part) for part in spot.split(","))
            state: State = (objective.room, x, y, False, 0, 0)
            if kit.nearest(entered, lambda reached, _steps: reached == state):
                return state
    return entered


def unreached(world: World, order: list[Objective], sweep: bool) -> list[str]:
    """Pickups, mini-bosses (`mini:<id>`) and rooms (`room:<id>`) the sweep never takes or
    crosses."""
    if not sweep:
        return []
    taken = {objective.target for objective in order}
    missing = [pickup_id for pickup_id, _kind in world.pickups.values() if pickup_id not in taken]
    missing += [f"mini:{mini}" for mini in world.minis if mini not in taken]
    crossed = {objective.room for objective in order}
    for objective in order:
        crossed.update(state[0] for state in objective.path)
    missing += [f"room:{room}" for room in world.rooms if room not in crossed]
    return sorted(missing)


def flow_field(kit: Kit, objective: Objective, known: dict | None = None) -> dict[str, list]:
    """'room:x:y:b' -> [steps, hop] for every resting state that can reach the objective, where
    hop is the list of [room, x, y, ball, rising] cells up to the next resting state, which may lie
    in the next room. `kit` is reached from the start. Entries already in `known` are kept as
    they are."""
    states = kit.states
    distance = kit.distances_to(kit.covering(objective.room, set(objective.cells)))
    result: dict[str, list] = dict(known or {})
    for number, steps in enumerate(distance):
        if steps != UNREACHED and kit.rest[number]:
            name = key(states[number])
            if name not in result:
                result[name] = [steps, hop(kit, number, distance)]
    return result


def hop(kit: Kit, number: int, distance: list[int]) -> list[list]:
    states = kit.states
    cells: list[list] = []
    here = number
    for _ in range(MAX_HOP_STEPS):
        if distance[here] == 0:
            break
        options = [
            after for after, cost in kit.moves(here) if distance[after] + cost == distance[here]
        ]
        # Deterministic, and prefer staying on the ground over starting a jump when both are
        # shortest.
        here = min(options, key=lambda n: (states[n][4] > 0 or states[n][5] > 0, states[n]))
        state = states[here]
        cells.append([state[0], state[1], state[2], int(state[3]), int(state[4] > 0)])
        if kit.rest[here]:
            break
    return cells


def key(state: State) -> str:
    return f"{state[0]}:{state[1]}:{state[2]}:{int(state[3])}"


def seconds_for(objective: Objective) -> float | None:
    """Time budget of an optional objective (None: the agent's default for required ones)."""
    if not objective.optional:
        return None
    if objective.kind == "mini":
        return OPTIONAL_MAX_SECONDS
    budget = OPTIONAL_SECONDS + objective.steps * SECONDS_PER_STEP
    return min(max(budget, OPTIONAL_MIN_SECONDS), OPTIONAL_MAX_SECONDS)


def build(out: Path, sweep: bool = True) -> dict:
    world = World(load_rooms())
    out.mkdir(parents=True, exist_ok=True)
    fields: dict[int, int] = {}

    def write_field(index: int, objective: Objective, kit: Kit, base: Kit | None) -> None:
        # A trap the plan backs out of is overwritten by the objective that takes its place.
        # Where the way on needs no mini-boss flag, follow that way: a reward gate the live run
        # left shut is never on it. Spots only an open gate leads to take the full kit's way.
        data = flow_field(kit, objective, flow_field(base, objective) if base else None)
        text = json.dumps(data, separators=(",", ":"))
        (out / f"field_{index}.json").write_text(text, encoding="utf-8")
        fields[index] = len(data)

    order = plan(world, sweep, RouteGraph(world), write_field)
    objectives = []
    for index, objective in enumerate(order):
        entry = {
            "index": index,
            "kind": objective.kind,
            "target": objective.target,
            "room": objective.room,
            "cells": [list(cell) for cell in objective.cells],
            "grants": objective.grants,
            "abilities": objective.abilities,
            "flags": objective.flags,
            "steps": objective.steps,
            "optional": objective.optional,
            "field": f"field_{index}.json",
            "states": fields[index],
            "rest": key(objective.rest) if objective.rest else None,
        }
        budget = seconds_for(objective)
        if budget is not None:
            entry["seconds"] = budget
        objectives.append(entry)
    for stale in out.glob("field_*.json"):
        if int(stale.stem.split("_")[1]) >= len(order):
            stale.unlink()
    route = {
        "format": FORMAT,
        "start": list(world.start),
        "objectives": objectives,
        "unreached": unreached(world, order, sweep),
    }
    (out / "route.json").write_text(json.dumps(route, indent=1), encoding="utf-8")
    return route


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", type=Path, required=True, help="directory for route.json")
    parser.add_argument("--minimum-kit", action="store_true", help="required items only")
    args = parser.parse_args()
    began = time.monotonic()
    route = build(args.out, not args.minimum_kit)
    for objective in route["objectives"]:
        print(
            f"{objective['index']:2d} {objective['kind']:7s} {objective['target']:26s} "
            f"{objective['room']:10s} {objective['steps']:5d} steps, {objective['states']} states"
        )
    if route["unreached"]:
        print(f"unreached: {', '.join(route['unreached'])}")
    print(f"{len(route['objectives'])} objectives in {time.monotonic() - began:.1f} s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
