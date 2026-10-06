"""Updraft rule for the campaign graph check (tools/check_campaign_graph.py).

A strong updraft is a lift: she rides it on purpose, either by standing under it and jumping (its
floor is within a jump of it) or by falling or climbing into it. One whose floor is out of reach
must not hang within a hop of a ledge beside it either, or a hop across the gap below catches her
and carries her into the room above. In kiln_01 the steam over the lava pit reached down to row 5,
and the pillar hop over the pit pulled the player into nexus_03 on every pass (Jev round 11: rated
navigation confusing; a heuristic seed 1 trace: kiln_01, 0.7 s in nexus_03, kiln_01 again).
"""

from __future__ import annotations

from campaign_layout import Room, _open

# Real jump (docs/game-feel.md: apex 256 px) plus the standing body (176 px), in 64 px rows: a
# player standing on feet row y reaches every row above y - 5.75, so a current whose first row
# below lies at most HOP_ROWS above her feet row catches her head at the apex.
HOP_ROWS = 5
# Columns beside the current from which a hop's rise still reaches it (about 3 cells of run
# before the apex at 380 to 480 px/s).
HOP_SIDE = 3
LIFT_STRENGTH = 500


def lift_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    for room in rooms.values():
        for zone in room.currents:
            x, y, w, h = zone["rect"]
            options = zone["options"]
            if options["dir"] != "up" or float(options.get("strength", 260)) < LIFT_STRENGTH:
                continue
            below = y + h
            if any(
                _floor_row(room, column, below) <= below + HOP_ROWS for column in range(x, x + w)
            ):
                continue
            beside = [*range(x - HOP_SIDE, x), *range(x + w, x + w + HOP_SIDE)]
            ledges = [
                (column, row)
                for column in beside
                for row in range(below, min(room.height - 1, below + HOP_ROWS + 1))
                if 0 <= column < room.width
                and _open(room, column, row)
                and not _open(room, column, row + 1)
            ]
            if ledges:
                errors.append(
                    f"{room.room_id}: the updraft at {x},{y} is out of reach from its floor but a "
                    f"hop from {ledges[0]} catches it; end it higher or let its floor reach it"
                )
    return errors


def _floor_row(room: Room, column: int, row: int) -> int:
    """Feet row of the first floor under `row` in `column` (the room's last row if none)."""
    while row < room.height - 1 and _open(room, column, row + 1):
        row += 1
    return row
