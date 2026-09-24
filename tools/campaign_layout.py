"""Shared parser for Hollowtide campaign room layouts.

Layouts live in scenes/campaign/layouts/<room_id>.txt. Format:

    id: fringe_01
    area: fringe
    name: Surface Breach
    origin: 0 0            # world position in tiles (rooms abut exactly; doors are derived)
    heat: 10 2 8 6         # optional, repeatable heat-zone rectangle in local tiles
    ambush: 4 3 20 12 wave=hopper,hopper,vent_flyer [id=arena]   # seals its border openings
    ambush: 1 1 58 14 wave=hopper,hopper wave2=hopper,ceiling_diver [wave3=...] [trigger=x,y,w,h]
            [spawns=x,y,w,h]   # waves in order; trigger/spawns are sub-rectangles in room tiles
    current: 6 10 12 3 dir=right strength=260 [kind=water|wind|steam]
    rising: 10 1 7 15 [kind=lava|water] [speed=110] [safe=3] [rest=1]   # flood shaft
    legend:
      @ start
      S save
      R refill
      1 pickup slipstream slip
      h enemy hopper w=10 h=6 dir=-1
      m gate missile
      G flaggate boss:stone_guardian
      ~ lava
      t timeddoor [seconds=6] [id=door]   # solid door cells, opened by its switches
      o switch door=t                      # shootable switch (air cell, mount it by rock)
      c crumble [permanent]                # brittle floor tiles (drawn as solid cells)
      v stalactite                         # air cell right under the ceiling
      k crusher [offset=0]                 # block rest footprint (air, rock slot above)
    grid:
    ##############...

Grid characters: '#' is rock, '.' is air, everything else must be in the legend. Legend marks are air
cells except gates (solid until opened). A lava run drawn on top of a floor (open to the side at walk
level, at least two rock rows below) is sunk one row into the floor at parse time, so lava always sits
in a basin below the floor line; runs already enclosed by rock on both sides are left as they are. An air cell on the room boundary is a door opening; the
neighbouring room must have the mirrored opening at the same world cells.
"""

from __future__ import annotations

import pathlib
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parents[1]
LAYOUT_DIR = ROOT / "scenes" / "campaign" / "layouts"
AREAS = ("fringe", "nexus", "vaults", "kiln", "depths")
GATE_KINDS = ("missile", "bomb", "wave", "undertow")
ENTITY_KINDS = (
    "start",
    "save",
    "refill",
    "missilerefill",
    "pickup",
    "enemy",
    "floater",
    "boss",
    "gate",
    "flaggate",
    "lava",
    "ending",
    "light",
    "timeddoor",
    "switch",
    "crumble",
    "stalactite",
    "crusher",
)
CURRENT_DIRS = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}
CURRENT_KINDS = ("water", "wind", "steam")
# A horizontal current above this pushes harder than a walking player can resist.
MAX_SIDE_CURRENT = 360
FLYING_ENEMIES = ("vent_flyer", "energy_parasite", "frost_floater", "ceiling_diver")
ENEMY_IDS = (
    "crawler",
    "ceiling_diver",
    "vent_flyer",
    "hopper",
    "spitter",
    "armored_guard",
    "frost_floater",
    "energy_parasite",
    "shard_turret",
    "burrower",
    "grasshopper",
    "shooting_gargoyle",
    "lava_monster",
    "bat_swarm",
    "mimic",
    "mimic_lure",
    "drop_spider",
    "surface_eel",
    "stalker",
    "chasm_sniper",
)
BOSS_IDS = ("stone_guardian", "furnace_mother", "tidal_heart")
PICKUP_KINDS = (
    "beam",
    "slipstream",
    "missiles",
    "long_beam",
    "ice_beam",
    "wave_beam",
    "bombs",
    "high_jump",
    "pressure_seal",
    "undertow_dash",
    "energy_tank",
    "missile_tank",
    # Tide Sockets and Glyphs (docs/features/tide-modules.md); mirrors TIDE_PICKUP_KINDS.
    "tide_socket",
    "glyph_quickstring",
    "glyph_farcast",
    "glyph_heavy_barb",
    "glyph_brine_hide",
    "glyph_ebb_mend",
    "glyph_deep_pulse",
    "glyph_spring_tide",
)


class LayoutError(Exception):
    pass


@dataclass
class LegendEntry:
    char: str
    kind: str
    args: list[str]
    options: dict[str, str]


@dataclass
class Room:
    room_id: str
    area: str
    name: str
    origin: tuple[int, int]
    grid: list[str]
    legend: dict[str, LegendEntry]
    heat: list[tuple[int, int, int, int]] = field(default_factory=list)
    path: pathlib.Path | None = None
    # Living-environment zones (D21): {"rect": (x, y, w, h), "options": {...}}.
    ambushes: list[dict] = field(default_factory=list)
    currents: list[dict] = field(default_factory=list)
    risings: list[dict] = field(default_factory=list)

    @property
    def width(self) -> int:
        return len(self.grid[0])

    @property
    def height(self) -> int:
        return len(self.grid)

    def char(self, x: int, y: int) -> str:
        if 0 <= y < self.height and 0 <= x < self.width:
            return self.grid[y][x]
        return "#"

    def entry(self, x: int, y: int) -> LegendEntry | None:
        return self.legend.get(self.char(x, y))

    def is_rock(self, x: int, y: int) -> bool:
        return self.char(x, y) == "#"

    def gate_at(self, x: int, y: int) -> LegendEntry | None:
        entry = self.entry(x, y)
        if entry is not None and entry.kind in ("gate", "flaggate", "timeddoor"):
            return entry
        return None

    def world_rect(self) -> tuple[int, int, int, int]:
        return (self.origin[0], self.origin[1], self.width, self.height)

    def cells_of(self, char: str) -> list[tuple[int, int]]:
        return [
            (x, y)
            for y, row in enumerate(self.grid)
            for x, value in enumerate(row)
            if value == char
        ]

    def regions_of(self, char: str) -> list[list[tuple[int, int]]]:
        """Four-connected regions of one legend character."""
        remaining = set(self.cells_of(char))
        regions: list[list[tuple[int, int]]] = []
        while remaining:
            seed = min(remaining, key=lambda cell: (cell[1], cell[0]))
            stack = [seed]
            remaining.discard(seed)
            region = []
            while stack:
                x, y = stack.pop()
                region.append((x, y))
                for neighbour in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if neighbour in remaining:
                        remaining.discard(neighbour)
                        stack.append(neighbour)
            region.sort(key=lambda cell: (cell[1], cell[0]))
            regions.append(region)
        regions.sort(key=lambda region: (region[0][1], region[0][0]))
        return regions


def _parse_options(tokens: list[str]) -> tuple[list[str], dict[str, str]]:
    args: list[str] = []
    options: dict[str, str] = {}
    for token in tokens:
        if "=" in token:
            key, value = token.split("=", 1)
            options[key] = value
        else:
            args.append(token)
    return args, options


def parse_layout(path: pathlib.Path) -> Room:
    header: dict[str, str] = {}
    heat: list[tuple[int, int, int, int]] = []
    zones: dict[str, list[dict]] = {"ambush": [], "current": [], "rising": []}
    legend: dict[str, LegendEntry] = {}
    grid: list[str] = []
    section = "header"
    for number, raw in enumerate(path.read_text().splitlines(), start=1):
        line = raw.rstrip()
        if section != "grid":
            line = line.split("#", 1)[0].rstrip() if not line.lstrip().startswith("#") else ""
            if not line.strip():
                continue
        if section == "grid":
            if line.strip():
                grid.append(line.strip())
            continue
        stripped = line.strip()
        if stripped == "legend:":
            section = "legend"
            continue
        if stripped == "grid:":
            section = "grid"
            continue
        if section == "legend":
            char, _, rest = stripped.partition(" ")
            if len(char) != 1 or char in "#.":
                raise LayoutError(f"{path.name}:{number}: bad legend char {char!r}")
            tokens = rest.split()
            if not tokens or tokens[0] not in ENTITY_KINDS:
                raise LayoutError(f"{path.name}:{number}: unknown legend kind {rest!r}")
            args, options = _parse_options(tokens[1:])
            if char in legend:
                raise LayoutError(f"{path.name}:{number}: duplicate legend char {char!r}")
            legend[char] = LegendEntry(char, tokens[0], args, options)
            continue
        key, _, value = stripped.partition(":")
        key = key.strip()
        value = value.strip()
        if key in zones:
            numbers, options = _parse_options(value.split())
            if len(numbers) != 4:
                raise LayoutError(f"{path.name}:{number}: {key} needs x y w h then options")
            rect = tuple(int(part) for part in numbers)
            zones[key].append({"rect": rect, "options": options})
        elif key == "heat":
            parts = [int(part) for part in value.split()]
            if len(parts) != 4:
                raise LayoutError(f"{path.name}:{number}: heat needs x y w h")
            heat.append((parts[0], parts[1], parts[2], parts[3]))
        else:
            header[key] = value
    for key in ("id", "area", "name", "origin"):
        if key not in header:
            raise LayoutError(f"{path.name}: missing header {key}")
    if header["area"] not in AREAS:
        raise LayoutError(f"{path.name}: unknown area {header['area']}")
    if header["id"] != path.stem:
        raise LayoutError(f"{path.name}: id {header['id']} does not match file name")
    if not grid:
        raise LayoutError(f"{path.name}: empty grid")
    width = len(grid[0])
    for index, row in enumerate(grid):
        if len(row) != width:
            raise LayoutError(
                f"{path.name}: grid row {index} has width {len(row)}, expected {width}"
            )
        for char in row:
            if char not in "#." and char not in legend:
                raise LayoutError(f"{path.name}: grid row {index} uses unknown char {char!r}")
    if width < 30 or len(grid) < 17:
        raise LayoutError(f"{path.name}: rooms must be at least one screen (30x17 tiles)")
    grid = _sink_lava(grid, legend)
    origin_parts = [int(part) for part in header["origin"].split()]
    room = Room(
        room_id=header["id"],
        area=header["area"],
        name=header["name"],
        origin=(origin_parts[0], origin_parts[1]),
        grid=grid,
        legend=legend,
        heat=heat,
        path=path,
        ambushes=zones["ambush"],
        currents=zones["current"],
        risings=zones["rising"],
    )
    _validate_legend(room)
    _validate_world_fx(room)
    return room


def _sink_lava(grid: list[str], legend: dict[str, LegendEntry]) -> list[str]:
    """Moves lava slabs that sit on a floor one row down into a carved basin."""
    lava = {char for char, entry in legend.items() if entry.kind == "lava"}
    if not lava:
        return grid
    rows = [list(row) for row in grid]
    height = len(rows)
    width = len(rows[0])
    for y in range(height - 2, -1, -1):
        x = 0
        while x < width:
            char = rows[y][x]
            if char not in lava:
                x += 1
                continue
            end = x
            while end < width and rows[y][end] == char:
                end += 1
            left_rock = x == 0 or rows[y][x - 1] == "#"
            right_rock = end == width or rows[y][end] == "#"
            floor = (
                0 < x
                and end < width
                and all(
                    y + 2 < height and rows[y + 1][cx] == "#" and rows[y + 2][cx] == "#"
                    for cx in range(x, end)
                )
            )
            if floor and not (left_rock and right_rock):
                for cx in range(x, end):
                    rows[y + 1][cx] = char
                    rows[y][cx] = "."
            x = end
    return ["".join(row) for row in rows]


def _validate_legend(room: Room) -> None:
    for char, entry in room.legend.items():
        count = len(room.cells_of(char))
        where = f"{room.room_id} legend {char!r}"
        if count == 0:
            raise LayoutError(f"{where}: not used in grid")
        if entry.kind == "pickup":
            if len(entry.args) != 2 or entry.args[0] not in PICKUP_KINDS:
                raise LayoutError(f"{where}: pickup needs <kind> <local_id>")
            if count != 1:
                raise LayoutError(f"{where}: pickup must appear exactly once")
        elif entry.kind == "enemy":
            if len(entry.args) != 1 or entry.args[0] not in ENEMY_IDS:
                raise LayoutError(f"{where}: enemy needs a known enemy id")
        elif entry.kind == "boss":
            if len(entry.args) != 1 or entry.args[0] not in BOSS_IDS:
                raise LayoutError(f"{where}: boss needs a known boss id")
            if "arena" not in entry.options or count != 1:
                raise LayoutError(f"{where}: boss needs arena=x,y,w,h and exactly one cell")
        elif entry.kind == "gate":
            if not entry.args or entry.args[0] not in GATE_KINDS:
                raise LayoutError(f"{where}: gate needs one of {GATE_KINDS}")
        elif entry.kind == "flaggate":
            if len(entry.args) != 1:
                raise LayoutError(f"{where}: flaggate needs comma separated flags")
        elif entry.kind in ("start", "save", "refill", "missilerefill"):
            if entry.kind == "start" and count != 1:
                raise LayoutError(f"{where}: start must appear once")
            for x, y in room.cells_of(char):
                if not room.is_rock(x, y + 1):
                    raise LayoutError(f"{where}: {entry.kind} at {x},{y} must stand on rock")


def _open(room: Room, x: int, y: int) -> bool:
    """Air for the purpose of arena openings (rock, gates and crumble tiles are closed)."""
    if room.is_rock(x, y):
        return False
    entry = room.entry(x, y)
    return entry is None or entry.kind not in ("gate", "flaggate", "timeddoor", "crumble")


def _validate_world_fx(room: Room) -> None:
    """Checks the living-environment marks (D21) so the builder never emits an unsafe setup."""
    where = room.room_id
    for char, entry in room.legend.items():
        cells = room.cells_of(char)
        if entry.kind == "switch":
            door = entry.options.get("door", "")
            target = room.legend.get(door)
            if target is None or target.kind != "timeddoor":
                raise LayoutError(f"{where} legend {char!r}: switch needs door=<timeddoor char>")
        elif entry.kind == "timeddoor":
            if float(entry.options.get("seconds", 6)) < 3:
                raise LayoutError(f"{where} legend {char!r}: timed door needs seconds >= 3")
            if not any(
                other.kind == "switch" and other.options.get("door") == char
                for other in room.legend.values()
            ):
                raise LayoutError(f"{where} legend {char!r}: timed door has no switch")
        elif entry.kind == "stalactite":
            for x, y in cells:
                if not room.is_rock(x, y - 1):
                    raise LayoutError(f"{where}: stalactite at {x},{y} must hang from rock")
        elif entry.kind == "crusher":
            for region in room.regions_of(char):
                xs = [cell[0] for cell in region]
                ys = [cell[1] for cell in region]
                if len(region) != (max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1):
                    raise LayoutError(f"{where}: crusher at {region[0]} must be a rectangle")
                if not all(room.is_rock(x, min(ys) - 1) for x in set(xs)):
                    raise LayoutError(f"{where}: crusher at {region[0]} needs rock right above it")
        elif entry.kind == "crumble":
            if entry.args and entry.args != ["permanent"]:
                raise LayoutError(f"{where} legend {char!r}: crumble takes only 'permanent'")
    # Imported here: campaign_ambush builds on this module.
    from campaign_ambush import validate_ambush

    for zone in room.ambushes:
        validate_ambush(room, zone)
    for zone in room.currents:
        options = zone["options"]
        if options.get("dir", "") not in CURRENT_DIRS:
            raise LayoutError(f"{where}: current needs dir=left|right|up|down")
        if options.get("kind", "water") not in CURRENT_KINDS:
            raise LayoutError(f"{where}: current kind must be one of {CURRENT_KINDS}")
        strength = float(options.get("strength", 260))
        if options["dir"] in ("left", "right") and strength > MAX_SIDE_CURRENT:
            raise LayoutError(f"{where}: sideways current stronger than {MAX_SIDE_CURRENT}")
    for zone in room.risings:
        x, y, w, h = zone["rect"]
        options = zone["options"]
        if options.get("kind", "lava") not in ("lava", "water"):
            raise LayoutError(f"{where}: rising kind must be lava or water")
        if int(options.get("safe", 3)) < 3 or h < 8:
            raise LayoutError(f"{where}: rising shaft needs h >= 8 and safe >= 3 tiles of headroom")
        if float(options.get("speed", 110)) > 180:
            raise LayoutError(f"{where}: rising speed above 180 px/s is not readable")


def load_rooms() -> dict[str, Room]:
    rooms: dict[str, Room] = {}
    for path in sorted(LAYOUT_DIR.glob("*.txt")):
        room = parse_layout(path)
        rooms[room.room_id] = room
    return rooms


# --- Doors -----------------------------------------------------------------------------------


@dataclass
class Door:
    room: str
    edge: str  # west / east / north / south
    cells: list[tuple[int, int]]  # local boundary cells
    target: str | None = None

    @property
    def span(self) -> int:
        return len(self.cells)


def boundary_openings(room: Room) -> list[Door]:
    doors: list[Door] = []
    width, height = room.width, room.height

    def is_open(x: int, y: int) -> bool:
        return not room.is_rock(x, y) and room.gate_at(x, y) is None

    def runs(edge: str, cells: list[tuple[int, int]]) -> None:
        current: list[tuple[int, int]] = []
        for cell in cells:
            if is_open(*cell):
                current.append(cell)
            elif current:
                doors.append(Door(room.room_id, edge, current))
                current = []
        if current:
            doors.append(Door(room.room_id, edge, current))

    runs("west", [(0, y) for y in range(height)])
    runs("east", [(width - 1, y) for y in range(height)])
    runs("north", [(x, 0) for x in range(width)])
    runs("south", [(x, height - 1) for x in range(width)])
    return doors


EDGE_STEP = {"west": (-1, 0), "east": (1, 0), "north": (0, -1), "south": (0, 1)}
OPPOSITE = {"west": "east", "east": "west", "north": "south", "south": "north"}


def room_at_world(rooms: dict[str, Room], wx: int, wy: int) -> Room | None:
    for room in rooms.values():
        ox, oy = room.origin
        if ox <= wx < ox + room.width and oy <= wy < oy + room.height:
            return room
    return None


def link_doors(rooms: dict[str, Room]) -> tuple[list[Door], list[str]]:
    """Returns all doors with targets plus a list of errors."""
    errors: list[str] = []
    all_doors: list[Door] = []
    by_room: dict[str, list[Door]] = {}
    for room in rooms.values():
        by_room[room.room_id] = boundary_openings(room)
    for room in rooms.values():
        for door in by_room[room.room_id]:
            dx, dy = EDGE_STEP[door.edge]
            targets = set()
            mirrored = set()
            for x, y in door.cells:
                wx, wy = room.origin[0] + x + dx, room.origin[1] + y + dy
                other = room_at_world(rooms, wx, wy)
                if other is None:
                    errors.append(f"{room.room_id}: {door.edge} opening at {x},{y} leads nowhere")
                    continue
                targets.add(other.room_id)
                mirrored.add((wx - other.origin[0], wy - other.origin[1]))
            if len(targets) > 1:
                errors.append(f"{room.room_id}: {door.edge} opening spans rooms {sorted(targets)}")
            if len(targets) == 1:
                door.target = targets.pop()
                other_doors = by_room[door.target]
                match = [
                    other_door
                    for other_door in other_doors
                    if other_door.edge == OPPOSITE[door.edge] and set(other_door.cells) == mirrored
                ]
                if not match:
                    errors.append(
                        f"{room.room_id}: {door.edge} opening {door.cells[0]}..{door.cells[-1]} "
                        f"has no exactly mirrored opening in {door.target}"
                    )
            all_doors.append(door)
    return all_doors, errors


def overlap_errors(rooms: dict[str, Room]) -> list[str]:
    errors = []
    items = list(rooms.values())
    for index, first in enumerate(items):
        ax, ay, aw, ah = first.world_rect()
        for second in items[index + 1 :]:
            bx, by, bw, bh = second.world_rect()
            if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                errors.append(f"rooms {first.room_id} and {second.room_id} overlap")
    return errors
