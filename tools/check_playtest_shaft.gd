extends RefCounted
## The nexus_07 shaft up into nexus_01 (docs/features/playtest-agent.md, section 29), run by
## tools/check_playtest_boss_rooms.gd in the real rooms. The PR 12 review run stood under it for
## 225 s after its jump fell back, and round 10's first smoke run jumped and fell back for 860 s:
## the loop let go of jump while the room faded in, which cut the north door's entry boost. Each
## case plays the campaign loop itself from the stand under the shaft (cell 33, 3) along the route
## solver's hop and checks that she stands in nexus_01; both fail when the loop lets go.

const Loop = preload("res://tools/playtest_loop.gd")
const CampaignMode = preload("res://tools/playtest_campaign.gd")
const DIRECTORY := "user://playtest_shaft_check"
const TILE := 64.0
const START := Vector2i(33, 3)
const GOAL := Vector2i(7, 31)
const LIMIT_FRAMES := 900
## The route solver's hop from START to GOAL (tools/playtest/campaign_route.py), the same with a
## plain jump or the High Jump: the game boosts a north door's entry (UP_ENTRY_SPEED in
## scripts/campaign/campaign_root.gd), which the solver counts as NORTH_ENTRY_RISE rows.
const HOP := [
	["nexus_07", 33, 2, 0, 1],
	["nexus_07", 33, 1, 0, 1],
	["nexus_07", 33, 0, 0, 1],
	["nexus_01", 3, 33, 0, 1],
	["nexus_01", 3, 32, 0, 1],
	["nexus_01", 3, 31, 0, 1],
	["nexus_01", 3, 30, 0, 0],
	["nexus_01", 4, 30, 0, 0],
	["nexus_01", 5, 30, 0, 0],
	["nexus_01", 6, 30, 0, 0],
	["nexus_01", 7, 31, 0, 0],
]

var _host: Node
var _root: Node
var _player: Player


func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	_check(await _follow(), "with the High Jump the campaign loop climbs into nexus_01")
	GameState.reset_progress()
	for id in [&"beam", &"slipstream", &"bombs"]:
		GameState.unlock_ability(id)
	GameState.collect_pickup("shaft.quiver", &"missile_tank")
	GameState.reset_health()
	_check(await _follow(), "with a plain jump the campaign loop climbs into nexus_01")
	for id in [&"ice_beam", &"high_jump", &"pressure_seal", &"wave_beam", &"undertow_dash"]:
		GameState.unlock_ability(id)


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


## Plays the campaign loop along HOP from START through real inputs; true when she stands at GOAL
## in nexus_01.
func _follow() -> bool:
	_route(
		{
			"nexus_07:%d:%d:0" % [START.x, START.y]: [HOP.size(), HOP],
			"nexus_01:%d:%d:0" % [GOAL.x, GOAL.y]: [0, []],
		}
	)
	_root.call("teleport", "nexus_07", Vector2((START.x + 0.5) * TILE, (START.y + 1) * TILE))
	for _frame in 40:
		await _player.get_tree().physics_frame
	# The campaign loop itself, as a run plays it: room changes end the running program.
	var campaign := CampaignMode.new()
	campaign.setup(ProjectSettings.globalize_path(DIRECTORY), _root, _player)
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
	return arrived and String(_root.get("current_room_id")) == "nexus_01"


func _route(field: Dictionary) -> void:
	var directory := ProjectSettings.globalize_path(DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("field_0.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(field))
	file.close()
	var objective := {
		"index": 0,
		"kind": "pickup",
		"target": "check.shaft",
		"room": "nexus_01",
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
