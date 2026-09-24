"""Scene emission for the living-environment marks (D21) in campaign layouts.

Used by tools/build_campaign_rooms.py. Each mark becomes one node under the room's Entities with a
script from scripts/world/dynamic/. See tools/campaign_layout.py for the layout syntax.
"""

from __future__ import annotations

from campaign_ambush import ambush_box, ambush_openings, ambush_waves
from campaign_layout import (
    CURRENT_DIRS,
    FLYING_ENEMIES,
    LayoutError,
    Room,
    _open,
)

TILE = 64

EXT = {
    "ambush": ("Script", "res://scripts/world/dynamic/ambush_arena.gd"),
    "timeddoor": ("Script", "res://scripts/world/dynamic/timed_door.gd"),
    "crumble": ("Script", "res://scripts/world/dynamic/crumble_floor.gd"),
    "stalactite": ("Script", "res://scripts/world/dynamic/stalactite.gd"),
    "crusher": ("Script", "res://scripts/world/dynamic/crusher.gd"),
    "current": ("Script", "res://scripts/world/dynamic/push_current.gd"),
    "rising": ("Script", "res://scripts/world/dynamic/rising_shaft.gd"),
}


def _num(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:.3f}"


def _vec(x: float, y: float) -> str:
    return f"Vector2({_num(x)}, {_num(y)})"


def _rect(x: float, y: float, w: float, h: float) -> str:
    return f"Rect2({_num(x)}, {_num(y)}, {_num(w)}, {_num(h)})"


def _strings(values: list[str]) -> str:
    return "PackedStringArray(" + ", ".join(f'"{value}"' for value in values) + ")"


def _bbox(cells: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [cell[0] for cell in cells]
    ys = [cell[1] for cell in cells]
    return min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


def ambush_spawns(
    room: Room, rect: tuple[int, int, int, int], wave: list[str]
) -> list[tuple[int, int]]:
    """Spawn cells spread across the arena: floor spots for walkers, open air for flyers."""
    x0, y0, w, h = rect
    floors = [
        (x, y)
        for x in range(x0 + 2, x0 + w - 2)
        for y in range(y0 + 2, y0 + h)
        if _open(room, x, y)
        and _open(room, x, y - 1)
        and _open(room, x, y - 2)
        and not _open(room, x, y + 1)
    ]
    air = [
        (x, y)
        for x in range(x0 + 2, x0 + w - 2)
        for y in range(y0 + 1, y0 + h - 3)
        if all(_open(room, x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    ]
    if not floors:
        raise LayoutError(f"{room.room_id}: ambush arena {rect} has no floor to spawn on")
    spawns = []
    for index, enemy in enumerate(wave):
        pool = air if enemy in FLYING_ENEMIES and air else floors
        pool = sorted(pool)
        pick = pool[(index * 2 + 1) * len(pool) // (2 * len(wave))]
        spawns.append(pick)
    return spawns


def emit(writer, room: Room, next_name) -> None:
    """Adds the D21 nodes for `room` to the scene writer."""
    for char, entry in sorted(room.legend.items(), key=lambda item: item[0]):
        kind = entry.kind
        if kind == "timeddoor":
            regions = room.regions_of(char)
            if len(regions) != 1:
                raise LayoutError(f"{room.room_id}: timed door {char!r} must be one region")
            bx, by, bw, bh = _bbox(regions[0])
            cx, cy = bx * TILE + bw * TILE / 2, by * TILE + bh * TILE / 2
            offsets = []
            for other_char, other in sorted(room.legend.items()):
                if other.kind == "switch" and other.options.get("door") == char:
                    for sx, sy in room.cells_of(other_char):
                        ox = sx * TILE + TILE / 2 - cx
                        oy = sy * TILE + TILE / 2 - cy
                        offsets.append(f"{_num(ox)}, {_num(oy)}")
            local_id = entry.options.get("id", f"door_{char}")
            writer.node(
                f"TimedDoor_{local_id}",
                "Node2D",
                "Entities",
                [
                    f"position = {_vec(cx, cy)}",
                    f"script = {writer.ext('timeddoor')}",
                    f"door_size = {_vec(bw * TILE, bh * TILE)}",
                    f"seconds = {_num(float(entry.options.get('seconds', 6)))}",
                    "switch_offsets = PackedVector2Array(" + ", ".join(offsets) + ")",
                    f'local_id = "{local_id}"',
                ],
            )
        elif kind == "crumble":
            permanent = "permanent" in entry.args
            for region in room.regions_of(char):
                rows: dict[int, list[int]] = {}
                for x, y in region:
                    rows.setdefault(y, []).append(x)
                for y, xs in sorted(rows.items()):
                    xs.sort()
                    start = xs[0]
                    previous = xs[0]
                    for x in [*xs[1:], None]:
                        if x is not None and x == previous + 1:
                            previous = x
                            continue
                        writer.node(
                            next_name("Crumble"),
                            "Node2D",
                            "Entities",
                            [
                                f"position = {_vec(start * TILE, y * TILE)}",
                                f"script = {writer.ext('crumble')}",
                                f"cells = {previous - start + 1}",
                                f"permanent = {'true' if permanent else 'false'}",
                            ],
                        )
                        if x is not None:
                            start = previous = x
        elif kind == "stalactite":
            for x, y in room.cells_of(char):
                writer.node(
                    next_name("Stalactite"),
                    "Node2D",
                    "Entities",
                    [
                        f"position = {_vec(x * TILE + TILE / 2, y * TILE)}",
                        f"script = {writer.ext('stalactite')}",
                    ],
                )
        elif kind == "crusher":
            for region in room.regions_of(char):
                bx, by, bw, bh = _bbox(region)
                writer.node(
                    next_name("Crusher"),
                    "Node2D",
                    "Entities",
                    [
                        f"position = {_vec(bx * TILE + bw * TILE / 2, by * TILE)}",
                        f"script = {writer.ext('crusher')}",
                        f"width = {bw * TILE}.0",
                        f"block_height = {bh * TILE}.0",
                        f"phase_offset = {_num(float(entry.options.get('offset', 0)))}",
                    ],
                )
    for index, zone in enumerate(room.ambushes, start=1):
        x, y, w, h = zone["rect"]
        waves = ambush_waves(zone["options"])
        cx, cy = x * TILE + w * TILE / 2, y * TILE + h * TILE / 2
        doors = [
            _rect(sx * TILE - cx, sy * TILE - cy, sw * TILE, sh * TILE)
            for sx, sy, sw, sh in ambush_openings(room, zone["rect"])
        ]
        spawns = []
        for wave in waves:
            for enemy, (sx, sy) in zip(wave, ambush_spawns(room, ambush_box(zone, "spawns"), wave)):
                # Walkers appear just above their floor cell; flyers at the cell centre.
                oy = sy * TILE + TILE / 2 if enemy in FLYING_ENEMIES else sy * TILE + TILE - 40
                spawns.append(f"{_num(sx * TILE + TILE / 2 - cx)}, {_num(oy - cy)}")
        local_id = zone["options"].get("id", f"arena_{index}")
        properties = [
            f"position = {_vec(cx, cy)}",
            f"script = {writer.ext('ambush')}",
            f"arena_size = {_vec(w * TILE, h * TILE)}",
            f"wave = {_strings(waves[0])}",
        ]
        if len(waves) > 1:
            extra = ", ".join(_strings(wave) for wave in waves[1:])
            properties.append(f"extra_waves = Array[PackedStringArray]([{extra}])")
        properties += [
            "spawn_offsets = PackedVector2Array(" + ", ".join(spawns) + ")",
            f"door_rects = Array[Rect2]([{', '.join(doors)}])",
        ]
        if "trigger" in zone["options"]:
            tx, ty, tw, th = ambush_box(zone, "trigger")
            properties.append(
                f"trigger_rect = {_rect(tx * TILE - cx, ty * TILE - cy, tw * TILE, th * TILE)}"
            )
        properties.append(f'local_id = "{local_id}"')
        writer.node(f"Ambush_{local_id}", "Node2D", "Entities", properties)
    for zone in room.currents:
        x, y, w, h = zone["rect"]
        options = zone["options"]
        dx, dy = CURRENT_DIRS[options["dir"]]
        writer.node(
            next_name("Current"),
            "Area2D",
            "Entities",
            [
                f"position = {_vec(x * TILE + w * TILE / 2, y * TILE + h * TILE / 2)}",
                f"script = {writer.ext('current')}",
                f"zone_size = {_vec(w * TILE, h * TILE)}",
                f"direction = {_vec(dx, dy)}",
                f"strength = {_num(float(options.get('strength', 260)))}",
                f'kind = &"{options.get("kind", "water")}"',
            ],
        )
    for zone in room.risings:
        x, y, w, h = zone["rect"]
        options = zone["options"]
        writer.node(
            next_name("Rising"),
            "Node2D",
            "Entities",
            [
                f"position = {_vec(x * TILE, y * TILE)}",
                f"script = {writer.ext('rising')}",
                f"shaft_size = {_vec(w * TILE, h * TILE)}",
                f"rest_depth = {_num(float(options.get('rest', 1)) * TILE)}",
                f"safe_line = {_num(float(options.get('safe', 3)) * TILE)}",
                f"speed = {_num(float(options.get('speed', 110)))}",
                f'kind = &"{options.get("kind", "lava")}"',
            ],
        )
