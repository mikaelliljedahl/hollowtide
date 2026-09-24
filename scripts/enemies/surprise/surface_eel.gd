extends SurpriseEnemy
## Lives under a lava or water surface (place the spawn ON the surface line). When the player
## comes near the edge, bubbles and ripples boil up for a beat, then the eel rears out in an
## arc toward her, holds for a moment and sinks back. Submerged it cannot be hit at all.
## Variant: `liquid` = lava | water | auto (auto: depths rooms are water, everything else lava).

const TRIGGER_HALF_WIDTH := 320.0
const TRIGGER_HEIGHT := 440.0
const BUBBLE_SECONDS := 0.65
const RISE_SECONDS := 0.24
const HOLD_SECONDS := 0.5
const SINK_SECONDS := 0.3
const COOLDOWN_SECONDS := 1.5
const ART_SCALE := 1.1
## Where the body leaves the liquid (x) in the 256 px art, and the head relative to it.
const EMERGE_X_IN_ART := 95.0
const HEAD_IN_ART := Vector2(55.0, -226.0)

@export var liquid: StringName = &"auto"

var _surface := Vector2.ZERO
var _rise := 0.0
var _exposed := true


func _surprise_ready() -> void:
	free_moving = true
	collision_mask = 0
	_surface = global_position
	_set_exposed(false)


func configure_arena(bounds: Rect2) -> void:
	arena_bounds = bounds
	# Layout markers sit at a liquid cell centre (surface = that cell's top edge) or in the air
	# cell directly above a liquid basin (surface = the marker cell's bottom edge).
	var cell_top := floorf(global_position.y / 64.0) * 64.0
	if (
		not _liquid_at(Vector2(global_position.x, cell_top + 32.0))
		and _liquid_at(Vector2(global_position.x, cell_top + 96.0))
	):
		cell_top += 64.0
	_surface = Vector2(global_position.x, cell_top + 6.0)
	global_position = _surface
	_home_position = _surface


## True when `point` lies inside a sibling lava/water basin marker (anything with `hazard_size`).
func _liquid_at(point: Vector2) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for node in parent.get_children():
		var size = node.get(&"hazard_size") if node is Node2D else null
		if size is Vector2:
			var centre := (node as Node2D).global_position
			if Rect2(centre - size * 0.5, size).has_point(point):
				return true
	return false


func _pose_files() -> Dictionary:
	return {&"strike": "surface_eel_" + String(_liquid())}


func _current_pose() -> StringName:
	return &"strike"


func _liquid() -> StringName:
	if liquid == &"lava" or liquid == &"water":
		return liquid
	var node := get_parent()
	while node != null:
		if node.get(&"area_id") != null:
			liquid = &"water" if StringName(node.get(&"area_id")) == &"depths" else &"lava"
			return liquid
		node = node.get_parent()
	return &"lava"


func _art_scale() -> float:
	return ART_SCALE


func _faces_player() -> bool:
	return _special_state in [&"lurk", &"bubble"]


func _reset_state() -> void:
	_set_state(&"lurk", 0.6)
	_rise = 0.0
	if _surface != Vector2.ZERO:
		global_position = _surface


func _contact_active() -> bool:
	return _exposed


func _hit_gate(_kind: StringName) -> int:
	return HitResult.Reaction.PASS if not _exposed else NO_GATE


func _surprise_ai(player: Node2D, has_target: bool, delta: float) -> void:
	velocity = Vector2.ZERO
	_special_timer -= delta
	match _special_state:
		&"lurk":
			_rise = 0.0
			if _special_timer <= 0.0 and player != null and has_target and _player_near(player):
				_set_state(&"bubble", BUBBLE_SECONDS)
				_sfx(&"eel_bubble")
		&"bubble":
			if _special_timer <= 0.0:
				_set_exposed(true)
				_set_state(&"rise", RISE_SECONDS)
				_sfx(&"eel_strike")
		&"rise":
			_rise = clampf(_state_age / RISE_SECONDS, 0.0, 1.0)
			if _special_timer <= 0.0:
				_rise = 1.0
				_set_state(&"hold", HOLD_SECONDS)
		&"hold":
			_rise = 1.0
			if _special_timer <= 0.0:
				_set_state(&"sink", SINK_SECONDS)
		&"sink":
			_rise = clampf(1.0 - _state_age / SINK_SECONDS, 0.0, 1.0)
			if _special_timer <= 0.0:
				_rise = 0.0
				_set_exposed(false)
				_set_state(&"lurk", COOLDOWN_SECONDS)
				_sfx(&"eel_splash", -6.0)
	_place_head()


func _player_near(player: Node2D) -> bool:
	var offset := player.global_position - _surface
	return absf(offset.x) < TRIGGER_HALF_WIDTH and offset.y < 60.0 and offset.y > -TRIGGER_HEIGHT


func _head_offset(rise: float) -> Vector2:
	var eased := 1.0 - pow(1.0 - rise, 3.0)
	var head := HEAD_IN_ART * ART_SCALE
	var sway := sin(_age * 9.0) * 6.0 if _special_state == &"hold" else 0.0
	return Vector2((head.x + sway) * _facing, head.y * eased)


func _place_head() -> void:
	global_position = _surface + _head_offset(_rise)


func _set_exposed(active: bool) -> void:
	_exposed = active
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null:
		body.set_deferred("disabled", not active)
	collision_layer = 8 if active else 0
	if _projectile_hurtbox != null:
		_projectile_hurtbox.set_enabled(active)


func _thaw() -> void:
	super._thaw()
	if not _exposed:
		collision_layer = 0


func _decorate_sprite() -> void:
	# Anchor the art's bottom-centre on the surface; scale.y grows as it rears out.
	var scale_y := maxf(_rise, 0.001)
	var frame_half := 128.0 * ART_SCALE
	_sprite.scale.y *= scale_y
	var emerge := (128.0 - EMERGE_X_IN_ART) * ART_SCALE * _facing
	_sprite.position = to_local(_surface) + Vector2(emerge, -frame_half * scale_y)
	_sprite.visible = _rise > 0.01


func _surface_color() -> Color:
	return Color(1.0, 0.55, 0.18) if _liquid() == &"lava" else Color(0.45, 0.85, 0.95)


func _draw_extra(canvas: CanvasItem) -> void:
	var local_surface := to_local(_surface)
	var tint := _surface_color()
	if _special_state == &"lurk":
		# A faint, slow ripple is the only tell while it waits.
		var ring := fmod(_age * 0.5, 1.0)
		canvas.draw_arc(
			local_surface,
			10.0 + ring * 30.0,
			PI,
			TAU,
			14,
			Color(tint, 0.18 * (1.0 - ring)),
			1.5,
			true
		)
	elif _special_state == &"bubble":
		# Boiling tell: a glowing welling spot, fat rising bubbles and expanding rings.
		var strength := clampf(_state_age / BUBBLE_SECONDS, 0.0, 1.0)
		var bright := tint.lerp(Color.WHITE, 0.45)
		canvas.draw_set_transform(local_surface, 0.0, Vector2(1.0, 0.35))
		canvas.draw_circle(Vector2.ZERO, 30.0 + 40.0 * strength, Color(tint, 0.22 * strength))
		canvas.draw_circle(Vector2.ZERO, 14.0 + 20.0 * strength, Color(bright, 0.3 * strength))
		canvas.draw_set_transform(Vector2.ZERO)
		for i in 12:
			var seed_x := sin(float(i) * 12.9898) * 43758.5453
			var x := (seed_x - floorf(seed_x) - 0.5) * 130.0
			var rise := fmod(_age * (1.3 + float(i) * 0.13) + float(i) * 0.37, 1.0)
			canvas.draw_circle(
				local_surface + Vector2(x, -rise * 70.0),
				3.0 + 6.0 * (1.0 - rise) * strength,
				Color(bright, 0.85 * strength * (1.0 - rise))
			)
		for ring_index in 3:
			var ring := fmod(_age * 1.6 + float(ring_index) / 3.0, 1.0)
			canvas.draw_set_transform(local_surface, 0.0, Vector2(1.0, 0.3))
			canvas.draw_arc(
				Vector2.ZERO,
				16.0 + ring * 90.0,
				0.0,
				TAU,
				28,
				Color(bright, 0.7 * strength * (1.0 - ring)),
				3.5,
				true
			)
			canvas.draw_set_transform(Vector2.ZERO)
	elif _rise > 0.0:
		# Churned surface where the body breaks through.
		canvas.draw_arc(local_surface, 34.0, PI, TAU, 18, Color(tint, 0.55), 3.0, true)


func _draw_placeholder() -> void:
	if _rise <= 0.01:
		return
	var color := _placeholder_color(
		Color(0.16, 0.12, 0.1) if _liquid() == &"lava" else Color(0.14, 0.2, 0.26)
	)
	var base := to_local(_surface)
	var control := base + Vector2(-50.0 * _facing, -150.0 * _rise)
	var points := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		points.append(base.lerp(control, t).lerp(control.lerp(Vector2.ZERO, t), t))
	draw_polyline(points, color, 24.0, true)
	draw_circle(Vector2.ZERO, 18.0, color)
	draw_circle(Vector2(8.0 * _facing, -6.0), 3.5, _surface_color())
