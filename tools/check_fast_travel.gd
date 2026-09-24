extends Node

## Fast travel check: station index and rules, activation by walking onto a shrine, travel only
## between activated shrines (real move_up / jump / Esc input on the map's travel mode), the shared
## shrine menu offering Travel and Tide Sockets only when each is available, refusal
## during an ambush, a boss fight and a rising flood, the save round-trip of activated_stations,
## old saves without the key, tampered data, and the branch boss shortcut gates opening only after
## their own boss. godot --headless --path . res://tools/check_fast_travel.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const FastTravel = preload("res://scripts/campaign/fast_travel.gd")
const GameStateScript = preload("res://scripts/autoload/game_state.gd")
const SaveStoreScript = preload("res://scripts/save/save_store.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")

const TILE := 64.0
const SHORTCUTS := {
	"vaults_03": "boss:stone_guardian",
	"kiln_03": "boss:furnace_mother",
}

var _root: Node
var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_index()
	_check_rules()
	_check_state()
	_check_saves()
	await _check_runtime()
	await _check_blockers()
	await _check_shortcuts()
	await _check_old_save_resume()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print(
		(
			"fast-travel: %s (%d checks, %d failures)"
			% ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()]
		)
	)
	get_tree().paused = false
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check_index() -> void:
	var expected := 0
	for room_id in Rooms.ROOMS:
		expected += (Rooms.ROOMS[room_id]["saves"] as Array).size()
	var stations := FastTravel.stations()
	_check(stations.size() == expected and expected > 0, "every save shrine is a station")
	var ids: Array[String] = []
	for entry in stations:
		if not ids.has(entry["id"]):
			ids.append(entry["id"])
	_check(ids.size() == stations.size(), "station ids are unique")
	_check(not FastTravel.validated(ids).is_empty(), "generated ids pass save validation")
	var ordered := true
	for index in range(1, stations.size()):
		ordered = ordered and stations[index - 1]["tile"].x <= stations[index]["tile"].x
	_check(ordered, "stations are ordered west to east")
	var fringe := _station_in("fringe_02")
	_check(fringe["id"] == "fringe_02.save.17_31", "id is the shrine's layout cell")
	_check(FastTravel.station(fringe["id"])["room"] == "fringe_02", "station lookup by id")
	_check(
		FastTravel.station_near("fringe_02", fringe["position"] + Vector2(20, 0)) == fringe["id"],
		"station_near finds the shrine at a feet position"
	)
	_check(FastTravel.station_near("fringe_01", Vector2.ZERO).is_empty(), "no shrine, no station")


func _check_rules() -> void:
	var a := String(_station_in("fringe_02")["id"])
	var b := String(_station_in("nexus_01")["id"])
	var c := String(_station_in("kiln_01")["id"])
	_check(FastTravel.targets([], a).is_empty(), "nothing activated: no targets")
	_check(FastTravel.targets([a], a).is_empty(), "one activated shrine: nowhere to go")
	var targets := FastTravel.targets([a, b], a)
	_check(targets.size() == 1 and targets[0]["id"] == b, "the other activated shrine is a target")
	_check(FastTravel.targets([b, c], a).is_empty(), "no travel from a shrine never activated")
	_check(FastTravel.can_travel([a, b], a, b), "travel between two activated shrines")
	_check(not FastTravel.can_travel([a, b], a, c), "no travel to a shrine never activated")
	_check(not FastTravel.can_travel([a, b], a, a), "no travel to the shrine you stand on")
	_check(
		FastTravel.targets([a, b, "gone_09.save.1_1"], a).size() == 1,
		"an id the index no longer knows is never a target"
	)
	var cases := {
		"a duplicate id": [a, a],
		"a non-string id": [a, 3],
		"an id without a cell": ["fringe_02.save"],
		"an id with a word cell": ["fringe_02.save.x_y"],
		"an empty room part": [".save.1_2"],
		"a non-list value": {"ids": [a]},
	}
	var many: Array = []
	for index in FastTravel.MAX_STATIONS + 1:
		many.append("r.save.%d_1" % index)
	cases["too many ids"] = many
	for label in cases:
		_check(FastTravel.validated(cases[label]).is_empty(), "validation rejects %s" % label)
	_check(not FastTravel.validated(["gone_09.save.1_1"]).is_empty(), "unknown well-formed id kept")


func _check_state() -> void:
	var state = GameStateScript.new()
	state.reset_progress()
	var id := String(_station_in("fringe_02")["id"])
	_check(not state.snapshot().has("activated_stations"), "no stations: the key is omitted")
	_check(state.activate_station(id), "GameState activates a shrine")
	_check(not state.activate_station(id), "activating twice changes nothing")
	_check(not state.activate_station("not a station"), "a malformed id is refused")
	_check(state.activated_stations == [id], "only the valid shrine is stored")
	_check(state.snapshot()["activated_stations"] == [id], "snapshot carries activated_stations")
	state.reset_progress()
	_check(state.activated_stations.is_empty(), "reset clears the stations")
	state.free()


func _check_saves() -> void:
	var root := _store_root()
	var state = GameStateScript.new()
	var store = SaveStoreScript.new()
	_check(store.set_test_state(state), "test state accepted")
	_check(store.configure_test_environment(root, &"campaign"), "campaign test root accepted")
	state.reset_progress()
	state.discover_room("fringe_02")
	var ids: Array[String] = [_station_in("fringe_02")["id"], _station_in("nexus_01")["id"]]
	for id in ids:
		state.activate_station(id)
	state.set_map_pins([{"room": "fringe_02", "x": 3, "y": 4, "kind": "danger"}])
	_check(store.save_game() == OK, "save with stations written")
	var path := root.path_join("campaign/slot_01.json")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(
		(
			written["schema_version"] == Catalog.SCHEMA_VERSION
			and written["snapshot"]["activated_stations"] == ids
		),
		"stations are stored as snapshot.activated_stations without a schema bump"
	)
	state.reset_progress()
	_check(store.load_game() == OK, "save with stations and pins loads")
	_check(state.activated_stations == ids, "stations survive the save in order")
	_check(state.map_pins.size() == 1, "map pins survive next to the stations")

	var old: Dictionary = state.snapshot()
	old.erase("activated_stations")
	old.erase("map_pins")
	_write_wrapper(path, Catalog.SCHEMA_VERSION, old)
	_check(store.load_game() == OK, "a v2 save from before fast travel still loads")
	_check(state.activated_stations.is_empty(), "an old save loads with no stations")
	_check(state.discovered_rooms == ["fringe_02"], "the rest of the old save is intact")

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
	state.activate_station(ids[0])
	_write_wrapper(path, Catalog.LEGACY_SCHEMA_VERSION, legacy)
	_check(store.load_game() == OK and state.activated_stations.is_empty(), "v1 save: no stations")
	legacy["activated_stations"] = [ids[0]]
	_check(not state.validate_snapshot(legacy), "v1 snapshots never carry activated_stations")

	var good: Dictionary = state.snapshot()
	for label in ["a duplicate", "a number", "a bad id"]:
		var bad := good.duplicate(true)
		bad["activated_stations"] = {
			"a duplicate": [ids[0], ids[0]], "a number": [7], "a bad id": ["nexus_01"]
		}[label]
		_check(not state.validate_snapshot(bad), "snapshot with %s station is rejected" % label)
	for file_name in ["slot_01.json", "slot_01.json.bak", "slot_01.json.tmp"]:
		DirAccess.remove_absolute(root.path_join("campaign").path_join(file_name))
	store.free()
	state.free()


func _check_runtime() -> void:
	CampaignEntry.prepare_new_game()
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(30)
	var map := _root.get("map") as CanvasLayer
	var fringe := _station_in("fringe_02")
	var nexus := _station_in("nexus_01")
	var kiln := _station_in("kiln_01")

	# Walk onto the fringe_02 shrine: it saves and activates.
	_root.call("teleport", "fringe_02", fringe["position"] - Vector2(3 * TILE, 0))
	await _frames(40)
	Input.action_press(&"move_right")
	await _wait_for(func(): return GameState.activated_stations.has(fringe["id"]), 120)
	Input.action_release(&"move_right")
	_check(GameState.activated_stations == [fringe["id"]], "walking onto a shrine activates it")
	_check(SaveStore.has_save(), "the activating save reached disk")
	var prompt := _prompt_of(fringe)
	await _frames(20)
	_check(prompt != null and prompt.modulate.a < 0.05, "no travel prompt with one shrine")
	Input.action_press(&"move_up")
	await _frames(2)
	Input.action_release(&"move_up")
	await _frames(2)
	_check(not map.visible, "move_up at the only shrine opens nothing")
	_check(
		_same(_root.call("shrine_options", fringe["id"]), []),
		"a lone shrine without glyphs offers nothing"
	)

	# A second activated shrine makes the first one a travel point.
	GameState.discover_room("nexus_01")
	GameState.activate_station(nexus["id"])
	var targets: Array = _root.call("travel_targets", fringe["id"])
	_check(targets.size() == 1 and targets[0]["id"] == nexus["id"], "one target from fringe_02")
	_root.call("teleport", "fringe_02", fringe["position"])
	await _frames(40)
	prompt = _prompt_of(fringe)
	_check(prompt != null and prompt.modulate.a > 0.9, "the up chevron shows at a travel shrine")
	_check(
		not bool(_root.call("travel_to", fringe["id"], kiln["id"])),
		"travel to a shrine never activated is refused"
	)
	_check(
		not bool(_root.call("travel_to", nexus["id"], fringe["id"])),
		"travel from a shrine in another room is refused"
	)
	Input.action_press(&"move_up")
	await _frames(2)
	Input.action_release(&"move_up")
	await _frames(2)
	_check(bool(map.call("is_travel_mode")), "move_up at the shrine opens the travel map")
	_check(get_tree().paused, "the travel map pauses the game")
	_check(String(map.call("travel_selection")) == nexus["id"], "the only target is selected")
	_press_key(KEY_RIGHT)
	_check(String(map.call("travel_selection")) == nexus["id"], "stepping wraps over one target")
	_press_key(KEY_X)
	_check(GameState.map_pins.is_empty(), "fire_beam places no pin in travel mode")
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_check(not map.visible and not get_tree().paused, "Esc cancels travel and resumes")
	_check(_room() == "fringe_02", "cancelling stays in place")
	await _check_shrine_menu(fringe["id"], map)

	# Confirm with jump: fade, arrive standing on the nexus shrine, checkpoint and save there.
	GameState.apply_damage(30)
	Input.action_press(&"move_up")
	await _frames(2)
	Input.action_release(&"move_up")
	await _frames(2)
	_press_action(&"jump")
	await _wait_for(func(): return _room() == "nexus_01" and not bool(_root.get("_busy")), 240)
	_check(_room() == "nexus_01", "jump on the travel map travels to the selected shrine")
	var player := _root.get("player") as Node2D
	var room := _root.get("current_room") as Node2D
	var local := player.global_position - room.global_position
	_check(local.distance_to(nexus["position"]) < 48.0, "the player arrives on the target shrine")
	_check(String(GameState.checkpoint["room"]) == "nexus_01", "travel moves the checkpoint")
	_check(GameState.health == GameState.max_health, "arriving at a shrine refills like resting")
	_check(not get_tree().paused and not map.visible, "the game resumes after travel")
	GameState.reset_progress()
	_check(CampaignEntry.prepare_continue(), "continue after travel")
	_check(String(GameState.checkpoint["room"]) == "nexus_01", "travel saved the new checkpoint")
	_check(GameState.activated_stations.size() == 2, "both shrines stay activated on disk")


## Owning a glyph adds Tide Sockets: one shrine menu then lists both, and each choice opens its
## own screen. Without the glyph, Travel alone opens the map directly (checked above).
func _check_shrine_menu(from_id: String, map: CanvasLayer) -> void:
	var shrine_menu := _root.get("shrine_menu") as CanvasLayer
	var tide_menu := (_root.get("tide_hook") as Node).get("menu") as CanvasLayer
	_check(
		_same(_root.call("shrine_options", from_id), [&"travel"]),
		"a travel shrine without glyphs offers only Travel"
	)
	GameState.tide.collect(&"glyph_quickstring")
	_check(
		_same(_root.call("shrine_options", from_id), [&"travel", &"tide"]),
		"owning a glyph adds Tide Sockets"
	)
	await _tap_up()
	_check(bool(shrine_menu.call("is_open")), "move_up opens the shrine menu when both are offered")
	_check(get_tree().paused and not map.visible, "the shrine menu pauses and opens no map yet")
	_check(
		_same(shrine_menu.call("options"), [&"travel", &"tide"]),
		"the shrine menu lists Travel and Tide Sockets"
	)
	_check(not bool(shrine_menu.call("choose", &"missing")), "an option not offered is refused")
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_check(
		not bool(shrine_menu.call("is_open")) and not get_tree().paused,
		"Esc leaves the shrine menu and resumes"
	)
	await _tap_up()
	_check(bool(shrine_menu.call("choose", &"tide")), "Tide Sockets can be chosen")
	_check(
		bool(tide_menu.call("is_open")) and get_tree().paused and not map.visible,
		"choosing Tide Sockets opens the socket screen"
	)
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_check(
		not bool(tide_menu.call("is_open")) and not get_tree().paused,
		"Esc closes the socket screen and resumes"
	)
	await _tap_up()
	await _frames(2)
	_press_action(&"jump")
	await _frames(2)
	_check(
		not bool(shrine_menu.call("is_open")) and bool(map.call("is_travel_mode")),
		"jump on the focused Travel entry opens the travel map"
	)
	_check(get_tree().paused, "the travel map keeps the game paused")
	_press_key(KEY_ESCAPE)
	await _frames(3)
	_check(not map.visible and not get_tree().paused, "Esc from travel chosen in the menu resumes")
	GameState.tide.reset()


func _check_blockers() -> void:
	var vaults := _station_in("vaults_01")
	var fringe := _station_in("fringe_02")
	GameState.discover_room("vaults_01")
	GameState.activate_station(vaults["id"])
	_root.call("teleport", "vaults_01", vaults["position"])
	await _frames(30)
	_check(
		String(_root.call("travel_blocker")) == "", "nothing blocks travel at a quiet vaults shrine"
	)
	var arena := get_tree().get_first_node_in_group(&"worldfx_ambush") as AmbushArena
	_check(arena != null, "vaults_01 has an ambush arena around its shrine")
	if arena != null:
		for state in [AmbushArena.State.SEALING, AmbushArena.State.FIGHTING]:
			arena.state = state
			_check(String(_root.call("travel_blocker")) == "ambush", "ambush %d blocks" % state)
			_check(
				(_root.call("travel_targets", vaults["id"]) as Array).is_empty(),
				"no targets during an ambush"
			)
			_check(
				not bool(_root.call("travel_to", vaults["id"], fringe["id"])),
				"travel_to is refused during an ambush"
			)
			_check(not bool(_root.call("open_travel", vaults["id"])), "no travel map in an ambush")
			GameState.tide.collect(&"glyph_quickstring")
			_check(
				_same(_root.call("shrine_options", vaults["id"]), [&"tide"]),
				"during an ambush the shrine offers only Tide Sockets"
			)
			GameState.tide.reset()
		arena.state = AmbushArena.State.CLEARED
		_check(String(_root.call("travel_blocker")) == "", "a cleared ambush no longer blocks")
		arena.state = AmbushArena.State.ARMED

	GameState.collect_pickup("travel.missile", &"missile_tank")
	_root.call("teleport", "vaults_03", Vector2(6.5 * TILE, 15 * TILE))
	await _frames(30)
	_check(String(_root.call("travel_blocker")) == "boss", "a live boss in its arena blocks travel")

	_root.call("teleport", "depths_03", Vector2(3.5 * TILE, 8 * TILE))
	await _frames(20)
	var shaft := get_tree().get_first_node_in_group(&"worldfx_rising_shaft") as RisingShaft
	_check(shaft != null, "depths_03 has a rising shaft")
	if shaft != null:
		shaft.state = RisingShaft.State.ARMED
		_check(String(_root.call("travel_blocker")) == "", "a resting flood does not block")
		shaft.state = RisingShaft.State.RISING
		_check(String(_root.call("travel_blocker")) == "hazard", "a rising flood blocks travel")
		shaft.state = RisingShaft.State.ARMED


func _check_shortcuts() -> void:
	for flag in SHORTCUTS.values():
		GameState.set_world_flag(flag, false)
	for room_id in SHORTCUTS:
		var flag: String = SHORTCUTS[room_id]
		var other: String = SHORTCUTS.values()[1 - SHORTCUTS.keys().find(room_id)]
		_root.call("teleport", room_id, _gate_side(room_id))
		await _frames(10)
		var gate := _flag_gate(flag)
		_check(gate != null, "%s has a shortcut gate on %s" % [room_id, flag])
		if gate == null:
			continue
		_check(not bool(gate.get("is_open")), "%s shortcut is sealed before its boss" % room_id)
		GameState.set_world_flag(other)
		await _frames(2)
		_check(not bool(gate.get("is_open")), "%s shortcut ignores the other boss" % room_id)
		GameState.set_world_flag(other, false)
		GameState.set_world_flag(flag)
		await _frames(2)
		_check(bool(gate.get("is_open")), "%s shortcut opens after its boss" % room_id)
		_root.call("teleport", room_id, _gate_side(room_id))
		await _frames(10)
		gate = _flag_gate(flag)
		_check(gate != null and bool(gate.get("is_open")), "%s shortcut stays open" % room_id)
		GameState.set_world_flag(flag, false)


func _check_old_save_resume() -> void:
	# A slot written at a shrine before fast travel existed: the shrine counts once resumed.
	var kiln := _station_in("kiln_01")
	GameState.reset_progress()
	GameState.discover_room("kiln_01")
	GameState.set_checkpoint("kiln_01", kiln["position"])
	_check(SaveStore.save_game() == OK, "old-style slot written")
	_root.queue_free()
	await get_tree().process_frame
	GameState.reset_progress()
	_check(CampaignEntry.prepare_continue(), "old-style slot continues")
	_check(GameState.activated_stations.is_empty(), "the old slot has no stations")
	_root = CAMPAIGN.instantiate()
	add_child(_root)
	await _frames(20)
	_check(_room() == "kiln_01", "resumed at the kiln shrine")
	_check(GameState.activated_stations == [kiln["id"]], "the resumed shrine is activated")
	_root.queue_free()
	await get_tree().process_frame


func _gate_side(room_id: String) -> Vector2:
	# Standing spot on the boss-room side of each shortcut gate, clear of the boss arena.
	return (
		Vector2(25.5 * TILE, 15 * TILE)
		if room_id == "vaults_03"
		else Vector2(4.5 * TILE, 15 * TILE)
	)


func _flag_gate(flag: String) -> Node:
	for node in get_tree().get_nodes_in_group(&"campaign_flag_gate"):
		if (node.get("required_flags") as PackedStringArray).has(flag):
			return node
	return null


func _station_in(room_id: String) -> Dictionary:
	for entry in FastTravel.stations():
		if entry["room"] == room_id:
			return entry
	return {}


func _prompt_of(station: Dictionary) -> Node2D:
	for node in get_tree().get_nodes_in_group(&"campaign_station"):
		if node.has_method("station_id") and node.call("station_id") == station["id"]:
			return node.get_node_or_null("ShrinePrompt") as Node2D
	return null


## Same entries in the same order; never relies on sorting.
func _same(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if StringName(actual[index]) != StringName(expected[index]):
			return false
	return true


func _tap_up() -> void:
	Input.action_press(&"move_up")
	await _frames(2)
	Input.action_release(&"move_up")
	await _frames(2)


func _room() -> String:
	return String(_root.get("current_room_id")) if is_instance_valid(_root) else ""


func _press_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)


func _press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
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
			return argument.trim_prefix("--test-save-root=").path_join("travel-store")
	return OS.get_cache_dir().path_join("hollowtide-travel-%d" % Time.get_ticks_usec())


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


func _wait_for(condition: Callable, max_frames: int) -> void:
	for frame in max_frames:
		if condition.call():
			return
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
