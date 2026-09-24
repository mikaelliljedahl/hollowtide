extends Node
## Timed dash deflect (docs/features/dash-deflect.md): window length, a shot touched inside the
## window returns along its line and damages the shooter, a shot touched later is only passed
## through, other action presses inside the window do nothing now or later, and boss shots turn
## but never bypass a boss phase guard.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const TILE := 64
const FLOOR_ROW := 15
const START := Vector2(6 * TILE, FLOOR_ROW * TILE)

var failures: Array[String] = []
var _world: Node2D
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _start_world()
	await _test_window_length()
	await _test_reflect_inside_window()
	await _test_pass_through_after_window()
	await _test_other_inputs_ignored()
	await _test_boss_shot()
	Weapons.reset_runtime()
	_world.queue_free()
	await _frames(2)
	if failures.is_empty():
		print("PASS: dash deflect window, reflect, pass-through, input lockout, boss shots")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _start_world() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"undertow_dash")
	_world = Node2D.new()
	add_child(_world)
	var tiles := TileMapLayer.new()
	tiles.tile_set = _make_tileset()
	_world.add_child(tiles)
	for x in range(0, 60):
		tiles.set_cell(Vector2i(x, FLOOR_ROW), 0, Vector2i.ZERO)
	_player = PLAYER_SCENE.instantiate() as Player
	_world.add_child(_player)
	_player._camera.enabled = false
	await _respawn()


func _respawn() -> void:
	Weapons.reset_runtime()
	GameState.reset_health()
	_player.facing = 1
	_player.reset_for_spawn(START)
	await _frames(40)


# --- Cases --------------------------------------------------------------------------------


func _test_window_length() -> void:
	_check(is_equal_approx(DashDeflect.WINDOW_SECONDS, 0.10), "deflect window is 0.10 s")
	_player.start_dash(1)
	_check(_player._dash.deflect.is_open(), "window opens with the dash")
	var open_frames := 0
	for index in 20:
		await get_tree().physics_frame
		if _player._dash.deflect.is_open():
			open_frames += 1
	# The start frame plus five more: six physics frames at 60 Hz.
	_check(open_frames == 5, "window stays open five frames after the start (%d)" % open_frames)
	_check(not _player.dash_active, "dash ends after its burst")
	await _respawn()


func _test_reflect_inside_window() -> void:
	var enemy := _spawn_enemy(&"spitter", START + Vector2(720.0, -80.0))
	await _frames(2)
	var before := int(enemy.get("health"))
	var health := GameState.health
	var count := _player._dash.deflect.reflected_count
	var aim := _aim_point(enemy)
	var shot := _shoot_at_player(aim, 1.0)
	var incoming := shot.direction
	_player.start_dash(1)
	await get_tree().physics_frame
	_check(_player._dash.deflect.reflected_count == count + 1, "shot touched in the window turns")
	_check(not is_instance_valid(shot) or shot.is_queued_for_deletion(), "turned shot is consumed")
	var returned := _reflected_shots()
	_check(returned.size() == 1, "one player-owned shot returns (%d)" % returned.size())
	if returned.size() == 1:
		var reflected := returned[0] as ReflectedShot
		_check(
			reflected._direction.dot(-incoming) > 0.999, "returned shot follows its incoming line"
		)
		_check(reflected.collision_layer == 16, "returned shot is on the player projectile layer")
		_check(reflected.damage_kind == &"beam", "returned shot hits as a Seed Bolt kind")
	await _frames(45)
	var dealt := before - int(enemy.get("health")) if is_instance_valid(enemy) else before
	_check(
		dealt == mini(ReflectedShot.DAMAGE, before),
		"returned shot damages the shooter (%d of %d)" % [dealt, ReflectedShot.DAMAGE]
	)
	_check(GameState.health == health, "deflect costs no health")
	_check(_reflected_shots().is_empty(), "returned shot is spent on the hit")
	if is_instance_valid(enemy):
		enemy.queue_free()
	await _respawn()


func _test_pass_through_after_window() -> void:
	var enemy := _spawn_enemy(&"spitter", START + Vector2(900.0, -80.0))
	await _frames(2)
	var before := int(enemy.get("health"))
	var health := GameState.health
	var count := _player._dash.deflect.reflected_count
	_player.start_dash(1)
	await _frames(7)
	_check(_player.dash_active, "dash is still active after the window")
	_check(not _player._dash.deflect.is_open(), "window has closed")
	var chest := _player.global_position + Vector2(0.0, -80.0)
	var shot := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	_world.add_child(shot)
	shot.global_position = chest + Vector2(40.0, 0.0)
	shot.launch(Vector2.LEFT, 12)
	await _frames(12)
	_check(_player._dash.deflect.reflected_count == count, "a late touch does not turn the shot")
	_check(_reflected_shots().is_empty(), "no returned shot after the window")
	_check(GameState.health == health, "a late touch is still passed through without damage")
	_check(int(enemy.get("health")) == before, "a passed-through shot hurts nobody")
	if is_instance_valid(shot):
		shot.queue_free()
	enemy.queue_free()
	await _respawn()


func _test_other_inputs_ignored() -> void:
	GameState.acquire_beam()
	GameState.unlock_ability(&"slipstream")
	GameState.acquire_missiles(5)
	await _respawn()
	var floor_y := _player.global_position.y
	await _tap(&"dash")
	_check(_player.dash_active and _player._dash.deflect.is_open(), "real dash input opens window")
	var direction := _player._dash.direction
	for action in [&"jump", &"fire_beam", &"fire_missile", &"slipstream", &"dash", &"cycle_beam"]:
		_press(action, true)
	var extra := false
	while _player._dash.deflect.is_open():
		await get_tree().physics_frame
		extra = extra or _player.is_ball or _player.velocity.y < 0.0 or not _player.dash_active
	for action in [&"jump", &"fire_beam", &"fire_missile", &"slipstream", &"dash", &"cycle_beam"]:
		_press(action, false)
	_check(not extra, "presses inside the window start nothing inside it")
	_check(_player.dash_active, "a jump press inside the window does not end the dash")
	_check(_player._dash.direction == direction, "a second dash press does not redirect")
	await _frames(30)
	_check(_player_shots() == 0, "fire presses inside the window are dropped, not held")
	_check(not _player.is_ball, "a Slipstream press inside the window is dropped")
	_check(
		absf(_player.global_position.y - floor_y) < 2.0, "a jump press inside the window is dropped"
	)
	_check(GameState.missile_count == 5, "no harpoon was spent")
	# Control: the same jump press after the window ends the dash as before.
	await _frames(20)
	await _tap(&"dash")
	await _frames(7)
	_check(
		_player.dash_active and not _player._dash.deflect.is_open(), "control dash is past window"
	)
	await _tap(&"jump")
	await _frames(2)
	_check(not _player.dash_active, "a jump after the window ends the dash as before")
	await _respawn()


func _test_boss_shot() -> void:
	var boss := EnemyFactory.create(&"stone_guardian")
	_world.add_child(boss)
	boss.global_position = START + Vector2(700.0, -120.0)
	await _frames(2)
	boss.set_physics_process(false)
	var before := int(boss.get("health"))
	var count := _player._dash.deflect.reflected_count
	var shot := _shoot_at_player(_aim_point(boss), 1.6)
	_player.start_dash(1)
	await get_tree().physics_frame
	_check(_player._dash.deflect.reflected_count == count + 1, "a boss shot turns like any shot")
	var returned := _reflected_shots()
	_check(returned.size() == 1, "boss shot returns once")
	await _frames(45)
	_check(_reflected_shots().is_empty(), "returned boss shot reaches the boss")
	_check(int(boss.get("health")) == before, "returned shot never bypasses a boss phase guard")
	if is_instance_valid(shot):
		shot.queue_free()
	boss.queue_free()
	await _respawn()


# --- Helpers ------------------------------------------------------------------------------


func _spawn_enemy(runtime_id: StringName, position: Vector2) -> Node2D:
	var enemy := EnemyFactory.create(runtime_id)
	_world.add_child(enemy)
	enemy.global_position = position
	enemy.set_physics_process(false)
	return enemy


func _aim_point(enemy: Node) -> Vector2:
	for child in enemy.get_children():
		if child.is_in_group(&"projectile_hurtbox"):
			return (child as Node2D).global_position
	return (enemy as Node2D).global_position


## An enemy shot on the line from `origin` to the player's chest, just before it reaches her.
func _shoot_at_player(origin: Vector2, size_scale: float) -> EnemyProjectile:
	var chest := _player.global_position + Vector2(0.0, -80.0)
	var direction := (chest - origin).normalized()
	var shot := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	_world.add_child(shot)
	shot.global_position = chest - direction * 70.0
	shot.size_scale = size_scale
	shot.launch(direction, 12)
	return shot


func _reflected_shots() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group(&"reflected_shot"):
		if not node.is_queued_for_deletion():
			result.append(node)
	return result


func _player_shots() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(&"transient"):
		if node is ProjectileBase and not node is ReflectedShot:
			count += 1
	return count


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(action: StringName) -> void:
	_press(action, true)
	await get_tree().physics_frame
	_press(action, false)
	await get_tree().physics_frame


func _make_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	var source := TileSetAtlasSource.new()
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.3, 0.3))
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, 0)
	source.create_tile(Vector2i.ZERO)
	var data := source.get_tile_data(Vector2i.ZERO, 0)
	var half := TILE * 0.5
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(
		0,
		0,
		PackedVector2Array(
			[Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
		)
	)
	return tileset


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok  ", label)
	else:
		failures.append(label)
		print("  FAIL ", label)
