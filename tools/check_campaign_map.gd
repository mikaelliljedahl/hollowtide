extends Node

## Campaign map check: silhouettes from the generated index, unexplored exits and ghost rooms,
## gate icons on blocked exits (missile, flag, final seal), seen pickups, a save round-trip of the
## discovered data, and a smoke run of the map screen plus the HUD minimap.
## godot --headless --path . res://tools/check_campaign_map.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Model = preload("res://scripts/campaign/campaign_map_model.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CampaignEntry.prepare_new_game()
	_check_index()
	_check_exits()
	_check_gates()
	_check_pickups()
	_check_save_round_trip()
	await _check_screens()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"campaign-map: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	get_tree().paused = false
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check_index() -> void:
	for room_id in Rooms.ROOMS:
		var data: Dictionary = Rooms.ROOMS[room_id]
		var mask: Array = data.get("map_mask", [])
		var size: Vector2i = data["size"]
		_check(mask.size() == size.y, "%s mask has one row per tile row" % room_id)
		var open := 0
		for row in mask:
			_check(String(row).length() == size.x, "%s mask rows match the room width" % room_id)
			for char in String(row):
				if char != "#":
					open += 1
		var geometry := Model.geometry(room_id)
		var area := 0
		for rect in geometry["air"]:
			area += int(rect.size.x * rect.size.y)
		_check(area == open, "%s air rectangles cover every open cell exactly" % room_id)
		_check(geometry["walls"].size() > 0, "%s has wall edges" % room_id)
		for door in data["doors"]:
			_check(door.has("gate") and door.has("gate_flag"), "%s doors carry gate info" % room_id)


func _check_exits() -> void:
	var start: Array = [Rooms.START_ROOM]
	var exits := Model.unexplored_exits(start)
	var targets: Array[String] = []
	for door in Rooms.ROOMS[Rooms.START_ROOM]["doors"]:
		targets.append(String(door["target"]))
	_check(exits.size() == targets.size(), "every door of the start room is an unexplored exit")
	for exit in exits:
		_check(targets.has(exit["target"]), "exit %s leads to a real neighbour" % exit["target"])
	var ghosts := Model.ghost_rooms(start)
	_check(not ghosts.has(Rooms.START_ROOM), "a visited room is never a ghost")
	for ghost in ghosts:
		_check(targets.has(ghost), "ghost %s was seen through a door" % ghost)
	var two: Array = ["fringe_01", "fringe_02"]
	for exit in Model.unexplored_exits(two):
		_check(not two.has(exit["target"]), "no unexplored exit into a visited room")
	_check(
		Model.unexplored_exits(["fringe_02"]).any(func(e): return e["target"] == "fringe_01"),
		"the way back counts as unexplored when its room was never entered"
	)
	var all: Array = Rooms.ROOMS.keys()
	_check(Model.unexplored_exits(all).is_empty(), "a fully explored map has no unexplored exits")
	_check(Model.ghost_rooms(all).is_empty(), "a fully explored map has no ghost rooms")
	var progress := Model.area_progress(two)
	_check(progress[&"fringe"].x == 2, "area progress counts visited fringe rooms")


func _check_gates() -> void:
	GameState.world_flags.clear()
	var exit := _exit_to(["fringe_03"], "fringe_04")
	_check(exit.get("blocked", false), "fringe_03 -> fringe_04 is blocked while the gate is shut")
	_check(exit.get("gate", &"") == &"missile", "that blocked exit shows the missile icon")
	GameState.set_world_flag("fringe_03.gate.missile_1")
	exit = _exit_to(["fringe_03"], "fringe_04")
	_check(not exit.get("blocked", true), "opening the missile gate clears the blocked icon")
	_check(exit.get("gate", &"x") == &"", "an open gate leaves a plain unexplored exit")
	var bomb := _exit_to(["fringe_04"], "fringe_05")
	_check(bomb.get("gate", &"") == &"bomb", "fringe_04 -> fringe_05 shows the bomb icon")
	var final := _exit_to(["nexus_01"], "depths_01")
	_check(final.get("gate", &"") == &"flag", "the final gate blocks the way to the depths")
	var seal := {}
	for gate in Model.gate_markers(["nexus_01"]):
		if gate["final"]:
			seal = gate
	_check(not seal.is_empty(), "the final seal has its own marker")
	GameState.set_world_flag("regional:stone_guardian")
	_check(Model.seal_progress(seal.get("flag", "")) == Vector2i(1, 2), "one boss lights one seal")
	_check(_exit_to(["nexus_01"], "depths_01").get("blocked", false), "one seal is not enough")
	GameState.set_world_flag("regional:furnace_mother")
	_check(not _exit_to(["nexus_01"], "depths_01").get("blocked", true), "both seals open it")
	var boss := {}
	for gate in Model.gate_markers(["vaults_03"]):
		if gate["kind"] == &"boss":
			boss = gate
	_check(not boss.is_empty() and not boss["defeated"], "a live boss has a marker")
	GameState.set_world_flag("boss:stone_guardian")
	for gate in Model.gate_markers(["vaults_03"]):
		if gate["kind"] == &"boss":
			_check(gate["defeated"], "a defeated boss stays marked as defeated")
	var undertow := _exit_to(["depths_01"], "depths_02")
	_check(
		undertow.get("gate", &"") == &"undertow", "depths_01 -> depths_02 shows the undertow icon"
	)
	GameState.world_flags.clear()


func _check_pickups() -> void:
	GameState.collected_pickup_ids.clear()
	var seen := Model.seen_pickups(["fringe_02"], GameState.collected_pickup_ids)
	_check(
		seen.any(func(p): return p["id"] == "fringe_02.slipstream"),
		"an item in a visited room shows"
	)
	_check(
		not Model.seen_pickups([], []).any(func(p): return true), "unvisited rooms reveal no items"
	)
	seen = Model.seen_pickups(["fringe_02"], ["fringe_02.slipstream"])
	_check(seen.is_empty(), "a collected item disappears from the map")


func _check_save_round_trip() -> void:
	CampaignEntry.prepare_new_game()
	for room_id in ["fringe_01", "fringe_02", "fringe_03"]:
		GameState.discover_room(room_id)
	GameState.set_world_flag("fringe_03.gate.missile_1")
	GameState.set_checkpoint("fringe_02", Vector2(17.5 * 64.0, 32 * 64.0))
	var before := Model.unexplored_exits(GameState.discovered_rooms)
	_check(SaveStore.save_game() == OK, "campaign save written")
	GameState.reset_progress()
	_check(GameState.discovered_rooms.is_empty(), "reset clears the discovered rooms")
	_check(SaveStore.load_game() == OK, "campaign save loaded")
	_check(
		GameState.discovered_rooms == ["fringe_01", "fringe_02", "fringe_03"],
		"discovered rooms survive the save"
	)
	var after := Model.unexplored_exits(GameState.discovered_rooms)
	_check(after == before, "unexplored exits (seen doors) are identical after loading")


func _check_screens() -> void:
	CampaignEntry.prepare_new_game()
	var root := CAMPAIGN.instantiate()
	add_child(root)
	for frame in 20:
		await get_tree().process_frame
	var map := root.get("map") as CanvasLayer
	var minimap := root.get("minimap") as CanvasLayer
	_check(map != null and minimap != null, "campaign root has a map and a minimap")
	if map == null or minimap == null:
		root.queue_free()
		return
	var plate := minimap.get_node_or_null("MinimapPlate") as Control
	_check(plate != null and plate.visible, "minimap shows during play")
	if plate != null:
		var rect := plate.get_global_rect()
		_check(rect.position.x > 960.0 and rect.position.y < 100.0, "minimap sits top-right")
		_check(rect.end.x <= 1920.0 and rect.size.x <= 280.0, "minimap stays small and on screen")
	map.call("open")
	for frame in 5:
		await get_tree().process_frame
	_check(map.visible and get_tree().paused, "map opens and pauses")
	_check(plate == null or not plate.visible, "minimap hides behind the map")
	_check(float(map.call("map_scale")) > 1.0, "map has a usable scale")
	map.call("close")
	for frame in 3:
		await get_tree().process_frame
	_check(not get_tree().paused, "closing the map resumes")
	minimap.set("enabled", false)
	await get_tree().process_frame
	_check(plate == null or not plate.visible, "minimap can be switched off in code")
	root.queue_free()
	await get_tree().process_frame


func _exit_to(discovered: Array, target: String) -> Dictionary:
	for exit in Model.unexplored_exits(discovered):
		if exit["target"] == target:
			return exit
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
