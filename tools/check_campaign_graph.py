"""Validates the campaign room graph and proves progression without softlocks.

    python3 tools/check_campaign_graph.py [--verbose]

Checks: layouts parse, rooms do not overlap, every boundary opening has an exactly mirrored
opening in the neighbouring room, pickup IDs are unique, generated scenes are up to date, every
boss room has a guaranteed missile refill, and a cell-level movement solver can finish the
campaign (vaults-first, kiln-first, and without optional tanks/Long Beam). The solver also proves
that every position reachable at every progression stage can still walk back to a save shrine
with the abilities owned at that moment (no softlocks, including entering rooms too early).
Each branch boss room must hold a shortcut back to the hub: a flag gate on that boss's flag at a
door into a hub room, sealed before the fight and walkable once the boss is down.
Intended sequence breaks (tools/campaign_breaks.py) join the solver as explicit edges; the campaign
must also finish without them, and their reward pickups may only be reachable through them.

Movement model (deliberately conservative versus the real player): standing body is 1x3 cells,
ball 1x1, jumps rise 3 cells (High Jump 5) with at most 3 cells of sideways drift while rising,
falling drifts one cell per row, wall jumps only in chimneys (a second wall within 3 cells).

Living environment (D21), modelled conservatively: crushers are solid at rest (their column is
passable on the rhythm); crumble tiles carry the player but can also drop her through (permanent ones
count as already gone, with a second softlock pass where they are still present); a timed door is
solid until a reachable standing spot can shoot one of its switches and then reach the door within
its countdown (about five cells per second), after which it stays open (it latches in game); strong
updrafts (strength >= 500) let the body climb, downward currents cap jumps to one cell. Stalactites,
floods and ambush arenas never block movement (an arena only seals when the wave can be beaten).
"""

from __future__ import annotations

import sys
from collections import deque

sys.path.insert(0, __file__.rsplit("/", 1)[0])

from campaign_breaks import break_edges, break_errors  # noqa: E402
from campaign_layout import (  # noqa: E402
    LayoutError,
    Room,
    link_doors,
    load_rooms,
    overlap_errors,
    room_at_world,
)
from campaign_shortcuts import shortcut_errors  # noqa: E402

JUMP = 3
HIGH_JUMP = 5
BALL_JUMP = 3
SIDE = 3
NORTH_ENTRY_RISE = 3
CHIMNEY = 3
BOSS_NEEDS = {
    "stone_guardian": {"missiles"},
    "furnace_mother": {"missiles"},
    "tidal_heart": {"missiles", "ice_beam", "wave_beam"},
}
REGIONAL = {"stone_guardian", "furnace_mother"}
GATE_NEEDS = {
    "missile": "missiles",
    "bomb": "bombs",
    "wave": "wave_beam",
    "undertow": "undertow_dash",
}
# Tide Sockets and Glyphs are optional loadout rewards and never open a route.
TIDE_KINDS = {"tide_socket"} | {
    f"glyph_{glyph}"
    for glyph in (
        "quickstring",
        "farcast",
        "heavy_barb",
        "brine_hide",
        "ebb_mend",
        "deep_pulse",
        "spring_tide",
    )
}
OPTIONAL_KINDS = {"energy_tank", "long_beam", *TIDE_KINDS}
RACE_CELLS_PER_SECOND = 5
SWITCH_RANGE = 14
UPDRAFT_STRENGTH = 500
REQUIRED_MISSILE_TANK = "fringe_03.missile_01"


class World:
    def __init__(self, rooms: dict[str, Room]) -> None:
        self.rooms = rooms
        self.pickups: dict[tuple[str, int, int], tuple[str, str]] = {}
        self.saves: set[tuple[str, int, int]] = set()
        self.refills: dict[str, int] = {}
        self.bosses: dict[str, tuple[str, tuple[int, int, int, int]]] = {}
        self.endings: set[tuple[str, int, int]] = set()
        self.floaters: dict[str, set[tuple[int, int]]] = {}
        self.heat: dict[str, set[tuple[int, int]]] = {}
        self.start: tuple[str, int, int] | None = None
        # D21: timed doors keyed by (room, char); updraft/downdraft cells per room.
        self.timed: dict[tuple[str, str], dict] = {}
        self.updraft: dict[str, set[tuple[int, int]]] = {}
        self.downdraft: dict[str, set[tuple[int, int]]] = {}
        self.permanent_crumbles = False
        self.breaks = break_edges()
        for room in rooms.values():
            self.updraft[room.room_id] = set()
            self.downdraft[room.room_id] = set()
            for zone in room.currents:
                zx, zy, zw, zh = zone["rect"]
                direction = zone["options"]["dir"]
                strength = float(zone["options"].get("strength", 260))
                target = None
                if direction == "up" and strength >= UPDRAFT_STRENGTH:
                    target = self.updraft[room.room_id]
                elif direction == "down":
                    target = self.downdraft[room.room_id]
                if target is not None:
                    target.update((x, y) for x in range(zx, zx + zw) for y in range(zy, zy + zh))
            for char, entry in room.legend.items():
                if entry.kind == "timeddoor":
                    switches = set()
                    for other_char, other in room.legend.items():
                        if other.kind == "switch" and other.options.get("door") == char:
                            switches.update(room.cells_of(other_char))
                    self.timed[(room.room_id, char)] = {
                        "cells": set(room.cells_of(char)),
                        "switches": switches,
                        "seconds": float(entry.options.get("seconds", 6)),
                    }
                elif entry.kind == "crumble" and "permanent" in entry.args:
                    self.permanent_crumbles = True
            self.floaters[room.room_id] = set()
            self.heat[room.room_id] = set()
            for hx, hy, hw, hh in room.heat:
                for y in range(hy, hy + hh):
                    for x in range(hx, hx + hw):
                        self.heat[room.room_id].add((x, y))
            for char, entry in room.legend.items():
                cells = room.cells_of(char)
                if entry.kind == "pickup":
                    x, y = cells[0]
                    self.pickups[(room.room_id, x, y)] = (
                        f"{room.room_id}.{entry.args[1]}",
                        entry.args[0],
                    )
                elif entry.kind == "save":
                    for x, y in cells:
                        self.saves.add((room.room_id, x, y))
                elif entry.kind in ("refill", "missilerefill"):
                    self.refills[room.room_id] = self.refills.get(room.room_id, 0) + len(cells)
                elif entry.kind == "boss":
                    ax, ay, aw, ah = (int(part) for part in entry.options["arena"].split(","))
                    self.bosses[entry.args[0]] = (room.room_id, (ax, ay, aw, ah))
                elif entry.kind == "ending":
                    for x, y in cells:
                        self.endings.add((room.room_id, x, y))
                elif entry.kind == "floater":
                    self.floaters[room.room_id].update(cells)
                elif entry.kind == "start":
                    self.start = (room.room_id, cells[0][0], cells[0][1])


class Solver:
    def __init__(
        self,
        world: World,
        abilities: set[str],
        flags: set[str],
        blocked_areas: set[str],
        crumble_gone: bool = True,
        breaks: bool = True,
    ) -> None:
        self.world = world
        self.breaks = world.breaks if breaks else {}
        self.abilities = abilities
        self.flags = flags
        self.blocked_areas = blocked_areas
        self.crumble_gone = crumble_gone
        self.jump = HIGH_JUMP if "high_jump" in abilities else JUMP

    # --- terrain ---------------------------------------------------------------------------
    def solid(self, room: Room, x: int, y: int) -> bool:
        x = min(max(x, 0), room.width - 1)
        y = min(max(y, 0), room.height - 1)
        char = room.grid[y][x]
        if char == "#":
            return True
        entry = room.legend.get(char)
        if entry is None:
            return False
        if entry.kind == "gate":
            return GATE_NEEDS[entry.args[0]] not in self.abilities
        if entry.kind == "flaggate":
            return not all(flag in self.flags for flag in entry.args[0].split(","))
        if entry.kind == "timeddoor":
            return timed_flag(room.room_id, char) not in self.flags
        if entry.kind == "crusher":
            return True
        if entry.kind == "crumble":
            return not ("permanent" in entry.args and self.crumble_gone)
        return False

    def crumble(self, room: Room, x: int, y: int) -> bool:
        entry = room.entry(x, y)
        return entry is not None and entry.kind == "crumble" and self.solid(room, x, y)

    def lava(self, room: Room, x: int, y: int) -> bool:
        entry = room.entry(x, y)
        return entry is not None and entry.kind == "lava"

    def platform(self, room: Room, x: int, y: int) -> bool:
        """Solid for standing on (includes frozen floaters)."""
        if self.solid(room, x, y):
            return True
        return "ice_beam" in self.abilities and (x, y) in self.world.floaters[room.room_id]

    def hot(self, room: Room, x: int, y: int) -> bool:
        return "pressure_seal" not in self.abilities and (x, y) in self.world.heat[room.room_id]

    def body_clear(self, room: Room, x: int, y: int, ball: bool) -> bool:
        rows = (y,) if ball else (y, y - 1, y - 2)
        for row in rows:
            if self.solid(room, x, row) or self.hot(room, x, row):
                return False
            if row != y and self.lava(room, x, row):
                return False
            if not ball and row != y and (x, row) in self.world.floaters[room.room_id]:
                if "ice_beam" in self.abilities:
                    return False
        return True

    def wall(self, room: Room, x: int, torso: int) -> bool:
        """A wall the torso ray can hold: at least two rock cells tall around the torso."""
        return self.solid(room, x, torso) and (
            self.solid(room, x, torso - 1) or self.solid(room, x, torso + 1)
        )

    def chimney(self, room: Room, x: int, y: int) -> bool:
        torso = y - 1
        if self.wall(room, x - 1, torso):
            return any(self.wall(room, x + k, torso) for k in range(1, CHIMNEY + 1))
        if self.wall(room, x + 1, torso):
            return any(self.wall(room, x - k, torso) for k in range(1, CHIMNEY + 1))
        return False

    # --- movement graph ----------------------------------------------------------------------
    def neighbours(self, state):
        room_id, x, y, ball, up, side = state
        room = self.world.rooms[room_id]
        result = []
        exit_state = self.exit(state)
        if exit_state is not None and exit_state != "blocked":
            return [exit_state]
        supported = self.platform(room, x, y + 1)
        jump = BALL_JUMP if ball else self.jump
        rows = (y,) if ball else (y, y - 1, y - 2)
        if any((x, row) in self.world.downdraft[room_id] for row in rows):
            jump = min(jump, 1)
        if any((x, row) in self.world.updraft[room_id] for row in rows):
            # Strong updraft: the body can climb and drift sideways inside the column.
            if self.body_clear(room, x, y - 1, ball):
                result.append((room_id, x, y - 1, ball, 0, 0))
            for dx in (-1, 1):
                if self.body_clear(room, x + dx, y, ball):
                    result.append((room_id, x + dx, y, ball, 0, 0))
        if supported and self.crumble(room, x, y + 1) and up == 0 and side == 0:
            # The tile gives way: drop to the first spot fully below it.
            below = y + (2 if ball else 4)
            if self.body_clear(room, x, below, ball):
                result.append((room_id, x, below, ball, 0, 0))
        if up > 0 or side > 0:
            if up > 0 and self.body_clear(room, x, y - 1, ball):
                result.append((room_id, x, y - 1, ball, up - 1, side))
            if side > 0:
                for dx in (-1, 1):
                    if self.body_clear(room, x + dx, y, ball):
                        result.append((room_id, x + dx, y, ball, up, side - 1))
            result.append((room_id, x, y, ball, 0, 0))
        elif supported or self.lava(room, x, y + 1):
            # Standing in a lava basin burns but still allows jumping out (no walking along it).
            result.append((room_id, x, y, ball, jump, SIDE))
            if not supported:
                return result
            if not ball:
                for ex, ey, needs in self.breaks.get((room_id, x, y), ()):
                    if needs <= self.abilities:
                        result.append((room_id, ex, ey, False, 0, 0))
            for dx in (-1, 1):
                if self.body_clear(room, x + dx, y, ball):
                    result.append((room_id, x + dx, y, ball, 0, 0))
        else:
            if self.body_clear(room, x, y + 1, ball):
                result.append((room_id, x, y + 1, ball, 0, 0))
            for dx in (-1, 1):
                if self.body_clear(room, x + dx, y, ball) and self.body_clear(
                    room, x + dx, y + 1, ball
                ):
                    result.append((room_id, x + dx, y + 1, ball, 0, 0))
            if not ball and self.chimney(room, x, y):
                result.append((room_id, x, y, ball, self.jump, SIDE))
        if ball:
            if self.body_clear(room, x, y, False):
                result.append((room_id, x, y, False, 0 if up == 0 else up, side))
        elif "slipstream" in self.abilities:
            result.append((room_id, x, y, True, 0 if up == 0 else min(up, BALL_JUMP), side))
        return result

    def exit(self, state):
        room_id, x, y, ball, up, side = state
        room = self.world.rooms[room_id]
        edge = None
        if x == 0:
            edge = (-1, 0)
        elif x == room.width - 1:
            edge = (1, 0)
        elif y == 0:
            edge = (0, -1)
        elif y == room.height - 1 and up == 0:
            edge = (0, 1)
        if edge is None:
            return None
        wx = room.origin[0] + x + edge[0]
        wy = room.origin[1] + y + edge[1]
        target = room_at_world(self.world.rooms, wx, wy)
        if target is None or target.area in self.blocked_areas:
            return "blocked"
        tx, ty = wx - target.origin[0], wy - target.origin[1]
        if edge == (-1, 0):
            tx = target.width - 2
        elif edge == (1, 0):
            tx = 1
        elif edge == (0, 1):
            ty = 3
        else:
            ty = target.height - 1
            up, side = NORTH_ENTRY_RISE, SIDE
        if not self.body_clear(target, tx, ty, ball):
            return "blocked"
        return (target.room_id, tx, ty, ball, up, side)

    def inside(self, state) -> bool:
        room = self.world.rooms[state[0]]
        return 0 <= state[1] < room.width and 0 <= state[2] < room.height

    def explore(self, starts):
        seen = set(starts)
        queue = deque(starts)
        edges: dict = {}
        while queue:
            state = queue.popleft()
            for nxt in self.neighbours(state):
                if not self.inside(nxt):
                    continue
                edges.setdefault(nxt, []).append(state)
                if nxt not in seen:
                    seen.add(nxt)
                    queue.append(nxt)
        return seen, edges


def timed_flag(room_id: str, char: str) -> str:
    return f"timed:{room_id}:{char}"


def _clear_line(solver: Solver, room: Room, cells: list[tuple[int, int]]) -> bool:
    return all(not solver.solid(room, x, y) for x, y in cells)


def can_shoot(solver: Solver, state, switch: tuple[int, int]) -> bool:
    """Standing (not ball) state with a clear straight shot at the switch cell."""
    room_id, x, y, ball, _up, _side = state
    if ball:
        return False
    room = solver.world.rooms[room_id]
    sx, sy = switch
    if sy in (y - 1, y - 2) and 0 < abs(sx - x) <= SWITCH_RANGE:
        step = 1 if sx > x else -1
        return _clear_line(solver, room, [(cx, sy) for cx in range(x + step, sx, step)])
    if sx == x and y - 2 > sy >= y - 2 - SWITCH_RANGE:
        return _clear_line(solver, room, [(x, cy) for cy in range(sy + 1, y - 2)])
    return False


def race_reaches(solver: Solver, starts, door: set[tuple[int, int]], budget: int) -> bool:
    """Forward BFS limited to `budget` moves from the shooting spots to a cell touching the door."""
    frontier = deque((state, 0) for state in starts)
    seen = set(starts)
    while frontier:
        state, steps = frontier.popleft()
        for _room, cx, cy in covered_cells(state):
            for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                if (nx, ny) in door:
                    return True
        if steps >= budget:
            continue
        for nxt in solver.neighbours(state):
            if nxt not in seen and solver.inside(nxt) and nxt[0] == state[0]:
                seen.add(nxt)
                frontier.append((nxt, steps + 1))
    return False


def open_timed_doors(world: World, solver: Solver, seen, flags: set[str]) -> bool:
    changed = False
    for (room_id, char), door in world.timed.items():
        flag = timed_flag(room_id, char)
        if flag in flags:
            continue
        shooters = [
            state
            for state in seen
            if state[0] == room_id and any(can_shoot(solver, state, sw) for sw in door["switches"])
        ]
        budget = int(door["seconds"] * RACE_CELLS_PER_SECOND)
        if shooters and race_reaches(solver, shooters, door["cells"], budget):
            flags.add(flag)
            changed = True
    return changed


def covered_cells(state) -> list[tuple[str, int, int]]:
    room_id, x, y, ball, _up, _side = state
    rows = (y,) if ball else (y, y - 1, y - 2)
    return [(room_id, x, row) for row in rows]


def progress(
    world: World,
    blocked_until: dict[str, str],
    skip_optional: bool,
    label: str,
    crumble_gone: bool = True,
    breaks: bool = True,
):
    """Runs progression to a fixpoint. Returns (errors, stages)."""
    abilities: set[str] = set()
    flags: set[str] = set()
    collected: set[str] = set()
    start_room, sx, sy = world.start
    start = (start_room, sx, sy, False, 0, 0)
    errors: list[str] = []
    stages = []
    for _ in range(64):
        blocked = {area for area, flag in blocked_until.items() if flag not in flags}
        solver = Solver(world, abilities, flags, blocked, crumble_gone, breaks)
        seen, edges = solver.explore([start])
        stages.append((set(abilities), set(flags), blocked, seen, edges, solver))
        changed = open_timed_doors(world, solver, seen, flags)
        cells = set()
        for state in seen:
            cells.update(covered_cells(state))
        for key, (pickup_id, kind) in sorted(world.pickups.items()):
            if key not in cells or pickup_id in collected:
                continue
            if skip_optional and (
                kind in OPTIONAL_KINDS
                or (kind == "missile_tank" and pickup_id != REQUIRED_MISSILE_TANK)
            ):
                continue
            collected.add(pickup_id)
            ability = "missiles" if kind == "missile_tank" else kind
            if kind != "energy_tank" and kind not in TIDE_KINDS and ability not in abilities:
                abilities.add(ability)
                changed = True
        for boss, (room_id, (ax, ay, aw, ah)) in world.bosses.items():
            flag = f"boss:{boss}"
            if flag in flags or not BOSS_NEEDS[boss] <= abilities:
                continue
            inside = any(
                room == room_id and ax <= x < ax + aw and ay <= y < ay + ah for room, x, y in cells
            )
            if inside:
                flags.add(flag)
                if boss in REGIONAL:
                    flags.add(f"regional:{boss}")
                changed = True
        if not changed:
            break
    finished = "boss:tidal_heart" in flags and any(cell in world.endings for cell in cells)
    if not finished:
        errors.append(
            f"[{label}] campaign not completable: abilities={sorted(abilities)} flags={sorted(flags)}"
        )
    return errors, stages, collected


def softlock_errors(world: World, stages, label: str) -> list[str]:
    errors = []
    for abilities, flags, _blocked, seen, edges, solver in stages:
        safe = {
            state
            for state in seen
            if (state[0], state[1], state[2]) in world.saves and not state[3]
        }
        if world.start is not None:
            safe.update(
                state
                for state in seen
                if (state[0], state[1], state[2]) == world.start and not state[3]
            )
        back = set(safe)
        queue = deque(safe)
        while queue:
            state = queue.popleft()
            for previous in edges.get(state, []):
                if previous not in back:
                    back.add(previous)
                    queue.append(previous)
        stuck = [state for state in seen if state not in back]
        if stuck:
            sample = sorted(stuck)[:4]
            by_room: dict[str, int] = {}
            for state in stuck:
                by_room[state[0]] = by_room.get(state[0], 0) + 1
            errors.append(
                f"[{label}] softlock with abilities={sorted(abilities)}: "
                f"{len(stuck)} states cannot return to a save ({by_room}); e.g. {sample}"
            )
    return errors


def static_errors(rooms: dict[str, Room]) -> list[str]:
    errors = overlap_errors(rooms)
    doors, door_errors = link_doors(rooms)
    errors += door_errors
    for door in doors:
        if door.target is None or door.edge in ("north", "south"):
            continue
        target = rooms[door.target]
        room = rooms[door.room]
        entry_x = target.width - 2 if door.edge == "west" else 1
        for _x, y in door.cells:
            ty = room.origin[1] + y - target.origin[1]
            if target.char(entry_x, ty) != "." and target.entry(entry_x, ty) is not None:
                if target.entry(entry_x, ty).kind in ("gate", "flaggate", "lava"):
                    errors.append(
                        f"{door.room} {door.edge} door lands on a gate/lava in {door.target} "
                        f"at {entry_x},{ty}; keep two clear cells inside every door"
                    )
                    break
    seen_ids: dict[str, str] = {}
    for room in rooms.values():
        for char, entry in room.legend.items():
            if entry.kind != "pickup":
                continue
            pickup_id = f"{room.room_id}.{entry.args[1]}"
            if pickup_id in seen_ids:
                errors.append(f"duplicate pickup id {pickup_id}")
            seen_ids[pickup_id] = room.room_id
        has_boss = any(entry.kind == "boss" for entry in room.legend.values())
        has_refill = any(
            entry.kind in ("refill", "missilerefill") for entry in room.legend.values()
        )
        if has_boss and not has_refill:
            errors.append(f"{room.room_id}: boss room without guaranteed missile refill")
    areas_with_save = {
        room.area
        for room in rooms.values()
        if any(entry.kind == "save" for entry in room.legend.values())
    }
    for room in rooms.values():
        if room.area not in areas_with_save:
            errors.append(f"area {room.area} has no save shrine")
    return errors


def generated_errors(rooms: dict[str, Room]) -> list[str]:
    import build_campaign_rooms as builder

    errors = []
    doors, _ = link_doors(rooms)
    for room in rooms.values():
        path = builder.ROOM_DIR / f"{room.room_id}.tscn"
        expected = builder.SceneWriter(room).build({})
        if not path.exists() or path.read_text() != expected:
            errors.append(f"{path.name} is stale; run python3 tools/build_campaign_rooms.py")
    return errors


def show_reach(world: World, stages, room_id: str) -> None:
    """Prints a room with feet cells reached in the final stage ('o') for layout debugging."""
    _abilities, _flags, _blocked, seen, _edges, _solver = stages[-1]
    room = world.rooms[room_id]
    feet = {(state[1], state[2]) for state in seen if state[0] == room_id}
    for y, row in enumerate(room.grid):
        print(
            "".join("o" if (x, y) in feet and char == "." else char for x, char in enumerate(row))
        )


def main() -> int:
    verbose = "--verbose" in sys.argv
    show = [argument.split("=", 1)[1] for argument in sys.argv if argument.startswith("--show=")]
    try:
        rooms = load_rooms()
    except LayoutError as error:
        print(f"campaign-graph: FAIL layout: {error}")
        return 1
    errors = static_errors(rooms)
    errors += generated_errors(rooms)
    world = World(rooms)
    if world.start is None:
        errors.append("no start marker")
    if errors:
        for error in errors:
            print(f"campaign-graph: {error}")
        print("campaign-graph: FAIL")
        return 1
    runs = [
        ("any-order", {}, False),
        ("vaults-first", {"kiln": "regional:stone_guardian"}, False),
        ("kiln-first", {"vaults": "regional:furnace_mother"}, False),
        ("no-optional", {}, True),
        ("no-breaks", {}, False),
    ]
    if world.permanent_crumbles:
        runs.append(("permanent-crumbles-present", {}, False))
    all_pickups = {pickup_id for pickup_id, _kind in world.pickups.values()}
    tide_pickups = {pickup_id for pickup_id, kind in world.pickups.values() if kind in TIDE_KINDS}
    every_ability = {
        "missiles" if kind == "missile_tank" else kind for _id, kind in world.pickups.values()
    }
    errors += break_errors(world, Solver, every_ability - {"energy_tank"}, covered_cells)
    for label, blocked_until, skip_optional in runs:
        run_errors, stages, collected = progress(
            world,
            blocked_until,
            skip_optional,
            label,
            label != "permanent-crumbles-present",
            label != "no-breaks",
        )
        errors += run_errors
        errors += softlock_errors(world, stages, label)
        errors += shortcut_errors(world, stages, label, REGIONAL, covered_cells)
        if label == "any-order":
            missing = sorted(all_pickups - collected)
            if missing:
                errors.append(f"[{label}] unreachable pickups: {missing}")
        if label == "no-breaks":
            break_only = sorted(tide_pickups - collected)
            if break_only:
                errors.append(
                    f"[{label}] Tide pickups reachable only through a break: {break_only}"
                )
        if label == "any-order":
            for room_id in show:
                show_reach(world, stages, room_id)
        if verbose:
            final = stages[-1]
            print(
                f"campaign-graph: {label}: {len(stages)} stages, abilities={sorted(final[0])}, "
                f"flags={sorted(final[1])}, pickups={len(collected)}"
            )
    for error in errors:
        print(f"campaign-graph: {error}")
    if errors:
        print("campaign-graph: FAIL")
        return 1
    print(
        f"campaign-graph: PASS ({len(rooms)} rooms, {len(world.pickups)} pickups, "
        f"both branch orders, boss shortcuts, {len(world.breaks)} break starts, no softlocks)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
