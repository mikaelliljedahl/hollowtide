extends SurpriseEnemy
## Area stalker: a patient predator that keeps its distance, paces, and pounces with a clear
## crouch-and-growl wind-up. Hit it and it springs back out of reach. In the campaign it follows
## the player between rooms of its area (see StalkerFollower) and dies for good.

const NEAR_DISTANCE := 230.0
const FAR_DISTANCE := 390.0
const APPROACH_SPEED := 300.0
const BACKOFF_SPEED := 260.0
const PACE_SPEED := 120.0
const WINDUP_SECONDS := 0.46
const POUNCE_SPEED_MIN := 430.0
const POUNCE_SPEED_MAX := 800.0
const POUNCE_LIFT := -560.0
const RECOVER_SECONDS := 0.55
const RETREAT_SECONDS := 0.42
const RETREAT_SPEED := 460.0
const GRAVITY := 2000.0
const SIGHT_DISTANCE := 900.0

## True for the copy StalkerFollower spawns at the door the player used.
var is_follower := false
var _follower: StalkerFollower
var _area: StringName = &""
var _pace_sign := 1.0
var _pounce_dir := 1.0
var _removed := false


func _surprise_ready() -> void:
	grounded = true
	_attack_timer = 1.4
	_follower = StalkerFollower.attach(self)
	if _follower == null:
		return
	_area = StalkerFollower.area_of(self)
	if _follower.is_defeated(_area) or (_follower.is_hunting(_area) and not is_follower):
		# Already dead, or the live one is out hunting the player elsewhere in this area.
		_removed = true
		_dying = true
		hide()
		collision_layer = 0
		process_mode = Node.PROCESS_MODE_DISABLED
		queue_free.call_deferred()
		return
	var room := StalkerFollower.find_root(self).get(&"current_room") as Node2D
	if room != null and room.has_method(&"size_px"):
		# In the campaign it hunts across the whole room, not just its spawn box.
		var size: Vector2 = room.call(&"size_px")
		arena_bounds = Rect2(room.global_position + Vector2(64, 64), size - Vector2(128, 96))
	health = clampi(_follower.stored_hp(_area, max_health), 1, max_health)
	_follower.register(_area, health)
	if is_follower:
		_follower.mark_hunting(_area)
		_set_state(&"enter", 0.5)
		_sfx(&"stalker_growl")


func _exit_tree() -> void:
	if _follower != null and is_instance_valid(_follower) and not _removed and not _dying:
		_follower.store(_area, health)


func _on_defeated() -> void:
	if _follower != null and is_instance_valid(_follower) and not _removed:
		_follower.defeat(_area)
	_sfx(&"stalker_death")


func _pose_files() -> Dictionary:
	return {&"idle": "stalker", &"pounce": "stalker_pounce"}


func _current_pose() -> StringName:
	return &"pounce" if _special_state == &"pounce" else &"idle"


func _art_scale() -> float:
	return 0.95


func _faces_player() -> bool:
	return _special_state != &"pounce"


func _reset_state() -> void:
	_set_state(&"prowl", 0.0)


func _on_damaged(_kind: StringName) -> void:
	if _special_state in [&"prowl", &"recover", &"windup", &"enter"]:
		_set_state(&"retreat", RETREAT_SECONDS)
		_telegraph_remaining = 0.0
		_attack_timer = minf(_attack_timer, 0.9)
		_sfx(&"stalker_hiss", -4.0)


func _surprise_ai(player: Node2D, has_target: bool, delta: float) -> void:
	_special_timer -= delta
	_apply_gravity(delta, GRAVITY)
	if player == null or not has_target:
		_ground_toward(0.0, delta)
		return
	var offset := player.global_position - global_position
	var distance := absf(offset.x)
	var toward := signf(offset.x) if offset.x != 0.0 else 1.0
	if (
		_follower != null
		and not is_follower
		and offset.length() < SIGHT_DISTANCE
		and _line_of_sight(player.global_position + Vector2(0, -30))
	):
		_follower.mark_hunting(_area)
	match _special_state:
		&"enter":
			_ground_toward(toward * APPROACH_SPEED, delta)
			if _special_timer <= 0.0:
				_set_state(&"prowl")
		&"prowl":
			if distance < NEAR_DISTANCE:
				_ground_toward(-toward * BACKOFF_SPEED, delta)
			elif distance > FAR_DISTANCE:
				_ground_toward(toward * APPROACH_SPEED, delta)
			else:
				if _rng.randf() < delta * 0.8 or is_on_wall():
					_pace_sign = -_pace_sign
				_ground_toward(_pace_sign * PACE_SPEED, delta)
			if (
				_attack_timer <= 0.0
				and is_on_floor()
				and distance > 150.0
				and distance < 520.0
				and absf(offset.y) < 240.0
			):
				_pounce_dir = toward
				_set_state(&"windup", WINDUP_SECONDS)
				_wind_up(WINDUP_SECONDS)
				_sfx(&"stalker_growl")
		&"windup":
			_ground_toward(0.0, delta * 2.0)
			if _special_timer <= 0.0:
				var speed := clampf(distance * 1.45, POUNCE_SPEED_MIN, POUNCE_SPEED_MAX)
				velocity = Vector2(_pounce_dir * speed, POUNCE_LIFT + minf(offset.y, 0.0) * 0.6)
				_facing = _pounce_dir
				_set_state(&"pounce", 0.2)
				_sfx(&"stalker_pounce")
		&"pounce":
			if _special_timer <= 0.0 and is_on_floor():
				_set_state(&"recover", RECOVER_SECONDS)
				_squash = 1.0
		&"recover":
			_ground_toward(0.0, delta)
			if _special_timer <= 0.0:
				_attack_timer = _rng.randf_range(1.8, 2.8)
				_set_state(&"prowl")
		&"retreat":
			_ground_toward(-toward * RETREAT_SPEED, delta * 1.5)
			if _special_timer <= 0.0:
				_set_state(&"prowl")


func _decorate_sprite() -> void:
	match _special_state:
		&"windup":
			var t := clampf(_state_age / WINDUP_SECONDS, 0.0, 1.0)
			_sprite.scale *= Vector2(1.0 + 0.08 * t, 1.0 - 0.14 * t)
			_sprite.position.y += 10.0 * t
			_sprite.position.x += sin(_age * 50.0) * 1.5 * t
		&"pounce":
			_sprite.rotation = clampf(velocity.y / 2600.0, -0.3, 0.3) * _facing


func _draw_placeholder() -> void:
	var color := _placeholder_color(Color(0.18, 0.18, 0.21))
	var crouch := 8.0 if _special_state == &"windup" else 0.0
	var stretch := 1.3 if _special_state == &"pounce" else 1.0
	var body := PackedVector2Array(
		[
			Vector2(-50 * stretch, -12 + crouch),
			Vector2(-20, -30 + crouch),
			Vector2(30 * stretch, -28 + crouch),
			Vector2(56 * stretch, -18 + crouch),
			Vector2(44 * stretch, -4 + crouch),
			Vector2(-44, 0 + crouch),
		]
	)
	draw_colored_polygon(_mirror(body), color)
	for leg_x: float in [-36.0, -22.0, 22.0, 36.0]:
		var x := leg_x * stretch * _facing
		draw_line(Vector2(x, -6 + crouch), Vector2(x + 4.0 * _facing, 25), color, 5.0)
	draw_line(
		Vector2(-50 * stretch * _facing, -12 + crouch),
		Vector2(-86 * _facing, -30 + sin(_age * 3.0) * 6.0),
		color,
		4.0
	)
	var glow := 1.0 if _special_state in [&"windup", &"pounce"] else 0.55
	draw_circle(Vector2(46 * stretch * _facing, -20 + crouch), 3.0, Color(1.0, 0.62, 0.2, glow))
