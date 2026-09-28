"""Lava rules for the campaign graph check (tools/check_campaign_graph.py).

A player who walks straight in through a side door must not drop into lava: the floor line from the
door runs until a wall, a lip or a drop, and a lava basin may only follow a lip that stops the walk
(the kiln_03 sweep took lava damage on every entry). Gates count as open, since the walk-in that
matters happens once they are.

No flying enemy that knocks the player back patrols above lava: its patrol box (the layout's w and
h around its cell) may not span a lava column. A contact over the kiln_01 pit knocked the player
into the lava on top of its own damage (Jev round 2, 2026-09-28). Frost floaters are platforms,
not attackers, and are exempt.
"""

from __future__ import annotations

from campaign_layout import FLYING_ENEMIES, Room, boundary_openings

# The builder's default patrol box (tools/build_campaign_rooms.py), in cells.
DEFAULT_PATROL = (12.0, 8.0)


def lava_errors(rooms: dict[str, Room]) -> list[str]:
    return walk_in_errors(rooms) + flyer_errors(rooms)


def flyer_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    for room in rooms.values():
        lava_columns = {
            x for y in range(room.height) for x in range(room.width) if _lava(room, x, y)
        }
        for char, entry in room.legend.items():
            if entry.kind != "enemy" or entry.args[0] not in FLYING_ENEMIES:
                continue
            if entry.args[0] == "frost_floater":
                continue
            width = float(entry.options.get("w", DEFAULT_PATROL[0]))
            for x, y in room.cells_of(char):
                left, right = x + 0.5 - width / 2, x + 0.5 + width / 2
                over = sorted(column for column in lava_columns if left <= column + 0.5 <= right)
                if over:
                    errors.append(
                        f"{room.room_id}: {entry.args[0]} at {x},{y} patrols above lava columns "
                        f"{over[0]}-{over[-1]}; move it or narrow its w"
                    )
    return errors


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
