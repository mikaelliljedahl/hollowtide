class_name Player extends CharacterBody2D

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const PlayerFluxRuntime = preload("res://scripts/player/player_flux_runtime.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")
const SHOT_POSE_DURATION := 0.14
const WALL_POSE_SCALE := 0.74
const WALL_POSE_CENTER_Y := -96.0
const WALL_SLIDE_CONTACT_OFFSET_X := 21.0
const RUN_ACTION := &"run"
const SLIP_ACTION := &"slipstream"
const DASH_ACTION := &"dash"
enum PlayerForm { STANDING, CROUCHING, BALL }
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _standing_collision: CollisionShape2D = $StandingCollisionShape2D
@onready var _crouch_collision: CollisionShape2D = $CrouchCollisionShape2D
@onready var _ball_collision: CollisionShape2D = $BallCollisionShape2D
@onready var _ceiling_cast: ShapeCast2D = $CeilingShapeCast2D
@onready var _wall_cast_left: RayCast2D = $WallCastLeft
@onready var _wall_cast_right: RayCast2D = $WallCastRight
@onready var _camera: Camera2D = $Camera2D
@onready var _muzzle: Marker2D = $Muzzle
var facing: int = 1
var is_ball: bool = false
var is_crouching: bool = false
var form: PlayerForm = PlayerForm.STANDING
var is_spinning: bool = false
## Undertow Dash (internal ability `undertow_dash`, D19): true during the short dash burst.
var dash_active: bool:
	get:
		return _dash != null and _dash.active
var dev_invulnerable: bool = false
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_cutoff_applied: bool = true
var _slip_timer: float = 0.0
var _is_slipping: bool = false
var _step_timer: float = 0.0
var _floor_state_initialized: bool = false
var _wall_side: int = 0
var _last_wall_side: int = 0
var _wall_coyote_timer: float = 0.0
var _wall_input_lock_timer: float = 0.0
var _wall_sliding: bool = false
var _wall_jump_pose_timer: float = 0.0
var _hurt_input_lock_timer: float = 0.0
var _invulnerability_timer: float = 0.0
var _invulnerability_elapsed: float = 0.0
var _aim_direction: Vector2 = Vector2.RIGHT
var _aim_pose: StringName = &""
var _shot_pose: StringName = &""
var _shot_pose_timer := 0.0
var _dash: UndertowDash = UndertowDash.new(self)
var _dead: bool = false
var _death_cue_played := false
var _death_effect: Node2D
var _is_running: bool = false
var _slip_press_queued := false
var _jump_press_queued := false
var _beam_press_queued := false
var _missile_press_queued := false
var _cycle_press_queued := false
var _flux_runtime: PlayerFluxRuntime
var _juice: RefCounted = preload("res://scripts/player/player_juice.gd").new(self)


func _ready() -> void:
	_flux_runtime = PlayerFluxRuntime.new(self, _play_optional_sfx)
	add_to_group(&"player")
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	_configure_optional_sprite_frames()
	_set_ball_form(false)
	_wall_cast_left.position.y = -PlayerConfig.WALL_CHECK_OFFSET
	_wall_cast_right.position.y = -PlayerConfig.WALL_CHECK_OFFSET
	_sprite.flip_h = false
	_sprite.visible = true
	_sprite.play(&"idle")
	_aim_direction = Vector2(facing, 0)
	_update_muzzle_position(&"idle_armed")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(&"jump"):
		_jump_press_queued = true
	if event.is_action_pressed(SLIP_ACTION):
		_slip_press_queued = true
	if event.is_action_pressed(&"fire_beam"):
		_beam_press_queued = true
	if event.is_action_pressed(&"fire_missile"):
		_missile_press_queued = true
	if event.is_action_pressed(&"cycle_beam"):
		_cycle_press_queued = true
	if InputMap.has_action(DASH_ACTION) and event.is_action_pressed(DASH_ACTION):
		_dash.press_queued = true


func _physics_process(delta: float) -> void:
	if _dead or GameState.health <= 0:
		_on_player_died()
		return

	var move_input: float = Input.get_axis("move_left", "move_right")
	_update_damage_timers(delta)
	var jump_held: bool = Input.is_action_pressed("jump")
	var jump_just_pressed := Input.is_action_just_pressed(&"jump") or _jump_press_queued
	_jump_press_queued = false
	_update_jump_timers(delta, jump_just_pressed)
	_update_wall_state(delta)

	_resolve_jump(move_input)

	_apply_jump_cutoff(jump_held)

	velocity.y += _select_gravity() * delta
	_apply_wall_slide(move_input)
	UpdraftCloak.glide(self, jump_held)

	_handle_slip_input()
	_handle_crouch_input()
	_apply_horizontal_movement(move_input, delta)
	_dash.update(delta, move_input)
	_handle_weapon_input(delta)
	_flux_runtime.sync_aura(not is_ball and not _dead)
	_advance_slip(delta)

	velocity.y = minf(velocity.y, PlayerConfig.TERMINAL_VELOCITY)

	var was_on_floor: bool = is_on_floor()
	var previous_position_x: float = global_position.x
	_dash.strike(delta)
	move_and_slide()
	_dash.after_move()
	var actual_horizontal_motion: float = global_position.x - previous_position_x
	if _floor_state_initialized and not was_on_floor and is_on_floor():
		Audio.play_sfx(&"land")
	_floor_state_initialized = true
	if is_spinning and is_on_floor():
		_stop_spin()
	if is_crouching and not is_on_floor():
		_try_stand_up()
	_update_footsteps(delta, actual_horizontal_motion)

	_update_animation()
	_update_camera_look_ahead(delta)
	_juice.call(&"tick", delta)


func _update_damage_timers(delta: float) -> void:
	_hurt_input_lock_timer = maxf(_hurt_input_lock_timer - delta, 0.0)
	_shot_pose_timer = maxf(_shot_pose_timer - delta, 0.0)
	if _shot_pose_timer == 0.0:
		_shot_pose = &""
	_wall_jump_pose_timer = maxf(_wall_jump_pose_timer - delta, 0.0)
	if _invulnerability_timer > 0.0:
		_invulnerability_timer = maxf(_invulnerability_timer - delta, 0.0)
		_invulnerability_elapsed += delta
	else:
		_invulnerability_elapsed = 0.0


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0 or _dead or GameState.health <= 0 or _invulnerability_timer > 0.0:
		return
	if dev_invulnerable:  # Dev cheat: no damage, knockback or flash.
		return
	if _dash.protects():  # Undertow Dash passes through harm.
		return

	var applied_damage := amount
	if GameState.has_ability(&"pressure_seal"):
		applied_damage = ceili(float(amount) / Catalog.PRESSURE_SEAL_DAMAGE_DIVISOR)
	applied_damage = _flux_runtime.absorb_damage(applied_damage)
	if applied_damage <= 0:
		return
	GameState.apply_damage(applied_damage)
	if GameState.health <= 0:
		_on_player_died()
		return

	var knockback_direction: float = -float(facing)
	if source_position != Vector2.ZERO:
		knockback_direction = signf(global_position.x - source_position.x)
		if is_zero_approx(knockback_direction):
			knockback_direction = -float(facing)

	velocity.x = knockback_direction * PlayerConfig.HURT_KNOCKBACK_X
	velocity.y = PlayerConfig.HURT_KNOCKBACK_Y
	_hurt_input_lock_timer = PlayerConfig.HURT_INPUT_LOCK
	_invulnerability_timer = PlayerConfig.INVULN_TIME
	_invulnerability_elapsed = 0.0
	_stop_spin()
	Audio.play_sfx(&"player_hurt")


func _on_player_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_stop_spin()
	_end_dash(false)
	_flux_runtime.on_death()
	if not _death_cue_played:
		_death_cue_played = true
		_play_optional_sfx(&"player_death")
	if is_crouching and _can_stand_up():
		_set_form(PlayerForm.STANDING)
	_sprite.stop()
	_sprite.visible = true
	_death_effect = CombatFeedback.spawn_player_death(self)
	_sprite.visible = false


func apply_bomb_impulse(origin: Vector2, radius: float) -> void:
	if _dead or not is_ball or radius <= 0.0:
		return
	if _ball_center().distance_to(origin) > radius:
		return
	velocity.y = -Catalog.BOMB_LIFT_SPEED
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jump_cutoff_applied = true
	_stop_spin()


func _update_jump_timers(delta: float, jump_just_pressed: bool) -> void:
	if jump_just_pressed:
		_jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if is_on_floor():
		_coyote_timer = PlayerConfig.COYOTE_TIME
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)


func _resolve_jump(move_input: float = 0.0) -> void:
	if _jump_buffer_timer <= 0.0:
		return

	var can_jump: bool = is_on_floor() or _coyote_timer > 0.0
	if is_ball:
		if not can_jump:
			return
		velocity.y = -PlayerConfig.JUMP_VELOCITY
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		_jump_cutoff_applied = false
		Audio.play_sfx(&"jump")
		return

	if can_jump:
		velocity.y = -PlayerConfig.JUMP_VELOCITY
		if GameState.has_ability(&"high_jump"):
			velocity.y = -Catalog.HIGH_JUMP_IMPULSE
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		_jump_cutoff_applied = false
		if move_input != 0.0:
			_start_spin()
		Audio.play_sfx(&"jump")
		return

	_resolve_wall_jump()


func _resolve_wall_jump() -> void:
	var jump_wall_side: int = _wall_side
	if jump_wall_side == 0 and _wall_coyote_timer > 0.0:
		jump_wall_side = _last_wall_side
	if jump_wall_side == 0:
		return

	velocity.y = -PlayerConfig.WALL_JUMP_VELOCITY
	velocity.x = -float(jump_wall_side) * PlayerConfig.WALL_PUSH_VELOCITY
	facing = -jump_wall_side
	_start_spin()
	_jump_buffer_timer = 0.0
	_jump_cutoff_applied = false
	_wall_coyote_timer = 0.0
	_wall_input_lock_timer = PlayerConfig.WALL_INPUT_LOCK
	_wall_jump_pose_timer = 0.12
	Audio.play_sfx(&"jump")


func _apply_jump_cutoff(jump_held: bool) -> void:
	if jump_held or _jump_cutoff_applied or velocity.y >= 0.0:
		return

	velocity.y *= PlayerConfig.JUMP_CUTOFF
	_jump_cutoff_applied = true


func _select_gravity() -> float:
	var gravity: float = (
		PlayerConfig.GRAVITY_RISING if velocity.y < 0.0 else PlayerConfig.GRAVITY_FALLING
	)

	if not is_on_floor() and absf(velocity.y) < PlayerConfig.APEX_THRESHOLD:
		gravity *= PlayerConfig.APEX_GRAVITY_MUL
	return gravity


func _update_wall_state(delta: float) -> void:
	_wall_sliding = false
	_wall_input_lock_timer = maxf(_wall_input_lock_timer - delta, 0.0)
	if is_ball:
		_wall_side = 0
		_last_wall_side = 0
		_wall_coyote_timer = 0.0
		return

	_wall_side = _detect_wall_side()
	if _wall_side != 0:
		_last_wall_side = _wall_side
		_wall_coyote_timer = PlayerConfig.WALL_COYOTE
	else:
		_wall_coyote_timer = maxf(_wall_coyote_timer - delta, 0.0)
		if _wall_coyote_timer == 0.0:
			_last_wall_side = 0


func _detect_wall_side() -> int:
	_wall_cast_left.force_raycast_update()
	_wall_cast_right.force_raycast_update()
	var left_colliding: bool = _wall_cast_left.is_colliding()
	var right_colliding: bool = _wall_cast_right.is_colliding()
	if left_colliding and not right_colliding:
		return -1
	if right_colliding and not left_colliding:
		return 1
	if left_colliding and right_colliding:
		return facing
	return 0


func _apply_wall_slide(move_input: float) -> void:
	_wall_sliding = false
	if is_ball or _wall_side == 0 or velocity.y <= 0.0:
		return
	if signf(move_input) != float(_wall_side):
		return

	velocity.y = minf(velocity.y, PlayerConfig.WALL_SLIDE_SPEED)
	_wall_sliding = true


func _apply_horizontal_movement(move_input: float, delta: float) -> void:
	_is_running = false
	if _wall_input_lock_timer > 0.0 or _hurt_input_lock_timer > 0.0:
		return

	var grounded: bool = is_on_floor()
	var acceleration: float = PlayerConfig.GROUND_ACCEL if grounded else PlayerConfig.AIR_ACCEL
	var friction: float = PlayerConfig.GROUND_FRICTION if grounded else PlayerConfig.AIR_FRICTION
	var max_speed: float = PlayerConfig.WALK_MAX
	_is_running = (Input.is_action_pressed(RUN_ACTION) and not is_ball and not is_crouching)

	if is_ball:
		acceleration = PlayerConfig.ROLL_ACCEL
		friction = PlayerConfig.ROLL_FRICTION
		max_speed = PlayerConfig.ROLL_MAX
	elif _is_running:
		max_speed = PlayerConfig.RUN_MAX
	elif not grounded and absf(velocity.y) < PlayerConfig.APEX_THRESHOLD:
		acceleration *= PlayerConfig.APEX_ACCEL_MUL

	if move_input != 0.0:
		if velocity.x != 0.0 and signf(move_input) != signf(velocity.x):
			acceleration *= PlayerConfig.TURN_BOOST if not is_ball else 1.0
		velocity.x = move_toward(velocity.x, move_input * max_speed, acceleration * delta)
		facing = 1 if move_input > 0.0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	if _wall_sliding:
		facing = -_wall_side


func _handle_weapon_input(delta: float = 0.0) -> void:
	_aim_direction = _calculate_aim_direction()
	_flux_runtime.handle_input()
	var fire_beam_pressed := Input.is_action_just_pressed(&"fire_beam") or _beam_press_queued
	var fire_missile_pressed := (
		Input.is_action_just_pressed(&"fire_missile") or _missile_press_queued
	)
	var cycle_pressed := Input.is_action_just_pressed(&"cycle_beam") or _cycle_press_queued
	_beam_press_queued = false
	_missile_press_queued = false
	_cycle_press_queued = false
	if cycle_pressed and not is_ball:
		_cycle_beam()
	if is_spinning and (_aim_direction.y != 0.0 or fire_beam_pressed or fire_missile_pressed):
		_stop_spin()

	if is_ball:
		_flux_runtime.reset_burst_drain()
		if fire_beam_pressed:
			Weapons.fire(&"bomb", _ball_center(), Vector2.UP)
		return

	var burst_active := _flux_runtime.burst_active()
	if burst_active and Input.is_action_pressed("fire_beam"):
		_shot_pose = _aim_pose
		if _shot_pose == &"" or (is_crouching and _aim_direction.y == 0.0):
			_shot_pose = _horizontal_shot_pose()
		_shot_pose_timer = SHOT_POSE_DURATION
	var burst_pose := _shot_pose if _shot_pose_timer > 0.0 else _aim_pose
	if burst_pose == &"":
		burst_pose = &"idle_armed"
	_update_muzzle_position(burst_pose)
	var burst_valid := false
	if burst_active and Input.is_action_pressed("fire_beam"):
		burst_valid = Weapons.can_flux_burst_fire(_muzzle.global_position, _aim_direction)
		if burst_valid:
			if delta > 0.0:
				_flux_runtime.drain_burst_flux(delta)
			Weapons.fire_flux_burst(_muzzle.global_position, _aim_direction)
		else:
			_flux_runtime.reset_burst_drain()
	else:
		_flux_runtime.reset_burst_drain()

	var firing := (fire_beam_pressed and not burst_active) or fire_missile_pressed
	if firing:
		_shot_pose = _aim_pose
		if _shot_pose == &"" or (is_crouching and _aim_direction.y == 0.0):
			_shot_pose = _horizontal_shot_pose()
		_shot_pose_timer = SHOT_POSE_DURATION
	var muzzle_pose := _shot_pose if _shot_pose_timer > 0.0 else _aim_pose
	if muzzle_pose == &"":
		muzzle_pose = &"idle_armed"
	_update_muzzle_position(muzzle_pose)

	if fire_beam_pressed and not burst_active:
		Weapons.fire(&"beam", _muzzle.global_position, _aim_direction)
	if fire_missile_pressed:
		Weapons.fire(&"missile", _muzzle.global_position, _aim_direction)


func _cycle_beam() -> void:
	var owned_beams: Array[StringName] = []
	if GameState.has_beam:
		owned_beams.append(&"base")
	if GameState.has_ability(&"ice_beam"):
		owned_beams.append(&"ice")
	if GameState.has_ability(&"wave_beam"):
		owned_beams.append(&"wave")
	if owned_beams.size() < 2:
		return
	var current_index := owned_beams.find(GameState.active_beam)
	var next_index := (current_index + 1) % owned_beams.size()
	GameState.set_active_beam(owned_beams[next_index])


func _play_optional_sfx(id: StringName) -> void:
	if Audio.SFX_PATHS.has(id):
		Audio.play_sfx(id)


func _horizontal_shot_pose() -> StringName:
	if is_crouching:
		return &"crouch_shoot_horizontal"
	if not is_on_floor():
		if _sprite.sprite_frames.has_animation(&"shoot_horizontal_air"):
			return &"shoot_horizontal_air"
		return &"shoot_horizontal_air_fallback"
	return &"shoot_horizontal"


func _update_muzzle_position(pose: StringName) -> void:
	var source_offset: Vector2 = _muzzle_offset_for_pose(pose)
	_muzzle.position = Vector2(source_offset.x * float(facing), source_offset.y)


func _muzzle_offset_for_pose(pose: StringName):
	match pose:
		&"shoot_horizontal":
			return PlayerConfig.STANDING_HORIZONTAL_MUZZLE_OFFSET
		&"shoot_horizontal_air", &"shoot_horizontal_air_fallback":
			return PlayerConfig.AIR_HORIZONTAL_MUZZLE_OFFSET
		&"crouch_shoot_horizontal":
			return PlayerConfig.CROUCH_HORIZONTAL_MUZZLE_OFFSET
		&"aim_up":
			return Vector2(15.0, -190.0)
		&"aim_diag_up":
			return Vector2(44.0, -191.0)
		&"aim_diag_down":
			return Vector2(73.0, -95.0)
		&"aim_down":
			return Vector2(24.0, -42.0)
		_:
			return (
				PlayerConfig.AIM_SHOULDER_OFFSET
				+ (
					Vector2(absf(_aim_direction.x), _aim_direction.y)
					* PlayerConfig.AIM_MUZZLE_DISTANCE
				)
			)


func _calculate_aim_direction() -> Vector2:
	var horizontal_held: bool = (
		Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
	)
	if Input.is_action_pressed("move_up"):
		_aim_pose = &"aim_diag_up" if horizontal_held else &"aim_up"
		return Vector2(float(facing) if horizontal_held else 0.0, -1.0).normalized()

	if Input.is_action_pressed("move_down") and not is_on_floor():
		_aim_pose = &"aim_diag_down" if horizontal_held else &"aim_down"
		return Vector2(float(facing) if horizontal_held else 0.0, 1.0).normalized()

	_aim_pose = &""
	return Vector2(float(facing), 0.0)


func _handle_slip_input() -> void:
	var slip_edge := Input.is_action_just_pressed(SLIP_ACTION) or _slip_press_queued
	if not GameState.has_slipstream:
		_slip_press_queued = false
		return
	if _is_slipping or _hurt_input_lock_timer > 0.0:
		return
	if not slip_edge:
		return
	_slip_press_queued = false

	if is_ball:
		if _can_stand_up():
			_begin_slip(false)
	elif is_on_floor() and velocity.y >= 0.0:
		_begin_slip(true)


func _handle_crouch_input() -> void:
	if is_ball or _is_slipping or _dead or _hurt_input_lock_timer > 0.0:
		return
	var down_held := Input.is_action_pressed("move_down")
	if is_crouching:
		if not down_held or not is_on_floor():
			_try_stand_up()
		return
	if is_on_floor() and velocity.y >= 0.0 and down_held:
		_set_form(PlayerForm.CROUCHING)


func _try_stand_up() -> bool:
	if not is_crouching or not _can_stand_up():
		return false
	_set_form(PlayerForm.STANDING)
	return true


func _can_stand_up() -> bool:
	_ceiling_cast.force_shapecast_update()
	return not _ceiling_cast.is_colliding()


func _begin_slip(to_ball: bool) -> void:
	_stop_spin()
	_end_dash(false)
	if to_ball:
		_set_form(PlayerForm.BALL)
	else:
		if not _can_stand_up():
			return
		_set_form(PlayerForm.STANDING)
	_slip_timer = PlayerConfig.SLIP_DURATION
	_is_slipping = true

	if to_ball:
		_sprite.play(&"slip")
	else:
		_sprite.play_backwards(&"slip")
	Audio.play_sfx(&"slip_in" if to_ball else &"slip_out")


func _advance_slip(delta: float) -> void:
	if not _is_slipping:
		return

	_slip_timer = maxf(_slip_timer - delta, 0.0)
	if _slip_timer == 0.0:
		_is_slipping = false
		_sprite.play(&"ball_roll" if is_ball else &"idle")


func _set_form(next_form: PlayerForm) -> void:
	form = next_form
	is_ball = next_form == PlayerForm.BALL
	is_crouching = next_form == PlayerForm.CROUCHING
	_standing_collision.set_deferred("disabled", is_ball or is_crouching)
	_crouch_collision.set_deferred("disabled", not is_crouching)
	_ball_collision.set_deferred("disabled", not is_ball)
	match next_form:
		PlayerForm.BALL:
			_sprite.position = Vector2(0.0, -32.0)
		PlayerForm.CROUCHING:
			_sprite.position = Vector2(0.0, -112.0)
		_:
			_sprite.position = Vector2(0.0, -112.0)


func _set_ball_form(ball_form: bool) -> void:
	_set_form(PlayerForm.BALL if ball_form else PlayerForm.STANDING)


func _ball_center() -> Vector2:
	return global_position + Vector2(0.0, -28.0)


func _configure_optional_sprite_frames() -> void:
	_add_optional_strip_animation(
		&"idle_armed", "res://assets/sprites/player_idle_armed.png", 4, 6.0
	)
	_add_optional_strip_animation(
		&"run_armed", "res://assets/sprites/player_run_armed.png", 8, 12.0
	)
	_add_optional_strip_animation(&"sprint", "res://assets/sprites/player_sprint.png", 8, 14.0)
	_add_optional_strip_animation(
		&"sprint_armed", "res://assets/sprites/player_sprint_armed.png", 8, 14.0
	)
	_add_optional_strip_animation(
		&"jump_armed", "res://assets/sprites/player_jump_armed.png", 3, 8.0
	)
	_add_optional_strip_animation(&"spin", "res://assets/sprites/player_spin.png", 8, 15.0)
	_add_optional_strip_animation(
		&"spin_armed", "res://assets/sprites/player_spin_armed.png", 8, 15.0
	)
	_add_optional_pose_animation(&"aim_up", "res://assets/sprites/player_aim_up.png")
	_add_optional_pose_animation(&"aim_diag_up", "res://assets/sprites/player_aim_diag_up.png")
	_add_optional_pose_animation(&"aim_diag_down", "res://assets/sprites/player_aim_diag_down.png")
	_add_optional_pose_animation(&"aim_down", "res://assets/sprites/player_aim_down.png")
	_add_optional_pose_animation(
		&"shoot_horizontal", "res://assets/sprites/player_shoot_horizontal.png"
	)
	_add_optional_pose_animation(
		&"shoot_horizontal_air", "res://assets/sprites/player_shoot_horizontal_air.png"
	)
	_add_optional_pose_animation(&"crouch", "res://assets/sprites/player_crouch.png")
	_add_optional_pose_animation(&"crouch_armed", "res://assets/sprites/player_crouch_armed.png")
	_add_optional_pose_animation(
		&"crouch_shoot_horizontal", "res://assets/sprites/player_crouch_shoot_horizontal.png"
	)
	_add_optional_pose_animation(&"wall_slide", "res://assets/sprites/player_wall_slide.png")
	_add_optional_pose_animation(
		&"wall_slide_armed", "res://assets/sprites/player_wall_slide_armed.png"
	)
	_add_optional_pose_animation(&"wall_jump", "res://assets/sprites/player_wall_jump.png")
	_add_optional_pose_animation(
		&"wall_jump_armed", "res://assets/sprites/player_wall_jump_armed.png"
	)
	_add_optional_strip_frame_pose(
		&"shoot_horizontal_air_fallback",
		"res://assets/sprites/player_jump_armed.png",
		1,
	)


func _add_optional_strip_animation(
	animation_name: StringName, path: String, frame_count: int, speed: float
) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		return

	var frames: SpriteFrames = _sprite.sprite_frames
	if frames.has_animation(animation_name):
		frames.clear(animation_name)
	else:
		frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, true)
	frames.set_animation_speed(animation_name, speed)
	for index in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(index * 256.0, 0.0, 256.0, 256.0)
		frames.add_frame(animation_name, atlas)


func _add_optional_strip_frame_pose(
	animation_name: StringName, path: String, frame_index: int
) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		return
	var frames := _sprite.sprite_frames
	if frames.has_animation(animation_name):
		frames.clear(animation_name)
	else:
		frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, false)
	frames.set_animation_speed(animation_name, 1.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(frame_index * 256.0, 0.0, 256.0, 256.0)
	frames.add_frame(animation_name, atlas)


func _add_optional_pose_animation(animation_name: StringName, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		return

	var frames: SpriteFrames = _sprite.sprite_frames
	if frames.has_animation(animation_name):
		frames.clear(animation_name)
	else:
		frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, false)
	frames.set_animation_speed(animation_name, 1.0)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(0.0, 0.0, 256.0, 256.0)
	frames.add_frame(animation_name, atlas)


func _update_footsteps(delta: float, actual_horizontal_motion: float) -> void:
	if not is_on_floor() or is_ball or absf(actual_horizontal_motion) <= 0.1:
		_step_timer = 0.0
		return

	_step_timer = maxf(_step_timer - delta, 0.0)
	if _step_timer > 0.0:
		return

	Audio.play_sfx(&"step")
	var actual_horizontal_speed: float = absf(actual_horizontal_motion) / delta
	var speed_ratio: float = clampf(actual_horizontal_speed / PlayerConfig.WALK_MAX, 0.1, 1.0)
	_step_timer = 0.30 / speed_ratio


func _update_animation() -> void:
	_update_invulnerability_visual()
	_sprite.scale = Vector2.ONE
	_sprite.rotation = 0.0
	if form == PlayerForm.STANDING:
		_sprite.position = Vector2(0.0, -112.0)
	_sprite.flip_h = facing < 0
	if _wall_sliding:
		_sprite.flip_h = _wall_side > 0
	if _is_slipping:
		return

	if is_ball:
		_sprite.speed_scale = 1.0
		_sprite.play(&"ball_roll")
		return

	if is_crouching:
		_sprite.speed_scale = 1.0
		var crouch_animation := &"crouch_armed" if GameState.has_beam else &"crouch"
		if (
			GameState.has_beam
			and _shot_pose_timer > 0.0
			and _shot_pose == &"crouch_shoot_horizontal"
			and _sprite.sprite_frames.has_animation(&"crouch_shoot_horizontal")
		):
			crouch_animation = &"crouch_shoot_horizontal"
		if _sprite.sprite_frames.has_animation(crouch_animation):
			_sprite.play(crouch_animation)
		else:
			_sprite.play(_armed_animation_for(&"idle") if GameState.has_beam else &"idle")
		return

	var display_pose := _shot_pose if _shot_pose_timer > 0.0 else _aim_pose
	var using_aim_pose: bool = (
		GameState.has_beam
		and display_pose != &""
		and _sprite.sprite_frames.has_animation(display_pose)
	)
	if using_aim_pose:
		_sprite.play(display_pose)
		return

	if _wall_jump_pose_timer > 0.0:
		var wall_jump_animation := &"wall_jump_armed" if GameState.has_beam else &"wall_jump"
		if _sprite.sprite_frames.has_animation(wall_jump_animation):
			_sprite.play(wall_jump_animation)
			_apply_wall_pose_transform(0)
			return

	if dash_active:
		var dash_animation: StringName = &"sprint_armed" if GameState.has_beam else &"sprint"
		if _sprite.sprite_frames.has_animation(dash_animation):
			_sprite.play(dash_animation)
			_sprite.speed_scale = 1.8
			_sprite.rotation = 0.14 * float(facing)
			return

	if is_spinning:
		var spin_animation: StringName = &"spin_armed" if GameState.has_beam else &"spin"
		if _sprite.sprite_frames.has_animation(spin_animation):
			_sprite.play(spin_animation)
			return

	var base_animation: StringName = (
		(&"sprint" if _is_running else &"run")
		if is_on_floor() and absf(velocity.x) > 0.1
		else (&"jump" if not is_on_floor() else &"idle")
	)
	_sprite.speed_scale = 1.0
	if GameState.has_beam:
		base_animation = _armed_animation_for(base_animation)

	_sprite.play(base_animation)
	if _wall_sliding:
		var wall_slide_animation := &"wall_slide_armed" if GameState.has_beam else &"wall_slide"
		if _sprite.sprite_frames.has_animation(wall_slide_animation):
			_sprite.play(wall_slide_animation)
			_apply_wall_pose_transform(_wall_side)
		else:
			_sprite.frame = 2


func _apply_wall_pose_transform(contact_side: int) -> void:
	_sprite.scale = Vector2.ONE * WALL_POSE_SCALE
	_sprite.position = Vector2(
		-float(contact_side) * WALL_SLIDE_CONTACT_OFFSET_X, WALL_POSE_CENTER_Y
	)


func _update_invulnerability_visual() -> void:
	_sprite.visible = true
	if _invulnerability_timer <= 0.0:
		_sprite.modulate.a = 1.0
		return
	var half_flash_period: float = 0.5 / PlayerConfig.INVULN_FLASH_HZ
	var flash_step: int = floori(maxf(_invulnerability_elapsed - 0.1, 0.0) / half_flash_period)
	_sprite.modulate.a = 1.0 if flash_step % 2 == 0 else 0.28


func _armed_animation_for(base_animation: StringName) -> StringName:
	var armed_animation: StringName = &""
	match base_animation:
		&"idle":
			armed_animation = &"idle_armed"
		&"run":
			armed_animation = &"run_armed"
		&"sprint":
			armed_animation = &"sprint_armed"
		&"jump":
			armed_animation = &"jump_armed"
		_:
			return base_animation
	if _sprite.sprite_frames.has_animation(armed_animation):
		return armed_animation
	return base_animation


func _start_spin() -> void:
	if is_ball or is_spinning:
		return
	is_spinning = true


func _stop_spin() -> void:
	is_spinning = false


# --- Undertow Dash (D19): logic lives in UndertowDash; these are the public entry points. ---


func can_dash() -> bool:
	return _dash.can_start()


func start_dash(direction: int = 0) -> bool:
	return _dash.start(direction)


func _end_dash(keep_speed := true) -> void:
	_dash.end(keep_speed)


func reset_for_spawn(position: Vector2) -> void:
	_clear_death_visual()
	_dead = false
	_death_cue_played = false
	_flux_runtime.reset()
	global_position = position
	velocity = Vector2.ZERO
	_is_running = false
	_slip_press_queued = false
	_jump_press_queued = false
	_beam_press_queued = false
	_missile_press_queued = false
	_cycle_press_queued = false
	_set_form(PlayerForm.STANDING)
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_cutoff_applied = true
	_slip_timer = 0.0
	_is_slipping = false
	_step_timer = 0.0
	_floor_state_initialized = false
	_wall_side = 0
	_last_wall_side = 0
	_wall_coyote_timer = 0.0
	_wall_input_lock_timer = 0.0
	_wall_sliding = false
	_wall_jump_pose_timer = 0.0
	_hurt_input_lock_timer = 0.0
	_invulnerability_timer = 0.0
	_invulnerability_elapsed = 0.0
	_aim_direction = Vector2(float(facing), 0.0)
	_aim_pose = &""
	_shot_pose = &""
	_shot_pose_timer = 0.0
	_stop_spin()
	_dash.reset()
	_camera.position = Vector2.ZERO
	_camera.reset_smoothing()
	_update_muzzle_position(&"idle_armed")
	_sprite.modulate = Color.WHITE
	_sprite.visible = true
	_sprite.play(&"idle")


func _clear_death_visual() -> void:
	if is_instance_valid(_death_effect):
		_death_effect.queue_free()
	_death_effect = null
	if is_instance_valid(_sprite):
		_sprite.modulate = Color.WHITE
		_sprite.visible = true


func _exit_tree() -> void:
	_clear_death_visual()
	if _flux_runtime != null:
		_flux_runtime.cleanup()


func _update_camera_look_ahead(delta: float) -> void:
	var target_x: float = float(facing) * PlayerConfig.CAMERA_LOOK_AHEAD
	var blend: float = minf(delta / PlayerConfig.CAMERA_LOOK_AHEAD_DURATION, 1.0)
	var camera_position: Vector2 = _camera.position
	camera_position.x = lerpf(camera_position.x, target_x, blend)
	_camera.position = camera_position
