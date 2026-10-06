extends RefCounted
## Round 12 cases of the playtest agent (docs/features/playtest-agent.md, "Harness round 12"), run
## by tools/check_playtest_boss_rooms.gd in the real campaign rooms. Each fails on the round 11
## harness.
## vaults_03: stage 4 chains Rockfall straight after the Fault Slam's double jump, so the Rockfall
## telegraph starts with her in the air at the alcove roof's end, where no dodge was offered (a Jev
## room run took 2 of 2 Rockfall hits there). She now lands in place first and rolls under the roof.
## kiln_06: the route back west to kiln_02 from the lower half rolled the ball hop at (12, 21) off
## the platform under the door ledge, and from the row 5 platform the north steam held her with
## every hop cell passed (r11-full-s2 chose `go_to_door:west:kiln_02` 5,227 times).
## kiln_03: refill trips jumped the arena's east wall from its face and came down in the lava pit
## behind it (27 of 27 probe trips, 9 damage each); they now hop onto the wall and jump the pit.
## kiln_08: from under the rock slab over columns 20 to 24 her standing muzzle is inside it, yet
## the forward shot was offered (a Jev room run fired 676 bolts there for 240 s); the approach
## from the east pocket now rolls under the slab.
## kiln_01: rising through the steam from the ledge at (13, 10), her head stopped 5 px under the
## shaft's west wall, inside the steering dead zone, for 940 s (r12-full-s1b). Round 12's rooms
## change ended the steam inside its shaft, out of that rise; the route now climbs onto the rock
## step under the shaft and rides the steam from there.
## nexus_09: r12-full-s1 fought the Tollwing there for over 1,000 s after its objective timed out,
## on the way to later objectives; a boss the route's goal is not is passed by.

const Actions = preload("res://tools/playtest_actions.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
const CampaignMode = preload("res://tools/playtest_campaign.gd")
const TILE := 64.0
const KIT: Array[StringName] = [&"beam", &"slipstream", &"bombs", &"missiles", &"pressure_seal"]
## vaults_03 (room-local): the Fault Slam dodge's spot at the alcove roof's end, the Guardian's
## pursuit stop, and the frames the chain gets.
const SLAM_SPOT := Vector2(284, 960)
const GUARDIAN_STOP := Vector2(476, 868)
const CHAIN_FRAMES := 300
## kiln_06 starts (feet cells) and the frames each gets to reach kiln_02; the route's field for
## them (tools/playtest/campaign_route.py, full sweep, objective 21: kiln_02.spring_tide).
const KILN06_STARTS := [Vector2i(13, 21), Vector2i(16, 4)]
const KILN06_FRAMES := 900
const DIRECTORY := "user://playtest_round12_check"
const KILN06_FIELD := {
	"kiln_06:13:21:0": [63, [["kiln_06", 12, 21, 0, 0]]],
	"kiln_06:12:21:0": [62, [["kiln_06", 12, 21, 1, 0]]],
	"kiln_06:12:21:1":
	[
		56,
		[
			["kiln_06", 12, 21, 1, 1],
			["kiln_06", 11, 21, 1, 1],
			["kiln_06", 11, 20, 1, 1],
			["kiln_06", 11, 19, 1, 1],
			["kiln_06", 10, 19, 1, 1],
			["kiln_06", 10, 19, 0, 1],
			["kiln_06", 10, 19, 0, 0],
		]
	],
	"kiln_06:10:19:0": [32, [["kiln_06", 9, 19, 0, 0]]],
	"kiln_06:9:19:0": [31, [["kiln_06", 8, 19, 0, 0]]],
	"kiln_06:8:19:0": [30, [["kiln_06", 7, 19, 0, 0]]],
	"kiln_06:7:19:0": [29, [["kiln_06", 6, 19, 0, 0]]],
	"kiln_06:6:19:0": [28, [["kiln_06", 5, 19, 0, 0]]],
	"kiln_06:5:19:0": [27, [["kiln_06", 4, 19, 0, 0]]],
	"kiln_06:4:19:0": [26, [["kiln_06", 3, 19, 0, 0]]],
	"kiln_06:3:19:0": [25, [["kiln_06", 2, 19, 0, 0]]],
	"kiln_06:2:19:0": [24, [["kiln_06", 1, 19, 0, 0]]],
	"kiln_06:1:19:0": [23, [["kiln_06", 0, 19, 0, 0]]],
	"kiln_06:0:19:0": [22, [["kiln_02", 28, 19, 0, 0]]],
	"kiln_02:28:19:0": [0, []],
	"kiln_06:16:4:0": [44, [["kiln_06", 15, 4, 0, 0]]],
	"kiln_06:15:4:0": [43, [["kiln_06", 14, 4, 0, 0]]],
	"kiln_06:14:4:0": [42, [["kiln_06", 13, 4, 0, 0]]],
	"kiln_06:13:4:0": [41, [["kiln_06", 12, 4, 0, 0]]],
	"kiln_06:12:4:0": [40, [["kiln_06", 11, 4, 0, 0]]],
	"kiln_06:11:4:0":
	[
		39,
		[
			["kiln_06", 10, 4, 0, 0],
			["kiln_06", 9, 5, 0, 0],
			["kiln_06", 8, 6, 0, 0],
			["kiln_06", 7, 7, 0, 0],
			["kiln_06", 6, 8, 0, 0],
			["kiln_06", 5, 9, 0, 0],
			["kiln_06", 4, 10, 0, 0],
			["kiln_06", 3, 11, 0, 0],
			["kiln_06", 2, 12, 0, 0],
			["kiln_06", 1, 13, 0, 0],
			["kiln_06", 1, 14, 0, 0],
			["kiln_06", 1, 15, 0, 0],
			["kiln_06", 1, 16, 0, 0],
			["kiln_06", 1, 17, 0, 0],
			["kiln_06", 1, 18, 0, 0],
			["kiln_06", 1, 19, 0, 0],
		]
	],
}
## The route from the kiln_01 return step to nexus_03 (full sweep, objective 32): onto the rock step
## under the shaft, then straight up the steam; and its frames.
const KILN01_FIELD := {
	"kiln_01:13:10:0":
	[
		16,
		[
			["kiln_01", 13, 10, 0, 1],
			["kiln_01", 13, 9, 0, 1],
			["kiln_01", 13, 8, 0, 1],
			["kiln_01", 13, 7, 0, 0],
			["kiln_01", 14, 7, 0, 0],
			["kiln_01", 15, 7, 0, 0],
			["kiln_01", 15, 7, 0, 0],
		]
	],
	"kiln_01:15:7:0":
	[
		9,
		[
			["kiln_01", 15, 7, 0, 1],
			["kiln_01", 15, 6, 0, 1],
			["kiln_01", 15, 5, 0, 1],
			["kiln_01", 15, 4, 0, 0],
			["kiln_01", 15, 3, 0, 0],
			["kiln_01", 15, 2, 0, 0],
			["kiln_01", 15, 1, 0, 0],
			["kiln_01", 15, 0, 0, 0],
			["nexus_03", 15, 16, 0, 1],
		]
	],
	"nexus_03:13:15:0": [0, []],
}
const KILN01_FRAMES := 400
## kiln_03 floor columns the refill trip starts from (west of the Warden, and east of it) and the
## lava pit east of the arena wall (room-local x).
const REFILL_COLUMNS := [12, 40, 47]
const REFILL_FRAMES := 600
const PIT := Vector2(3328, 3456)
## kiln_08 (room-local): the Emberkite held where the Jev run fought it, the east pocket cell she
## fired from, and the frames the approach gets to pass under the slab (its west end at x 1280).
const KITE_SPOT := Vector2(1047, 868)
const POCKET := Vector2i(25, 14)
const SLAB_WEST := 1280.0
const APPROACH_FRAMES := 240

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
	GameState.collect_pickup("round12.quiver", &"missile_tank")
	await _test_slam_then_rockfall()
	for cell: Vector2i in KILN06_STARTS:
		await _test_kiln06_west(cell)
	await _test_kiln01_steam()
	for column: int in REFILL_COLUMNS:
		await _test_refill_over_wall(column)
	GameState.unlock_ability(&"wave_beam")
	GameState.set_active_beam(&"wave")
	await _test_kite_pocket()
	await _test_pass_tollwing()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _test_slam_then_rockfall() -> void:
	GameState.reset_health()
	_root.call("teleport", "vaults_03", SLAM_SPOT)
	await _frames(40)
	var boss := _player.get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	if boss == null:
		_check(false, "the vaults_03 Stone Guardian spawned")
		return
	var room := _root.get("current_room") as Node2D
	boss.call(&"set_test_stage", 4)
	_player.global_position = room.global_position + SLAM_SPOT
	_player.velocity = Vector2.ZERO
	for _frame in 10:
		boss.global_position = room.global_position + GUARDIAN_STOP
		boss.set("_attack_timer", 99.0)
		await _player.get_tree().physics_frame
	GameState.reset_health()
	var health := GameState.health
	var chain: Array[StringName] = [&"fault_slam", &"rockfall"]
	boss.set("_attack_chain", chain)
	boss.call(&"_start_telegraph")
	var driver := Programs.Driver.new()
	var in_air_offer := ""
	var hits := 0
	for _frame in CHAIN_FRAMES:
		var rockfall: bool = boss.get("_attack_id") == &"rockfall"
		if rockfall and boss.get("_attack_state") == &"idle":
			break
		var telegraph: bool = rockfall and boss.get("_attack_state") == &"telegraph"
		if driver.done() or (telegraph and in_air_offer.is_empty() and not _player.is_on_floor()):
			driver.release_all()
			var dodge := _dodge(String(boss.get("_attack_id")))
			if telegraph and in_air_offer.is_empty() and not _player.is_on_floor():
				in_air_offer = String(dodge.get("label", "none"))
			driver.start(dodge.get("program", Programs.idle()))
		driver.step()
		await _player.get_tree().physics_frame
		if GameState.health < health:
			hits += 1
		health = GameState.health
	driver.release_all()
	_check(
		not in_air_offer.is_empty() and in_air_offer != "none",
		(
			"in the air at the Rockfall telegraph after the Fault Slam a dodge is offered (%s)"
			% in_air_offer
		)
	)
	_check(
		hits == 0,
		"the stage 4 Fault Slam then Rockfall played by the dodges costs nothing (%d)" % hits
	)


## The offered `dodge:<attack>` entry, or {}.
func _dodge(attack: String) -> Dictionary:
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	return Actions.find(Actions.candidates(state, _player), "dodge:%s" % attack)


## Follows the route's own program from `cell` (every decision takes the route), as Jev did.
func _test_kiln06_west(cell: Vector2i) -> void:
	var arrived := await _follow(KILN06_FIELD, "kiln_02", "kiln_06", cell, KILN06_FRAMES)
	_check(arrived, "kiln_06 %s: the route back west reaches kiln_02" % cell)


func _test_kiln01_steam() -> void:
	var arrived := await _follow(
		KILN01_FIELD, "nexus_03", "kiln_01", Vector2i(13, 10), KILN01_FRAMES
	)
	_check(arrived, "kiln_01 (13, 10): the route over the step and up the steam reaches nexus_03")


## True when the route's own programs from `cell` in `room` bring her into `goal_room`.
func _follow(
	field: Dictionary, goal_room: String, room: String, cell: Vector2i, limit: int
) -> bool:
	_write_route(field, goal_room)
	GameState.reset_health()
	_root.call("teleport", room, Vector2((cell.x + 0.5) * TILE, (cell.y + 1) * TILE))
	await _frames(30)
	var campaign := CampaignMode.new()
	campaign.setup(ProjectSettings.globalize_path(DIRECTORY), _root, _player)
	campaign.progress.current = 0
	var driver := Programs.Driver.new()
	var arrived := false
	for _frame in limit:
		if String(_root.get("current_room_id")) == goal_room:
			arrived = true
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
	# kiln_02's crushers measure their travel two frames after it loads; leaving sooner errors.
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
		"kind": "pickup",
		"target": "check.kiln06",
		"room": goal_room,
		"cells": [],
		"grants": "",
		"abilities": [],
		"flags": [],
		"steps": 63,
		"field": "field_0.json",
	}
	var route_file := FileAccess.open(directory.path_join("route.json"), FileAccess.WRITE)
	route_file.store_string(JSON.stringify({"format": 1, "start": [], "objectives": [objective]}))
	route_file.close()


func _test_refill_over_wall(column: int) -> void:
	GameState.reset_health()
	_root.call("teleport", "kiln_03", Vector2((column + 0.5) * TILE, 15 * TILE))
	await _frames(30)
	var boss := _player.get_tree().get_first_node_in_group(&"campaign_boss") as Node2D
	if boss == null:
		_check(false, "the kiln_03 Cinder Warden spawned")
		return
	var room := _root.get("current_room") as Node2D
	boss.call(&"set_test_stage", 1)
	while GameState.spend_missile():
		pass
	var driver := Programs.Driver.new()
	var lava := 0
	var health := GameState.health
	var refilled := false
	for _frame in REFILL_FRAMES:
		if boss.get("_attack_state") == &"idle":
			boss.set("_attack_timer", 99.0)
		if driver.done():
			driver.release_all()
			if GameState.missile_count > 0:
				refilled = true
				break
			var state := State.new().snapshot(_root, _player, 1, 0.0)
			var runs: Array = Actions.candidates(state, _player).filter(
				func(entry: Dictionary) -> bool: return entry["kind"] == "go_to_refill"
			)
			driver.start(runs[0]["program"] if not runs.is_empty() else Programs.idle())
		driver.step()
		await _player.get_tree().physics_frame
		var x := _player.global_position.x - room.global_position.x
		if GameState.health < health and x > PIT.x - 32.0 and x < PIT.y + 32.0:
			lava += health - GameState.health
		health = GameState.health
	driver.release_all()
	_check(refilled, "kiln_03 column %d: the refill run reaches the quiver refill" % column)
	_check(
		lava == 0,
		"kiln_03 column %d: the refill run stays out of the lava pit (%d)" % [column, lava]
	)


func _test_kite_pocket() -> void:
	GameState.reset_health()
	_root.call("teleport", "kiln_08", Vector2((POCKET.x + 0.5) * TILE, (POCKET.y + 1) * TILE))
	await _frames(30)
	var boss := _player.get_tree().get_first_node_in_group(&"bosses") as Node2D
	if boss == null:
		_check(false, "the kiln_08 Emberkite spawned")
		return
	var room := _root.get("current_room") as Node2D
	await _hold_kite(boss, room, 5)
	var options := Actions.candidates(State.new().snapshot(_root, _player, 1, 0.0), _player)
	var shots: Array = options.filter(
		func(entry: Dictionary) -> bool: return entry["kind"] in ["shoot", "harpoon"]
	)
	_check(
		shots.is_empty(),
		"kiln_08 %s: no shot from a muzzle inside the slab (%s)" % [POCKET, Actions.public(shots)]
	)
	var driver := Programs.Driver.new()
	for _frame in APPROACH_FRAMES:
		if driver.done():
			driver.release_all()
			var state := State.new().snapshot(_root, _player, 1, 0.0)
			var approach := {}
			for entry: Dictionary in Actions.candidates(state, _player):
				if entry["kind"] == "approach":
					approach = entry
			if approach.is_empty():
				break
			if _player.is_ball:
				driver.start(Programs.StandFirst.new(approach["program"]))
			else:
				driver.start(approach["program"])
		driver.step()
		await _hold_kite(boss, room, 1)
	driver.release_all()
	var x := _player.global_position.x - room.global_position.x
	_check(
		x < SLAB_WEST and not _player.is_ball,
		"kiln_08: the approach from the east pocket passes under the slab and stands (x %d)" % x
	)


func _test_pass_tollwing() -> void:
	GameState.reset_health()
	_root.call("teleport", "nexus_09", Vector2(21.5 * TILE, 16 * TILE))
	await _frames(30)
	var boss := _player.get_tree().get_first_node_in_group(&"bosses") as Node2D
	if boss == null:
		_check(false, "the nexus_09 Tollwing spawned")
		return
	var room := _root.get("current_room") as Node2D
	for _frame in 5:
		boss.set("_attack_timer", 99.0)
		boss.global_position = room.global_position + Vector2(18.5 * TILE, 15 * TILE)
		await _player.get_tree().physics_frame
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	var route := [{"key": "go_to_objective", "kind": "go_to_objective", "label": "", "program": []}]
	var offered := Actions.public(Actions.candidates(state, _player, route))
	var policy := Policy.new(1)
	state["goal"] = {"kind": "visit", "target": "nexus_05", "room": "nexus_05", "gate_ahead": null}
	var passing := policy.heuristic(state, offered, false)
	state["goal"] = {"kind": "mini", "target": "tollwing", "room": "nexus_09", "gate_ahead": null}
	var fighting := policy.heuristic(state, offered, false)
	_check(
		passing == "go_to_objective" and fighting != "go_to_objective",
		(
			"nexus_09: the Tollwing is passed on the way elsewhere (%s) and fought as the goal (%s)"
			% [passing, fighting]
		)
	)


func _hold_kite(boss: Node2D, room: Node2D, count: int) -> void:
	for _index in count:
		boss.set("_attack_timer", 99.0)
		boss.global_position = room.global_position + KITE_SPOT
		await _player.get_tree().physics_frame


func _frames(count: int) -> void:
	for _index in count:
		await _player.get_tree().physics_frame
