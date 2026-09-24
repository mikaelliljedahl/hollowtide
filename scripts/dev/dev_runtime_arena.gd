extends RefCounted
class_name DevRuntimeArena

const SAFE_BOSS_DISTANCE := 300.0
const SAFE_HAZARD_MARGIN := Vector2(48.0, 96.0)
const FLOOR_CONTACT_Y := 1152.0
const ROOM_WIDTH := 32
const WAVE_GRATE_SCRIPT = preload("res://scripts/world/wave_grate.gd")

var _host: Node2D
var _room_origins: Dictionary
var _player: Node2D
var _boss_arena_start := Vector2.ZERO
var _boss_starts: Dictionary = {}
var _current_tidal: Node2D
var _tidal_wave_grate: Node2D


func configure(host: Node2D, room_origins: Dictionary, player: Node2D) -> void:
	_host = host
	_room_origins = room_origins
	_player = player


func build_enemy_arena() -> void:
	# The left catalog cell stays readable; the panel can replace it with any of all 13 IDs.
	# The right half is reserved for the naturally encountered Cinder Warden arena.
	var gallery := [
		[&"crawler", Vector2(320, 806)],
		[&"ceiling_diver", Vector2(680, 650)],
		[&"frost_floater", Vector2(860, 820)],
	]
	for entry in gallery:
		var runtime_id: StringName = entry[0]
		var local: Vector2 = entry[1]
		var bounds := Rect2(_room_origins["S7"] + local - Vector2(130, 180), Vector2(260, 360))
		var enemy := spawn_enemy(runtime_id, _room_origins["S7"] + local, "S7", bounds)
		if runtime_id == &"crawler" and enemy != null:
			enemy.set("travel_direction", -1)
	spawn_enemy(
		&"shooting_gargoyle",
		_room_origins["S2"] + Vector2(960, 448),
		"S2",
		Rect2(_room_origins["S2"] + Vector2(768, 256), Vector2(960, 640)),
	)
	spawn_enemy(
		&"grasshopper",
		_room_origins["S3"] + Vector2(1120, 1020),
		"S3",
		Rect2(_room_origins["S3"] + Vector2(896, 704), Vector2(512, 384)),
	)
	spawn_enemy(
		&"lava_monster",
		_room_origins["S6"] + Vector2(1504, 1052),
		"S6",
		Rect2(_room_origins["S6"] + Vector2(1344, 768), Vector2(320, 320)),
	)
	var freeze_test_enemy := spawn_enemy(
		&"frost_floater", _room_origins["S5"] + Vector2(1440, 544), "S5"
	)
	if freeze_test_enemy != null:
		freeze_test_enemy.add_to_group("dev_freeze_test")


func build_boss_arena(allow_defeated_test: bool = false) -> void:
	_boss_starts = {
		"S5": _room_origins["S5"] + Vector2(960, 1050),
		"S7": _room_origins["S7"] + Vector2(760, 1050),
		"S8": _room_origins["S8"] + Vector2(760, 1050),
	}
	_boss_arena_start = _boss_starts["S8"]
	_host.call("_spawn_pickup", "S8.entrance.missile_tank", &"missile_tank", _boss_arena_start)
	var specs := [
		[&"stone_guardian", "S5"],
		[&"furnace_mother", "S7"],
		[&"tidal_heart", "S8"],
	]
	for spec in specs:
		var runtime_id: StringName = spec[0]
		var room_id: String = spec[1]
		if GameState.has_world_flag("boss:" + String(runtime_id)) and not allow_defeated_test:
			continue
		var boss := spawn_boss(
			runtime_id,
			_room_origins[room_id] + Vector2(1600, 1060),
			0,
			allow_defeated_test,
			room_id,
		)
		if boss != null and runtime_id == &"tidal_heart":
			ensure_tidal_wave_grate()


func boss_arena_start() -> Vector2:
	return _boss_arena_start


func boss_arena_bounds(room_id := "S8") -> Rect2:
	return Rect2(_room_origins[room_id] + Vector2(1180, 480), Vector2(740, 672))


func arena_bounds(room_id: String) -> Rect2:
	var origin: Vector2 = _room_origins.get(room_id, Vector2.ZERO)
	return Rect2(
		origin + Vector2(80.0, 120.0), Vector2(ROOM_WIDTH * 64 - 160.0, FLOOR_CONTACT_Y - 120.0)
	)


func spawn_enemy(
	runtime_id: StringName, location: Vector2, room_id := "S7", bounds := Rect2()
) -> Node2D:
	var enemy := EnemyFactory.create(runtime_id)
	if enemy == null:
		_host.call("_set_status", "Dev error: EnemyFactory could not create " + String(runtime_id))
		return null
	enemy.global_position = location
	_host.add_child(enemy)
	if enemy.has_method("configure_arena"):
		enemy.call(
			"configure_arena", bounds if bounds.size != Vector2.ZERO else arena_bounds(room_id)
		)
	enemy.add_to_group("dev_owned")
	enemy.add_to_group("dev_enemy")
	return enemy


func spawn_boss(
	runtime_id: StringName,
	location: Vector2,
	requested_phase: int,
	explicit_test := false,
	room_id := "S8"
) -> Node2D:
	if explicit_test:
		_host.call("_clear_group", &"dev_boss")
	var boss := EnemyFactory.create(runtime_id)
	if boss == null:
		_host.call(
			"_set_status", "Dev error: EnemyFactory could not create boss " + String(runtime_id)
		)
		return null
	boss.global_position = safe_boss_position(location, room_id)
	_host.add_child(boss)
	if boss.has_method("configure_arena"):
		boss.call("configure_arena", boss_arena_bounds(room_id))
	boss.add_to_group("dev_owned")
	boss.add_to_group("dev_enemy")
	boss.add_to_group("dev_boss")
	boss.set_meta("dev_explicit_test", explicit_test)
	boss.set_meta("dev_boss_room", room_id)
	if runtime_id == &"tidal_heart":
		_current_tidal = boss
		ensure_tidal_wave_grate()
	if requested_phase in [1, 2] and boss.has_method("set_test_phase"):
		boss.call("set_test_phase", requested_phase)
	if boss.has_signal("defeated"):
		boss.connect("defeated", Callable(_host, "_on_boss_defeated"))
	return boss


func ensure_tidal_wave_grate() -> void:
	if not is_instance_valid(_current_tidal) or not _current_tidal.is_inside_tree():
		return
	if is_instance_valid(_tidal_wave_grate) and _tidal_wave_grate.is_inside_tree():
		_tidal_wave_grate.call("set_relay", _current_tidal)
		return
	_tidal_wave_grate = WAVE_GRATE_SCRIPT.new()
	_tidal_wave_grate.set("grate_size", Vector2(36, 192))
	_tidal_wave_grate.global_position = _current_tidal.global_position - Vector2(150, 0)
	_host.add_child(_tidal_wave_grate)
	_tidal_wave_grate.add_to_group("dev_owned")
	_tidal_wave_grate.add_to_group("dev_gate")
	_tidal_wave_grate.add_to_group("dev_wave_grate")
	_tidal_wave_grate.call("set_relay", _current_tidal)


func safe_boss_position(preferred: Vector2, room_id := "S8") -> Vector2:
	var origin: Vector2 = _room_origins.get(room_id, Vector2.ZERO)
	var candidates := [
		preferred,
		origin + Vector2(1600, 1060),
		origin + Vector2(1760, 1060),
		origin + Vector2(1500, 1060),
	]
	for candidate in candidates:
		if is_safe_boss_position(candidate):
			return candidate
	return candidates[0]


func is_safe_boss_position(position: Vector2) -> bool:
	if _player == null or not position.is_finite():
		return position.is_finite()
	if position.distance_to(_player.global_position) < SAFE_BOSS_DISTANCE:
		return false
	for hazard in _host.get_tree().get_nodes_in_group("dev_hazard"):
		if not is_instance_valid(hazard):
			continue
		var size: Vector2 = hazard.get("hazard_size")
		var hazard_rect := Rect2(
			hazard.global_position - size * 0.5 - SAFE_HAZARD_MARGIN,
			size + SAFE_HAZARD_MARGIN * 2.0
		)
		if hazard_rect.has_point(position):
			return false
	return true


func reset_selector() -> void:
	_host.call("_clear_group", &"dev_enemy")
	_host.call("_clear_group", &"dev_wave_grate")
	_current_tidal = null
	_tidal_wave_grate = null
	if _host.get_node_or_null("/root/Weapons") != null:
		Weapons.reset_runtime()


func clear() -> void:
	_current_tidal = null
	_tidal_wave_grate = null


func on_boss_defeated(id: StringName) -> void:
	var defeated_boss := _boss_instance(id)
	var explicit_test := (
		bool(defeated_boss.get_meta("dev_explicit_test", false))
		if is_instance_valid(defeated_boss)
		else false
	)
	var room_id := (
		String(defeated_boss.get_meta("dev_boss_room", "S8"))
		if is_instance_valid(defeated_boss)
		else "S8"
	)
	if id == &"tidal_heart":
		_current_tidal = null
		if is_instance_valid(_tidal_wave_grate):
			_tidal_wave_grate.queue_free()
		_tidal_wave_grate = null
	var flag := "boss:" + String(id)
	if explicit_test:
		GameState.set_world_flag(flag)
		if id in [&"stone_guardian", &"furnace_mother"]:
			GameState.set_world_flag("regional:" + String(id))
		_host.call("_set_status", "Boss test defeated; victory not autosaved.")
		_host.call("_update_final_gate")
		return
	var before := GameState.snapshot()
	var return_position: Vector2 = _boss_starts.get(room_id, _boss_arena_start)
	if not _host.call("_is_valid_checkpoint_spawn", room_id, return_position):
		_host.call(
			"_set_status", "Boss victory rejected: %s return checkpoint is unsafe." % room_id
		)
		return
	GameState.set_world_flag(flag)
	if id in [&"stone_guardian", &"furnace_mother"]:
		GameState.set_world_flag("regional:" + String(id))
	if not GameState.set_checkpoint(room_id, return_position):
		GameState.restore_snapshot(before)
		_host.call("_set_status", "Boss victory rejected: checkpoint validation failed.")
		return
	var store := _host.get_node_or_null("/root/SaveStore")
	if store == null:
		GameState.restore_snapshot(before)
		_host.call("_set_status", "Boss victory rejected: SaveStore is missing.")
		return
	var result: Error = store.call("save_game")
	if result != OK:
		GameState.restore_snapshot(before)
		_host.call(
			"_set_status", "Boss victory rolled back; atomic save failed: " + error_string(result)
		)
	else:
		_host.call("_set_status", "Boss defeated. Flag and safe return point saved atomically.")
	_host.call("_update_final_gate")


func _boss_instance(id: StringName) -> Node2D:
	for boss in _host.get_tree().get_nodes_in_group("dev_boss"):
		if is_instance_valid(boss) and boss.get("enemy_id") == id:
			return boss as Node2D
	return null


func is_explicit_test_boss(id: StringName) -> bool:
	var boss := _boss_instance(id)
	return is_instance_valid(boss) and bool(boss.get_meta("dev_explicit_test", false))
