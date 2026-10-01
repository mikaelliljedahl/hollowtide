"""Encounter pacing rule for the campaign graph check (tools/check_campaign_graph.py).

No stretch of PACING_SPAN columns (CLIMB_SPAN rows in a room taller than wide) along a room's long
axis may be empty of threats: each span needs a resident enemy, an ambush arena's spawn area or a
stalactite (docs/phase-2-campaign.md, encounter pacing). The Jev critic rated the empty rooms lowest of all segments (rounds 6 to 8: fringe_01 and
fringe_02 had no enemy near the route, fun 0.39 and 0.42). Stalactites count because the rooms
before the first weapon may only hold threats the player can dodge, but not in a room with an
ambush: the arena proves she is armed there, so its spans need enemies. Boss and mini-boss rooms, the ending
room and the hub are exempt: the fight, the epilogue and the crossroads set their own pace.
"""

from __future__ import annotations

from campaign_ambush import ambush_box
from campaign_layout import Room
from campaign_shortcuts import HUB_AREA

PACING_SPAN = 24
# A climb covers a row far more slowly than a walk covers a column (fringe_04: 16.7 s for 34 rows,
# fringe_01: 6.3 s for 60 columns), so a room taller than wide gets a shorter span.
CLIMB_SPAN = 12
EXEMPT_KINDS = ("boss", "miniboss", "ending")
THREAT_KINDS = ("enemy", "floater")


def pacing_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    for room in rooms.values():
        if room.area == HUB_AREA or any(e.kind in EXEMPT_KINDS for e in room.legend.values()):
            continue
        axis = 0 if room.width >= room.height else 1
        length = room.width if axis == 0 else room.height
        span = PACING_SPAN if axis == 0 else CLIMB_SPAN
        kinds = THREAT_KINDS if room.ambushes else (*THREAT_KINDS, "stalactite")
        covered = [
            (cell[axis], cell[axis] + 1)
            for char, entry in room.legend.items()
            if entry.kind in kinds
            for cell in room.cells_of(char)
        ]
        for zone in room.ambushes:
            box = ambush_box(zone, "spawns")
            covered.append((box[axis], box[axis] + box[axis + 2]))
        for start in range(length - span + 1):
            end = start + span
            if not any(lo < end and start < hi for lo, hi in covered):
                name = "columns" if axis == 0 else "rows"
                errors.append(
                    f"{room.room_id}: no threat in {name} {start}..{end - 1} "
                    f"(every {span} cells need one)"
                )
                break
    return errors
