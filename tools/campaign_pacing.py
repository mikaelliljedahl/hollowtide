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
# Rooms before the first weapon: only threats she outlasts or jumps. Round 10's Crawlers hit her
# unforeseen (Jev round 11: readability 0.02, "unclear warning"); a Drop Spider twitches and draws
# its drop line first and re-arms, so each room needs one (docs/phase-2-campaign.md).
WEAPONLESS_ROOMS = ("fringe_01", "fringe_02")
WEAPONLESS_ENEMIES = ("crawler", "drop_spider", "mimic_lure")
TELEGRAPHED_ENEMY = "drop_spider"
# Floor stretches the route walks (a heuristic seed 1 trace, Jev round 11) that rated "too easy"
# with no enemy within 180 px: (room, row, first column, last column) needs a resident enemy
# standing on that row inside the span.
ROUTE_WALKS = (
    ("fringe_03", 7, 13, 50),
    ("vaults_02", 14, 39, 57),
    ("nexus_07", 12, 13, 24),
)


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


def _enemy_cells(room: Room) -> list[tuple[str, tuple[int, int]]]:
    return [
        (entry.args[0], cell)
        for char, entry in room.legend.items()
        if entry.kind == "enemy" and entry.args
        for cell in room.cells_of(char)
    ]


def dodge_room_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    for room_id in WEAPONLESS_ROOMS:
        enemies = [enemy for enemy, _ in _enemy_cells(rooms[room_id])]
        unbeatable = sorted({e for e in enemies if e not in WEAPONLESS_ENEMIES})
        if unbeatable:
            errors.append(f"{room_id}: no weapon yet, but it holds {unbeatable}")
        if TELEGRAPHED_ENEMY not in enemies:
            errors.append(f"{room_id}: no weapon yet and no telegraphed {TELEGRAPHED_ENEMY}")
    for room_id, row, first, last in ROUTE_WALKS:
        if not any(
            cell[1] == row and first <= cell[0] <= last for _, cell in _enemy_cells(rooms[room_id])
        ):
            errors.append(
                f"{room_id}: no enemy on the route walk, row {row} columns {first}..{last}"
            )
    return errors
