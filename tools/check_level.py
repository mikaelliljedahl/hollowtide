#!/usr/bin/env python3
"""Check Level 01's ability-gated route on a discrete tile collision model.

The model follows the game's contract at tile scale: standing bodies occupy one
column by three empty cells, balls one by one; bodies may walk over supported
cells, fall through gaps, and standing bodies may jump up to three tiles with
six tiles of horizontal reach.  It intentionally checks collision along jump
arcs instead of treating all platforms as teleport-connected.
"""

from __future__ import annotations

import base64
import math
import re
import struct
import sys
from collections import deque
from pathlib import Path

TILE_SIZE = 64
STANDING_HEIGHT = 3
BALL_HEIGHT = 1
MAX_JUMP_RISE = 3
MAX_JUMP_RUN = 6
MAX_FALL_RUN = 6
JUMP_APEX = 4.0
JUMP_RISE_TIME = 0.4
GRAVITY_FALLING = 72.5  # 4640 px/s² in tile units
JUMP_FLIGHT_STEPS = 48

ROOT = Path(__file__).resolve().parents[1]
SCENE_PATH = ROOT / "scenes" / "levels" / "level_01.tscn"

State = tuple[int, int, int]  # x, supporting solid row, body height


class Level:
    def __init__(self, scene_path: Path):
        self.scene_path = scene_path
        text = scene_path.read_text(encoding="utf-8")
        self.solid = self._read_tilemap(text)
        if not self.solid:
            raise ValueError("CaveTiles has no tile data")
        self.width = max(x for x, _ in self.solid) + 1
        self.height = max(y for _, y in self.solid) + 1
        self.orb = self._read_cell_position(text, "Orb")
        self.weapon = self._read_cell_position(text, "WeaponPickup")
        self.crawler = self._read_cell_position(text, "Crawler")
        spawn = self._read_cell_position(text, "PlayerSpawn")
        self.spawn = (spawn[0], spawn[1], STANDING_HEIGHT)

    @staticmethod
    def _cell(value: float) -> int:
        # Object positions are authored at cell centers; floor maps center to
        # its containing tile. PlayerSpawn is on a cell boundary and remains
        # exact under same conversion.
        return math.floor(value / TILE_SIZE)

    @classmethod
    def _read_cell_position(cls, text: str, node_name: str) -> tuple[int, int]:
        match = re.search(
            rf'^\[node name="{re.escape(node_name)}"[^\n]*\]\nposition = '
            r"Vector2\((-?[0-9.]+), (-?[0-9.]+)\)",
            text,
            re.MULTILINE,
        )
        if match is None:
            raise ValueError(f"missing position for node {node_name}")
        return (cls._cell(float(match.group(1))), cls._cell(float(match.group(2))))

    @staticmethod
    def _signed16(value: int) -> int:
        return value - 0x10000 if value & 0x8000 else value

    @classmethod
    def _read_tilemap(cls, text: str) -> set[tuple[int, int]]:
        match = re.search(r'tile_map_data = PackedByteArray\("([^\"]+)"\)', text)
        if match is None:
            raise ValueError("CaveTiles tile_map_data not found")
        try:
            data = base64.b64decode(match.group(1), validate=True)
        except ValueError as error:
            raise ValueError("invalid PackedByteArray base64") from error

        # Godot serializes each TileMapLayer cell as 12 bytes:
        # encoded x (signed 16 in high word), encoded y (signed 16), tile id.
        record_count = len(data) // 12
        if record_count == 0 or len(data) - record_count * 12 > 3:
            raise ValueError("unexpected TileMapLayer cell-data length")
        cells: set[tuple[int, int]] = set()
        for offset in range(0, record_count * 12, 12):
            encoded_x, encoded_y, tile_id = struct.unpack_from("<III", data, offset)
            # Erased cells are retained as tombstones when Godot serializes
            # an edited TileMapLayer. They are not terrain.
            if tile_id == 0xFFFFFFFF:
                continue
            x = cls._signed16((encoded_x >> 16) & 0xFFFF)
            y = cls._signed16(encoded_y & 0xFFFF)
            cells.add((x, y))
        return cells

    def body_clear(self, x: int, floor_y: int, body_height: int) -> bool:
        top = floor_y - body_height
        return (
            0 <= x < self.width
            and top >= 0
            and floor_y <= self.height
            and all((x, y) not in self.solid for y in range(top, floor_y))
        )

    def valid_state(self, state: State) -> bool:
        x, floor_y, body_height = state
        return (x, floor_y) in self.solid and self.body_clear(x, floor_y, body_height)

    def fall_destination(self, x: int, source_floor: int, body_height: int) -> State | None:
        """Find first solid floor below source that body can land on."""
        for floor_y in range(source_floor + 1, self.height):
            if (x, floor_y) not in self.solid:
                continue
            candidate = (x, floor_y, body_height)
            if self.valid_state(candidate):
                return candidate
            # A solid row that intersects body prevents falling farther.
            return None
        return None

    def body_intersects_solid(self, x: int, feet_y: float, body_height: int) -> bool:
        top = feet_y - body_height
        bottom = feet_y
        first_row = max(0, math.floor(top))
        last_row = min(self.height - 1, math.ceil(bottom) - 1)
        for row in range(first_row, last_row + 1):
            if (x, row) in self.solid:
                solid_top = float(row)
                solid_bottom = solid_top + 1.0
                if min(bottom, solid_bottom) - max(top, solid_top) > 1e-6:
                    return True
        return False

    def jump_flight_time(self, rise: int) -> float:
        fall_distance = JUMP_APEX - float(rise)
        return JUMP_RISE_TIME + math.sqrt(2.0 * fall_distance / GRAVITY_FALLING)

    def jump_path_clear(self, source: State, target: State) -> bool:
        source_x, source_floor, body_height = source
        target_x, target_floor, target_height = target
        if body_height not in (STANDING_HEIGHT, BALL_HEIGHT) or target_height != body_height:
            return False
        rise = source_floor - target_floor
        if not 0 <= rise <= MAX_JUMP_RISE:
            return False
        flight_time = self.jump_flight_time(rise)
        for step in range(1, JUMP_FLIGHT_STEPS + 1):
            progress = step / JUMP_FLIGHT_STEPS
            t = flight_time * progress
            if t <= JUMP_RISE_TIME:
                feet_offset = -20.0 * t + 25.0 * t * t
            else:
                fall_t = t - JUMP_RISE_TIME
                feet_offset = -JUMP_APEX + 0.5 * GRAVITY_FALLING * fall_t * fall_t
            feet_y = float(source_floor) + feet_offset
            x_position = source_x + 0.5 + (target_x - source_x) * progress
            x_cell = math.floor(x_position)
            if self.body_intersects_solid(x_cell, feet_y, body_height):
                # Final sample touches target floor by design, not overlap.
                if step != JUMP_FLIGHT_STEPS:
                    return False
        return True

    def transition_cells(self, source: State, target: State) -> set[tuple[int, int]]:
        """Return cells occupied while taking one graph edge.

        A fall is continuous, so checking only supported landing states would
        miss pickups passed while dropping through a shaft. Jump samples also
        contribute transient body cells for the same reason.
        """
        source_x, source_floor, source_height = source
        target_x, target_floor, target_height = target
        cells: set[tuple[int, int]] = set()
        if target_floor > source_floor:
            for top in range(source_floor - source_height, target_floor - source_height + 1):
                cells.update((target_x, row) for row in range(top, top + source_height))
            return cells
        if source_height in (STANDING_HEIGHT, BALL_HEIGHT) and target_height == source_height:
            if abs(target_x - source_x) > 1 or target_floor != source_floor:
                rise = source_floor - target_floor
                if 0 <= rise <= MAX_JUMP_RISE:
                    flight_time = self.jump_flight_time(rise)
                    for step in range(JUMP_FLIGHT_STEPS + 1):
                        progress = step / JUMP_FLIGHT_STEPS
                        t = flight_time * progress
                        if t <= JUMP_RISE_TIME:
                            feet_offset = -20.0 * t + 25.0 * t * t
                        else:
                            fall_t = t - JUMP_RISE_TIME
                            feet_offset = -JUMP_APEX + 0.5 * GRAVITY_FALLING * fall_t * fall_t
                        x_cell = math.floor(source_x + 0.5 + (target_x - source_x) * progress)
                        top = math.floor(source_floor + feet_offset - source_height)
                        cells.update((x_cell, row) for row in range(top, top + source_height))
                    return cells
        cells.update((target_x, row) for row in range(target_floor - target_height, target_floor))
        return cells

    def transitions(self, state: State, standing_only: bool = False):
        x, floor_y, body_height = state
        # Slip transition preserves position and momentum. A standing state is
        # only emitted where both collision shapes fit.
        if not standing_only:
            other_height = BALL_HEIGHT if body_height == STANDING_HEIGHT else STANDING_HEIGHT
            other = (x, floor_y, other_height)
            if self.valid_state(other):
                yield other

        for direction in (-1, 1):
            next_x = x + direction
            if not self.body_clear(next_x, floor_y, body_height):
                continue
            if (next_x, floor_y) in self.solid:
                yield (next_x, floor_y, body_height)
            else:
                # Air control lets player continue across a drop while falling.
                # Check several cells in input direction, not just edge cell;
                # this is needed for pickups hanging inside a shaft.
                for landing_x in range(
                    next_x,
                    max(-1, next_x + direction * (MAX_FALL_RUN + 1)),
                    direction,
                ):
                    if (landing_x, floor_y) in self.solid:
                        continue
                    if not self.body_clear(landing_x, floor_y, body_height):
                        continue
                    fallen = self.fall_destination(landing_x, floor_y, body_height)
                    if fallen is not None:
                        yield fallen

        # Grounded and coyote jumps use the same base arc in both forms. Coyote
        # time does not add reachability from a supported graph state, so the
        # discrete model represents it with the same grounded jump edges.
        for target_floor in range(max(0, floor_y - MAX_JUMP_RISE), floor_y + 1):
            for target_x in range(max(0, x - MAX_JUMP_RUN), min(self.width, x + MAX_JUMP_RUN + 1)):
                target = (target_x, target_floor, body_height)
                if target == state or not self.valid_state(target):
                    continue
                if self.jump_path_clear(state, target):
                    yield target

    def reachable(self, allow_ball: bool) -> tuple[set[State], set[tuple[int, int]]]:
        start = self.spawn
        if not self.valid_state(start):
            raise ValueError(f"spawn is not a valid standing state: {start}")
        queue: deque[State] = deque([start])
        reached: set[State] = {start}
        reached_cells: set[tuple[int, int]] = set()
        while queue:
            state = queue.popleft()
            x, floor_y, body_height = state
            reached_cells.update((x, y) for y in range(floor_y - body_height, floor_y))
            for next_state in self.transitions(state, standing_only=not allow_ball):
                reached_cells.update(self.transition_cells(state, next_state))
                if next_state in reached:
                    continue
                reached.add(next_state)
                queue.append(next_state)
        return reached, reached_cells

    @staticmethod
    def cell_reached(reached_cells: set[tuple[int, int]], target: tuple[int, int]) -> bool:
        return target in reached_cells

    def ascii_map(
        self,
        reached_cells: set[tuple[int, int]],
        orb_reached: bool,
        weapon_reached: bool,
        gate_reached: bool,
        crawler_reached: bool,
    ) -> str:
        labels = {
            self.orb: "O" if orb_reached else "o",
            self.weapon: "W" if weapon_reached else "w",
            self.crawler: "C" if crawler_reached else "c",
        }
        gate_cell = (31, 17)
        lines = []
        for y in range(self.height):
            chars = []
            for x in range(self.width):
                cell = (x, y)
                if cell in self.solid:
                    char = "#"
                elif cell == gate_cell:
                    char = "G" if gate_reached else "g"
                elif cell in labels:
                    char = labels[cell]
                elif cell in reached_cells:
                    char = "R"
                else:
                    char = "."
                chars.append(char)
            lines.append(f"{y:02} {''.join(chars)}")
        return "\n".join(lines)


def main() -> int:
    scene_path = Path(sys.argv[1]) if len(sys.argv) > 1 else SCENE_PATH
    if not scene_path.is_absolute():
        scene_path = Path.cwd() / scene_path
    try:
        level = Level(scene_path)
        before_states, before_cells = level.reachable(allow_ball=False)
        orb_reached = level.cell_reached(before_cells, level.orb)
        after_states, after_cells = level.reachable(allow_ball=orb_reached)
        weapon_reached = orb_reached and level.cell_reached(after_cells, level.weapon)
        gate_reached = weapon_reached and any(
            body_height == BALL_HEIGHT and x == 31 and floor_y - body_height <= 17 < floor_y
            for x, floor_y, body_height in after_states
        )
        crawler_reached = gate_reached and level.cell_reached(after_cells, level.crawler)
        all_reached = orb_reached and weapon_reached and gate_reached and crawler_reached
        print(f"Scene: {scene_path}")
        print(f"Standing states from spawn: {len(before_states)}")
        print(f"Orb reached: {'YES' if orb_reached else 'NO'}")
        print(f"Weapon reached after orb: {'YES' if weapon_reached else 'NO'}")
        print(f"1-tile gap reached in ball form: {'YES' if gate_reached else 'NO'}")
        print(f"Crawler reached after gap: {'YES' if crawler_reached else 'NO'}")
        print("\nReachability map (R = body-reachable cell, G = ball gate):")
        print(
            level.ascii_map(after_cells, orb_reached, weapon_reached, gate_reached, crawler_reached)
        )
        if not all_reached:
            missing = [
                name
                for name, reached in (
                    ("orb", orb_reached),
                    ("weapon", weapon_reached),
                    ("gap", gate_reached),
                    ("crawler", crawler_reached),
                )
                if not reached
            ]
            print(f"\nFAIL: unreachable {', '.join(missing)}", file=sys.stderr)
            return 1
        print("\nPASS: complete route is reachable")
        return 0
    except (OSError, ValueError, struct.error) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
