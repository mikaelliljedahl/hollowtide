"""Ambush zone rules (D21) for campaign layouts: waves, sub-rectangles, sealed openings, validation.

Used by tools/campaign_layout.py (validation at parse time) and tools/campaign_worldfx.py (scene
emission). See the `ambush:` line in the campaign_layout.py docstring for the syntax.
"""

from __future__ import annotations

from campaign_layout import BOSS_IDS, ENEMY_IDS, LayoutError, Room, _open

MAX_SEAL_SPAN = 4
# Enemies an ambush never spawns: the Lava Monster needs an authored lava basin.
NEVER_SPAWNED = ("lava_monster", *BOSS_IDS)


def ambush_waves(options: dict[str, str]) -> list[list[str]]:
    """Wave lists of an ambush zone in order: wave=, then wave2=, wave3=, ..."""
    waves = [options.get("wave", "")]
    while f"wave{len(waves) + 1}" in options:
        waves.append(options[f"wave{len(waves) + 1}"])
    return [wave.split(",") if wave else [] for wave in waves]


def ambush_box(zone: dict, key: str) -> tuple[int, int, int, int]:
    """Optional sub-rectangle option (trigger=, spawns=) as x,y,w,h room tiles; default: arena."""
    value = zone["options"].get(key)
    if value is None:
        return zone["rect"]
    parts = value.split(",")
    if len(parts) != 4 or not all(part.isdigit() for part in parts):
        raise LayoutError(f"ambush {key}= needs x,y,w,h in tiles, got {value!r}")
    x, y, w, h = (int(part) for part in parts)
    return x, y, w, h


def _cells_bbox(cells: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [cell[0] for cell in cells]
    ys = [cell[1] for cell in cells]
    return min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


def ambush_openings(room: Room, rect: tuple[int, int, int, int]) -> list[tuple[int, int, int, int]]:
    """Runs of open border cells of the arena that lead outside; each becomes a seal slab
    (x, y, w, h in tiles, one tile thick)."""
    x0, y0, w, h = rect
    sides = [
        ([(x0, y) for y in range(y0, y0 + h)], (-1, 0)),
        ([(x0 + w - 1, y) for y in range(y0, y0 + h)], (1, 0)),
        ([(x, y0) for x in range(x0, x0 + w)], (0, -1)),
        ([(x, y0 + h - 1) for x in range(x0, x0 + w)], (0, 1)),
    ]
    slabs: set[tuple[int, int, int, int]] = set()
    for cells, (dx, dy) in sides:
        run: list[tuple[int, int]] = []
        for cell in [*cells, None]:
            leads_out = (
                cell is not None and _open(room, *cell) and _open(room, cell[0] + dx, cell[1] + dy)
            )
            if leads_out:
                run.append(cell)
                continue
            if run:
                bx, by, bw, bh = _cells_bbox(run)
                if max(bw, bh) > MAX_SEAL_SPAN:
                    raise LayoutError(
                        f"{room.room_id}: ambush opening at {run[0]} is {max(bw, bh)} cells wide; "
                        f"arena borders must be walls with openings of at most {MAX_SEAL_SPAN}"
                    )
                slabs.add((bx, by, bw, bh))
                run = []
    return sorted(slabs, key=lambda slab: (slab[1], slab[0]))


def _inside(inner: tuple[int, int, int, int], outer: tuple[int, int, int, int]) -> bool:
    ix, iy, iw, ih = inner
    ox, oy, ow, oh = outer
    return iw > 0 and ih > 0 and ox <= ix and oy <= iy and ix + iw <= ox + ow and iy + ih <= oy + oh


def validate_ambush(room: Room, zone: dict) -> None:
    where = room.room_id
    x, y, w, h = zone["rect"]
    options = zone["options"]
    waves = ambush_waves(options)
    for index, wave in enumerate(waves, start=1):
        if not wave or any(enemy not in ENEMY_IDS for enemy in wave):
            raise LayoutError(f"{where}: ambush wave {index} needs known enemy ids")
        if any(enemy in NEVER_SPAWNED for enemy in wave):
            raise LayoutError(f"{where}: ambush wave {index} uses an enemy ambushes never spawn")
    stray = [key for key in options if key.startswith("wave") and key != "wave"]
    if len(stray) != len(waves) - 1:
        raise LayoutError(f"{where}: ambush waves must be wave=, wave2=, wave3=... without gaps")
    if x < 0 or y < 0 or x + w > room.width or y + h > room.height or w < 6 or h < 4:
        raise LayoutError(f"{where}: ambush rect {zone['rect']} outside the room or too small")
    trigger = ambush_box(zone, "trigger")
    for key in ("trigger", "spawns"):
        if not _inside(ambush_box(zone, key), zone["rect"]):
            raise LayoutError(f"{where}: ambush {key}= must lie inside the arena rect")
    ambush_openings(room, zone["rect"])
    for char, entry in room.legend.items():
        if entry.kind not in ("save", "start", "boss"):
            continue
        for cx, cy in room.cells_of(char):
            # A save may sit in the arena outside the trigger: death aborts the fight anyway.
            part, (bx, by, bw, bh) = (
                ("trigger", trigger) if entry.kind == "save" else ("arena", zone["rect"])
            )
            if bx <= cx < bx + bw and by <= cy < by + bh:
                raise LayoutError(f"{where}: ambush {part} must not contain a {entry.kind}")
