"""Air rule for rising floods (D21) in campaign layouts.

Used by tools/campaign_layout.py at parse time. The surge throws a caught player upward, so she can
rise or drift sideways but not dive. From every standing spot under a flood's stop line she must
reach, moving only that way, a dry foothold above the stop line or a column outside the flood's
rect (leaving it drains the flood). A stop line above a ceiling that closes in a hall breaks this:
the whole hall floods and she is held under the rock until she dies.
"""

from __future__ import annotations

from collections import deque

from campaign_layout import LayoutError, Room, _open

BODY = 3  # standing body height in cells, as in tools/check_campaign_graph.py
LIFT = 5  # rows the surge throw carries her above the surface (1500 px/s against 3200 px/s^2)


def flood_trap(room: Room, zone: dict) -> tuple[int, int] | None:
    """First feet cell under the stop line that cannot reach air, or None when all can."""
    x0, y0, w, h = zone["rect"]
    stop = y0 + int(zone["options"].get("safe", 3))
    top = stop - LIFT

    def fits(x: int, y: int) -> bool:
        return y >= top and all(_open(room, x, y - row) for row in range(BODY))

    def escape(x: int, y: int) -> bool:
        return not x0 <= x < x0 + w or (y < stop and room.is_rock(x, y + 1))

    spots = [(x, y) for x in range(x0 - 1, x0 + w + 1) for y in range(top, y0 + h) if fits(x, y)]
    free = {spot for spot in spots if escape(*spot)}
    queue = deque(free)
    # Walk the allowed moves backwards: a spot is free when it rises or steps sideways onto one.
    while queue:
        x, y = queue.popleft()
        for previous in ((x, y + 1), (x - 1, y), (x + 1, y)):
            if previous not in free and previous[1] < y0 + h and fits(*previous):
                free.add(previous)
                queue.append(previous)
    for x, y in sorted(spots, key=lambda spot: (spot[1], spot[0])):
        if y >= stop and x0 <= x < x0 + w and (x, y) not in free:
            return x, y
    return None


def validate_flood(room: Room, zone: dict) -> None:
    trap = flood_trap(room, zone)
    if trap is not None:
        raise LayoutError(
            f"{room.room_id}: rising flood {zone['rect']} leaves no air for a player caught at "
            f"{trap[0]},{trap[1]}; stop it below the ceiling that closes her in"
        )
