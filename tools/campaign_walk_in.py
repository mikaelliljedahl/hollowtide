"""Door walk-in rule for the campaign graph check (tools/check_campaign_graph.py).

A player who walks straight in through a side door must not drop into lava: the floor line from the
door runs until a wall, a lip or a drop, and a lava basin may only follow a lip that stops the walk
(the kiln_03 sweep took lava damage on every entry). Gates count as open, since the walk-in that
matters happens once they are.
"""

from __future__ import annotations

from campaign_layout import Room, boundary_openings


def _lava(room: Room, x: int, y: int) -> bool:
    entry = room.entry(x, y)
    return entry is not None and entry.kind == "lava"


def _solid(room: Room, x: int, y: int) -> bool:
    entry = room.entry(x, y)
    return room.is_rock(x, y) or (entry is not None and entry.kind in ("crumble", "crusher"))


def walk_in_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    for room in rooms.values():
        for door in boundary_openings(room):
            if door.edge not in ("west", "east"):
                continue
            step = 1 if door.edge == "west" else -1
            x, y = door.cells[-1]
            if not _solid(room, x, y + 1):
                continue
            while 0 <= x + step < room.width:
                ahead = x + step
                if any(_solid(room, ahead, row) for row in (y, y - 1, y - 2)):
                    break
                if _lava(room, ahead, y + 1):
                    errors.append(
                        f"{room.room_id}: walking in through the {door.edge} door drops into lava "
                        f"at {ahead},{y + 1}; put a lip before the basin"
                    )
                    break
                if not _solid(room, ahead, y + 1):
                    break
                x = ahead
    return errors
