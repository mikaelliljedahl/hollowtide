extends RefCounted
## Round 13 cases of the playtest agent (docs/features/playtest-agent.md, "Harness round 13"), run
## by tools/check_playtest_boss_rooms.gd in the real campaign rooms. Each fails on the round 12
## harness.
## nexus_05: the one-tile chimneys over column 13 (rows 24-25 and 18-19) cost about 1,000 s per
## full run (r12-full-s2): the run off the lip stops in column 13, and steering for the solver's
## column 12 or 14 put her head under the rock beside the chimney, round after round.
## kiln_01: dropped through the nexus_03 floor hole, she lands beside the lava basin; the route
## back up past the step under the steam shaft fell back every time (2 of 16 probe drops got out).
## nexus_09: the Tollwing timed out unwon in every full run: the Shard Drop step left the arena,
## so the boss dropped its chains and opened no punish window, and in stage 2 the Peal Lane jump
## waited through the Harpoon window.

const Loop = preload("res://tools/playtest_loop.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
const CampaignMode = preload("res://tools/playtest_campaign.gd")
const Nav = preload("res://tools/playtest_nav.gd")
const TILE := 64.0
const KIT: Array[StringName] = [
	&"beam", &"bombs", &"missiles", &"pressure_seal", &"slipstream", &"wave_beam"
]
const DIRECTORY := "user://playtest_round13_check"
## The full route's field toward the Tollwing (objective 29) over both nexus_05 chimneys; a
## resting cell on row 17, above the upper one, is the goal here. Starts and frames.
const CHIMNEY_STARTS := [Vector2i(12, 29), Vector2i(14, 29), Vector2i(12, 23)]
const CHIMNEY_FRAMES := 900
const CHIMNEY_TOP := 17
const NEXUS05_FIELD := {
	"nexus_05:10:23:0":
	[
		32,
		[
			["nexus_05", 10, 23, 0, 1],
			["nexus_05", 10, 22, 0, 1],
			["nexus_05", 11, 22, 0, 1],
			["nexus_05", 12, 22, 0, 1],
			["nexus_05", 13, 22, 0, 1],
			["nexus_05", 13, 21, 0, 1],
			["nexus_05", 13, 20, 0, 0],
			["nexus_05", 13, 20, 0, 1],
			["nexus_05", 13, 19, 0, 1],
			["nexus_05", 13, 18, 0, 1],
			["nexus_05", 13, 17, 0, 0],
			["nexus_05", 14, 17, 0, 0],
			["nexus_05", 15, 17, 0, 0],
			["nexus_05", 16, 17, 0, 0]
		]
	],
	"nexus_05:10:29:0":
	[
		44,
		[
			["nexus_05", 10, 29, 0, 1],
			["nexus_05", 10, 28, 0, 1],
			["nexus_05", 11, 28, 0, 1],
			["nexus_05", 12, 28, 0, 1],
			["nexus_05", 13, 28, 0, 1],
			["nexus_05", 13, 27, 0, 1],
			["nexus_05", 13, 26, 0, 0],
			["nexus_05", 13, 26, 0, 1],
			["nexus_05", 13, 25, 0, 1],
			["nexus_05", 13, 24, 0, 1],
			["nexus_05", 13, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0]
		]
	],
	"nexus_05:11:23:0": [32, [["nexus_05", 12, 23, 0, 0]]],
	"nexus_05:11:29:0": [44, [["nexus_05", 12, 29, 0, 0]]],
	"nexus_05:12:23:0":
	[
		31,
		[
			["nexus_05", 12, 23, 0, 1],
			["nexus_05", 12, 22, 0, 1],
			["nexus_05", 13, 22, 0, 1],
			["nexus_05", 13, 21, 0, 1],
			["nexus_05", 13, 20, 0, 0],
			["nexus_05", 13, 20, 0, 0],
			["nexus_05", 13, 20, 0, 1],
			["nexus_05", 13, 19, 0, 1],
			["nexus_05", 13, 18, 0, 1],
			["nexus_05", 13, 17, 0, 0],
			["nexus_05", 14, 17, 0, 0],
			["nexus_05", 15, 17, 0, 0],
			["nexus_05", 16, 17, 0, 0]
		]
	],
	"nexus_05:12:29:0":
	[
		43,
		[
			["nexus_05", 12, 29, 0, 1],
			["nexus_05", 12, 28, 0, 1],
			["nexus_05", 13, 28, 0, 1],
			["nexus_05", 13, 27, 0, 1],
			["nexus_05", 13, 26, 0, 0],
			["nexus_05", 13, 26, 0, 0],
			["nexus_05", 13, 26, 0, 1],
			["nexus_05", 13, 25, 0, 1],
			["nexus_05", 13, 24, 0, 1],
			["nexus_05", 13, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0]
		]
	],
	"nexus_05:14:23:0":
	[
		31,
		[
			["nexus_05", 14, 23, 0, 1],
			["nexus_05", 13, 23, 0, 1],
			["nexus_05", 13, 22, 0, 1],
			["nexus_05", 13, 21, 0, 1],
			["nexus_05", 13, 20, 0, 0],
			["nexus_05", 13, 20, 0, 0],
			["nexus_05", 13, 20, 0, 1],
			["nexus_05", 13, 19, 0, 1],
			["nexus_05", 13, 18, 0, 1],
			["nexus_05", 13, 17, 0, 0],
			["nexus_05", 14, 17, 0, 0],
			["nexus_05", 15, 17, 0, 0],
			["nexus_05", 16, 17, 0, 0]
		]
	],
	"nexus_05:14:29:0":
	[
		43,
		[
			["nexus_05", 14, 29, 0, 1],
			["nexus_05", 13, 29, 0, 1],
			["nexus_05", 13, 28, 0, 1],
			["nexus_05", 13, 27, 0, 1],
			["nexus_05", 13, 26, 0, 0],
			["nexus_05", 13, 26, 0, 0],
			["nexus_05", 13, 26, 0, 1],
			["nexus_05", 13, 25, 0, 1],
			["nexus_05", 13, 24, 0, 1],
			["nexus_05", 13, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0]
		]
	],
	"nexus_05:15:23:0": [32, [["nexus_05", 14, 23, 0, 0]]],
	"nexus_05:15:29:0": [44, [["nexus_05", 14, 29, 0, 0]]],
	"nexus_05:16:23:0":
	[
		32,
		[
			["nexus_05", 16, 23, 0, 1],
			["nexus_05", 15, 23, 0, 1],
			["nexus_05", 14, 23, 0, 1],
			["nexus_05", 13, 23, 0, 1],
			["nexus_05", 13, 22, 0, 1],
			["nexus_05", 13, 21, 0, 1],
			["nexus_05", 13, 20, 0, 0],
			["nexus_05", 13, 20, 0, 1],
			["nexus_05", 13, 19, 0, 1],
			["nexus_05", 13, 18, 0, 1],
			["nexus_05", 13, 17, 0, 0],
			["nexus_05", 14, 17, 0, 0],
			["nexus_05", 15, 17, 0, 0],
			["nexus_05", 16, 17, 0, 0]
		]
	],
	"nexus_05:16:29:0":
	[
		44,
		[
			["nexus_05", 16, 29, 0, 1],
			["nexus_05", 15, 29, 0, 1],
			["nexus_05", 14, 29, 0, 1],
			["nexus_05", 13, 29, 0, 1],
			["nexus_05", 13, 28, 0, 1],
			["nexus_05", 13, 27, 0, 1],
			["nexus_05", 13, 26, 0, 0],
			["nexus_05", 13, 26, 0, 1],
			["nexus_05", 13, 25, 0, 1],
			["nexus_05", 13, 24, 0, 1],
			["nexus_05", 13, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0],
			["nexus_05", 12, 23, 0, 0]
		]
	],
	"nexus_05:12:17:0": [0, []],
	"nexus_05:13:17:0": [0, []],
	"nexus_05:14:17:0": [0, []],
	"nexus_05:15:17:0": [0, []],
	"nexus_05:16:17:0": [0, []],
	"nexus_05:17:17:0": [0, []],
}
## The full route's field from kiln_01 back to nexus_03 (objective 33: visit nexus_02), the drop
## spots she lands on from the nexus_03 hole (room-local feet), and the frames to climb out.
const KILN01_FIELD := {
	"kiln_01:12:10:0":
	[
		34,
		[
			["kiln_01", 12, 10, 0, 1],
			["kiln_01", 12, 9, 0, 1],
			["kiln_01", 12, 8, 0, 1],
			["kiln_01", 12, 7, 0, 0],
			["kiln_01", 13, 7, 0, 0],
			["kiln_01", 14, 7, 0, 0],
			["kiln_01", 15, 7, 0, 0]
		]
	],
	"kiln_01:13:10:0":
	[
		34,
		[
			["kiln_01", 13, 10, 0, 1],
			["kiln_01", 13, 9, 0, 1],
			["kiln_01", 13, 8, 0, 1],
			["kiln_01", 13, 7, 0, 0],
			["kiln_01", 14, 7, 0, 0],
			["kiln_01", 15, 7, 0, 0],
			["kiln_01", 15, 7, 0, 0]
		]
	],
	"kiln_01:14:12:0":
	[
		39,
		[
			["kiln_01", 14, 12, 0, 1],
			["kiln_01", 14, 11, 0, 1],
			["kiln_01", 14, 10, 0, 1],
			["kiln_01", 13, 10, 0, 1],
			["kiln_01", 13, 10, 0, 0]
		]
	],
	"kiln_01:15:7:0":
	[
		27,
		[
			["kiln_01", 15, 7, 0, 1],
			["kiln_01", 14, 7, 0, 1],
			["kiln_01", 14, 6, 0, 1],
			["kiln_01", 14, 5, 0, 1],
			["kiln_01", 14, 4, 0, 0],
			["kiln_01", 14, 3, 0, 0],
			["kiln_01", 14, 2, 0, 0],
			["kiln_01", 14, 1, 0, 0],
			["kiln_01", 14, 0, 0, 0],
			["nexus_03", 14, 16, 0, 1],
			["nexus_03", 14, 15, 0, 1],
			["nexus_03", 13, 15, 0, 1],
			["nexus_03", 13, 15, 0, 0]
		]
	],
	"nexus_03:13:15:0": [0, []],
}
const KILN01_STARTS := [Vector2(1000, 512), Vector2(924, 832)]
const KILN01_FRAMES := 900
## nexus_09: where the fight starts (the mini-boss return cell) and the frames it gets.
const TOLLWING_START := Vector2i(3, 15)
const TOLLWING_FRAMES := 3600

var _host: Node
var _root: Node
var _player: Player


func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	GameState.reset_progress()
	for id in KIT:
		GameState.unlock_ability(id)
	GameState.collect_pickup("round13.quiver", &"missile_tank")
	GameState.collect_pickup("round13.quiver2", &"missile_tank")
	GameState.set_active_beam(&"wave")
	for cell: Vector2i in CHIMNEY_STARTS:
		var feet := Vector2((cell.x + 0.5) * TILE, (cell.y + 1) * TILE)
		var top := await _follow(NEXUS05_FIELD, "nexus_05", feet, "", CHIMNEY_FRAMES)
		_check(top, "nexus_05 %s: the route climbs the column 13 chimneys to row 17" % cell)
	for feet: Vector2 in KILN01_STARTS:
		var out := await _follow(KILN01_FIELD, "kiln_01", feet, "nexus_03", KILN01_FRAMES)
		_check(out, "kiln_01 %s: the route climbs back past the step into nexus_03" % feet)
	await _test_tollwing()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


## True when the route's own programs from `feet` in `room` bring her into `goal_room`, or (with
## none) onto a resting cell at CHIMNEY_TOP or above.
func _follow(field: Dictionary, room: String, feet: Vector2, goal_room: String, limit: int) -> bool:
	_write_route(field, goal_room if not goal_room.is_empty() else room)
	GameState.reset_health()
	_root.call("teleport", room, feet)
	await _frames(30)
	var campaign := CampaignMode.new()
	campaign.setup(ProjectSettings.globalize_path(DIRECTORY), _root, _player)
	campaign.progress.current = 0
	var driver := Programs.Driver.new()
	var arrived := false
	for _frame in limit:
		var where := Nav.Navigator.locate(_root, _player)
		if goal_room.is_empty():
			arrived = bool(where["grounded"]) and (where["cell"] as Vector2i).y <= CHIMNEY_TOP
		else:
			arrived = String(_root.get("current_room_id")) == goal_room
		if arrived:
			break
		GameState.reset_health()
		if _root.get("_busy") != true and driver.done():
			driver.release_all()
			var state := State.new().snapshot(_root, _player, 1, 0.0)
			state["goal"] = campaign.goal(state)
			var route: Array = campaign.candidates(state)
			driver.start(route[0]["program"] if not route.is_empty() else Programs.idle())
		driver.step()
		await _player.get_tree().physics_frame
	driver.release_all()
	await _frames(30)
	return arrived


func _write_route(field: Dictionary, goal_room: String) -> void:
	var directory := ProjectSettings.globalize_path(DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("field_0.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(field))
	file.close()
	var objective := {
		"index": 0,
		"kind": "visit",
		"target": goal_room,
		"room": goal_room,
		"cells": [],
		"grants": "",
		"abilities": [],
		"flags": [],
		"steps": 44,
		"field": "field_0.json",
	}
	var route_file := FileAccess.open(directory.path_join("route.json"), FileAccess.WRITE)
	route_file.store_string(JSON.stringify({"format": 1, "start": [], "objectives": [objective]}))
	route_file.close()


## The heuristic plays the Tollwing from its return cell through the real decision loop.
func _test_tollwing() -> void:
	GameState.reset_health()
	var feet := Vector2((TOLLWING_START.x + 0.5) * TILE, (TOLLWING_START.y + 1) * TILE)
	_root.call("teleport", "nexus_09", feet)
	await _frames(30)
	var boss := _player.get_tree().get_first_node_in_group(&"bosses") as Node2D
	if boss == null:
		_check(false, "the nexus_09 Tollwing spawned")
		return
	var loop := Loop.new(_root, _player, "heuristic", 1, [])
	var won := false
	var frames := 0
	for frame in TOLLWING_FRAMES:
		frames = frame
		if not is_instance_valid(boss) or int(boss.get("health")) <= 0:
			won = true
			break
		if GameState.health <= 0:
			break
		loop.physics_step(1.0 / 60.0)
		await _player.get_tree().physics_frame
	loop.finish({})
	_check(won, "nexus_09: the heuristic beats the Tollwing (%d frames)" % frames)
	await _frames(30)


func _frames(count: int) -> void:
	for _index in count:
		await _player.get_tree().physics_frame
