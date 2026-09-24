extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FLOOR_Y := 900.0
const WALL_X := 500.0
const PLAYER_WALL_X := WALL_X - 28.0

var _test_root: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var simple_height: float = await _measure_simple_jump()
	var direct_height: float = await _measure_wall_jump(-1.0, simple_height)
	var late_height: float = await _measure_wall_jump(0.5, simple_height)
	var repeated_jumps: int = await _verify_same_wall_reuse()
	var ball_result: Array = await _verify_ball_jump()
	var ball_height: float = ball_result[0]
	var ball_pass: bool = ball_result[1]

	print("Walljump actual height measurements (px):")
	print("  a) simple jump H: %.1f" % simple_height)
	print("  b) directly on wall contact: %.1f" % direct_height)
	print("  c) after half descent: %.1f (%.2fx H)" % [late_height, late_height / simple_height])
	print("  same wall, repeated jumps: %d" % repeated_jumps)
	print("  ball-form grounded jump height: %.1f px" % float(ball_height))

	var measurements_pass: bool = (
		simple_height > 0.0
		and direct_height > simple_height * 1.5
		and late_height > simple_height * 1.25
		and late_height < simple_height * 1.75
	)
	var reuse_pass: bool = repeated_jumps >= 3
	if not measurements_pass:
		push_error("FAIL: walljump height timing is outside expected ranges")
	if not reuse_pass:
		push_error("FAIL: same-wall reuse did not produce three wall jumps")
	if not ball_pass:
		push_error("FAIL: ball grounded/coyote jump contract failed")

	_release_inputs()
	await TestShutdown.finish(
		get_tree(), 0 if measurements_pass and reuse_pass and ball_pass else 1
	)


func _measure_simple_jump() -> float:
	await _start_world(false)
	var player: Player = await _spawn_player(300.0)
	var baseline_y: float = player.global_position.y
	var minimum_y: float = baseline_y
	var left_floor: bool = false

	# Start movement directly, then measure positions after move_and_slide().
	player.velocity.y = -PlayerConfig.JUMP_VELOCITY
	player._jump_cutoff_applied = true
	for frame in 180:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)
		if not player.is_on_floor():
			left_floor = true
		if left_floor and player.is_on_floor():
			break
	await _clear_world()
	return baseline_y - minimum_y


func _measure_wall_jump(trigger_mode: float, simple_height: float) -> float:
	await _start_world(true)
	var player: Player = await _spawn_player(300.0)
	var baseline_y: float = player.global_position.y
	var minimum_y: float = baseline_y
	var target_y: float = baseline_y - simple_height * trigger_mode if trigger_mode >= 0.0 else 0.0
	var left_floor: bool = false
	var wall_jump_started: bool = false

	Input.action_press("move_right")
	player.velocity.y = -PlayerConfig.JUMP_VELOCITY
	player._jump_cutoff_applied = true
	for frame in 180:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)
		if not player.is_on_floor():
			left_floor = true

		var at_wall: bool = player.global_position.x >= PLAYER_WALL_X - 0.5
		if not wall_jump_started and at_wall:
			if trigger_mode >= 0.0 and player.global_position.y < target_y:
				continue
			# Drive exact production jump resolution with buffered jump input.
			player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
			player._resolve_jump()
			player._jump_cutoff_applied = true
			wall_jump_started = true

		if wall_jump_started and left_floor and player.is_on_floor():
			break

	_release_inputs()
	await _clear_world()
	return baseline_y - minimum_y


func _verify_same_wall_reuse() -> int:
	await _start_world(true)
	var player: Player = await _spawn_player(300.0)
	var wall_jumps: int = 0
	var last_jump_frame: int = -100

	Input.action_press("move_right")
	player.velocity.y = -PlayerConfig.JUMP_VELOCITY
	player._jump_cutoff_applied = true
	for frame in 420:
		await get_tree().physics_frame
		var at_wall: bool = player.global_position.x >= PLAYER_WALL_X - 0.5
		var descending: bool = player.velocity.y > 0.0
		if at_wall and descending and frame - last_jump_frame > 18:
			player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
			player._resolve_jump()
			player._jump_cutoff_applied = true
			wall_jumps += 1
			last_jump_frame = frame
			if wall_jumps >= 3:
				break

	_release_inputs()
	await _clear_world()
	return wall_jumps


func _verify_ball_jump() -> Array:
	await _start_world(false)
	var player: Player = await _spawn_player(300.0)
	player._set_ball_form(true)
	await get_tree().physics_frame
	var baseline_y: float = player.global_position.y
	var minimum_y: float = baseline_y
	Input.action_press("jump")
	player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	player._resolve_jump()
	var impulse_matches_base := is_equal_approx(player.velocity.y, -PlayerConfig.JUMP_VELOCITY)
	var ball_before_jump := player.is_ball and player.form == Player.PlayerForm.BALL
	var ball_collision := player.get_node("BallCollisionShape2D") as CollisionShape2D
	var standing_collision := player.get_node("StandingCollisionShape2D") as CollisionShape2D
	var collision_before_jump: bool = not ball_collision.disabled and standing_collision.disabled
	await get_tree().physics_frame
	await get_tree().physics_frame
	player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	player._coyote_timer = 0.0
	player._wall_side = 1
	var airborne_velocity := player.velocity
	player._resolve_jump()
	var no_double_or_wall_jump := (
		player.velocity == airborne_velocity and player._jump_buffer_timer > 0.0
	)
	for frame in 180:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)
		if player.is_on_floor() and frame > 10:
			break
	var jump_height := baseline_y - minimum_y
	Input.action_release("jump")
	player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	player._coyote_timer = PlayerConfig.COYOTE_TIME
	player._resolve_jump()
	var coyote_buffer_works := (
		is_equal_approx(player.velocity.y, -PlayerConfig.JUMP_VELOCITY)
		and player._jump_buffer_timer == 0.0
	)
	player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	player.reset_for_spawn(Vector2(PLAYER_WALL_X, FLOOR_Y))
	var reset_clears_buffer := player._jump_buffer_timer == 0.0
	player._set_ball_form(true)
	player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	GameState.reset_health()
	player.take_damage(100)
	var death_clears_buffer := player._jump_buffer_timer == 0.0
	var contract_pass: bool = (
		jump_height > 180.0
		and jump_height < 310.0
		and impulse_matches_base
		and ball_before_jump
		and collision_before_jump
		and player.is_ball
		and not player.is_spinning
		and not player.dash_active
		and no_double_or_wall_jump
		and coyote_buffer_works
		and reset_clears_buffer
		and death_clears_buffer
	)
	if not impulse_matches_base:
		push_error("FAIL: ball jump impulse is not base JUMP_VELOCITY")
	if not ball_before_jump or not collision_before_jump:
		push_error("FAIL: ball jump changed form or collider")
	if not no_double_or_wall_jump:
		push_error("FAIL: ball double-jump or wall-jump was accepted")
	if not coyote_buffer_works:
		push_error("FAIL: ball coyote/buffer jump was not accepted")
	if not reset_clears_buffer or not death_clears_buffer:
		push_error("FAIL: ball jump buffer survived reset or death")
	await _clear_world()
	return [jump_height, contract_pass]


func _start_world(with_wall: bool) -> void:
	await _clear_world()
	_test_root = Node2D.new()
	get_tree().root.add_child(_test_root)
	_add_static_rect(Vector2(960.0, FLOOR_Y + 32.0), Vector2(1920.0, 64.0))
	if with_wall:
		_add_static_rect(Vector2(WALL_X + 32.0, 600.0), Vector2(64.0, 600.0))
	await get_tree().physics_frame


func _spawn_player(spawn_x: float) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	_test_root.add_child(player)
	player.global_position = Vector2(spawn_x, FLOOR_Y)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return player


func _add_static_rect(position: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	_test_root.add_child(body)


func _clear_world() -> void:
	if is_instance_valid(_test_root):
		_test_root.queue_free()
		await get_tree().physics_frame
	_test_root = null


func _release_inputs() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("jump")
