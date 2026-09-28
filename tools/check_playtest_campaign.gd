extends RefCounted
## Campaign mode cases of the playtest agent check (tools/check_playtest_agent.gd runs them in its
## scene): the next objective follows the route order under the live GameState, door routing
## over the real room index picks a valid path and respects gates, an objective that times out is
## set aside and a second timeout ends the run, the heuristic prefers the route's gate and
## objective over far enemies and far refills, and in a real room the navigator follows a flow
## field onto a ledge and the gate candidate opens a real harpoon socket, all through inputs.

const Route = preload("res://tools/playtest_route.gd")
const Nav = preload("res://tools/playtest_nav.gd")
const CampaignMode = preload("res://tools/playtest_campaign.gd")
const Progress = preload("res://tools/playtest_progress.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Actions = preload("res://tools/playtest_actions.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const State = preload("res://tools/playtest_state.gd")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const DIRECTORY := "user://playtest_campaign_check"
const ROOM_ID := "campaign_check"
## A floor with a three-tile block to climb, and room for a gate to its right.
const GRID := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#...........#####............#",
	"#...........#####............#",
	"#...........#####............#",
	"##############################",
]
const START := Vector2i(4, 8)
const BLOCK_TOP := Vector2i(14, 5)
const GATE_CELL := Vector2i(23, 6)
const GATE_FLAG := "check.gate.missile"

var _host: Node
var _root: Node
var _player: Player


func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	_test_next_objective()
	_test_door_route()
	_test_progress_timeout()
	_test_heuristic_prefers_the_route()
	await _test_in_a_real_room()
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


static func _objective(
	index: int, kind: String, target: String, grants: String, abilities: Array, flags: Array
) -> Dictionary:
	return {
		"index": index,
		"kind": kind,
		"target": target,
		"room": ROOM_ID,
		"cells": [],
		"grants": grants,
		"abilities": abilities,
		"flags": flags,
		"steps": 0,
		"field": "field_%d.json" % index,
	}


## Writes a route directory (route.json and one field per objective) and loads it.
func _route(objectives: Array, fields: Array) -> Route:
	var directory := ProjectSettings.globalize_path(DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	for index in objectives.size():
		var file := FileAccess.open(directory.path_join("field_%d.json" % index), FileAccess.WRITE)
		file.store_string(JSON.stringify(fields[index] if index < fields.size() else {}))
		file.close()
	var route_file := FileAccess.open(directory.path_join("route.json"), FileAccess.WRITE)
	route_file.store_string(JSON.stringify({"format": 1, "start": [], "objectives": objectives}))
	route_file.close()
	var route := Route.new()
	var problem := route.load_dir(directory)
	_check(problem.is_empty(), "the route fixture loads (%s)" % problem)
	return route


func _four_objectives() -> Route:
	return _route(
		[
			_objective(0, "pickup", "check.slipstream", "slipstream", [], []),
			_objective(1, "boss", "stone_guardian", "boss:stone_guardian", ["slipstream"], []),
			_objective(2, "pickup", "check.beam", "beam", ["slipstream"], ["boss:stone_guardian"]),
			_objective(3, "ending", "ending", "", ["slipstream", "beam"], ["boss:stone_guardian"]),
		],
		[]
	)


# --- planner ----------------------------------------------------------------------------------


func _test_next_objective() -> void:
	var route := _four_objectives()
	GameState.reset_progress()
	_check(route.next_index(false, {}) == 0, "a new game starts on the first objective")
	GameState.set_world_flag("boss:stone_guardian")
	_check(route.next_index(false, {}) == 0, "a flag alone does not skip the missing kit")
	GameState.reset_progress()
	GameState.collect_pickup("check.slipstream", &"slipstream")
	_check(route.next_index(false, {}) == 1, "with the Slipstream the boss is next")
	_check(
		route.next_index(false, {1: 1}) == 1,
		"a set-aside objective returns when it is the only one ready"
	)
	GameState.set_world_flag("boss:stone_guardian")
	_check(route.next_index(false, {}) == 2, "with the boss flag the beam is next")
	GameState.collect_pickup("check.beam", &"beam")
	_check(route.next_index(false, {}) == 3, "then the ending")
	_check(route.next_index(true, {}) == -1, "every objective done once the ending plays")
	_check(
		Route.describe(route.objectives[1]) == "defeat the Stone Guardian in %s" % ROOM_ID,
		"objectives read as plain language (%s)" % Route.describe(route.objectives[1])
	)


func _test_door_route() -> void:
	GameState.reset_progress()
	var path := Route.door_route("fringe_01", "fringe_03")
	_check(
		_valid(path, "fringe_01", "fringe_03"), "door route fringe_01 to fringe_03 (%s)" % [path]
	)
	_check(
		Route.door_route("nexus_01", "depths_01").is_empty(),
		"the sealed hub floor blocks the depths"
	)
	GameState.set_world_flag("regional:stone_guardian")
	GameState.set_world_flag("regional:furnace_mother")
	path = Route.door_route("nexus_01", "depths_01")
	_check(path == ["south:depths_01"], "both regional flags open the hub floor (%s)" % [path])
	GameState.reset_progress()
	path = Route.door_route("fringe_03", "fringe_04")
	_check(
		path.is_empty() or _valid(path, "fringe_03", "fringe_04"),
		"without a quiver no route crosses the harpoon socket (%s)" % [path]
	)
	GameState.collect_pickup("check.quiver", &"missile_tank")
	path = Route.door_route("fringe_03", "fringe_04")
	_check(path == ["east:fringe_04"], "with a quiver the socket door is taken (%s)" % [path])
	GameState.reset_progress()


## Every door exists in the room it leaves, is passable with the live kit, and the last one
## reaches `to`.
static func _valid(path: Array, from: String, to: String) -> bool:
	if path.is_empty():
		return false
	var room := from
	for id in path:
		var found: Dictionary = {}
		for door in Rooms.ROOMS[room]["doors"]:
			if "%s:%s" % [door["edge"], door["target"]] == id:
				found = door
		if found.is_empty() or not Route.door_open(found):
			return false
		room = String(found["target"])
	return room == to


func _test_progress_timeout() -> void:
	var route := _four_objectives()
	var telemetry := Telemetry.new()
	GameState.reset_progress()
	var progress := Progress.new()
	_check(progress.update(0.0, route, telemetry, 40, false).is_empty(), "the run starts")
	GameState.collect_pickup("check.slipstream", &"slipstream")
	progress.update(5.0, route, telemetry, 30, false)
	_check(
		progress.attempts.size() == 1 and progress.attempts[0]["outcome"] == "done",
		"a reached objective is recorded done (%s)" % [progress.attempts]
	)
	_check(progress.current == 1, "and the next one starts")
	var timeout := Progress.OBJECTIVE_TIMEOUT
	var first := progress.update(5.0 + timeout + 0.1, route, telemetry, 30, false)
	_check(
		first.is_empty() and progress.attempts[-1]["outcome"] == "timeout",
		"an objective past the timeout is recorded failed (%s)" % [progress.attempts[-1]]
	)
	progress.update(5.2 + timeout, route, telemetry, 30, false)
	var second := progress.update(5.3 + timeout * 2.0, route, telemetry, 30, false)
	_check(second == "objective_failed", "a second timeout ends the run (%s)" % second)
	var record := progress.finish(route, telemetry, false, second, {})
	_check(
		record["objectives_done"] == 1 and record["objectives"][1]["attempts"] == 2,
		"the record counts objectives and attempts (%s)" % [record["objectives"][1]]
	)
	GameState.reset_progress()


func _test_heuristic_prefers_the_route() -> void:
	var goal := {"kind": "pickup", "gate_ahead": null}
	var route := [
		{"key": "go_to_door:east:x", "kind": "go_to_door", "label": ""},
		{"key": "go_to_objective", "kind": "go_to_objective", "label": ""},
	]
	var gate := {"key": "open_gate:g", "kind": "open_gate", "label": ""}
	var far := _enemy(Vector2(900, 0))
	var shoot := {"key": "shoot:e1:forward", "kind": "shoot", "label": ""}
	var approach := {"key": "approach:e1", "kind": "approach", "label": ""}
	var refill := {"key": "go_to_refill:missilerefill", "kind": "go_to_refill", "label": ""}
	var state := _plain_state(goal, [])
	_check(_pick(state, route) == "go_to_objective", "the route beats a door off it")
	_check(_pick(state, route + [gate]) == "open_gate:g", "a gate on the route is opened first")
	state = _plain_state(goal, [far])
	_check(
		_pick(state, route + [shoot, approach]) == "go_to_objective",
		"a far enemy does not pull the player off the route"
	)
	state = _plain_state(goal, [])
	state["refills"] = [{"kind": "missilerefill", "restores": ["harpoons"], "rel": [120, 0]}]
	_check(_pick(state, route + [refill]) == "go_to_objective", "no bolt detour for a pickup")
	state["goal"] = {"kind": "boss", "gate_ahead": null}
	_check(_pick(state, route + [refill]) == refill["key"], "bolts are refilled for a boss")
	state["refills"][0]["rel"] = [2000, 0]
	_check(_pick(state, route + [refill]) == "go_to_objective", "a far refill is left alone")


static func _pick(state: Dictionary, offered: Array) -> String:
	var options: Array = [{"key": "idle", "kind": "idle", "label": ""}] + offered
	return Policy.new(1).heuristic(state, options, false)


static func _enemy(rel: Vector2) -> Dictionary:
	return {
		"id": "e1",
		"type": "hopper",
		"rel": [roundi(rel.x), roundi(rel.y)],
		"dist": roundi(rel.length()),
		"health": 40,
		"max_health": 40,
		"is_boss": false,
		"telegraph": false,
		"ambush": false,
		"hurt_by": ["beam"],
		"switch_to": "",
		"visible": true,
	}


static func _plain_state(goal: Dictionary, enemies: Array) -> Dictionary:
	return {
		"t": 1.0,
		"room": {"id": ROOM_ID},
		"player":
		{
			"health": 100,
			"max_health": 100,
			"grounded": true,
			"on_wall": false,
			"facing": 1,
			"form": "standing",
			"dash_ready": false,
			"cell": [4, 8],
		},
		"kit":
		{
			"abilities": ["beam", "missiles"],
			"beam": "base",
			"beams": ["base"],
			"missiles": 0,
			"max_missiles": 5
		},
		"enemies": enemies,
		"projectiles": [],
		"ambush": null,
		"exits": [],
		"pickups": [],
		"hazards": [],
		"refills": [],
		"goal": goal,
	}


# --- real room --------------------------------------------------------------------------------


func _test_in_a_real_room() -> void:
	var old_room: Node = _root.get("current_room")
	var old_id := String(_root.get("current_room_id"))
	var old_feet := _player.global_position
	_root.remove_child(old_room)
	var room := WorldFxTestbed.build_room(_root, &"fringe", GRID, ROOM_ID)
	_root.set("current_room", room)
	_root.set("current_room_id", ROOM_ID)
	await _test_navigator_climbs(room)
	await _test_gate_is_opened(room)
	room.queue_free()
	await _frames(2)
	_root.add_child(old_room)
	_root.set("current_room", old_room)
	_root.set("current_room_id", old_id)
	_player.reset_for_spawn(old_feet)
	await _frames(10)


## A hand-made flow field in the solver's format: walk right to the block, rise three rows
## beside it and step onto its top.
static func _climb_field() -> Dictionary:
	var field := {}
	var steps := 20
	for x in range(START.x, 11):
		field["%s:%d:8:0" % [ROOM_ID, x]] = [steps - x, [[ROOM_ID, x + 1, 8, 0, 0]]]
	field["%s:11:8:0" % ROOM_ID] = [
		8,
		[
			[ROOM_ID, 11, 8, 0, 1],
			[ROOM_ID, 11, 7, 0, 1],
			[ROOM_ID, 11, 6, 0, 1],
			[ROOM_ID, 11, 5, 0, 0],
			[ROOM_ID, 12, 5, 0, 0],
		]
	]
	field["%s:12:5:0" % ROOM_ID] = [2, [[ROOM_ID, 13, 5, 0, 0]]]
	field["%s:13:5:0" % ROOM_ID] = [1, [[ROOM_ID, 14, 5, 0, 0]]]
	field["%s:14:5:0" % ROOM_ID] = [0, []]
	return field


func _test_navigator_climbs(room: CampaignRoom) -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()
	_player.reset_for_spawn(WorldFxTestbed.feet(room, START))
	await _frames(10)
	_route([_objective(0, "pickup", "check.none", "", [], [])], [_climb_field()])
	var campaign := CampaignMode.new()
	campaign.setup(ProjectSettings.globalize_path(DIRECTORY), _root, _player)
	campaign.update(0.0, Telemetry.new())
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	state["goal"] = campaign.goal(state)
	_check(
		state["goal"]["route_status"] == "on_field" and state["goal"]["steps"] == 16,
		"the goal reads the flow field (%s)" % [state["goal"]]
	)
	var offered := Actions.public(Actions.candidates(state, _player, campaign.candidates(state)))
	var pick := Policy.new(1).heuristic(state, offered, false)
	_check(pick == "go_to_objective", "the heuristic follows the route (%s)" % pick)
	var follow := {"program": Nav.Follow.new(campaign.nav, _root, _player, 0, 1)}
	GameState.unlock_ability(&"slipstream")
	GameState.unlock_ability(&"bombs")
	var in_fringe_04 := state.duplicate(true)
	in_fringe_04["room"]["id"] = "fringe_04"
	var doors: Array = campaign._doors(in_fringe_04, {"room": "vaults_02"}, follow)
	_check(
		not doors.is_empty() and is_same(doors[0]["program"], follow["program"]),
		(
			"the route's door plays the route (%s)"
			% [doors.map(func(d): return [d["key"], d["label"]])]
		)
	)
	var driver := Programs.Driver.new()
	for _frame in 900:
		if driver.done():
			if campaign.nav.status == "at_goal":
				break
			driver.start(
				Nav.Follow.new(campaign.nav, _root, _player, 0, CampaignMode.FOLLOW_FRAMES)
			)
		driver.step()
		await _host.get_tree().physics_frame
	driver.release_all()
	await _frames(10)
	var where := Nav.Navigator.locate(_root, _player)
	_check(
		where["cell"].y == BLOCK_TOP.y and absi(where["cell"].x - BLOCK_TOP.x) <= 1,
		"inputs alone climb onto the block along the field (%s)" % [where["cell"]]
	)


func _test_gate_is_opened(room: CampaignRoom) -> void:
	var gate := AbilityGate.new()
	gate.gate_kind = &"missile"
	gate.flag_id = GATE_FLAG
	gate.gate_size = Vector2(64, 192)
	gate.position = (Vector2(GATE_CELL) + Vector2(0.5, 1.5)) * WorldFxTestbed.TILE
	WorldFxTestbed.entities(room).add_child(gate)
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.collect_pickup("check.quiver", &"missile_tank")
	GameState.reset_health()
	var field := {}
	for x in range(18, 27):
		field["%s:%d:8:0" % [ROOM_ID, x]] = [27 - x, [[ROOM_ID, x + 1, 8, 0, 0]]]
	field["%s:27:8:0" % ROOM_ID] = [0, []]
	_route([_objective(0, "pickup", "check.none", "", [], [])], [field])
	_player.reset_for_spawn(WorldFxTestbed.feet(room, Vector2i(19, 8)))
	await _frames(10)
	var campaign := CampaignMode.new()
	campaign.setup(ProjectSettings.globalize_path(DIRECTORY), _root, _player)
	campaign.update(0.0, Telemetry.new())
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	state["goal"] = campaign.goal(state)
	var options := Actions.candidates(state, _player, campaign.candidates(state))
	var pick := Policy.new(1).heuristic(state, Actions.public(options), false)
	_check(
		pick == "open_gate:%s" % GATE_FLAG, "the socket on the route is opened first (%s)" % pick
	)
	_check(state["goal"]["gate_ahead"] is Dictionary, "the goal names the gate ahead")
	var driver := Programs.Driver.new()
	driver.start(Actions.find(options, pick).get("program", []))
	while not driver.done():
		driver.step()
		await _host.get_tree().physics_frame
	driver.release_all()
	await _frames(40)
	_check(GameState.has_world_flag(GATE_FLAG), "a real harpoon through inputs opened the socket")
	gate.queue_free()
