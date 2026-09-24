extends RefCounted
class_name DevRuntimeCheckpoint

const PROTOTYPE_SPAWN := Vector2(3360.0, 448.0)
const RESPAWN_DELAY := 0.45
const ROOM_WIDTH := 32
const ROOM_FLOOR_Y := 18

var _host: Node2D
var _station_ids: Array[String]
var _player: Node2D
var _cave: TileMapLayer
var _room_origins: Dictionary
var _respawn_pending := false


func configure(
	host: Node2D,
	station_ids: Array[String],
	player: Node2D,
	cave: TileMapLayer,
	room_origins: Dictionary
) -> void:
	_host = host
	_station_ids = station_ids
	_player = player
	_cave = cave
	_room_origins = room_origins


func on_player_died() -> void:
	if _respawn_pending:
		return
	_respawn_pending = true
	_host.call_deferred("_start_respawn_timer")


func start_respawn_timer() -> void:
	if not _respawn_pending or not _host.is_inside_tree():
		return
	_host.get_tree().create_timer(RESPAWN_DELAY, true).timeout.connect(
		respawn_from_checkpoint, CONNECT_ONE_SHOT
	)


func respawn_from_checkpoint() -> void:
	if not _respawn_pending:
		return
	_respawn_pending = false
	if _host.call("_dev_enabled"):
		_host.call("_clear_dev_runtime")
	else:
		_host.call("_clear_transients")
	GameState.reset_health()
	var spawn := safe_checkpoint_spawn(GameState.checkpoint)
	if _player != null and _player.has_method("reset_for_spawn"):
		_player.call("reset_for_spawn", spawn)
	elif _player != null:
		_player.global_position = spawn
	if _host.call("_dev_enabled"):
		_host.call("_rebuild_runtime_content")
	else:
		_host.call("_configure_cave_visuals")
	_host.call("_set_status", "Dead: current session checkpoint used.")


func is_valid_checkpoint_spawn(room: String, position: Vector2) -> bool:
	if room == "prototype":
		return is_valid_spawn_position(position)
	if not _host.call("_dev_enabled") or _station_ids.find(room) < 1:
		return false
	var origin: Vector2 = _room_origins.get(room, Vector2.ZERO)
	var room_bounds := Rect2(
		origin + Vector2(28.0, 176.0),
		Vector2(ROOM_WIDTH * 64 - 56.0, (ROOM_FLOOR_Y + 1) * 64 - 176.0)
	)
	return room_bounds.has_point(position) and is_valid_spawn_position(position)


func is_valid_spawn_position(position: Vector2) -> bool:
	if _cave == null or _player == null or not position.is_finite():
		return false
	var used := _cave.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return false
	var level_bounds := Rect2(
		_cave.global_position + Vector2(used.position) * 64, Vector2(used.size) * 64
	)
	if (
		position.x < level_bounds.position.x + 28.0
		or position.x > level_bounds.end.x - 28.0
		or position.y < level_bounds.position.y + 176.0
		or position.y > level_bounds.end.y
	):
		return false
	var standing := _player.get_node_or_null("StandingCollisionShape2D") as CollisionShape2D
	if standing == null or standing.shape == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = standing.shape
	query.transform = Transform2D(
		0.0, position + standing.global_position - _player.global_position
	)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_player.get_rid()]
	return _host.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func on_checkpoint_entered(room_id: String, marker_position: Vector2) -> void:
	var spawn := marker_position
	if not is_valid_checkpoint_spawn(room_id, spawn):
		var index := _station_ids.find(room_id)
		spawn = _host.call("_safe_station_spawn", index) if index >= 1 else PROTOTYPE_SPAWN
	if is_valid_checkpoint_spawn(room_id, spawn):
		GameState.set_checkpoint(room_id, spawn)


func safe_checkpoint_spawn(checkpoint: Dictionary) -> Vector2:
	var room := String(checkpoint.get("room", "prototype"))
	var x: Variant = checkpoint.get("x", null)
	var y: Variant = checkpoint.get("y", null)
	if (x is int or x is float) and (y is int or y is float):
		var stored := Vector2(float(x), float(y))
		if is_valid_checkpoint_spawn(room, stored):
			return stored
	var index := _station_ids.find(room)
	if index >= 1:
		var station_spawn: Vector2 = _host.call("_safe_station_spawn", index)
		if is_valid_checkpoint_spawn(room, station_spawn):
			return station_spawn
	return PROTOTYPE_SPAWN


func save_checkpoint(room_id: String, position: Vector2) -> void:
	if _player == null or room_id.is_empty():
		return
	if not is_valid_checkpoint_spawn(room_id, position):
		_host.call("_set_status", "Checkpoint denied: invalid or unsafe coordinate.")
		return
	if not GameState.set_checkpoint(room_id, position):
		_host.call("_set_status", "Checkpoint denied: invalid coordinate.")
		return
	var store := _host.get_node_or_null("/root/SaveStore")
	if store == null:
		_host.call("_set_status", "Checkpoint updated, SaveStore is missing.")
		return
	var result: Error = store.call("save_game")
	_host.call(
		"_set_status",
		"Checkpoint saved." if result == OK else "Checkpoint error: " + error_string(result)
	)


func save_game() -> void:
	var store := _host.get_node_or_null("/root/SaveStore")
	if store == null:
		_host.call("_set_status", "Save error: SaveStore is missing.")
		return
	var result: Error = store.call("save_game")
	_host.call(
		"_set_status",
		"Dev profile saved." if result == OK else "Save error: " + error_string(result)
	)


func load_game() -> void:
	var store := _host.get_node_or_null("/root/SaveStore")
	if store == null:
		_host.call("_set_status", "Load error: SaveStore is missing.")
		return
	var result: Error = store.call("load_game")
	if result != OK:
		_host.call("_set_status", "Load error: " + error_string(result))
		return
	_host.call("_rebuild_runtime_content")
	_host.call("_teleport_station", station_for_checkpoint())
	_host.call("_set_status", "Dev profile loaded.")


func station_for_checkpoint() -> int:
	var room := String(GameState.checkpoint.get("room", "S0"))
	var index := _station_ids.find(room)
	return index if index >= 0 else 0


func cancel_respawn() -> void:
	_respawn_pending = false
