"""Boss refill rule for the campaign graph check (tools/check_campaign_graph.py).

A boss that pursues on the floor stops short of the first wall, low roof or step at each end of its
lane (`_pursuit_velocity`, scripts/enemies/boss_motion.gd), so a player who backs into either end
is pinned there. From each such pocket a Quiver Cache must be reachable without touching the boss:
a cache on the pocket's side of the stopped body (on the boss's floor or a step of up to two cells
above it), or enough free air above the stopped body to jump over it. A room's `refill` shrine does
not count: it lies dormant while a boss holds the player.

Round 3 (2026-09-30): with 100 health and 5 Harpoons, every refill trip from the vaults_03 west
pocket, under a platform, crossed the Stone Guardian for 24 contact; a real-input probe found 0 of
85 trips unhurt. From the east pocket, with open air above the body, hopping over it cleared 17 of
17. The Cinder Warden patrols and the Tidal Heart floats, so neither pins her; the same probe
cleared kiln_03 by hopping the Warden (10 of 17) and depths_02 by ball hops under the Heart (16 of
17), and they are exempt.
"""

from __future__ import annotations

from campaign_layout import Room

TILE = 64
FLOOR_PURSUERS = ("stone_guardian",)
# scripts/enemies/boss_attacks.gd: BODY_RADIUS, CHARGE_WALL_POCKET, LANE_MARGIN.
BODY_RADIUS = 92
WALL_POCKET = 128
LANE_MARGIN = 40
# scenes/enemies/boss.tscn PlayerDetector radius, the player's half width, a cache's half width.
CONTACT_RADIUS = 112
PLAYER_HALF_WIDTH = 28
CACHE_HALF_WIDTH = 56
# The body (184 px) plus 240 px of air: the vaults_03 east pocket clears a hop with this.
JUMP_AIR = 424
STEP_CELLS = 2


def pursuit_refill_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    for room in rooms.values():
        for char, entry in room.legend.items():
            if entry.kind != "boss" or entry.args[0] not in FLOOR_PURSUERS:
                continue
            (bx, by) = room.cells_of(char)[0]
            ax, _ay, aw, _ah = (int(part) for part in entry.options["arena"].split(","))
            floor_row = by
            while not _solid(room, bx, floor_row + 1):
                floor_row += 1
            lane = (ax * TILE + LANE_MARGIN, (ax + aw) * TILE - LANE_MARGIN)
            caches = [
                cell
                for key, cache in room.legend.items()
                if cache.kind == "missilerefill"
                for cell in room.cells_of(key)
            ]
            for side, step in (("west", -1), ("east", 1)):
                stop = _stop_x(room, bx, floor_row, step, lane[0] if step < 0 else lane[1])
                if _jumpable(room, stop, floor_row) or _cache_on_side(
                    caches, stop, floor_row, step
                ):
                    continue
                errors.append(
                    f"{room.room_id}: {entry.args[0]} pins the player in its {side} pocket (stops "
                    f"at x {stop}) with no Quiver Cache on her side and no air to jump it"
                )
    return errors


def _solid(room: Room, x: int, y: int) -> bool:
    return room.is_rock(x, y) or room.gate_at(x, y) is not None


def _stop_x(room: Room, bx: int, floor_row: int, step: int, lane_edge: int) -> int:
    """Where pursuit stops: the body keeps the pocket clear of the first wall or the lane end."""
    x = bx
    limit = lane_edge
    while 0 <= x + step < room.width:
        x += step
        if any(_solid(room, x, row) for row in range(floor_row - 2, floor_row + 1)):
            face = (x + 1) * TILE if step < 0 else x * TILE
            limit = max(limit, face) if step < 0 else min(limit, face)
            break
    return limit - step * (BODY_RADIUS + WALL_POCKET)


def _jumpable(room: Room, stop: int, floor_row: int) -> bool:
    reach = CONTACT_RADIUS + PLAYER_HALF_WIDTH
    columns = range((stop - reach) // TILE, (stop + reach) // TILE + 1)
    floor_y = (floor_row + 1) * TILE
    rows = range((floor_y - JUMP_AIR) // TILE, floor_row + 1)
    return not any(_solid(room, x, y) for x in columns for y in rows)


def _cache_on_side(caches: list[tuple[int, int]], stop: int, floor_row: int, step: int) -> bool:
    # She touches a cache while her body stays outside the stopped boss's contact circle.
    safe_edge = stop + step * (CONTACT_RADIUS + PLAYER_HALF_WIDTH)
    for x, y in caches:
        far_reach = (x + 0.5) * TILE + step * (CACHE_HALF_WIDTH + PLAYER_HALF_WIDTH)
        if floor_row - STEP_CELLS <= y <= floor_row and (far_reach - safe_edge) * step >= 0:
            return True
    return False
