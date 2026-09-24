"""Checks the D21 layout marks end to end: parsing and validation, scene emission, the graph
solver's conservative rules, and that Godot instantiates the generated room with working nodes.

    python3 tools/check_worldfx_layout.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_campaign_rooms as builder  # noqa: E402
from campaign_layout import ROOT, LayoutError, parse_layout  # noqa: E402
from check_campaign_graph import Solver, World, open_timed_doors  # noqa: E402

# 30 x 17 demo room. Row 16 is the bottom boundary; the start stands at the far left.
DEMO = """id: worldfx_demo
area: kiln
name: Living Demo
origin: 0 0
ambush: 2 1 11 8 wave=hopper,vent_flyer id=pit
current: 1 10 12 3 dir=right strength=240 kind=water
current: 19 2 4 8 dir=up strength=700 kind=steam
rising: 14 1 9 9 kind=lava safe=3
legend:
  @ start
  t timeddoor seconds=6 id=gate
  o switch door=t
  c crumble
  v stalactite
  k crusher offset=0.5
grid:
##############################
##...........#.v....kk.......#
##...........#......kk.......#
##...........#...............#
##...........#.........##....#
##...........#.........##....#
#o.#.........t..ccc....##....#
#............t.........##....#
#@...........t.........##....#
##############.........##....#
#.............################
#............................#
#............................#
##############################
##############################
##############################
##############################
"""

FAILURES: list[str] = []


def check(condition: bool, label: str) -> None:
    print(("  ok  " if condition else "  FAIL ") + label)
    if not condition:
        FAILURES.append(label)


def layout_room(text: str, name: str = "worldfx_demo"):
    folder = Path(tempfile.mkdtemp(prefix="worldfx-layout-"))
    path = folder / f"{name}.txt"
    path.write_text(text)
    return parse_layout(path)


def expect_error(text: str, fragment: str, label: str) -> None:
    try:
        layout_room(text)
    except LayoutError as error:
        check(fragment in str(error), f"{label} ({error})")
        return
    check(False, f"{label} (no error)")


def feet_cells(seen, room_id="worldfx_demo") -> set[tuple[int, int]]:
    return {(state[1], state[2]) for state in seen if state[0] == room_id}


def main() -> int:
    room = layout_room(DEMO)
    check(
        len(room.ambushes) == 1 and len(room.currents) == 2 and len(room.risings) == 1,
        "zones parse",
    )

    # --- validation -------------------------------------------------------------------------
    expect_error(
        DEMO.replace("  v stalactite", "  v stalactite\n  w stalactite").replace(
            "##...........#.........##....#\n#o.#.........t..ccc",
            "##....w......#.........##....#\n#o.#.........t..ccc",
        ),
        "hang from rock",
        "stalactite must hang from rock",
    )
    expect_error(
        DEMO.replace("strength=240", "strength=500"),
        "sideways current",
        "strong side current rejected",
    )
    expect_error(
        DEMO.replace("  o switch door=t", "  o switch door=x"),
        "switch",
        "switch door checked",
    )
    expect_error(DEMO.replace("safe=3", "safe=1"), "headroom", "flood needs headroom")
    expect_error(
        DEMO.replace("##...........#", "#............#"),
        "cells wide",
        "wide arena opening rejected",
    )

    expect_error(
        DEMO.replace("wave=hopper,vent_flyer", "wave=hopper wave3=hopper"),
        "without gaps",
        "ambush waves must be numbered without gaps",
    )
    expect_error(
        DEMO.replace("wave=hopper,vent_flyer", "wave=hopper wave2=lava_monster"),
        "never spawn",
        "ambush never spawns the lava monster",
    )
    expect_error(
        DEMO.replace("id=pit", "id=pit trigger=0,0,3,3"),
        "inside the arena",
        "ambush trigger must lie inside the arena",
    )

    # --- emission ---------------------------------------------------------------------------
    waves = builder.SceneWriter(
        layout_room(DEMO.replace("id=pit", "id=pit wave2=hopper,hopper trigger=5,5,6,4"))
    ).build({})
    check(
        'extra_waves = Array[PackedStringArray]([PackedStringArray("hopper", "hopper")])' in waves
        and waves.count("spawn_offsets = PackedVector2Array(") == 1
        and "trigger_rect = Rect2(" in waves,
        "second wave and trigger emitted",
    )
    scene = builder.SceneWriter(room).build({})
    check('[node name="Ambush_pit"' in scene, "ambush node emitted")
    check("door_rects = Array[Rect2]([Rect2(" in scene, "ambush seals its opening")
    check(
        '[node name="TimedDoor_gate"' in scene and "switch_offsets = PackedVector2Array(" in scene,
        "timed door with switch",
    )
    check(scene.count("crumble_floor.gd") == 1 and "cells = 3" in scene, "crumble row emitted")
    check("stalactite.gd" in scene and "crusher.gd" in scene, "stalactite and crusher emitted")
    check(
        scene.count("script = ExtResource") >= 9 and 'kind = &"steam"' in scene, "currents emitted"
    )
    check("rising_shaft.gd" in scene and "safe_line = 192" in scene, "rising shaft emitted")

    # --- solver -----------------------------------------------------------------------------
    world = World({room.room_id: room})
    start = (room.room_id, 1, 8, False, 0, 0)
    abilities = {"beam"}
    flags: set[str] = set()
    solver = Solver(world, abilities, flags, set())
    seen, _edges = solver.explore([start])
    cells = feet_cells(seen)
    covered = {(state[1], row) for state in seen for row in (state[2], state[2] - 1, state[2] - 2)}
    check((5, 8) in cells, "arena reachable up the side shaft")
    check(
        not any(x > 13 and y < 10 for x, y in cells),
        "timed door blocks the far side before the race",
    )
    opened = open_timed_doors(world, solver, seen, flags)
    check(
        opened and "timed:worldfx_demo:t" in flags,
        "switch shot within the countdown opens the door",
    )
    solver = Solver(world, abilities, flags, set())
    seen, _edges = solver.explore([start])
    cells = feet_cells(seen)
    covered = {(state[1], row) for state in seen for row in (state[2], state[2] - 1, state[2] - 2)}
    check((20, 9) in cells, "far side reachable once the door latches")
    check(not ({(20, 1), (21, 1), (20, 2), (21, 2)} & covered), "crusher footprint is solid")
    check((17, 5) in cells, "crumble ledge carries the player")
    drop = solver.neighbours((room.room_id, 17, 5, False, 0, 0))
    check((room.room_id, 17, 9, False, 0, 0) in drop, "crumble ledge can drop the player through")
    check((23, 3) in cells or (24, 3) in cells, "strong updraft lifts the player onto the pillar")
    still = World({room.room_id: room})
    still.updraft[room.room_id].clear()
    seen_still, _ = Solver(still, abilities, flags, set()).explore([start])
    check(not ({(23, 3), (24, 3)} & feet_cells(seen_still)), "the pillar top needs the updraft")
    # Too little time for the race: the door stays shut.
    world.timed[(room.room_id, "t")]["seconds"] = 0.4
    fresh: set[str] = set()
    solver = Solver(world, abilities, fresh, set())
    seen, _edges = solver.explore([start])
    open_timed_doors(world, solver, seen, fresh)
    check(not fresh, "a race longer than the countdown is not assumed")

    # --- Godot instantiation ----------------------------------------------------------------
    with tempfile.TemporaryDirectory(prefix="worldfx-scene-") as folder:
        scene_path = Path(folder) / "worldfx_demo.tscn"
        scene_path.write_text(scene)
        probe = Path(folder) / "probe.gd"
        probe.write_text(PROBE)
        godot = os.environ.get("GODOT", "godot")
        result = subprocess.run(
            [
                godot,
                "--headless",
                "--path",
                str(ROOT),
                "--script",
                str(probe),
                "--",
                str(scene_path),
                "--test-mode",
                f"--test-save-root={folder}",
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        output = result.stdout + result.stderr
        check(
            "PROBE PASS" in output and "SCRIPT ERROR" not in output,
            "Godot instantiates the generated room",
        )
        if "PROBE PASS" not in output or "SCRIPT ERROR" in output:
            print(output[-3000:])
    print("worldfx-layout: " + ("PASS" if not FAILURES else "FAIL"))
    return 1 if FAILURES else 0


PROBE = """extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var packed := load(path) as PackedScene
	var room := packed.instantiate()
	root.add_child(room)
	for _i in 5:
		await physics_frame
	var ambush = room.get_node("Entities/Ambush_pit")
	var door = room.get_node("Entities/TimedDoor_gate")
	var ok: bool = ambush.slabs.size() == 1 and ambush.wave.size() == 2 and door.switches.size() == 1
	ok = ok and get_nodes_in_group(&"worldfx_crumble").size() == 1
	ok = ok and get_nodes_in_group(&"worldfx_current").size() == 2
	ok = ok and get_nodes_in_group(&"worldfx_rising_shaft").size() == 1
	ok = ok and get_nodes_in_group(&"worldfx_crusher").size() == 1
	ok = ok and get_nodes_in_group(&"worldfx_stalactite").size() == 1
	ok = ok and door.flag() == "worldfx_demo.timed.gate" and ambush.flag() == "worldfx_demo.ambush.pit"
	print("PROBE PASS" if ok else "PROBE FAIL slabs=%d" % ambush.slabs.size())
	room.queue_free()
	await process_frame
	await process_frame
	quit()
"""


if __name__ == "__main__":
    sys.exit(main())
