extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const FLOOR_Y := 900.0

var failures: Array[String] = []
var _world: Node2D
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_action_has_key("jump", KEY_A), "InputMap maps A to jump")
	_check(_action_has_key("slipstream", KEY_Z), "InputMap maps Z to Slipstream")
	_check(_action_has_key("jump", KEY_SPACE), "InputMap maps Space to jump")
	_check(not _action_has_key("slipstream", KEY_A), "InputMap rejects A as Slipstream")
	_check(not _action_has_key("jump", KEY_Z), "InputMap rejects Z as jump")
	GameState.reset_progress()
	await _start_world()
	await _spawn_player(Vector2(300.0, FLOOR_Y))
	await _test_physical_key_runtime()
	await _test_crouch_and_slip_bindings()
	await _test_walk_and_run_speed()
	await _test_jump_height_is_run_independent()
	await _test_crouch_muzzle_both_facings()
	await _test_stand_clearance_and_transitions()
	await _test_ball_jump_and_timing()
	_test_presentation_animations()
	_release_inputs()
	await _clear_world()

	if failures.is_empty():
		print("PASS: player controls, crouch, run, muzzle, clearance, and transitions")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _test_physical_key_runtime() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"slipstream")
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	_parse_key(KEY_Z, true)
	_check(Input.is_action_pressed("slipstream"), "physical Z press activates Slipstream action")
	_check(not Input.is_action_pressed("jump"), "physical Z press does not activate jump action")
	await get_tree().physics_frame
	_parse_key(KEY_Z, false)
	_check(_player.is_ball, "physical Z key reaches live Slipstream input")
	_check(_player.velocity.y >= 0.0, "physical Z key cannot reach live jump input")
	_release_inputs()
	await get_tree().physics_frame
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	_parse_key(KEY_A, true)
	_check(Input.is_action_pressed("jump"), "physical A press activates jump action")
	_check(
		not Input.is_action_pressed("slipstream"), "physical A press does not activate Slipstream"
	)
	_player._physics_process(1.0 / 60.0)
	_parse_key(KEY_A, false)
	_check(_player.velocity.y < 0.0, "physical A key reaches live jump input")
	_check(not _player.is_ball, "physical A key cannot reach Slipstream input")
	_release_inputs()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	_parse_key(KEY_SPACE, true)
	_check(Input.is_action_pressed("jump"), "physical Space press activates jump action")
	_check(
		not Input.is_action_pressed("slipstream"),
		"physical Space press does not activate Slipstream",
	)
	_player._physics_process(1.0 / 60.0)
	_parse_key(KEY_SPACE, false)
	_check(_player.velocity.y < 0.0, "physical Space key reaches live jump input")
	_check(not _player.is_ball, "physical Space key cannot reach Slipstream input")
	_release_inputs()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()


func _parse_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _test_crouch_and_slip_bindings() -> void:
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_down")
	await get_tree().physics_frame
	_check(_player.is_crouching, "Down enters crouch on ground")
	_check(not _player.is_ball, "Down never slips")
	Input.action_release("move_down")
	await get_tree().physics_frame
	_check(not _player.is_crouching, "released Down stands when clear")

	Input.action_press("slipstream")
	await get_tree().physics_frame
	_check(not _player.is_ball, "Slipstream cannot activate before unlock")
	Input.action_release("slipstream")
	await get_tree().process_frame
	GameState.unlock_ability(&"slipstream")
	_parse_key(KEY_Z, true)
	await get_tree().physics_frame
	_parse_key(KEY_Z, false)
	await get_tree().process_frame
	_check(_player.is_ball, "Z enters Slipstream after unlock")
	for frame in 10:
		await get_tree().physics_frame
	_parse_key(KEY_Z, true)
	await get_tree().physics_frame
	_parse_key(KEY_Z, false)
	_check(not _player.is_ball, "Z exits Slipstream with headroom")


func _test_walk_and_run_speed() -> void:
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_right")
	for frame in 45:
		await get_tree().physics_frame
	var walk_speed := absf(_player.velocity.x)
	Input.action_press("run")
	for frame in 45:
		await get_tree().physics_frame
	var run_speed := absf(_player.velocity.x)
	_check(is_equal_approx(walk_speed, PlayerConfig.WALK_MAX), "walk reaches WALK_MAX")
	_check(is_equal_approx(run_speed, PlayerConfig.RUN_MAX), "Shift reaches RUN_MAX")
	_check(run_speed > walk_speed, "run is faster than walk")
	_release_inputs()


func _test_jump_height_is_run_independent() -> void:
	var walk_height := await _measure_jump(false)
	var run_height := await _measure_jump(true)
	_check(absf(walk_height - run_height) < 1.0, "run does not change vertical jump height")


func _measure_jump(running: bool) -> float:
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	var baseline_y := _player.global_position.y
	var minimum_y := baseline_y
	if running:
		Input.action_press("run")
	Input.action_press("jump")
	for frame in 2:
		await get_tree().physics_frame
	Input.action_release("jump")
	for frame in 90:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, _player.global_position.y)
		if _player.is_on_floor() and frame > 10:
			break
	Input.action_release("run")
	return baseline_y - minimum_y


func _test_crouch_muzzle_both_facings() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_down")
	await get_tree().physics_frame

	_player.facing = 1
	Input.action_release("fire_beam")
	await get_tree().process_frame
	Input.action_press("fire_beam")
	_player._handle_weapon_input()
	_player._update_animation()
	var right_muzzle: Vector2 = (_player.get_node("Muzzle") as Marker2D).position
	Input.action_release("fire_beam")
	_check(
		is_equal_approx(right_muzzle.x, PlayerConfig.CROUCH_HORIZONTAL_MUZZLE_OFFSET.x),
		"crouch shot muzzle faces right"
	)
	_check(
		is_equal_approx(right_muzzle.y, PlayerConfig.CROUCH_HORIZONTAL_MUZZLE_OFFSET.y),
		"crouch shot muzzle is low"
	)
	_check(
		_player.get_node("AnimatedSprite2D").animation == &"crouch_shoot_horizontal",
		"crouch shot uses firing pose"
	)

	_player.facing = -1
	await get_tree().process_frame
	Input.action_press("fire_beam")
	_player._handle_weapon_input()
	var left_muzzle: Vector2 = (_player.get_node("Muzzle") as Marker2D).position
	Input.action_release("fire_beam")
	Input.action_release("move_down")
	_check(
		is_equal_approx(left_muzzle.x, -PlayerConfig.CROUCH_HORIZONTAL_MUZZLE_OFFSET.x),
		"crouch shot muzzle faces left"
	)
	_check(
		is_equal_approx(left_muzzle.y, PlayerConfig.CROUCH_HORIZONTAL_MUZZLE_OFFSET.y),
		"left crouch shot remains low"
	)


func _test_stand_clearance_and_transitions() -> void:
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_down")
	await get_tree().physics_frame
	_add_static_rect(Vector2(960.0, 760.0), Vector2(1920.0, 40.0))
	await get_tree().physics_frame
	Input.action_release("move_down")
	await get_tree().physics_frame
	_check(_player.is_crouching, "stand is refused under low ceiling")
	_check(not _player._can_stand_up(), "standing ShapeCast detects ceiling")

	_player.take_damage(1, Vector2(0.0, FLOOR_Y))
	_check(_player.is_crouching, "hurt preserves safe crouch form")
	_world.get_child(_world.get_child_count() - 1).queue_free()
	await get_tree().physics_frame
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_check(not _player.is_crouching and not _player.is_ball, "reset restores standing form")
	_player.take_damage(100)
	_check(not _player.is_crouching, "death exits crouch when clear")


func _test_ball_jump_and_timing() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"slipstream")
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_player._set_ball_form(true)
	await _settle_player()
	var baseline_y := _player.global_position.y
	Input.action_press("jump")
	for frame in 2:
		await get_tree().physics_frame
	var first_jump_velocity := _player.velocity.y
	var minimum_y := _player.global_position.y
	for frame in 8:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, _player.global_position.y)
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	_player._coyote_timer = 0.0
	_player._wall_side = 1
	var airborne_velocity := _player.velocity
	_player._resolve_jump()
	_check(_player.velocity == airborne_velocity, "ball cannot double jump or wall-jump")
	_check(_player._jump_buffer_timer > 0.0, "airborne ball jump remains buffered")
	_player._jump_buffer_timer = 0.0
	for frame in 20:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, _player.global_position.y)
	Input.action_release("jump")
	for frame in 100:
		await get_tree().physics_frame
		minimum_y = minf(minimum_y, _player.global_position.y)
		if _player.is_on_floor() and frame > 10:
			break
	var jump_height := baseline_y - minimum_y
	_check(
		first_jump_velocity < -1100.0 and first_jump_velocity > -PlayerConfig.JUMP_VELOCITY - 1.0,
		"ball jump starts with base JUMP_VELOCITY"
	)
	_check(jump_height > 180.0 and jump_height < 310.0, "ball grounded jump reaches base height")
	_check(_player.is_ball and _player.form == Player.PlayerForm.BALL, "jump preserves ball form")
	_check(
		not _player.is_spinning and not _player.dash_active,
		"ball jump never spins or activates Undertow"
	)

	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	_player._coyote_timer = PlayerConfig.COYOTE_TIME
	_player._resolve_jump()
	_check(_player.velocity.y == -PlayerConfig.JUMP_VELOCITY, "ball coyote jump uses base impulse")
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_check(_player._jump_buffer_timer == 0.0, "reset clears buffered ball jump")
	_player._set_ball_form(true)
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	GameState.reset_health()
	_player.take_damage(100)
	_check(_player._jump_buffer_timer == 0.0, "death clears buffered ball jump")


func _test_presentation_animations() -> void:
	var frames := _player.get_node("AnimatedSprite2D").sprite_frames as SpriteFrames
	for animation_name in [&"sprint", &"sprint_armed"]:
		_check(
			frames.get_frame_count(animation_name) == 8,
			"%s has eight authored frames" % animation_name
		)
	for animation_name in [&"wall_slide", &"wall_slide_armed", &"wall_jump", &"wall_jump_armed"]:
		_check(
			frames.get_frame_count(animation_name) == 1, "%s uses authored pose" % animation_name
		)
	for animation_name in [&"sprint", &"sprint_armed"]:
		var texture := frames.get_frame_texture(animation_name, 0) as AtlasTexture
		_check(texture != null and texture.atlas != null, "%s has atlas texture" % animation_name)

	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	_player.velocity.x = PlayerConfig.RUN_MAX
	_player.set("_is_running", true)
	_player._update_animation()
	_check(frames.get_animation_names().has(&"sprint"), "Shift selects sprint animation")
	_check(
		_player.get_node("AnimatedSprite2D").animation == &"sprint",
		"running player presents sprint"
	)
	_player.set("_is_running", false)
	_player._update_animation()
	_check(_player.get_node("AnimatedSprite2D").animation == &"run", "released Shift presents run")
	GameState.unlock_ability(&"beam")
	_player.set("_is_running", true)
	_player._update_animation()
	_check(
		_player.get_node("AnimatedSprite2D").animation == &"sprint_armed",
		"armed Shift selects armed sprint"
	)

	_player.set("_is_running", false)
	_player.set("_wall_sliding", true)
	_player.set("_wall_side", -1)
	_player.facing = 1
	_player._update_animation()
	_check(
		not _player.get_node("AnimatedSprite2D").flip_h, "left wall slide keeps contact shoulder"
	)
	_check(
		_player.get_node("AnimatedSprite2D").animation == &"wall_slide_armed",
		"armed left wall slide pose"
	)
	_player.set("_wall_side", 1)
	_player.facing = -1
	_player._update_animation()
	_check(_player.get_node("AnimatedSprite2D").flip_h, "right wall slide mirrors contact shoulder")
	_player.set("_wall_sliding", false)
	_player.set("_wall_jump_pose_timer", 0.1)
	_player._update_animation()
	_check(
		_player.get_node("AnimatedSprite2D").animation == &"wall_jump_armed",
		"wall jump pose timer is visual only"
	)


func _start_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	_add_static_rect(Vector2(960.0, FLOOR_Y + 32.0), Vector2(1920.0, 64.0))
	await get_tree().physics_frame


func _spawn_player(position: Vector2) -> void:
	_player = PLAYER_SCENE.instantiate()
	_world.add_child(_player)
	_player.global_position = position
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


func _release_inputs() -> void:
	for action in [
		"move_left",
		"move_right",
		"move_up",
		"move_down",
		"jump",
		"run",
		"slipstream",
		"fire_beam",
		"fire_missile"
	]:
		Input.action_release(action)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
