extends Node2D
class_name DevController
const DEV_PANEL_SCRIPT = preload("res://scripts/ui/dev_panel.gd")
const DEV_ROOM_SCRIPT = preload("res://scripts/dev/dev_room.gd")
const DEV_MAP_SCRIPT = preload("res://scripts/dev/dev_map.gd")
const OVERLAY_SCRIPT = preload("res://scripts/dev/dev_overlay.gd")
const STATION_LAYOUT = preload("res://scripts/dev/dev_station_layout.gd")
const DEV_RUNTIME_ARENA = preload("res://scripts/dev/dev_runtime_arena.gd")
const DEV_RUNTIME_CHECKPOINT = preload("res://scripts/dev/dev_runtime_checkpoint.gd")
const DEV_RUNTIME_PANEL = preload("res://scripts/dev/dev_runtime_panel.gd")
const DEV_RUNTIME_ROOM = preload("res://scripts/dev/dev_runtime_room.gd")
const ROOM_WIDTH := 32
const ROOM_FLOOR_Y := 18
const TILE_SIZE := 64
const ANNEX_START_X := 60
const ROOM_ORIGIN_Y := 0
const PROTOTYPE_SPAWN := Vector2(3360.0, 448.0)
const SAFE_BOSS_DISTANCE := 300.0
const SAFE_HAZARD_MARGIN := Vector2(48.0, 96.0)
const WORLD_CONNECTIONS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 2),
	Vector2i(2, 3),
	Vector2i(3, 4),
	Vector2i(4, 5),
	Vector2i(5, 6),
	Vector2i(6, 7),
	Vector2i(7, 8),
	Vector2i(8, 9),
	Vector2i(9, 10),
]
var station_ids: Array[String] = ["S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10"]
var _station_names: Array[String] = [
	"S0 · Original Cave",
	"S1 · Movement",
	"S2 · Shooting Range",
	"S3 · Ball / Pulse",
	"S4 · Energy / Protection",
	"S5 · Bubble Snare",
	"S6 · Undertow Dash",
	"S7 · Bestiary",
	"S8 · Boss Arena",
	"S9 · World Test",
	"S10 · Graphics Test",
]
var _room_kinds := {
	"S1": "movement",
	"S2": "range",
	"S3": "bomb",
	"S4": "health",
	"S5": "freeze",
	"S6": "undertow",
	"S7": "enemy",
	"S8": "boss",
	"S9": "world",
	"S10": "graphics",
}
var _room_origins: Dictionary = {}
var _station_baselines: Dictionary = {}
var _session_baseline: Dictionary = {}
var _current_room := "S0"
var _current_station := 0
var _panel: CanvasLayer
var _map: CanvasLayer
var _overlay: CanvasLayer
var _player: Node2D
var _cave: TileMapLayer
var _cave_visuals: Node2D
var _checkpoint_near := false
var _cheat_ammo := false
var _overlay_enabled := false
var _boss_arena_start := Vector2.ZERO
var _last_status := ""
var _arena_runtime: DevRuntimeArena
var _checkpoint_runtime: DevRuntimeCheckpoint
var _panel_runtime: DevRuntimePanel
var _room_runtime: DevRuntimeRoom


func _ready() -> void:
	_player = get_node_or_null("PlayerSpawn/Player") as Node2D
	_cave = get_node_or_null("CaveTiles") as TileMapLayer
	_cave_visuals = get_node_or_null("CaveVisuals") as Node2D
	_arena_runtime = DEV_RUNTIME_ARENA.new()
	_arena_runtime.configure(self, _room_origins, _player)
	_checkpoint_runtime = DEV_RUNTIME_CHECKPOINT.new()
	_checkpoint_runtime.configure(self, station_ids, _player, _cave, _room_origins)
	_panel_runtime = DEV_RUNTIME_PANEL.new()
	_panel_runtime.configure(self, _station_baselines, _session_baseline)
	_room_runtime = DEV_RUNTIME_ROOM.new()
	_room_runtime.configure(self)
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
	if not _dev_enabled():
		_configure_cave_visuals()
		_room_runtime.route_room("S0")
		return
	var dependency_error := _dependency_error()
	if dependency_error != "":
		_create_panel()
		_set_status(dependency_error)
		return
	_build_dev_world()
	_room_runtime.route_room("S0")
	_session_baseline = GameState.snapshot()
	_panel_runtime.configure(self, _station_baselines, _session_baseline)
	_capture_station_baselines()
	_create_panel()
	_set_status("Dev track ready. Original cave preserved.")


func _physics_process(_delta: float) -> void:
	if not _dev_enabled():
		return
	if _cheat_ammo and GameState.has_missiles:
		GameState.refill_missiles(9999)


func _unhandled_input(event: InputEvent) -> void:
	if not _dev_enabled() or not _checkpoint_near:
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_UP
	):
		_save_checkpoint()
		get_viewport().set_input_as_handled()


func _dev_enabled() -> bool:
	return (
		OS.is_debug_build()
		and (
			OS.get_cmdline_args().has("--dev-mode") or OS.get_cmdline_user_args().has("--dev-mode")
		)
	)


func _dependency_error() -> String:
	var missing: Array[String] = []
	for path in ["/root/GameState", "/root/SaveStore", "/root/Weapons"]:
		if get_node_or_null(path) == null:
			missing.append(path)
	var store := get_node_or_null("/root/SaveStore")
	if store != null and store.get("domain") != &"dev":
		missing.append("SaveStore.domain=dev")
	if _cave == null:
		missing.append("Level01/CaveTiles")
	if _player == null:
		missing.append("Level01/PlayerSpawn/Player")
	return "Dev error: missing dependency " + ", ".join(missing) if not missing.is_empty() else ""


func _create_panel() -> void:
	_panel = DEV_PANEL_SCRIPT.new() as CanvasLayer
	if _panel == null:
		return
	add_child(_panel)
	_panel.action_requested.connect(_on_panel_action)
	_panel.set_stations(_station_names)
	_panel.set_status(_last_status if _last_status != "" else "Ready.")
	_overlay = OVERLAY_SCRIPT.new() as CanvasLayer
	if _overlay != null:
		add_child(_overlay)
		_overlay.configure(_player)
		if OS.get_cmdline_user_args().has("--perf-overlay"):
			_overlay_enabled = true
			_overlay.set_enabled(true)


func _build_dev_world() -> void:
	if _cave == null:
		return
	# Runtime annex opens original wall; original tile data itself remains untouched on disk.
	for y in range(14, 18):
		_cave.erase_cell(Vector2i(59, y))
	for index in range(1, station_ids.size()):
		var room_id := station_ids[index]
		var origin := Vector2((ANNEX_START_X + (index - 1) * ROOM_WIDTH) * TILE_SIZE, ROOM_ORIGIN_Y)
		_room_origins[room_id] = origin
		_build_room_tiles(origin, index)
		_create_room(room_id, origin)
	_create_dev_pickups()
	_create_station_mechanics()
	_create_enemy_arena()
	_create_boss_arena()
	_create_map()
	_update_camera_bounds()
	_configure_cave_visuals()
	GameState.discover_room("S0")


func _build_room_tiles(origin: Vector2, index: int) -> void:
	for x in range(ROOM_WIDTH):
		_set_cave_cell(origin, Vector2i(x, ROOM_FLOOR_Y))
		_set_cave_cell(origin, Vector2i(x, 0))
	for y in range(1, ROOM_FLOOR_Y):
		if y < 14:
			_set_cave_cell(origin, Vector2i(0, y))
			_set_cave_cell(origin, Vector2i(ROOM_WIDTH - 1, y))
	if index == 1:
		for y in range(14, 18):
			_cave.erase_cell(Vector2i(ANNEX_START_X, y))
	match station_ids[index]:
		"S1":
			_add_platform(origin, 7, 14, 7)
			_add_platform(origin, 17, 11, 6)
			_add_platform(origin, 25, 8, 4)
		"S2":
			_add_platform(origin, 5, 14, 5)
			_add_platform(origin, 22, 12, 5)
		"S3":
			_add_platform(origin, 9, 15, 5)
			_add_platform(origin, 20, 12, 5)
		"S4":
			_add_platform(origin, 5, 14, 5)
			_add_platform(origin, 18, 14, 6)
			_add_platform(origin, 22, 14, 5)
		"S5":
			_add_platform(origin, 5, 14, 5)
			_add_platform(origin, 11, 14, 8)
			_add_platform(origin, 20, 10, 5)
			_add_platform(origin, 24, 7, 4)
		"S6":
			_add_platform(origin, 6, 13, 5)
			_add_platform(origin, 21, 11, 6)
			_carve_lava_basin(origin, 14, 18, [15, 17])
			_carve_lava_basin(origin, 21, 25, [22, 24])
		"S7":
			_add_platform(origin, 4, 14, 5)
			_add_platform(origin, 10, 14, 5)
			_add_platform(origin, 16, 14, 5)
			_add_platform(origin, 22, 14, 5)
			_add_platform(origin, 4, 11, 5)
			_add_platform(origin, 10, 9, 5)
			_add_platform(origin, 16, 9, 5)
			_add_platform(origin, 22, 11, 5)
			# Leave an open lead cell so the first raised stone is jumpable from the run-up.
			_carve_lava_basin(origin, 15, 19, [16, 18])
		"S8":
			# Raised roof platform keeps full-height player route clear below the boss arena.
			_add_platform(origin, 3, 10, 26)
		"S9":
			_add_platform(origin, 5, 14, 7)
			_add_platform(origin, 14, 12, 6)
			_add_platform(origin, 23, 14, 5)
			# Three bounded test cells share ground-level doorways. Route remains bidirectional.
			_add_wall_column(origin, 12, 1, 13)
			_add_wall_column(origin, 21, 1, 13)
		"S10":
			_add_platform(origin, 5, 14, 6)
			_add_platform(origin, 18, 11, 7)


func _carve_lava_basin(origin: Vector2, start_x: int, end_x: int, stepping_cells: Array) -> void:
	var world_origin := Vector2i(origin / TILE_SIZE)
	for x in range(start_x, end_x + 1):
		_cave.erase_cell(world_origin + Vector2i(x, ROOM_FLOOR_Y))
		_set_cave_cell(origin, Vector2i(x, ROOM_FLOOR_Y + 1))
	for step_x in stepping_cells:
		_set_cave_cell(origin, Vector2i(int(step_x), ROOM_FLOOR_Y - 1))


func _set_cave_cell(origin: Vector2, cell: Vector2i) -> void:
	_cave.set_cell(Vector2i(origin / TILE_SIZE) + cell, 0, Vector2i.ZERO)


func _add_platform(origin: Vector2, start_x: int, y: int, width: int) -> void:
	for x in range(start_x, start_x + width):
		_set_cave_cell(origin, Vector2i(x, y))


func _add_wall_column(origin: Vector2, x: int, start_y: int, height: int) -> void:
	for y in range(start_y, start_y + height):
		_set_cave_cell(origin, Vector2i(x, y))


func _create_room(room_id: String, origin: Vector2) -> void:
	var room := DEV_ROOM_SCRIPT.new() as Node2D
	if room == null:
		return
	room.configure(room_id, String(_room_kinds.get(room_id, "world")), origin, _room_color(room_id))
	room.entered.connect(_on_room_entered)
	room.subcell_entered.connect(_on_room_subcell_entered)
	if room_id == "S9":
		(
			room
			. configure_subcells(
				[
					{"id": "S9-A", "rect": Rect2(64, 176, 704, 944)},
					{"id": "S9-B", "rect": Rect2(832, 176, 512, 944)},
					{"id": "S9-C", "rect": Rect2(1408, 176, 512, 944)},
				]
			)
		)
	add_child(room)


func _room_color(room_id: String) -> Color:
	var colors := {
		"S1": Color("6bb8b0"),
		"S2": Color("d9906a"),
		"S3": Color("ddbf71"),
		"S4": Color("e66d7d"),
		"S5": Color("6dc9e8"),
		"S6": Color("83ecc5"),
		"S7": Color("c57f69"),
		"S8": Color("d6a85e"),
		"S9": Color("80b5b5"),
		"S10": Color("8d7ed1"),
	}
	return colors.get(room_id, Color("568d94"))


func _create_map() -> void:
	_map = DEV_MAP_SCRIPT.new() as CanvasLayer
	if _map == null:
		return
	_map.name = "DevMap"
	add_child(_map)
	_map.set_rooms(station_ids)
	_map.set_room_names(_station_names)
	_map.set_connections(WORLD_CONNECTIONS)
	_map.set_markers(_world_map_markers())
	_map.set_current("S0")


func _world_map_markers() -> Dictionary:
	return {
		"S2": [{"kind": "gate", "id": "missile"}, {"kind": "gate", "id": "wave"}],
		"S3": [{"kind": "gate", "id": "bomb"}],
		"S4":
		[
			{"kind": "refill", "id": "health"},
			{"kind": "refill", "id": "missiles"},
			{"kind": "gate", "id": "hazard"}
		],
		"S6": [{"kind": "gate", "id": "undertow"}, {"kind": "gate", "id": "missile"}],
		"S8":
		[
			{"kind": "checkpoint", "id": "S8"},
			{"kind": "refill", "id": "health"},
			{"kind": "refill", "id": "missiles"}
		],
		"S9":
		[
			{"kind": "checkpoint", "id": "S9"},
			{"kind": "refill", "id": "health"},
			{"kind": "gate", "id": "final"}
		],
		"S10": [{"kind": "gate", "id": "hazard"}],
	}


func _update_camera_bounds() -> void:
	if _player == null:
		return
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = (ANNEX_START_X + 10 * ROOM_WIDTH) * TILE_SIZE
	camera.limit_bottom = 1280


func _create_dev_pickups() -> void:
	STATION_LAYOUT.create_pickups(self, _room_origins)


func _spawn_pickup(instance_id: String, kind: StringName, location: Vector2) -> void:
	STATION_LAYOUT.spawn_pickup(self, instance_id, kind, location)


func _create_station_mechanics() -> void:
	STATION_LAYOUT.create_station_mechanics(self, _room_origins)


func _on_station_checkpoint_entered(room_id: String, marker_position: Vector2) -> void:
	_checkpoint_near = true
	_on_checkpoint_entered(room_id, marker_position)


func _on_station_checkpoint_left() -> void:
	_checkpoint_near = false


func _capture_station_baselines() -> void:
	for room_id in station_ids:
		_station_baselines[room_id] = GameState.snapshot()


func _on_room_entered(room_id: String) -> void:
	_current_room = room_id
	_room_runtime.route_room(room_id)
	_current_station = station_ids.find(room_id)
	if _map != null:
		_map.set_current(room_id)
	if _overlay != null:
		_overlay.set("room_id", room_id)
	if not _station_baselines.has(room_id):
		_station_baselines[room_id] = GameState.snapshot()
	_update_final_gate()


func _on_room_subcell_entered(subcell_id: String) -> void:
	GameState.discover_room(subcell_id)
	if _map != null and _map.has_method("set_current_subcell"):
		_map.call("set_current_subcell", subcell_id)


func _on_state_changed() -> void:
	_update_final_gate()
	if _panel != null:
		_panel.refresh()


func _update_final_gate() -> void:
	for node in get_tree().get_nodes_in_group("dev_gate"):
		if node is DevFinalGate:
			node.refresh()


func _create_enemy_arena() -> void:
	_arena_runtime.build_enemy_arena()


func _create_boss_arena(allow_defeated_test: bool = false) -> void:
	_arena_runtime.build_boss_arena(allow_defeated_test)
	_boss_arena_start = _arena_runtime.boss_arena_start()


func _spawn_enemy(
	runtime_id: StringName, location: Vector2, room_id := "S7", bounds := Rect2()
) -> Node2D:
	return _arena_runtime.spawn_enemy(runtime_id, location, room_id, bounds)


func _spawn_boss(
	runtime_id: StringName,
	location: Vector2,
	requested_phase: int,
	explicit_test := false,
	room_id := "S8"
) -> Node2D:
	return _arena_runtime.spawn_boss(runtime_id, location, requested_phase, explicit_test, room_id)


func _is_safe_boss_position(position: Vector2) -> bool:
	return _arena_runtime.is_safe_boss_position(position)


func _on_panel_action(action: StringName, data: Dictionary) -> void:
	_panel_runtime.handle_action(action, data)


func _on_player_died() -> void:
	_checkpoint_runtime.on_player_died()


func _start_respawn_timer() -> void:
	_checkpoint_runtime.start_respawn_timer()


func _on_checkpoint_entered(room_id: String, marker_position: Vector2) -> void:
	_checkpoint_runtime.on_checkpoint_entered(room_id, marker_position)


func _on_boss_defeated(id: StringName) -> void:
	_arena_runtime.on_boss_defeated(id)


func _is_valid_checkpoint_spawn(room: String, position: Vector2) -> bool:
	return _checkpoint_runtime.is_valid_checkpoint_spawn(room, position)


func _safe_checkpoint_spawn(checkpoint: Dictionary) -> Vector2:
	return _checkpoint_runtime.safe_checkpoint_spawn(checkpoint)


func _save_checkpoint() -> void:
	_checkpoint_runtime.save_checkpoint(_current_room, _player.global_position)


func _save_game() -> void:
	_checkpoint_runtime.save_game()


func _load_game() -> void:
	_checkpoint_runtime.load_game()


func _station_for_checkpoint() -> int:
	return _checkpoint_runtime.station_for_checkpoint()


func _set_cheats(god: bool, ammo: bool) -> void:
	_panel_runtime.set_cheats(god, ammo)


func _clear_dev_runtime() -> void:
	_checkpoint_near = false
	_arena_runtime.clear()
	_clear_transients()
	_clear_group("dev_enemy")
	_clear_group("dev_gate")
	_clear_group("dev_hazard")
	_clear_group("dev_refill")
	_clear_group("dev_checkpoint")
	_clear_group("dev_pickup")
	_clear_group("dev_ambush")
	if get_node_or_null("/root/Weapons") != null:
		Weapons.reset_runtime()


func _clear_transients() -> void:
	_clear_group(&"transient")
	if get_node_or_null("/root/Weapons") != null:
		Weapons.reset_runtime()


func _clear_group(group_name: StringName) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if node == self:
			continue
		node.get_parent().remove_child(node)
		node.free()


func _rebuild_runtime_content(allow_defeated_boss_test: bool = false) -> void:
	_clear_dev_runtime()
	_create_dev_pickups()
	_create_station_mechanics()
	_create_enemy_arena()
	_create_boss_arena(allow_defeated_boss_test)
	_update_final_gate()
	_configure_cave_visuals()


func _configure_cave_visuals() -> void:
	if _cave_visuals == null or _cave == null or not _cave_visuals.has_method("configure"):
		return
	_cave_visuals.call("configure", _cave)


func _reset_arena() -> void:
	_arena_runtime.reset_selector()


func _teleport_station(index: int) -> void:
	if index < 0 or index >= station_ids.size() or _player == null:
		_set_status("Invalid station index.")
		return
	_current_station = index
	_current_room = station_ids[index]
	_room_runtime.route_room(_current_room)
	var position := _safe_station_spawn(index)
	if index > 0 and not _is_valid_checkpoint_spawn(_current_room, position):
		_set_status("Invalid station spawn; original spawn used.")
		position = PROTOTYPE_SPAWN
	if _player.has_method("reset_for_spawn"):
		_player.call("reset_for_spawn", position)
	else:
		_player.global_position = position
		_set_status("API missing: Player.reset_for_spawn; fallback spawn used.")
	if _map != null:
		_map.set_current(_current_room)
	if _overlay != null:
		_overlay.set("room_id", _current_room)
	var checkpoint_room := "prototype" if index == 0 else _current_room
	if not GameState.set_checkpoint(checkpoint_room, position):
		_set_status("Checkpoint denied: station spawn is invalid.")
	_set_status("Moved to " + _station_names[index] + ".")


func _safe_station_spawn(index: int) -> Vector2:
	if index == 0:
		return PROTOTYPE_SPAWN
	if _cave == null or index >= station_ids.size():
		return PROTOTYPE_SPAWN
	var room := station_ids[index]
	var origin: Vector2 = _room_origins.get(room, Vector2.ZERO)
	var local_candidates := [
		Vector2(320, 1088), Vector2(640, 1088), Vector2(1024, 1088), Vector2(1760, 1088)
	]
	if room == "S8":
		# Keep panel travel at entrance side; boss arena starts on opposite side.
		local_candidates = [Vector2(320, 1088), Vector2(480, 1088), Vector2(640, 1088)]
	# Fallbacks across the whole floor, so a boss or hazard near the preferred spots never sends the
	# player back to the S0 start.
	for x in range(192, ROOM_WIDTH * TILE_SIZE - 128, 128):
		local_candidates.append(Vector2(x, 1088))
	for local_position in local_candidates:
		var candidate: Vector2 = origin + local_position
		# Each candidate needs its own floor; S6/S7 carve lava basins through the room middle.
		var floor_cell := Vector2i(
			floori(candidate.x / TILE_SIZE), floori(origin.y / TILE_SIZE) + ROOM_FLOOR_Y
		)
		if _cave.get_cell_source_id(floor_cell) < 0:
			continue
		if _is_valid_checkpoint_spawn(room, candidate) and _is_safe_teleport_position(candidate):
			return candidate
	return PROTOTYPE_SPAWN


func _is_safe_teleport_position(position: Vector2) -> bool:
	for hazard in get_tree().get_nodes_in_group("dev_hazard"):
		if not is_instance_valid(hazard):
			continue
		var size: Vector2 = hazard.get("hazard_size")
		var hazard_rect := Rect2(
			hazard.global_position - size * 0.5 - SAFE_HAZARD_MARGIN,
			size + SAFE_HAZARD_MARGIN * 2.0
		)
		if hazard_rect.has_point(position):
			return false
	for boss in get_tree().get_nodes_in_group("dev_boss"):
		if (
			is_instance_valid(boss)
			and position.distance_to(boss.global_position) < SAFE_BOSS_DISTANCE
		):
			return false
	return true


func _set_status(message: String) -> void:
	_last_status = message
	if _panel != null and _panel.has_method("set_status"):
		_panel.call("set_status", message)
