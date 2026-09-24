extends Node

var _failures: Array[String] = []
var _level: Node
var _controller: Node
var _state: Node
var _store: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _is_isolated_test():
		_fail("run requires --test-mode and --test-save-root=<absolute path>")
		await _finish()
		return
	_state = get_tree().root.get_node_or_null("GameState")
	_store = get_tree().root.get_node_or_null("SaveStore")
	if _state == null or _store == null:
		_fail("GameState and SaveStore autoloads are required")
		await _finish()
		return
	var packed := load("res://scenes/levels/level_01.tscn") as PackedScene
	if packed == null:
		_fail("level_01.tscn could not be loaded")
		await _finish()
		return
	_level = packed.instantiate()
	get_tree().root.add_child(_level)
	await get_tree().process_frame
	await get_tree().process_frame
	_controller = _level
	if _level.get_tree().get_nodes_in_group("dev_room").size() != 10:
		_fail("dev world did not build for persistence test")
	else:
		await _test_boss_safety_and_disposable_selector()
		await _test_saved_boss_flag_and_runtime_rebuild()
		await _test_explicit_reset_and_hazard_bypass()
		await _test_map_and_world_discovery_persistence()
	await _finish()


func _test_boss_safety_and_disposable_selector() -> void:
	var arena := _controller.get("_arena_runtime") as DevRuntimeArena
	var origins: Dictionary = _controller.get("_room_origins")
	_expect(
		(
			arena != null
			and arena.arena_bounds("S9").has_point(origins["S9"] + Vector2(1024.0, 1151.0))
		),
		"enemy arena includes the real standing floor line",
	)
	_controller.call("_on_panel_action", &"preset", {"id": &"start"})
	_expect(_store.call("save_game") == OK, "isolated baseline save succeeds")
	_controller.call("_on_panel_action", &"boss", {"id": &"tidal_heart", "phase": 0})
	var player := _level.get_node("PlayerSpawn/Player") as Node2D
	var bosses := _level.get_tree().get_nodes_in_group("dev_boss")
	_expect(bosses.size() == 1, "explicit boss selector creates one test boss")
	if not bosses.is_empty():
		var boss := bosses[0] as Node2D
		_expect(
			player.global_position.distance_to(boss.global_position) >= 300.0,
			"boss selector leaves player outside contact detector"
		)
		_expect(
			bool(boss.get_meta("dev_explicit_test", false)),
			"selector marks disposable boss instance"
		)
	_state.call("reset_health")
	for _index in 4:
		await get_tree().physics_frame
	_expect(
		int(_state.get("health")) == int(_state.get("max_health")),
		"boss spawn causes no immediate contact damage"
	)
	_controller.call("_on_boss_defeated", &"tidal_heart")
	_expect(
		bool(_state.call("has_world_flag", "boss:tidal_heart")),
		"test defeat updates in-memory flag"
	)
	_expect(_store.call("load_game") == OK, "baseline load rejects disposable test victory")
	_expect(
		not bool(_state.call("has_world_flag", "boss:tidal_heart")),
		"disposable boss defeat is not autosaved"
	)
	_controller.call("_rebuild_runtime_content")
	_expect(
		_level.get_tree().get_nodes_in_group("dev_boss").size() == 3,
		"all three natural bosses return after baseline load"
	)


func _test_saved_boss_flag_and_runtime_rebuild() -> void:
	var return_point: Vector2 = _controller.get("_boss_arena_start")
	_expect(
		bool(_controller.call("_is_valid_checkpoint_spawn", "S8", return_point)),
		"S8 victory return checkpoint validates"
	)
	_controller.call("_on_boss_defeated", &"tidal_heart")
	_expect(
		bool(_state.call("has_world_flag", "boss:tidal_heart")), "default boss victory flag set"
	)
	_expect(_store.call("has_save"), "boss victory has durable save")
	_controller.call("_rebuild_runtime_content")
	_expect(
		_level.get_tree().get_nodes_in_group("dev_boss").size() == 2,
		"defeated Tidal boss stays absent while regional bosses remain"
	)
	_expect(_store.call("load_game") == OK, "saved boss flag loads")
	_controller.call("_rebuild_runtime_content")
	_expect(
		_level.get_tree().get_nodes_in_group("dev_boss").size() == 2,
		"saved Tidal defeat persists while regional bosses remain"
	)


func _test_explicit_reset_and_hazard_bypass() -> void:
	_controller.call("_on_panel_action", &"station", {"index": 8})
	_controller.call("_on_panel_action", &"reset", {"all": false})
	var reset_bosses := _level.get_tree().get_nodes_in_group("dev_boss")
	_expect(reset_bosses.size() == 1, "explicit S8 reset respawns disposable boss test instance")
	if not reset_bosses.is_empty():
		_expect(
			bool(reset_bosses[0].get_meta("dev_explicit_test", false)),
			"explicit reset does not clear saved defeat flag"
		)
	for room_id in ["S4", "S10"]:
		var index := int(_controller.get("station_ids").find(room_id))
		_controller.call("_teleport_station", index)
		_state.call("reset_health")
		for _frame in 4:
			await get_tree().physics_frame
		_expect(
			int(_state.get("health")) == int(_state.get("max_health")),
			"%s main floor bypass is safe" % room_id
		)
	var hazards := _level.get_tree().get_nodes_in_group("dev_optional_fixture")
	_expect(hazards.size() >= 2, "S4 and S10 hazards are explicit optional fixtures")


func _test_map_and_world_discovery_persistence() -> void:
	_controller.call("_teleport_station", 9)
	_controller.call("_on_room_subcell_entered", "S9-A")
	_controller.call("_on_room_subcell_entered", "S9-B")
	_controller.call("_on_room_subcell_entered", "S9-C")
	var map := _level.get_node_or_null("DevMap")
	_expect(map != null, "dev map exists in UI layer")
	if map != null:
		_expect(map.get("rooms").size() == 11, "map has S0-S10 nodes")
		_expect(map.get("connections").size() == 10, "map has true connected route edges")
		_expect(
			map.get("markers").has("S8") and map.get("markers").has("S9"),
			"map has checkpoint markers"
		)
		_expect(map.get_node_or_null("Miniature") != null, "map has readable miniature view")
	_expect(
		_state.call("has_world_flag", "boss:tidal_heart"),
		"world flag remains through map traversal"
	)
	_expect(_store.call("save_game") == OK, "map discovery save succeeds")
	_state.call("reset_progress")
	_expect(_store.call("load_game") == OK, "map discovery load succeeds")
	_expect(bool(_state.get("discovered_rooms").has("S9")), "S9 discovery persists")
	_expect(bool(_state.get("discovered_rooms").has("S9-A")), "S9-A discovery persists")
	_expect(bool(_state.get("discovered_rooms").has("S9-B")), "S9-B discovery persists")
	_expect(bool(_state.get("discovered_rooms").has("S9-C")), "S9-C discovery persists")
	_expect(String(_state.get("checkpoint").get("room", "")) == "S9", "S9 checkpoint persists")


func _is_isolated_test() -> bool:
	var has_mode := (
		OS.get_cmdline_args().has("--test-mode") or OS.get_cmdline_user_args().has("--test-mode")
	)
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--test-save-root="):
			return has_mode and argument.trim_prefix("--test-save-root=").is_absolute_path()
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_level):
		_level.free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("check_world_persistence: PASS")
		await TestShutdown.finish(get_tree(), 0)
		return
	for failure in _failures:
		push_error("check_world_persistence: " + failure)
	await TestShutdown.finish(get_tree(), 1)
