"""Updraft hold for the campaign graph solver (tools/check_campaign_graph.py).

The game's upward current (scripts/world/dynamic/push_current.gd) pulls her vertical speed toward
its rise speed by UPDRAFT_ACCEL every physics frame, while gravity pulls her down by
GRAVITY_FALLING (scripts/player/player_config.gd). Falling, the two net to a brake of
UPDRAFT_ACCEL - GRAVITY_FALLING whatever the current's strength (the strength only sets how fast she
rises once stopped; a probe in depths_05 measured 558 px/s^2 against 560 here). So a body that
steps, hops or rises into a current never sinks in it (the solver drops every downward move of a
body touching one), and a body falling in from above sinks on only as far as its entry speed
carries it: v^2 >= 2 * brake * travel, where travel ends when the body is out of the bottom of the
column or stands on rock inside it. `plunge` gives that move as one edge from a falling body still
clear above the current, counting her speed from rest at that height (capped at TERMINAL_VELOCITY).

Round 12: depths_01's south opening sat two rows under rock with the current filling it; the
solver let a body fall through, while in the game she hung there and depths_05 to depths_10 could
not be entered that way (only by a long drop from vaults_10's upper ledges into depths_07). So
`drop_errors` also asks that every floor opening of a reached room can be dropped through, unless
it is listed in ONE_WAY_UP.
"""

from __future__ import annotations

import re
from collections.abc import Callable

from campaign_layout import ROOT, Room, link_doors

TILE = 64
# Floor openings meant to be climbed only, (upper room, lower room): reason.
ONE_WAY_UP = {
    ("fringe_01", "vaults_08"): "its timed door is opened from below",
}


def _game_constant(path: str, name: str) -> float:
    """Read a numeric `const` from a game script so the model follows the game's tuning."""
    text = (ROOT / path).read_text()
    found = re.search(rf"const {name}\b[^=]*=\s*([0-9.]+)", text)
    if found is None:
        raise ValueError(f"{path}: no const {name}")
    return float(found.group(1))


UPDRAFT_ACCEL = _game_constant("scripts/world/dynamic/push_current.gd", "UPDRAFT_ACCEL")
GRAVITY_FALLING = _game_constant("scripts/player/player_config.gd", "GRAVITY_FALLING")
TERMINAL_VELOCITY = _game_constant("scripts/player/player_config.gd", "TERMINAL_VELOCITY")
STANDING_HEIGHT = _game_constant("scripts/player/player_config.gd", "STANDING_HEIGHT")
BALL_HEIGHT = _game_constant("scripts/player/player_config.gd", "BALL_HEIGHT")


def up_cells(rooms: dict[str, Room]) -> set[tuple[int, int]]:
    """World cells covered by an upward current of any strength."""
    cells = set()
    for room in rooms.values():
        ox, oy = room.origin
        for zone in room.currents:
            if zone["options"]["dir"] != "up":
                continue
            zx, zy, zw, zh = zone["rect"]
            cells.update((ox + x, oy + y) for x in range(zx, zx + zw) for y in range(zy, zy + zh))
    return cells


def up_runs(cells: set[tuple[int, int]]) -> dict[int, list[tuple[int, int]]]:
    """Per world column, its runs of upward current as (top row, bottom row), top to bottom."""
    runs: dict[int, list[tuple[int, int]]] = {}
    for wx, wy in sorted(cells):
        if (wx, wy - 1) in cells:
            continue
        bottom = wy
        while (wx, bottom + 1) in cells:
            bottom += 1
        runs.setdefault(wx, []).append((wy, bottom))
    return runs


def plunge(
    runs: dict[int, list[tuple[int, int]]],
    blocked: Callable[[int, int], bool],
    wx: int,
    feet: int,
    ball: bool,
) -> int | None:
    """World feet row where a body falling from rest with its feet in row `feet` of column `wx`
    comes out of the first upward current below it: under the column, or on rock inside it. None if
    no current lies below in clear air, or if she enters too slowly and is held."""
    run = next(((top, bottom) for top, bottom in runs.get(wx, ()) if top > feet), None)
    if run is None:
        return None
    top, bottom = run
    if any(blocked(wx, row) for row in range(feet + 1, top)):
        return None
    body = BALL_HEIGHT if ball else STANDING_HEIGHT
    out = bottom + (1 if ball else 3)
    travel = (bottom + 1 - top) * TILE + body
    for row in range(top, out + 1):
        if blocked(wx, row):
            out, travel = row - 1, (row - top) * TILE
            break
    if out < top:
        return None
    speed_squared = min(2.0 * GRAVITY_FALLING * (top - feet - 1) * TILE, TERMINAL_VELOCITY**2)
    brake = UPDRAFT_ACCEL - GRAVITY_FALLING
    return out if speed_squared >= 2.0 * brake * travel else None


def drop_errors(
    rooms: dict[str, Room], held: dict[str, set[tuple[int, int]]], seen, edges, label: str
) -> list[str]:
    """Every floor opening of a room the run reached (with her body clear of any upward current)
    is crossed downward by some move."""
    doors, _ = link_doors(rooms)
    crossed = {
        (previous[0], nxt[0], previous[1])
        for nxt, previous_states in edges.items()
        for previous in previous_states
        if previous[0] != nxt[0]
    }
    reached = {
        state[0]
        for state in seen
        if not any(
            (state[1], row) in held[state[0]]
            for row in ((state[2],) if state[3] else range(state[2] - 2, state[2] + 1))
        )
    }
    errors = []
    for door in doors:
        pair = (door.room, door.target)
        if door.edge != "south" or door.target is None or pair in ONE_WAY_UP:
            continue
        if door.room not in reached:
            continue
        if not any((door.room, door.target, x) in crossed for x, _y in door.cells):
            errors.append(
                f"[{label}] {door.room} floor opening into {door.target} cannot be dropped "
                "through (an upward current holds her); give it a lane without current or list "
                "it in ONE_WAY_UP"
            )
    return errors
