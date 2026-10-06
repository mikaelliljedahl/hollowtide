extends RefCounted
## Updraft stalls of round 10 (docs/features/playtest-agent.md), run by
## tools/check_playtest_boss_rooms.gd in the real campaign rooms. Each case plays the campaign
## loop itself through real inputs along the route solver's hops (taken from the r10 route
## fields) and checks that she gets past the updraft:
## - nexus_07: the vaults_09 water shaft lifts her to the lip of the nexus_07 updraft at (13, 12);
##   its 56 px body overlapped the wind zone, so she hovered 1 px off the floor 6 px short of the
##   hop's landing, inside the steering dead zone, for 140-580 s in every r10 run.
## - kiln_10: a kiln_05 hop toward (14, 4) rose into the kiln_05 steam, which carried her through
##   the north door into kiln_10's floor updraft; the hop had no cell there, so she was steered at
##   her own column and hovered 290 s until the Tollwing objective timed out.
## - kiln_08: the kiln_06 steam lifts her up through kiln_08's floor opening into the Emberkite
##   arena, where the fight's programs held no sideways move and she dropped straight back (a
##   0.7 s boss "attempt" in each r10 run). The loop leans her onto the floor beside it.

const Loop = preload("res://tools/playtest_loop.gd")
const CampaignMode = preload("res://tools/playtest_campaign.gd")
const Nav = preload("res://tools/playtest_nav.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const DIRECTORY := "user://playtest_updraft_check"
const TILE := 64.0
const LIMIT_FRAMES := 900
## r10-run3 field_5 (Updraft Cloak): vaults_09 (39, 3) up the water shaft to the nexus_07 lip.
const NEXUS_START := Vector2i(37, 3)
const NEXUS_GOAL := Vector2i(19, 12)
const NEXUS_HOP := [
	["vaults_09", 40, 3, 0, 0],
	["vaults_09", 40, 2, 0, 0],
	["vaults_09", 40, 1, 0, 0],
	["vaults_09", 40, 0, 0, 0],
	["nexus_07", 10, 16, 0, 1],
	["nexus_07", 10, 15, 0, 0],
	["nexus_07", 10, 14, 0, 0],
	["nexus_07", 10, 13, 0, 0],
	["nexus_07", 10, 12, 0, 0],
	["nexus_07", 11, 12, 0, 0],
	["nexus_07", 12, 12, 0, 0],
	["nexus_07", 13, 12, 0, 0],
]
## r10-run1 field_30 (Tollwing): the hop from kiln_05 (15, 7) toward (14, 4) under the kiln_05
## steam, and where the steam left her in kiln_10's floor updraft (room-local feet, x 938 as
## logged). The ride itself depends on timing, so the case plants the hop and places her there,
## with the room's enemies gone.
const KILN_START := Vector2i(15, 7)
const KILN_CARRIED := Vector2(938, 880)
const KILN_GOAL := Vector2i(10, 14)
const KILN_HOP := [
	["kiln_05", 15, 7, 0, 1],
	["kiln_05", 15, 6, 0, 1],
	["kiln_05", 15, 5, 0, 0],
	["kiln_05", 15, 4, 0, 0],
	["kiln_05", 14, 4, 0, 0],
]
const KILN_STEAM_HOP := [
	["kiln_05", 13, 3, 0, 0],
	["kiln_05", 13, 2, 0, 0],
	["kiln_05", 13, 1, 0, 0],
	["kiln_05", 13, 0, 0, 0],
	["kiln_10", 13, 16, 0, 1],
	["kiln_10", 13, 15, 0, 0],
	["kiln_10", 13, 14, 0, 0],
	["kiln_10", 12, 14, 0, 0],
]

var _host: Node
var _root: Node
var _player: Player


func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	var nexus := _row("nexus_07", 13, NEXUS_GOAL.x, 12)
	nexus["vaults_09:37:3:0"] = [3, [["vaults_09", 38, 3, 0, 0]]]
	nexus["vaults_09:38:3:0"] = [2, [["vaults_09", 39, 3, 0, 0]]]
	nexus["vaults_09:39:3:0"] = [1, NEXUS_HOP]
	var reached := await _follow(nexus, "vaults_09", NEXUS_START, "nexus_07", NEXUS_GOAL)
	_check(reached, "riding up to the nexus_07 lip, she leaves the updraft and goes on")
	var kiln := _row("kiln_10", 12, KILN_GOAL.x, 14)
	# East of the shaft the route crosses it over the steam (r10-run1 field_30).
	kiln["kiln_10:16:14:0"] = [
		6,
		[
			["kiln_10", 15, 14, 0, 0],
			["kiln_10", 14, 14, 0, 0],
			["kiln_10", 13, 14, 0, 0],
			["kiln_10", 12, 14, 0, 0],
		]
	]
	kiln["kiln_10:17:14:0"] = [7, [["kiln_10", 16, 14, 0, 0]]]
	kiln["kiln_05:15:7:0"] = [3, KILN_HOP]
	kiln["kiln_05:14:4:0"] = [2, [["kiln_05", 13, 4, 0, 0]]]
	kiln["kiln_05:13:4:0"] = [1, KILN_STEAM_HOP]
	reached = await _follow(kiln, "kiln_05", KILN_START, "kiln_10", KILN_GOAL, KILN_CARRIED)
	_check(reached, "carried by the kiln_05 steam into kiln_10, she steps out west of its shaft")
	var landed := 0
	for start_x in [13.8, 14.5, 15.2]:
		landed += 1 if await _rise_into_kiln_08(start_x) else 0
	_check(landed == 3, "rising into kiln_08 she lands beside its floor opening (%d of 3)" % landed)


## Rides the kiln_06 steam up into kiln_08 from `start_x` (tiles) with the loop playing a shot
## on the spot over and over, as r10's fight decisions did; true when she stands in kiln_08 within
## 4 s of arriving and never fell back.
func _rise_into_kiln_08(start_x: float) -> bool:
	_root.call("teleport", "kiln_06", Vector2(start_x * TILE, 4.0 * TILE))
	var loop := Loop.new(_root, _player, "heuristic", 1, [])
	var shots: Array = []
	for frame in 20:
		shots.append([&"fire_beam"] if frame % 4 == 0 else [])
	var arrived := -1
	var stood := false
	for frame in 420:
		if loop.driver.done():
			loop.current = {"key": "shoot:e1:forward", "kind": "shoot", "program": shots}
			loop.driver.start(shots)
		# The Emberkite's attacks are held: a telegraph would hand the choice back to the policy.
		for boss in _player.get_tree().get_nodes_in_group(&"bosses"):
			boss.set("_attack_timer", 99.0)
		loop.physics_step(1.0 / 60.0)
		await _player.get_tree().physics_frame
		var room := String(_root.get("current_room_id"))
		if room == "kiln_08" and arrived < 0:
			arrived = frame
		if arrived >= 0 and room != "kiln_08":
			break
		if arrived >= 0 and frame - arrived > 30 and _player.is_on_floor():
			stood = true
			break
		if arrived >= 0 and frame - arrived > 240:
			break
	loop.finish({})
	return stood and String(_root.get("current_room_id")) == "kiln_08"


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


## Field entries along row `y` of `room` from column `from` to the goal column `goal`, one cell
## per hop.
static func _row(room: String, from: int, goal: int, y: int) -> Dictionary:
	var field := {"%s:%d:%d:0" % [room, goal, y]: [0, []]}
	var step := signi(goal - from)
	for steps in range(1, absi(goal - from) + 1):
		var x := goal - step * steps
		field["%s:%d:%d:0" % [room, x, y]] = [steps, [[room, x + step, y, 0, 0]]]
	return field


## Plays the campaign loop from `start` in `room` along `field`; true when she stands at `goal` in
## `goal_room` within LIMIT_FRAMES. With `carried`, the hop from `start` is read first and she is
## then placed at `carried` in `goal_room`, as an updraft would carry her there.
func _follow(
	field: Dictionary,
	room: String,
	start: Vector2i,
	goal_room: String,
	goal: Vector2i,
	carried := Vector2.INF
) -> bool:
	_route(field, goal_room)
	_root.call("teleport", room, Vector2((start.x + 0.5) * TILE, (start.y + 1) * TILE))
	for _frame in 40:
		await _player.get_tree().physics_frame
	var campaign := CampaignMode.new()
	campaign.setup(ProjectSettings.globalize_path(DIRECTORY), _root, _player)
	if carried != Vector2.INF:
		campaign.update(0.0, Telemetry.new())
		campaign.nav.refresh(Nav.Navigator.locate(_root, _player), 0)
		_root.call("teleport", goal_room, carried)
		# Only the route moves her: a shot at the room's flyer drifts her out of the column.
		for _frame in 3:
			await _player.get_tree().physics_frame
		for enemy in _player.get_tree().get_nodes_in_group(&"enemies"):
			enemy.queue_free()
		await _player.get_tree().physics_frame
	var loop := Loop.new(_root, _player, "heuristic", 1, [])
	loop.campaign = campaign
	var arrived := false
	for _frame in LIMIT_FRAMES:
		campaign.update(loop.telemetry.now, loop.telemetry)
		loop.physics_step(1.0 / 60.0)
		await _player.get_tree().physics_frame
		if campaign.nav.status == "at_goal":
			arrived = true
			break
	loop.finish({})
	var where := Nav.Navigator.locate(_root, _player)
	print(
		(
			"  updraft %s -> %s: %s at %s %s"
			% [room, goal_room, "arrived" if arrived else "not there", where["room"], where["cell"]]
		)
	)
	return arrived and String(where["room"]) == goal_room and absi(where["cell"].x - goal.x) <= 1


func _route(field: Dictionary, goal_room: String) -> void:
	var directory := ProjectSettings.globalize_path(DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("field_0.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(field))
	file.close()
	var objective := {
		"index": 0,
		"kind": "pickup",
		"target": "check.updraft",
		"room": goal_room,
		"cells": [],
		"grants": "",
		"abilities": [],
		"flags": [],
		"steps": 12,
		"field": "field_0.json",
	}
	var route_file := FileAccess.open(directory.path_join("route.json"), FileAccess.WRITE)
	route_file.store_string(JSON.stringify({"format": 1, "start": [], "objectives": [objective]}))
	route_file.close()
