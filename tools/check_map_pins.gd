extends Node

## Map pin check: place / cycle / remove rules, the 12-pin limit, pins only on cells of explored
## rooms, a campaign save round-trip, old saves without the map_pins key, rejection of tampered
## pin data, and the map screen's cursor driven by the real fire_beam / fire_missile keys.
## godot --headless --path . res://tools/check_map_pins.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Model = preload("res://scripts/campaign/campaign_map_model.gd")
const Pins = preload("res://scripts/campaign/campaign_map_pins.gd")
const GameStateScript = preload("res://scripts/autoload/game_state.gd")
const SaveStoreScript = preload("res://scripts/save/save_store.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")

const SIZE := Vector2i(20, 12)

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_rules()
	_check_limit()
	_check_explored_only()
	_check_state()
	_check_saves()
	await _check_screen()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"map-pins: %s (%d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _failures.size()]
		)
	)
	get_tree().paused = false
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check_rules() -> void:
	var seen := ["a"]
	var pins := Pins.activated([], seen, "a", SIZE, Vector2i(3, 4))
	_check(pins.size() == 1 and pins[0]["kind"] == "return", "first activation places a return pin")
	pins = Pins.activated(pins, seen, "a", SIZE, Vector2i(3, 4))
	_check(pins.size() == 1 and pins[0]["kind"] == "danger", "second activation cycles to danger")
	pins = Pins.activated(pins, seen, "a", SIZE, Vector2i(3, 4))
	_check(pins[0]["kind"] == "item", "third activation cycles to item")
	pins = Pins.activated(pins, seen, "a", SIZE, Vector2i(3, 4))
	_check(pins[0]["kind"] == "return", "the cycle wraps back to return")
	var two := Pins.activated(pins, seen, "a", SIZE, Vector2i(5, 4))
	_check(two.size() == 2 and pins.size() == 1, "a second cell adds a pin; input is not mutated")
	var one := Pins.removed(two, "a", Vector2i(3, 4))
	_check(
		one.size() == 1 and one[0]["x"] == 5 and two.size() == 2,
		"remove drops only that cell's pin"
	)
	_check(Pins.removed(one, "a", Vector2i(9, 9)) == one, "removing an empty cell changes nothing")


func _check_limit() -> void:
	var pins: Array[Dictionary] = []
	for index in Pins.MAX_PINS:
		pins = Pins.activated(pins, ["a"], "a", SIZE, Vector2i(index, 0))
	_check(pins.size() == Pins.MAX_PINS, "twelve pins can be placed")
	var full := Pins.activated(pins, ["a"], "a", SIZE, Vector2i(0, 5))
	_check(full.size() == Pins.MAX_PINS, "a thirteenth pin is refused")
	full = Pins.activated(pins, ["a"], "a", SIZE, Vector2i(0, 0))
	_check(full[0]["kind"] == "danger", "a full set still cycles existing pins")
	full = Pins.activated(Pins.removed(pins, "a", Vector2i(0, 0)), ["a"], "a", SIZE, Vector2i(0, 5))
	_check(full.size() == Pins.MAX_PINS, "removing one frees a slot")


func _check_explored_only() -> void:
	_check(Pins.activated([], [], "a", SIZE, Vector2i.ZERO).is_empty(), "undiscovered room refused")
	_check(Pins.activated([], ["a"], "a", SIZE, SIZE).is_empty(), "cell outside the room refused")
	_check(
		Pins.activated([], ["a"], "a", SIZE, Vector2i(-1, 0)).is_empty(), "negative cell refused"
	)
	var start: Dictionary = Rooms.ROOMS[Rooms.START_ROOM]
	var inside := Vector2(start["origin"]) + Vector2(2.5, 3.5)
	var hit := Model.cell_at([Rooms.START_ROOM], inside)
	_check(
		hit.get("room", "") == Rooms.START_ROOM and hit.get("cell") == Vector2i(2, 3),
		"cell_at finds the local cell of a discovered room"
	)
	_check(Model.cell_at([], inside).is_empty(), "cell_at ignores rooms not yet entered")
	var ghost: String = Model.ghost_rooms([Rooms.START_ROOM])[0]
	var ghost_tile := Vector2(Rooms.ROOMS[ghost]["origin"]) + Vector2(1.5, 1.5)
	_check(
		Model.cell_at([Rooms.START_ROOM], ghost_tile).is_empty(),
		"a seen-but-unentered room is no target"
	)


func _check_state() -> void:
	var state = GameStateScript.new()
	state.reset_progress()
	state.discover_room("fringe_01")
	var pins := Pins.activated([], state.discovered_rooms, "fringe_01", SIZE, Vector2i(1, 1))
	_check(state.set_map_pins(pins) and state.map_pins == pins, "GameState stores valid pins")
	var foreign: Array[Dictionary] = [{"room": "fringe_09", "x": 1, "y": 1, "kind": "return"}]
	_check(not state.set_map_pins(foreign), "GameState refuses a pin in an undiscovered room")
	_check(state.map_pins == pins, "a refused list leaves the pins unchanged")
	state.reset_progress()
	_check(state.map_pins.is_empty(), "reset clears the pins")
	state.free()


func _check_saves() -> void:
	var root := _store_root()
	var state = GameStateScript.new()
	var store = SaveStoreScript.new()
	_check(store.set_test_state(state), "test state accepted")
	_check(store.configure_test_environment(root, &"campaign"), "campaign test root accepted")
	state.reset_progress()
	for room_id in ["fringe_01", "fringe_02"]:
		state.discover_room(room_id)
	var pins := Pins.activated([], state.discovered_rooms, "fringe_01", SIZE, Vector2i(4, 2))
	pins = Pins.activated(pins, state.discovered_rooms, "fringe_02", SIZE, Vector2i(7, 9))
	pins = Pins.activated(pins, state.discovered_rooms, "fringe_02", SIZE, Vector2i(7, 9))
	state.set_map_pins(pins)
	_check(store.save_game() == OK, "save with pins written")
	var path := root.path_join("campaign/slot_01.json")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(
		(
			written["schema_version"] == Catalog.SCHEMA_VERSION
			and (written["snapshot"]["map_pins"] as Array).size() == 2
		),
		"pins are stored as snapshot.map_pins without a schema bump"
	)
	state.reset_progress()
	_check(store.load_game() == OK, "save with pins loads")
	_check(state.map_pins == pins, "pins survive the save exactly (room, cell, kind, order)")
	_check(state.map_pins[0]["x"] is int, "loaded cells are integers again")

	var old: Dictionary = state.snapshot()
	old.erase("map_pins")
	_write_wrapper(path, Catalog.SCHEMA_VERSION, old)
	_check(store.load_game() == OK, "a v2 save from before map pins still loads")
	_check(state.map_pins.is_empty(), "an old save loads with no pins")
	_check(state.discovered_rooms.size() == 2, "the rest of the old save is intact")

	var legacy := {
		"version": Catalog.LEGACY_SCHEMA_VERSION,
		"abilities": [],
		"active_beam": "base",
		"energy_tanks": 0,
		"missile_tanks": 0,
		"max_health": Catalog.DEFAULT_MAX_HEALTH,
		"health": Catalog.DEFAULT_MAX_HEALTH,
		"max_missiles": 0,
		"missile_count": 0,
		"collected_ids": [],
		"world_flags": {},
		"discovered_rooms": ["fringe_01"],
		"checkpoint": {"room": "fringe_01", "x": 64.0, "y": 64.0},
	}
	state.set_map_pins(pins.slice(0, 1))
	_write_wrapper(path, Catalog.LEGACY_SCHEMA_VERSION, legacy)
	_check(store.load_game() == OK and state.map_pins.is_empty(), "a v1 save loads with no pins")
	_check(not state.snapshot().has("map_pins"), "a snapshot without pins omits the map_pins key")
	legacy["map_pins"] = []
	_check(not state.validate_snapshot(legacy), "v1 snapshots never carry map_pins")

	var good: Dictionary = state.snapshot()
	var pin := {"room": "fringe_01", "x": 1, "y": 1, "kind": "return"}
	var cases := {
		"a pin in an undiscovered room": [pin.merged({"room": "kiln_01"}, true)],
		"an unknown pin kind": [pin.merged({"kind": "treasure"}, true)],
		"a fractional cell": [pin.merged({"x": 1.5}, true)],
		"a negative cell": [pin.merged({"y": -1}, true)],
		"two pins on one cell": [pin, pin.merged({"kind": "danger"}, true)],
		"an extra pin key": [pin.merged({"note": "text"}, true)],
		"a missing pin key": [{"room": "fringe_01", "x": 1, "y": 1}],
		"a non-list value": {"pins": []},
	}
	var many: Array = []
	for index in Pins.MAX_PINS + 1:
		many.append(pin.merged({"x": index}, true))
	cases["thirteen pins"] = many
	for label in cases:
		var bad := good.duplicate(true)
		bad["map_pins"] = cases[label]
		_check(not state.validate_snapshot(bad), "snapshot with %s is rejected" % label)
	var fine := good.duplicate(true)
	fine["map_pins"] = [pin.merged({"x": 2.0}, true)]
	_check(state.validate_snapshot(fine), "whole-number floats from JSON are accepted")
	for file_name in ["slot_01.json", "slot_01.json.bak", "slot_01.json.tmp"]:
		DirAccess.remove_absolute(root.path_join("campaign").path_join(file_name))
	store.free()
	state.free()


func _check_screen() -> void:
	CampaignEntry.prepare_new_game()
	var root := CAMPAIGN.instantiate()
	add_child(root)
	for frame in 20:
		await get_tree().process_frame
	var map := root.get("map") as CanvasLayer
	var minimap := root.get("minimap") as CanvasLayer
	var room_id := String(root.get("current_room_id"))
	_check(GameState.discovered_rooms.has(room_id), "the start room is discovered")
	map.call("open")
	await get_tree().process_frame
	var origin := Vector2(Rooms.ROOMS[room_id]["origin"])
	map.call("focus", origin + Vector2(4.5, 5.5), 3.0)
	var target: Dictionary = map.call("cursor_target")
	_check(
		target.get("room", "") == room_id and target.get("cell") == Vector2i(4, 5),
		"the cursor snaps to the cell under the frame centre"
	)
	_press(KEY_X)
	_check(GameState.map_pins.size() == 1, "fire_beam on the map places a pin")
	_press(KEY_X)
	_check(
		GameState.map_pins.size() == 1 and GameState.map_pins[0]["kind"] == "danger",
		"fire_beam again cycles the pin"
	)
	await get_tree().process_frame
	_press(KEY_C)
	_check(GameState.map_pins.is_empty(), "fire_missile removes the pin")
	_press(KEY_X)
	var ghost: String = Model.ghost_rooms(GameState.discovered_rooms)[0]
	map.call("focus", Vector2(Rooms.ROOMS[ghost]["origin"]) + Vector2(1.5, 1.5), 3.0)
	_check((map.call("cursor_target") as Dictionary).is_empty(), "no target over unexplored rooms")
	_press(KEY_X)
	_check(GameState.map_pins.size() == 1, "fire_beam over an unexplored room places nothing")
	map.call("close")
	for frame in 3:
		await get_tree().process_frame
	_check(not get_tree().paused, "closing the map resumes")
	var plate := minimap.get_node_or_null("MinimapPlate") as Control
	_check(plate != null and plate.visible, "the minimap shows again after closing")
	root.queue_free()
	await get_tree().process_frame


func _press(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)


func _write_wrapper(path: String, schema: int, snapshot: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(
		JSON.stringify({"schema_version": schema, "domain": "campaign", "snapshot": snapshot})
	)
	file.close()


func _store_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-save-root="):
			return argument.trim_prefix("--test-save-root=").path_join("pins-store")
	return OS.get_cache_dir().path_join("hollowtide-pins-%d" % Time.get_ticks_usec())


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
