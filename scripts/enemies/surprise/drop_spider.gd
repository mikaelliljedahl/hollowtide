extends SurpriseEnemy
## Hangs tucked against the ceiling like a rock knob. When the player passes underneath it
## twitches (creak, shake, bright thread and a dashed line down to where it will stop), drops fast
## on a silk thread to just above the floor, dangles and bites for a moment, then climbs back up
## and re-arms.

const TRIGGER_HALF_WIDTH := 84.0
const MAX_DROP := 760.0
const TWITCH_SECONDS := 0.3
const DROP_GRAVITY := 3400.0
const DROP_MAX_SPEED := 1350.0
const DANGLE_SECONDS := 0.95
const CLIMB_SPEED := 300.0
const REARM_SECONDS := 1.3
const HANG_OFFSET := 34.0
const ART_SCALE := 0.5
## Twitch shake amplitude (px) and speed (rad/s): the body rattles on its thread before the drop.
const SHAKE_PX := 3.5
const SHAKE_SPEED := 70.0
const THREAD_COLOR := Color(0.85, 0.88, 0.92)
const DROP_LINE_COLOR := Color(1.0, 0.72, 0.35)
const DROP_DASH := 18.0
const DROP_GAP := 14.0

var _anchor := Vector2.ZERO
var _drop_target_y := 0.0
var _drop_speed := 0.0
var _snapped := false


func _surprise_ready() -> void:
	free_moving = true
	collision_mask = 0
	_anchor = global_position - Vector2(0, HANG_OFFSET)


func _pose_files() -> Dictionary:
	return {&"hidden": "drop_spider", &"attack": "drop_spider_attack"}


func _current_pose() -> StringName:
	return &"attack" if _special_state in [&"drop", &"dangle"] else &"hidden"


func _hurtbox_spans_poses() -> bool:
	return false


func _art_scale() -> float:
	return ART_SCALE


func _art_offset(_texture: Texture2D) -> Vector2:
	# Thread attachment (128, 24) of the frame sits at the top of the body.
	return Vector2(0.0, -28.0 + 104.0 * ART_SCALE)


func _reset_state() -> void:
	_set_state(&"hidden", 0.2)
	_drop_speed = 0.0


func configure_arena(bounds: Rect2) -> void:
	super.configure_arena(bounds)
	_anchor = global_position - Vector2(0, HANG_OFFSET)


func _on_damaged(_kind: StringName) -> void:
	if _special_state == &"hidden":
		_begin_twitch()


func _surprise_ai(player: Node2D, has_target: bool, delta: float) -> void:
	velocity = Vector2.ZERO
	if not _snapped and _age > 0.05:
		_snap_anchor()
	_special_timer -= delta
	match _special_state:
		&"hidden":
			global_position = _anchor + Vector2(0, HANG_OFFSET)
			if _special_timer <= 0.0 and player != null and has_target and _player_below(player):
				_begin_twitch()
		&"twitch":
			var shake := sin(_state_age * SHAKE_SPEED) * SHAKE_PX
			global_position = _anchor + Vector2(shake, HANG_OFFSET)
			if _special_timer <= 0.0:
				global_position = _anchor + Vector2(0, HANG_OFFSET)
				_drop_speed = 0.0
				_set_state(&"drop")
				_sfx(&"spider_drop")
		&"drop":
			_drop_speed = minf(_drop_speed + DROP_GRAVITY * delta, DROP_MAX_SPEED)
			global_position.y = minf(global_position.y + _drop_speed * delta, _drop_target_y)
			if global_position.y >= _drop_target_y:
				_set_state(&"dangle", DANGLE_SECONDS)
				_squash = 1.0
		&"dangle":
			global_position.x = _anchor.x + sin(_state_age * 7.0) * 10.0
			global_position.y = _drop_target_y + sin(_state_age * 11.0) * 4.0
			if _special_timer <= 0.0:
				_set_state(&"climb")
				_sfx(&"spider_climb", -6.0)
		&"climb":
			global_position.x = move_toward(global_position.x, _anchor.x, 120.0 * delta)
			global_position.y -= CLIMB_SPEED * delta
			if global_position.y <= _anchor.y + HANG_OFFSET:
				global_position = _anchor + Vector2(0, HANG_OFFSET)
				_set_state(&"hidden", REARM_SECONDS)


func _begin_twitch() -> void:
	# The stop point locks now so the twitch's drop line shows where the spider will hang.
	_drop_target_y = _find_drop_target()
	_set_state(&"twitch", TWITCH_SECONDS)
	_wind_up(TWITCH_SECONDS)
	_sfx(&"spider_creak")


func _player_below(player: Node2D) -> bool:
	var offset := player.global_position - global_position
	return absf(offset.x) < TRIGGER_HALF_WIDTH and offset.y > 0.0 and offset.y < MAX_DROP + 80.0


func _find_drop_target() -> float:
	var start := _anchor + Vector2(0, HANG_OFFSET)
	var limit := start.y + MAX_DROP
	var hit := _ray(start + Vector2(0, 30), Vector2(start.x, limit + 60.0))
	if not hit.is_empty():
		# Stop at chest height so it dangles in the player's face, not on the floor.
		limit = minf(limit, Vector2(hit["position"]).y - 120.0)
	return maxf(limit, start.y + 60.0)


func _snap_anchor() -> void:
	_snapped = true
	var hit := _ray(global_position + Vector2(0, 20), global_position + Vector2(0, -560))
	if not hit.is_empty():
		_anchor = Vector2(global_position.x, Vector2(hit["position"]).y)
		global_position = _anchor + Vector2(0, HANG_OFFSET)
		_home_position = global_position


func _draw_extra(canvas: CanvasItem) -> void:
	# Silk thread from the ceiling anchor down to the spider; it flares while twitching.
	var top := to_local(_anchor)
	var twitching := _special_state == &"twitch"
	var alpha := 0.5 if _special_state == &"hidden" else 0.75
	canvas.draw_line(
		top,
		Vector2(0, -26),
		Color(THREAD_COLOR, 0.95 if twitching else alpha),
		3.0 if twitching else 2.0,
		true
	)
	if not twitching:
		return
	# Dashed drop line from the body to the locked stop point, with a tick where it will hang.
	var bottom := to_local(Vector2(global_position.x, _drop_target_y))
	var y := 30.0
	while y < bottom.y:
		var end := minf(y + DROP_DASH, bottom.y)
		canvas.draw_line(Vector2(0, y), Vector2(0, end), Color(DROP_LINE_COLOR, 0.8), 3.0, true)
		y += DROP_DASH + DROP_GAP
	canvas.draw_line(
		bottom + Vector2(-22, 0), bottom + Vector2(22, 0), Color(DROP_LINE_COLOR, 0.9), 4.0, true
	)


func _draw_placeholder() -> void:
	var shell := _placeholder_color(Color(0.2, 0.2, 0.23))
	var open := _current_pose() == &"attack"
	if open:
		for i in 4:
			var spread := 14.0 + i * 10.0
			for side in [-1.0, 1.0]:
				var knee := Vector2(side * (spread + 14.0), -4.0 + i * 6.0)
				var foot := Vector2(side * (spread + 26.0), 26.0 + i * 5.0)
				draw_polyline(
					PackedVector2Array([Vector2(side * 8.0, i * 4.0), knee, foot]),
					Color(0.16, 0.16, 0.18),
					3.0
				)
	draw_circle(Vector2(0, -8), 18.0, shell)
	draw_circle(Vector2(0, 16), 13.0, shell)
	var eye := Color(1.0, 0.62, 0.2) if _special_state != &"hidden" else Color(0.4, 0.3, 0.2)
	draw_circle(Vector2(-4, 22), 2.2, eye)
	draw_circle(Vector2(4, 22), 2.2, eye)
