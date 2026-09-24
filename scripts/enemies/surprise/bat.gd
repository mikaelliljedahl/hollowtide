extends SurpriseEnemy
## One swarm bat: erratic swoops at the player, a short hover-screech before each dive, and a
## panicked scatter away from player shots, bomb flashes and muzzle light. Dies to any hit.

const SWOOP_SPEED := 470.0
const RISE_SPEED := 330.0
const FLEE_SPEED := 540.0
const STEER := 2600.0
const FLEE_RADIUS := 170.0
const HOVER_SECONDS := 0.26

var _phase := 0.0
var _goal := Vector2.ZERO
var _flee_from := Vector2.ZERO


func _surprise_ready() -> void:
	collision_mask = 1  # Terrain only: bats flit through the player and each other.
	_phase = _rng.randf_range(0.0, TAU)


func _pose_files() -> Dictionary:
	return {&"up": "bat_fly_up", &"down": "bat_fly_down"}


func _current_pose() -> StringName:
	var rate := 26.0 if _special_state == &"hover" else 17.0
	return &"up" if sin(_age * rate + _phase) > 0.0 else &"down"


func _art_scale() -> float:
	return 1.25


func _art_offset(_texture: Texture2D) -> Vector2:
	return Vector2.ZERO


func _faces_player() -> bool:
	return _special_state == &"hover"


func _reset_state() -> void:
	_set_state(&"burst", _rng.randf_range(0.28, 0.5))


## Called by the roost right after spawning so each bat scatters in its own direction.
func launch(initial_velocity: Vector2) -> void:
	velocity = initial_velocity
	_set_state(&"burst", _rng.randf_range(0.28, 0.5))


func _surprise_ai(player: Node2D, has_target: bool, delta: float) -> void:
	_special_timer -= delta
	var threat := _nearest_light()
	if threat != Vector2.INF and _special_state != &"flee":
		_flee_from = threat
		_set_state(&"flee", _rng.randf_range(0.45, 0.7))
		_sfx(&"bat_screech", -6.0, _rng.randf_range(1.15, 1.35))
	var desired := velocity
	match _special_state:
		&"burst":
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if _special_timer <= 0.0:
				_pick_rise(player)
			return
		&"hover":
			desired = Vector2(sin(_age * 9.0 + _phase) * 60.0, sin(_age * 13.0) * 40.0)
			if _special_timer <= 0.0 and player != null and has_target:
				_goal = player.global_position + Vector2(_rng.randf_range(-40, 40), -24.0)
				_set_state(&"swoop", 0.95)
				_sfx(&"bat_swoop", -8.0, _rng.randf_range(0.9, 1.2))
			elif _special_timer <= 0.0:
				_pick_rise(player)
		&"swoop":
			var to_goal := _goal - global_position
			desired = to_goal.normalized() * SWOOP_SPEED
			desired += to_goal.orthogonal().normalized() * sin(_age * 14.0 + _phase) * 110.0
			if to_goal.length() < 36.0 or _special_timer <= 0.0 or get_slide_collision_count() > 0:
				_pick_rise(player)
		&"rise":
			var to_goal := _goal - global_position
			desired = to_goal.normalized() * RISE_SPEED
			desired.y += sin(_age * 11.0 + _phase) * 90.0
			if to_goal.length() < 40.0 or _special_timer <= 0.0:
				_set_state(&"hover", HOVER_SECONDS + _rng.randf_range(0.0, 0.5))
				_wind_up(HOVER_SECONDS)
				if _rng.randf() < 0.5:
					_sfx(&"bat_screech", -10.0, _rng.randf_range(0.9, 1.3))
		&"flee":
			var away := global_position - _flee_from
			desired = (away.normalized() + Vector2(0, -0.6)).normalized() * FLEE_SPEED
			if _special_timer <= 0.0:
				_pick_rise(player)
	velocity = velocity.move_toward(desired, STEER * delta)


func _pick_rise(player: Node2D) -> void:
	var anchor := player.global_position if player != null else _home_position
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	_goal = anchor + Vector2(side * _rng.randf_range(140.0, 280.0), -_rng.randf_range(170.0, 280.0))
	if arena_bounds.size != Vector2.ZERO:
		_goal = _clamp_to_arena(_goal)
	_set_state(&"rise", _rng.randf_range(0.5, 0.9))


## Position of the nearest bright thing (player shot, bomb, muzzle flash) within range.
func _nearest_light() -> Vector2:
	var best := Vector2.INF
	var best_distance := FLEE_RADIUS
	for group in [&"transient", &"bombs", &"bat_repel"]:
		for node in get_tree().get_nodes_in_group(group):
			var light := node as Node2D
			if light == null or node is EnemyProjectile or node is CombatEnemy:
				continue
			var distance := light.global_position.distance_to(global_position)
			if distance < best_distance:
				best_distance = distance
				best = light.global_position
	return best


func _decorate_sprite() -> void:
	_sprite.rotation = clampf(velocity.x / 2400.0, -0.25, 0.25)


func _draw_placeholder() -> void:
	var body := _placeholder_color(Color(0.16, 0.15, 0.18))
	var flap := sin(_age * 17.0 + _phase)
	var tip := -18.0 * flap
	draw_colored_polygon(
		PackedVector2Array([Vector2(-6, -2), Vector2(-34, tip - 6), Vector2(-24, tip + 8)]), body
	)
	draw_colored_polygon(
		PackedVector2Array([Vector2(6, -2), Vector2(34, tip - 6), Vector2(24, tip + 8)]), body
	)
	draw_circle(Vector2.ZERO, 10.0, body)
	var eye := Color(0.55, 0.95, 0.9) if _special_state == &"hover" else Color(0.35, 0.6, 0.6)
	draw_circle(Vector2(4.0 * _facing, -3), 2.0, eye)
