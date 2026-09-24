"""Builds campaign room scenes from ASCII layouts.

    python3 tools/build_campaign_rooms.py

Reads scenes/campaign/layouts/*.txt and writes scenes/campaign/rooms/<room_id>.tscn plus the
generated room index scripts/campaign/campaign_rooms.gd. Output scenes are ordinary Godot scenes;
edit the layouts and rebuild rather than hand-editing generated files.
"""

from __future__ import annotations

import base64
import struct
import subprocess
import sys

import campaign_worldfx
from campaign_layout import ROOT, LayoutError, Room, link_doors, load_rooms, overlap_errors

TILE = 64
ROOM_DIR = ROOT / "scenes" / "campaign" / "rooms"
INDEX_PATH = ROOT / "scripts" / "campaign" / "campaign_rooms.gd"
FLOOR_OFFSET = 38

EXT = {
    "room": ("Script", "res://scripts/campaign/campaign_room.gd"),
    "tiles": ("TileSet", "res://scenes/campaign/cave_tileset.tres"),
    "visuals": ("Script", "res://scripts/world/cave_visuals.gd"),
    "pickup": ("PackedScene", "res://scenes/pickups/pickup.tscn"),
    "enemy": ("Script", "res://scripts/campaign/enemy_spawn.gd"),
    "boss": ("Script", "res://scripts/campaign/boss_spawn.gd"),
    "gate": ("Script", "res://scripts/world/ability_gate.gd"),
    "flaggate": ("Script", "res://scripts/campaign/flag_gate.gd"),
    "station": ("Script", "res://scripts/campaign/station.gd"),
    "hazard": ("Script", "res://scripts/campaign/hazard_spawn.gd"),
    "heat": ("Script", "res://scripts/campaign/heat_zone.gd"),
    "ending": ("Script", "res://scripts/campaign/ending_trigger.gd"),
    "light": ("Script", "res://scripts/campaign/light_shaft.gd"),
    **campaign_worldfx.EXT,
}


def _vec(x: float, y: float) -> str:
    return f"Vector2({_num(x)}, {_num(y)})"


def _num(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:.3f}"


def _rect(x: float, y: float, w: float, h: float) -> str:
    return f"Rect2({_num(x)}, {_num(y)}, {_num(w)}, {_num(h)})"


def _tile_data(room: Room) -> str:
    payload = bytearray(b"\x00\x00")
    for y, row in enumerate(room.grid):
        for x, char in enumerate(row):
            if char != "#":
                continue
            payload += struct.pack("<hhHHHH", x, y, 0, (x + y) % 4, (x * 7 + y) % 3, 0)
    return base64.b64encode(bytes(payload)).decode("ascii")


def _cell_center(x: int, y: int) -> tuple[float, float]:
    return (x * TILE + TILE / 2, y * TILE + TILE / 2)


def _floor_anchor(x: int, y: int) -> tuple[float, float]:
    return (x * TILE + TILE / 2, (y + 1) * TILE)


def _bbox(cells: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [cell[0] for cell in cells]
    ys = [cell[1] for cell in cells]
    return min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


class SceneWriter:
    def __init__(self, room: Room) -> None:
        self.room = room
        self.ext_ids: dict[str, str] = {}
        self.nodes: list[str] = []

    def ext(self, key: str) -> str:
        if key not in self.ext_ids:
            self.ext_ids[key] = f"{len(self.ext_ids) + 1}_{key}"
        return f'ExtResource("{self.ext_ids[key]}")'

    def node(self, name: str, kind: str | None, parent: str, props: list[str], **extra) -> None:
        header = f'[node name="{name}"'
        if kind:
            header += f' type="{kind}"'
        header += f' parent="{parent}"'
        if "instance" in extra:
            header += f" instance={extra['instance']}"
        header += "]"
        self.nodes.append("\n".join([header, *props]))

    def build(self, stable_ids: dict[str, int]) -> str:
        room = self.room
        width_px, height_px = room.width * TILE, room.height * TILE
        root_props = [
            f"script = {self.ext('room')}",
            f'room_id = "{room.room_id}"',
            f'area_id = &"{room.area}"',
            f'display_name = "{room.name}"',
            f"room_size = Vector2i({room.width}, {room.height})",
            f"world_origin = Vector2i({room.origin[0]}, {room.origin[1]})",
        ]
        root = "\n".join([f'[node name="{room.room_id}" type="Node2D"]', *root_props])
        self.node(
            "Backdrop",
            "Polygon2D",
            ".",
            [
                "z_index = -20",
                "color = Color(0.043, 0.055, 0.078, 1)",
                f"polygon = PackedVector2Array(0, 0, {width_px}, 0, {width_px}, {height_px}, "
                f"0, {height_px})",
            ],
        )
        self.node(
            "CaveTiles",
            "TileMapLayer",
            ".",
            [
                f'tile_map_data = PackedByteArray("{_tile_data(room)}")',
                f"tile_set = {self.ext('tiles')}",
            ],
        )
        self.node("CaveVisuals", "Node2D", ".", ["z_index = -5", f"script = {self.ext('visuals')}"])
        self.node("Entities", "Node2D", ".", [])
        self._entities()
        header = f"[gd_scene load_steps={len(self.ext_ids) + 1} format=3]"
        ext_lines = []
        for key, ident in self.ext_ids.items():
            kind, path = EXT[key]
            ext_lines.append(f'[ext_resource type="{kind}" path="{path}" id="{ident}"]')
        return "\n\n".join([header, "\n".join(ext_lines), root, *self.nodes]) + "\n"

    def _entities(self) -> None:
        room = self.room
        counters: dict[str, int] = {}

        def next_name(prefix: str) -> str:
            counters[prefix] = counters.get(prefix, 0) + 1
            return f"{prefix}{counters[prefix]:02d}"

        for char, entry in sorted(room.legend.items(), key=lambda item: item[0]):
            kind = entry.kind
            if kind == "start":
                (x, y) = room.cells_of(char)[0]
                self.node(
                    "Start", "Marker2D", "Entities", [f"position = {_vec(*_floor_anchor(x, y))}"]
                )
            elif kind in ("save", "refill", "missilerefill"):
                for x, y in room.cells_of(char):
                    fx, fy = _floor_anchor(x, y)
                    self.node(
                        next_name(
                            {"save": "Save", "refill": "Refill", "missilerefill": "AmmoRefill"}[
                                kind
                            ]
                        ),
                        "Area2D",
                        "Entities",
                        [
                            f"position = {_vec(fx, fy - FLOOR_OFFSET)}",
                            f"script = {self.ext('station')}",
                            f'station_kind = &"{kind}"',
                        ],
                    )
            elif kind == "pickup":
                (x, y) = room.cells_of(char)[0]
                pickup_kind, local_id = entry.args
                self.node(
                    f"Pickup_{local_id}",
                    None,
                    "Entities",
                    [
                        f"position = {_vec(*_cell_center(x, y))}",
                        f'instance_id = "{room.room_id}.{local_id}"',
                        f'kind = &"{pickup_kind}"',
                    ],
                    instance=self.ext("pickup"),
                )
            elif kind in ("enemy", "floater"):
                enemy_id = "frost_floater" if kind == "floater" else entry.args[0]
                w = float(entry.options.get("w", 12)) * TILE
                h = float(entry.options.get("h", 8)) * TILE
                for x, y in room.cells_of(char):
                    cx, cy = _cell_center(x, y)
                    left = max(cx - w / 2, TILE)
                    top = max(cy - h / 2, TILE)
                    right = min(cx + w / 2, (room.width - 1) * TILE)
                    bottom = min(cy + h / 2, (room.height - 1) * TILE)
                    self.node(
                        next_name("Enemy"),
                        "Marker2D",
                        "Entities",
                        [
                            f"position = {_vec(cx, cy)}",
                            f"script = {self.ext('enemy')}",
                            f'enemy_id = &"{enemy_id}"',
                            f"bounds = {_rect(left, top, right - left, bottom - top)}",
                            f"travel_direction = {int(entry.options.get('dir', 1))}",
                        ],
                    )
            elif kind == "boss":
                (x, y) = room.cells_of(char)[0]
                ax, ay, aw, ah = (int(part) for part in entry.options["arena"].split(","))
                rx, ry = (
                    int(part)
                    for part in entry.options.get("return", f"{ax + 2},{ay + ah - 1}").split(",")
                )
                self.node(
                    "Boss",
                    "Marker2D",
                    "Entities",
                    [
                        f"position = {_vec(*_cell_center(x, y))}",
                        f"script = {self.ext('boss')}",
                        f'boss_id = &"{entry.args[0]}"',
                        f"arena = {_rect(ax * TILE, ay * TILE, aw * TILE, ah * TILE)}",
                        f"return_point = {_vec(*_floor_anchor(rx, ry))}",
                    ],
                )
            elif kind == "gate":
                for index, region in enumerate(room.regions_of(char), start=1):
                    bx, by, bw, bh = _bbox(region)
                    gate_id = entry.args[1] if len(entry.args) > 1 else f"{entry.args[0]}_{index}"
                    if len(entry.args) > 1 and len(room.regions_of(char)) > 1:
                        gate_id = f"{gate_id}_{index}"
                    self.node(
                        f"Gate_{gate_id}",
                        "StaticBody2D",
                        "Entities",
                        [
                            f"position = {_vec(bx * TILE + bw * TILE / 2, by * TILE + bh * TILE / 2)}",
                            f"script = {self.ext('gate')}",
                            f'gate_kind = &"{entry.args[0]}"',
                            f'flag_id = "{room.room_id}.gate.{gate_id}"',
                            f"gate_size = {_vec(bw * TILE, bh * TILE)}",
                        ],
                    )
            elif kind == "flaggate":
                flags = entry.args[0].split(",")
                for region in room.regions_of(char):
                    bx, by, bw, bh = _bbox(region)
                    flag_list = ", ".join(f'"{flag}"' for flag in flags)
                    self.node(
                        next_name("FlagGate"),
                        "StaticBody2D",
                        "Entities",
                        [
                            f"position = {_vec(bx * TILE + bw * TILE / 2, by * TILE + bh * TILE / 2)}",
                            f"script = {self.ext('flaggate')}",
                            f"required_flags = PackedStringArray({flag_list})",
                            f"gate_size = {_vec(bw * TILE, bh * TILE)}",
                        ],
                    )
            elif kind == "lava":
                for region in room.regions_of(char):
                    bx, by, bw, bh = _bbox(region)
                    self.node(
                        next_name("Lava"),
                        "Marker2D",
                        "Entities",
                        [
                            f"position = {_vec(bx * TILE + bw * TILE / 2, by * TILE + bh * TILE / 2)}",
                            f"script = {self.ext('hazard')}",
                            f"hazard_size = {_vec(bw * TILE, bh * TILE)}",
                        ],
                    )
            elif kind == "ending":
                for region in room.regions_of(char):
                    bx, by, bw, bh = _bbox(region)
                    self.node(
                        next_name("Ending"),
                        "Area2D",
                        "Entities",
                        [
                            f"position = {_vec(bx * TILE + bw * TILE / 2, by * TILE + bh * TILE / 2)}",
                            f"script = {self.ext('ending')}",
                            f"trigger_size = {_vec(bw * TILE, bh * TILE)}",
                        ],
                    )
            elif kind == "light":
                for x, y in room.cells_of(char):
                    air = 0
                    while y - air - 1 >= 0 and not room.is_rock(x, y - air - 1):
                        air += 1
                    self.node(
                        next_name("Light"),
                        "Node2D",
                        "Entities",
                        [
                            f"position = {_vec(x * TILE + TILE / 2, (y + 1) * TILE)}",
                            f"script = {self.ext('light')}",
                            f'required_flag = "{entry.args[0] if entry.args else ""}"',
                            f"shaft_size = {_vec(192, (air + 1) * TILE)}",
                        ],
                    )
        for index, (x, y, w, h) in enumerate(room.heat, start=1):
            self.node(
                f"Heat{index:02d}",
                "Area2D",
                "Entities",
                [
                    f"position = {_vec(x * TILE + w * TILE / 2, y * TILE + h * TILE / 2)}",
                    f"script = {self.ext('heat')}",
                    f"zone_size = {_vec(w * TILE, h * TILE)}",
                ],
            )
        campaign_worldfx.emit(self, room, next_name)


def _gd_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _gate_regions(room: Room) -> list[tuple[str, str, list[tuple[int, int]]]]:
    """(kind, flag, cells) for every gate region, in the same order and with the same flags as the
    gate entries of the index."""
    result = []
    for char, entry in sorted(room.legend.items()):
        if entry.kind not in ("gate", "flaggate"):
            continue
        regions = room.regions_of(char)
        for index, region in enumerate(regions, start=1):
            if entry.kind == "gate":
                gate_id = entry.args[1] if len(entry.args) > 1 else f"{entry.args[0]}_{index}"
                if len(entry.args) > 1 and len(regions) > 1:
                    gate_id = f"{gate_id}_{index}"
                result.append((entry.args[0], f"{room.room_id}.gate.{gate_id}", region))
            else:
                result.append(("flag", entry.args[0], region))
    return result


def _map_mask(room: Room) -> list[str]:
    """Map silhouette rows: '#' rock, '.' air, 'g' gate, '~' lava (campaign map only)."""
    rows = []
    for row in room.grid:
        out = []
        for char in row:
            entry = room.legend.get(char)
            if char == "#":
                out.append("#")
            elif entry is not None and entry.kind in ("gate", "flaggate", "timeddoor"):
                out.append("g")
            elif entry is not None and entry.kind == "crumble":
                out.append("#")
            elif entry is not None and entry.kind == "lava":
                out.append("~")
            else:
                out.append(".")
        rows.append("".join(out))
    return rows


def _door_gates(
    room: Room, door_cells: list[list[tuple[int, int]]]
) -> list[tuple[str, str] | None]:
    """For each door: the (kind, flag) of the gate that seals it off from the room's largest open
    region, or None when the door is reachable without opening a gate."""
    gates = _gate_regions(room)
    gate_of: dict[tuple[int, int], tuple[str, str]] = {}
    for kind, flag, cells in gates:
        for cell in cells:
            gate_of[cell] = (kind, flag)
    component: dict[tuple[int, int], int] = {}
    sizes: list[int] = []
    for y in range(room.height):
        for x in range(room.width):
            if room.is_rock(x, y) or (x, y) in gate_of or (x, y) in component:
                continue
            index = len(sizes)
            stack = [(x, y)]
            component[(x, y)] = index
            count = 0
            while stack:
                cx, cy = stack.pop()
                count += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if not (0 <= nx < room.width and 0 <= ny < room.height):
                        continue
                    if room.is_rock(nx, ny) or (nx, ny) in gate_of or (nx, ny) in component:
                        continue
                    component[(nx, ny)] = index
                    stack.append((nx, ny))
            sizes.append(count)
    main = max(range(len(sizes)), key=lambda index: sizes[index]) if sizes else -1
    result: list[tuple[str, str] | None] = []
    for cells in door_cells:
        ids = {component[cell] for cell in cells if cell in component}
        if not ids or main in ids:
            direct = [gate_of[cell] for cell in cells if cell in gate_of]
            result.append(direct[0] if direct and not ids else None)
            continue
        found = None
        for (x, y), index in component.items():
            if index not in ids:
                continue
            for neighbour in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbour in gate_of:
                    found = gate_of[neighbour]
                    break
            if found:
                break
        result.append(found)
    return result


def write_index(rooms: dict[str, Room], doors) -> str:
    lines = [
        "# Generated by tools/build_campaign_rooms.py from scenes/campaign/layouts. Do not edit.",
        "# gdlint: disable=max-file-lines",
        "extends RefCounted",
        "",
    ]
    start_room = None
    start_position = None
    for room in rooms.values():
        for char, entry in room.legend.items():
            if entry.kind == "start":
                start_room = room.room_id
                start_position = _floor_anchor(*room.cells_of(char)[0])
    if start_room is None:
        raise LayoutError("no start marker in any room")
    lines.append(f"const START_ROOM := {_gd_string(start_room)}")
    lines.append(f"const START_POSITION := {_vec(*start_position)}")
    lines.append("const ROOMS := {")
    for room in rooms.values():
        saves = []
        refills = []
        gates = []
        for char, entry in sorted(room.legend.items()):
            if entry.kind == "save":
                saves += [_vec(*_floor_anchor(x, y)) for x, y in room.cells_of(char)]
            elif entry.kind in ("refill", "missilerefill"):
                refills += [_vec(*_floor_anchor(x, y)) for x, y in room.cells_of(char)]
            elif entry.kind in ("gate", "flaggate"):
                for index, region in enumerate(room.regions_of(char), start=1):
                    bx, by, bw, bh = _bbox(region)
                    if entry.kind == "gate":
                        gate_id = (
                            entry.args[1] if len(entry.args) > 1 else f"{entry.args[0]}_{index}"
                        )
                        if len(entry.args) > 1 and len(room.regions_of(char)) > 1:
                            gate_id = f"{gate_id}_{index}"
                        flag = f"{room.room_id}.gate.{gate_id}"
                        kind = entry.args[0]
                    else:
                        flag = entry.args[0]
                        kind = "flag"
                    gates.append(
                        f'{{"kind": &"{kind}", "flag": {_gd_string(flag)}, '
                        f'"cell": Vector2i({bx}, {by}), "size": Vector2i({bw}, {bh})}}'
                    )
            elif entry.kind == "boss":
                (x, y) = room.cells_of(char)[0]
                gates.append(
                    f'{{"kind": &"boss", "flag": "boss:{entry.args[0]}", '
                    f'"cell": Vector2i({x}, {y}), "size": Vector2i(1, 1)}}'
                )
        room_doors = []
        linked = [door for door in doors if door.room == room.room_id and door.target is not None]
        door_gates = _door_gates(room, [door.cells for door in linked])
        for door, gate in zip(linked, door_gates):
            xs = [cell[0] for cell in door.cells]
            ys = [cell[1] for cell in door.cells]
            gate_kind, gate_flag = gate if gate else ("", "")
            room_doors.append(
                f'{{"edge": &"{door.edge}", "target": {_gd_string(door.target)}, '
                f'"from": Vector2i({min(xs)}, {min(ys)}), "to": Vector2i({max(xs)}, {max(ys)}), '
                f'"gate": &"{gate_kind}", "gate_flag": {_gd_string(gate_flag)}}}'
            )
        pickups = []
        for char, entry in sorted(room.legend.items()):
            if entry.kind == "pickup":
                (x, y) = room.cells_of(char)[0]
                pickups.append(
                    f'{{"id": {_gd_string(f"{room.room_id}.{entry.args[1]}")}, '
                    f'"kind": &"{entry.args[0]}", "cell": Vector2i({x}, {y})}}'
                )
        lines.append(f"\t{_gd_string(room.room_id)}:")
        lines.append("\t{")
        lines.append(f'\t\t"area": &"{room.area}",')
        lines.append(f'\t\t"name": {_gd_string(room.name)},')
        lines.append(f'\t\t"scene": "res://scenes/campaign/rooms/{room.room_id}.tscn",')
        lines.append(f'\t\t"origin": Vector2i({room.origin[0]}, {room.origin[1]}),')
        lines.append(f'\t\t"size": Vector2i({room.width}, {room.height}),')
        lines.append(f'\t\t"saves": [{", ".join(saves)}],')
        lines.append(f'\t\t"refills": [{", ".join(refills)}],')
        lines.append(f'\t\t"gates": [{", ".join(gates)}],')
        lines.append(f'\t\t"doors": [{", ".join(room_doors)}],')
        lines.append(f'\t\t"pickups": [{", ".join(pickups)}],')
        mask = ", ".join(_gd_string(row) for row in _map_mask(room))
        lines.append(f'\t\t"map_mask": [{mask}],')
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    try:
        rooms = load_rooms()
    except LayoutError as error:
        print(f"layout error: {error}")
        return 1
    doors, errors = link_doors(rooms)
    errors += overlap_errors(rooms)
    if errors:
        for error in errors:
            print(f"layout error: {error}")
        return 1
    ROOM_DIR.mkdir(parents=True, exist_ok=True)
    stable_ids: dict[str, int] = {}
    for room in rooms.values():
        text = SceneWriter(room).build(stable_ids)
        (ROOM_DIR / f"{room.room_id}.tscn").write_text(text)
    INDEX_PATH.write_text(write_index(rooms, doors))
    try:
        subprocess.run(
            ["uv", "tool", "run", "--from", "gdtoolkit==4.5.0", "gdformat", str(INDEX_PATH)],
            check=False,
            capture_output=True,
        )
    except OSError:
        print("note: gdformat unavailable; run make format")
    print(f"built {len(rooms)} campaign rooms, {len([d for d in doors if d.target])} door openings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
