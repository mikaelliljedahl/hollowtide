extends Node2D
## Slipstream presentation (D19): the Ball form (internal id `slipstream`) is shown as a
## glowing water droplet with a trailing wake, velocity squash/stretch, splashes and a
## trickle loop. Purely visual: it reads player state after movement and never touches
## velocity, collision or form rules.

const BODY_CENTER := Vector2(0.0, -28.0)
const BODY_RADIUS := 27.0
const POUR_SECONDS := 0.2
const WAKE_POINTS := 14
const TRICKLE_PATH := "res://assets/audio/sfx/slipstream_trickle.wav"
const BODY_STRIP_PATH := "res://assets/sprites/slipstream_body.png"
const RIM := Color(0.08, 0.36, 0.44, 0.7)
const BODY := Color(0.2, 0.66, 0.76, 0.92)
const CORE := Color(0.72, 0.98, 1.0, 0.9)
const GLOW := Color(0.3, 0.85, 0.95, 0.16)

var _player: CharacterBody2D
var _sprite: AnimatedSprite2D
var _was_ball := false
var _was_on_floor := true
var _last_velocity := Vector2.ZERO
var _pour := 0.0
var _pour_in := true
var _time := 0.0
var _stretch := Vector2.ONE
var _angle := 0.0
var _wake: Array[Vector2] = []
var _drops: Array[Dictionary] = []
var _alpha := 1.0
var _trickle: AudioStreamPlayer
var _body_strip: Texture2D
var _glow: GradientTexture2D


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_sprite = _player.get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
	z_index = 1
	if ResourceLoader.exists(BODY_STRIP_PATH):
		_body_strip = load(BODY_STRIP_PATH) as Texture2D
	var stream := (
		load(TRICKLE_PATH) as AudioStreamWAV if ResourceLoader.exists(TRICKLE_PATH) else null
	)
	if stream != null:
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.data.size() / 2.0)
		_trickle = AudioStreamPlayer.new()
		_trickle.stream = stream
		_trickle.bus = &"SFX"
		_trickle.volume_db = -80.0
		add_child(_trickle)


func _process(delta: float) -> void:
	if _player == null or _sprite == null:
		return
	_time += delta
	var dead := bool(_player.get("_dead"))
	var is_ball := bool(_player.get("is_ball")) and not dead
	var on_floor := _player.is_on_floor()
	var velocity := _player.velocity
	var center := _player.global_position + BODY_CENTER
	if is_ball != _was_ball and not dead:
		_pour = POUR_SECONDS
		_pour_in = is_ball
		_splash(_player.global_position, 10, 1.0)
	_pour = maxf(_pour - delta, 0.0)
	if is_ball and on_floor and not _was_on_floor and _last_velocity.y > 250.0:
		_splash(_player.global_position, clampi(int(_last_velocity.y / 90.0), 4, 12), 0.8)
	_update_shape(velocity, on_floor, delta)
	_update_wake(center, is_ball)
	_update_drops(delta)
	_alpha = _sprite.modulate.a
	_apply_sprite(is_ball, dead)
	_update_trickle(is_ball and on_floor, absf(velocity.x), delta)
	_was_ball = is_ball
	_was_on_floor = on_floor
	_last_velocity = velocity
	visible = is_ball or _pour > 0.0 or not _drops.is_empty()
	queue_redraw()


func _update_shape(velocity: Vector2, on_floor: bool, delta: float) -> void:
	var speed := velocity.length()
	var target_angle := velocity.angle() if speed > 40.0 else (0.0 if _facing() > 0 else PI)
	if on_floor and speed > 40.0:
		target_angle = 0.0 if velocity.x >= 0.0 else PI
	_angle = lerp_angle(_angle, target_angle, minf(delta * 14.0, 1.0))
	var stretch := clampf(speed / 1400.0, 0.0, 0.28)
	var target := Vector2(1.0 + stretch, 1.0 - stretch * 0.45)
	_stretch = _stretch.lerp(target, minf(delta * 12.0, 1.0))


func _update_wake(center: Vector2, is_ball: bool) -> void:
	if is_ball:
		_wake.push_front(center)
	elif not _wake.is_empty():
		_wake.pop_back()
	while _wake.size() > WAKE_POINTS:
		_wake.pop_back()


func _update_drops(delta: float) -> void:
	for drop in _drops:
		drop.vel += Vector2(0.0, 1400.0) * delta
		drop.pos += drop.vel * delta
		drop.life -= delta
	_drops = _drops.filter(func(d: Dictionary) -> bool: return d.life > 0.0)


func _splash(at: Vector2, count: int, power: float) -> void:
	for i in count:
		var angle := randf_range(-PI * 0.92, -PI * 0.08)
		var speed := randf_range(160.0, 420.0) * power
		var drop := {
			"pos": at + Vector2(randf_range(-16.0, 16.0), -4.0),
			"vel": Vector2.from_angle(angle) * speed,
			"life": randf_range(0.22, 0.42),
			"size": randf_range(2.5, 5.0),
		}
		_drops.append(drop)


func _apply_sprite(is_ball: bool, dead: bool) -> void:
	if dead:
		return
	if is_ball:
		_sprite.visible = false
		_sprite.self_modulate = Color.TRANSPARENT
		return
	if _pour > 0.0 and not _pour_in:
		# Rising out of the puddle: grow from the feet, tint fades back to normal.
		var t := 1.0 - _pour / POUR_SECONDS
		var sy := lerpf(0.25, 1.0, ease(t, 0.5))
		_sprite.scale = Vector2(lerpf(1.25, 1.0, t), sy)
		_sprite.position = Vector2(0.0, -112.0 * sy)
		_sprite.self_modulate = Color(0.55, 0.95, 1.0).lerp(Color.WHITE, t)
	else:
		_sprite.self_modulate = Color.WHITE


func _update_trickle(active: bool, speed: float, delta: float) -> void:
	if _trickle == null:
		return
	var level := clampf(speed / 500.0, 0.0, 1.0) if active else 0.0
	var target_db := linear_to_db(maxf(level, 0.0001)) - 4.0
	_trickle.volume_db = move_toward(_trickle.volume_db, target_db, delta * 90.0)
	if level > 0.02 and not _trickle.playing:
		_trickle.play()
	elif level <= 0.02 and _trickle.playing and _trickle.volume_db < -60.0:
		_trickle.stop()
	_trickle.pitch_scale = lerpf(0.9, 1.15, level)


func _facing() -> int:
	return int(_player.get("facing"))


func _draw() -> void:
	for drop in _drops:
		var fade := clampf(drop.life / 0.3, 0.0, 1.0)
		var p := to_local(drop.pos)
		draw_circle(p, drop.size, Color(CORE, 0.85 * fade))
	var grow := 1.0
	if _pour > 0.0:
		var t := 1.0 - _pour / POUR_SECONDS
		grow = ease(t, 0.4) if _pour_in else 1.0 - t
		if _pour_in:
			_draw_pour_column(1.0 - t)
	if grow <= 0.02:
		return
	if not bool(_player.get("is_ball")) and _pour <= 0.0:
		return
	var a := _alpha
	for i in range(_wake.size() - 1, 0, -1):
		var k := 1.0 - float(i) / WAKE_POINTS
		var from := to_local(_wake[i]) + Vector2(0.0, 10.0 * (1.0 - k))
		var to := to_local(_wake[i - 1]) + Vector2(0.0, 10.0 * (1.0 - k))
		var width := BODY_RADIUS * (0.2 + 0.9 * k) * grow
		draw_line(from, to, Color(BODY, 0.35 * k * a), width)
		draw_line(from, to, Color(CORE, 0.25 * k * a), width * 0.3)
	# Mirror instead of rotating past vertical so the highlight stays on top.
	var mirrored := cos(_angle) < 0.0
	var body_scale := _stretch * grow * Vector2(-1.0 if mirrored else 1.0, 1.0)
	draw_set_transform(BODY_CENTER, _angle + (PI if mirrored else 0.0), body_scale)
	var glow_size := BODY_RADIUS * 4.4
	draw_texture_rect(
		_glow_texture(),
		Rect2(-glow_size / 2.0, -glow_size / 2.0, glow_size, glow_size),
		false,
		Color(1, 1, 1, a)
	)
	if _body_strip != null:
		_draw_strip(a)
	else:
		draw_colored_polygon(_droplet(BODY_RADIUS + 1.5, 0.0), Color(RIM, RIM.a * a))
		draw_colored_polygon(_droplet(BODY_RADIUS, 0.6), Color(BODY, BODY.a * a))
		var core := _droplet(BODY_RADIUS * 0.52, 1.3)
		for i in core.size():
			core[i] += Vector2(4.0, -3.0)
		draw_colored_polygon(core, Color(CORE, CORE.a * 0.7 * a))
		draw_circle(Vector2(10.0, -12.0), 4.2, Color(1, 1, 1, 0.85 * a))
		draw_circle(Vector2(3.0, -16.0), 2.0, Color(1, 1, 1, 0.6 * a))
	draw_set_transform(Vector2.ZERO)


func _glow_texture() -> Texture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(GLOW, 0.42))
		gradient.set_color(1, Color(GLOW, 0.0))
		gradient.add_point(0.35, Color(GLOW, 0.2))
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow


func _droplet(radius: float, phase: float) -> PackedVector2Array:
	# Round front (+x), tapering wobbling tail toward -x.
	var points := PackedVector2Array()
	for i in 32:
		var theta := TAU * i / 32.0
		var back := maxf(-cos(theta), 0.0)
		var r := radius * (1.0 + 0.55 * pow(back, 3.0))
		r += sin(theta * 3.0 + _time * 9.0 + phase) * radius * 0.05
		var y_scale := 1.0 - 0.45 * pow(back, 2.0)
		points.append(Vector2(cos(theta) * r, sin(theta) * r * y_scale))
	return points


func _draw_strip(a: float) -> void:
	var frame := int(_time * 10.0) % 4
	var size := _body_strip.get_height()
	var src := Rect2(frame * size, 0, size, size)
	# Art is 128 px frames with the body centered at (64, 94), bottom at y=119;
	# offset so that bottom rests on the feet.
	var dst := Rect2(-size * 0.5, -size * 89.0 / 128.0, size, size)
	draw_texture_rect_region(_body_strip, dst, src, Color(1, 1, 1, a))


func _draw_pour_column(remaining: float) -> void:
	# The standing figure "pours" down into the droplet as a thinning column of water.
	var h := 190.0 * remaining
	if h < 4.0:
		return
	var w := 22.0 * remaining + 8.0
	draw_rect(Rect2(-w / 2.0, -h - 20.0, w, h), Color(BODY, 0.55 * remaining))
	draw_rect(Rect2(-w / 5.0, -h - 20.0, w / 2.5, h), Color(CORE, 0.5 * remaining))
