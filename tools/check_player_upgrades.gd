extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BOMB_GROUP := &"bombs"
const FLOOR_Y := 900.0

var failures: Array[String] = []
var _world: Node2D
var _player: Player


class UndertowTarget:
	extends StaticBody2D

	var hit_count := 0

	func _ready() -> void:
		add_to_group(&"damageable")
		collision_layer = 8
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 12.0
		collision.shape = shape
		add_child(collision)

	func is_vulnerable_to(kind: StringName) -> bool:
		return kind == &"undertow"

	func take_damage(_amount: int, _kind: StringName) -> void:
		hit_count += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	await _start_world()
	var baseline_height := await _measure_jump(false)
	var high_height := await _measure_jump(true)
	_check(baseline_height > 0.0, "baseline jump rises")
	_check(high_height > baseline_height * 1.35, "high jump is materially higher")
	_check(high_height < baseline_height * 1.7, "high jump remains near 1.5x")
	print(
		(
			"Player jump measurements: baseline=%.1f px high_jump=%.1f px ratio=%.3f"
			% [
				baseline_height,
				high_height,
				high_height / baseline_height,
			]
		)
	)

	await _test_wall_jump_impulse()
	await _test_bomb_input()
	await _test_undertow_overlap()
	await _test_pressure_seal_and_death()
	_release_inputs()
	await _clear_world()

	if failures.is_empty():
		print("PASS: player upgrades, bomb input, undertow overlap, protection, and death")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _measure_jump(high_jump: bool) -> float:
	GameState.reset_progress()
	if high_jump:
		GameState.unlock_ability(&"high_jump")
	await _spawn_player(300.0)
	await _settle_player()
	var baseline_y := _player.global_position.y
	var minimum_y := baseline_y
	Input.action_press("move_right")
	Input.action_press("jump")
	for frame in 60:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, _player.global_position.y)
	Input.action_release("jump")
	_release_movement()
	await _settle_player()
	return baseline_y - minimum_y


func _test_wall_jump_impulse() -> void:
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	_player._wall_side = 1
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	_player._resolve_wall_jump()
	_check(
		is_equal_approx(_player.velocity.y, -PlayerConfig.WALL_JUMP_VELOCITY),
		"wall jump keeps 1280 impulse",
	)
	_check(_player.is_spinning, "wall jump starts spin")
	_player._stop_spin()


func _test_bomb_input() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"slipstream")
	GameState.unlock_ability(&"bombs")
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_player.is_ball = true
	_player._set_ball_form(true)
	await get_tree().physics_frame
	Weapons.reset_runtime()
	Input.action_press("fire_beam")
	await get_tree().process_frame
	_player._handle_weapon_input()
	await get_tree().physics_frame
	Input.action_release("fire_beam")
	_check(get_tree().get_nodes_in_group(BOMB_GROUP).size() == 1, "ball fire input places bomb")
	var health_before_explosion := GameState.health
	for _frame in 60:
		await get_tree().physics_frame
	_check(
		GameState.health == health_before_explosion,
		"bomb explosion lifts but never damages player",
	)
	_check(get_tree().get_nodes_in_group(BOMB_GROUP).is_empty(), "bomb fuse reaches real explosion")
	_player.velocity = Vector2.ZERO
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	_player._jump_cutoff_applied = false
	_player.apply_bomb_impulse(_player._ball_center(), Catalog.BOMB_RADIUS)
	_check(
		(
			_player.velocity.y == -Catalog.BOMB_LIFT_SPEED
			and _player._jump_buffer_timer == 0.0
			and _player._jump_cutoff_applied
		),
		"bomb lift clears jump buffer and cutoff state",
	)
	_player.velocity = Vector2.ZERO
	_player.apply_bomb_impulse(
		_player._ball_center() + Vector2(Catalog.BOMB_RADIUS + 1.0, 0.0), Catalog.BOMB_RADIUS
	)
	_check(_player.velocity == Vector2.ZERO, "bomb outside radius does not lift player")
	Weapons.reset_runtime()
	await get_tree().physics_frame


func _test_undertow_overlap() -> void:
	# D19 Undertow Dash (internal `undertow_dash`): one hit per target per dash.
	GameState.reset_progress()
	GameState.unlock_ability(&"undertow_dash")
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	var target := UndertowTarget.new()
	target.position = _player.global_position + Vector2(120.0, -88.0)
	_world.add_child(target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_player.start_dash(1), "dash starts on the ground")
	for frame in 6:
		await get_tree().physics_frame
	_check(target.hit_count == 1, "dash hits target once while passing through")
	for frame in 30:
		await get_tree().physics_frame
	target.position = _player.global_position + Vector2(-120.0, -88.0)
	await get_tree().physics_frame
	_check(_player.start_dash(-1), "second dash starts after cooldown")
	for frame in 6:
		await get_tree().physics_frame
	_check(target.hit_count == 2, "a new dash can hit the target again")
	target.queue_free()
	for frame in 20:
		await get_tree().physics_frame


func _test_pressure_seal_and_death() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"pressure_seal")
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_player.take_damage(11, Vector2.ZERO)
	_check(GameState.health == 94, "pressure_seal rounds 11 damage up to 6")
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_player._start_spin()
	_player.take_damage(100, Vector2.ZERO)
	_check(GameState.health == 0, "damage reaches zero health")
	_check(not _player.is_spinning and not _player.dash_active, "death clears spin and dash")
	var dead_position := _player.global_position
	Input.action_press("move_right")
	await get_tree().physics_frame
	_release_movement()
	_check(_player.global_position == dead_position, "dead player ignores movement input")
	GameState.reset_health()
	_player.reset_for_spawn(Vector2(320.0, FLOOR_Y))
	_check(
		not _player.is_ball and _player.velocity == Vector2.ZERO,
		"reset_for_spawn restores form and velocity"
	)


func _start_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	_add_static_rect(Vector2(960.0, FLOOR_Y + 32.0), Vector2(1920.0, 64.0))
	await get_tree().physics_frame


func _spawn_player(spawn_x: float) -> void:
	if is_instance_valid(_player):
		_player.queue_free()
		await get_tree().physics_frame
	_player = PLAYER_SCENE.instantiate()
	_world.add_child(_player)
	_player.global_position = Vector2(spawn_x, FLOOR_Y)
	await get_tree().physics_frame


func _settle_player() -> void:
	for frame in 3:
		await get_tree().physics_frame


func _add_static_rect(position: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 1
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	_world.add_child(body)


func _clear_world() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await get_tree().physics_frame
	_world = null


func _release_movement() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _release_inputs() -> void:
	_release_movement()
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("jump")
	Input.action_release("fire_beam")
	Input.action_release("fire_missile")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
