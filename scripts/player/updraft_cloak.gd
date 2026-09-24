class_name UpdraftCloak extends Node2D
## Updraft Cloak (internal ability id `high_jump`): a light cloth piece worn at the shoulders that
## billows with velocity, plus a gentle glide. The higher ground jump itself stays in player.gd.
## Glide: while owned, airborne, falling and holding jump, fall speed is capped at GLIDE_FALL_SPEED.

const ABILITY := &"high_jump"
const GLIDE_FALL_SPEED := 260.0
const SEGMENTS := 8
const SEGMENT_LENGTH := 13.0
const ANCHOR := Vector2(-8.0, -128.0)  # shoulder, in player space for facing right
const CLOTH_COLOR := Color(0.62, 0.85, 0.82, 0.92)
const LINING_COLOR := Color(0.94, 0.9, 0.81, 0.95)
const STREAK_COLOR := Color(0.9, 0.97, 1.0, 0.55)
const MIX_RATE := 22050.0

var gliding := false
var _player: CharacterBody2D
var _points: PackedVector2Array = PackedVector2Array()
var _previous: PackedVector2Array = PackedVector2Array()
var _time := 0.0
var _streaks: Array[Dictionary] = []
var _streak_timer := 0.0
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _wind_level := 0.0
var _noise_state := 0.0


func _enter_tree() -> void:
	_player = get_parent() as CharacterBody2D


func _ready() -> void:
	z_index = -1
	top_level = true
	for i in SEGMENTS:
		_points.append(Vector2.ZERO)
		_previous.append(Vector2.ZERO)
	_reset_cloth()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.15
	_audio = AudioStreamPlayer.new()
	_audio.stream = stream
	_audio.volume_db = -14.0
	if AudioServer.get_bus_index(&"SFX") >= 0:
		_audio.bus = &"SFX"
	add_child(_audio)


## One-line hook from Player._physics_process after gravity: finds or creates the cloak child.
static func glide(player: CharacterBody2D, jump_held: bool) -> void:
	var cloak := player.get_node_or_null(^"UpdraftCloak") as UpdraftCloak
	if cloak == null:
		cloak = UpdraftCloak.new()
		cloak.name = &"UpdraftCloak"
		player.add_child(cloak)
	cloak.apply_glide(jump_held)


## Caps fall speed while gliding. Returns true while gliding.
func apply_glide(jump_held: bool) -> bool:
	gliding = (
		jump_held
		and GameState.has_ability(ABILITY)
		and not bool(_player.get("is_ball"))
		and not bool(_player.get("_wall_sliding"))
		and not _player.is_on_floor()
		and _player.velocity.y > GLIDE_FALL_SPEED
	)
	if gliding:
		_player.velocity.y = GLIDE_FALL_SPEED
	return gliding


func _is_worn() -> bool:
	return (
		_player != null
		and GameState.has_ability(ABILITY)
		and not bool(_player.get("is_ball"))
		and _player.visible
	)


func _anchor_world() -> Vector2:
	var facing := int(_player.get("facing"))
	# The spin/tuck pose sits lower and more compact than the standing pose.
	var anchor_y := ANCHOR.y + (26.0 if bool(_player.get("is_spinning")) else 0.0)
	return _player.global_position + Vector2(ANCHOR.x * facing, anchor_y)


func _reset_cloth() -> void:
	if _player == null:
		return
	var origin := _anchor_world()
	var facing := int(_player.get("facing"))
	for i in SEGMENTS:
		var p := origin + Vector2(-facing * 4.0 * i, SEGMENT_LENGTH * i)
		_points[i] = p
		_previous[i] = p


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_time += delta
	var worn := _is_worn()
	visible = worn
	_update_wind_audio(delta, worn and gliding)
	_update_streaks(delta, worn and gliding)
	if not worn:
		_reset_cloth()
		queue_redraw()
		return
	var facing := int(_player.get("facing"))
	var vel := _player.velocity
	# Wind pushes cloth opposite to motion; a little flutter keeps it alive at rest.
	var wind := Vector2(-vel.x, -vel.y * 0.6) * 0.55
	wind.x += -facing * 60.0
	if gliding:
		wind.y -= 700.0
	var gravity := Vector2(0.0, 950.0)
	_points[0] = _anchor_world()
	_previous[0] = _points[0]
	for i in range(1, SEGMENTS):
		var flutter := Vector2(0.0, sin(_time * 9.0 + i * 0.9) * 90.0 * (float(i) / SEGMENTS))
		var accel := gravity + wind + flutter
		var current := _points[i]
		var next := current + (current - _previous[i]) * 0.9 + accel * delta * delta
		_previous[i] = current
		_points[i] = next
	for _pass in 3:
		for i in range(1, SEGMENTS):
			var dir := _points[i] - _points[i - 1]
			var length := dir.length()
			if length > 0.001:
				_points[i] = _points[i - 1] + dir / length * SEGMENT_LENGTH
	queue_redraw()


func _update_streaks(delta: float, active: bool) -> void:
	if active:
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			_streak_timer = randf_range(0.05, 0.11)
			var spawn := (
				_player.global_position
				+ Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 30.0))
			)
			_streaks.append({"pos": spawn, "life": 0.35, "len": randf_range(26.0, 48.0)})
	for s in _streaks:
		s["life"] = float(s["life"]) - delta
		s["pos"] = (s["pos"] as Vector2) + Vector2(0.0, -420.0 * delta)
	_streaks = _streaks.filter(func(s: Dictionary) -> bool: return float(s["life"]) > 0.0)
	if not _streaks.is_empty() or active:
		queue_redraw()


func _update_wind_audio(delta: float, active: bool) -> void:
	var target := 1.0 if active else 0.0
	_wind_level = move_toward(_wind_level, target, delta * (5.0 if active else 3.0))
	if _wind_level <= 0.001:
		if _audio.playing:
			_audio.stop()
			_playback = null
		return
	if not _audio.playing:
		_audio.play()
		_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for i in frames:
		# Low-passed noise with a slow swell reads as a soft whoosh.
		_noise_state = lerpf(_noise_state, randf_range(-1.0, 1.0), 0.08)
		var swell := 0.75 + 0.25 * sin(_time * 5.0 + i * 0.0004)
		var sample := _noise_state * _wind_level * swell * 0.9
		_playback.push_frame(Vector2(sample, sample))


func _draw() -> void:
	for s in _streaks:
		var alpha := clampf(float(s["life"]) / 0.35, 0.0, 1.0)
		var p := (s["pos"] as Vector2) - global_position
		var c := STREAK_COLOR
		c.a *= alpha
		draw_line(p, p + Vector2(0.0, float(s["len"])), c, 2.0, true)
	if not visible or _points.size() < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in SEGMENTS:
		var p := _points[i] - global_position
		var tangent := (_points[mini(i + 1, SEGMENTS - 1)] - _points[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var width := lerpf(13.0, 5.0, float(i) / (SEGMENTS - 1))
		left.append(p + normal * width)
		right.append(p - normal * width)
	var outline := left.duplicate()
	right.reverse()
	outline.append_array(right)
	if Geometry2D.triangulate_polygon(outline).is_empty():
		draw_polyline(left, CLOTH_COLOR, 12.0, true)
	else:
		draw_colored_polygon(outline, CLOTH_COLOR)
	var lining := PackedVector2Array()
	for i in SEGMENTS:
		lining.append(_points[i] - global_position)
	draw_polyline(lining, LINING_COLOR, 3.0, true)
	draw_polyline(outline, Color(0.12, 0.2, 0.22, 0.8), 1.5, true)
