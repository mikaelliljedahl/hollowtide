class_name BeamShot extends ProjectileBase

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/beam/beam_impact.tscn")
const BASE_TEXTURE = preload("res://assets/sprites/effects/base_core.png")
const ICE_TEXTURE = preload("res://assets/sprites/effects/ice_core.png")
const WAVE_TEXTURE = preload("res://assets/sprites/effects/wave_core.png")

## D19: `ice` is shown as Bubble Snare (a drifting air bubble) and `wave` as Echo Shot (a sound
## pulse that ricochets off terrain up to ECHO_MAX_BOUNCES times). Both are drawn procedurally.
const ECHO_COLOR := Color(0.72, 0.62, 1.0, 1.0)
const ECHO_CORE := Color(0.82, 0.98, 1.0, 1.0)
const BUBBLE_COLOR := Color(0.72, 0.95, 1.0, 1.0)
## Seed Crossbow base bolt: a faint leaf-green to turquoise trail behind the seed.
const SEED_TRAIL_OUTER := Color(0.36, 0.86, 0.56, 0.16)
const SEED_TRAIL_INNER := Color(0.66, 1.0, 0.86, 0.55)
const CORE_FRAME_SIZE := Vector2(96.0, 64.0)
const BASE_CORE_ANCHOR := Vector2(88.0, 32.0)
const ICE_CORE_ANCHOR := Vector2(88.0, 31.0)
const WAVE_CORE_ANCHOR := Vector2(63.0, 32.0)
const CORE_FPS := 22.0
const WAVE_CORE_FPS := 30.0
const MAX_RECORDED_PHYSICS_POINTS := 64

@onready var _core: Sprite2D = $Core
@onready var _trail: BeamFxTrail = $Trail

var _long_beam_enabled := false
var _visual_age := 0.0
var bounces := 0
var _traversed_physics_points: PackedVector2Array


func _ready() -> void:
	speed = 1800.0
	lifetime = 0.36
	damage_amount = Catalog.BEAM_DAMAGE
	damage_kind = &"beam"
	super._ready()
	_apply_visual_profile()


func _process(delta: float) -> void:
	_visual_age += delta
	var fps := WAVE_CORE_FPS if damage_kind == &"wave" else CORE_FPS
	_core.frame = int(_visual_age * fps) % _core.hframes
	if _procedural_kind():
		queue_redraw()


func launch(new_direction: Vector2) -> void:
	super.launch(new_direction)
	bounces = 0
	_traversed_physics_points.clear()
	if is_node_ready():
		_trail.clear_points()
	_record_physics_point(global_position)


func set_long_beam_enabled(enabled: bool) -> void:
	_long_beam_enabled = enabled
	if is_node_ready():
		_trail.set_long_history(enabled)


func _damage_kind_changed() -> void:
	if is_node_ready():
		_visual_age = 0.0
		_apply_visual_profile()


func _physics_point_traversed(point: Vector2) -> void:
	_record_physics_point(point)


func _handle_collision(hit: Dictionary) -> bool:
	if damage_kind == &"wave" and bounces < Catalog.ECHO_MAX_BOUNCES and _is_ricochet_surface(hit):
		_ricochet(hit)
		return true
	return super._handle_collision(hit)


func _is_ricochet_surface(hit: Dictionary) -> bool:
	if hit.get("gate_limit", false):
		return false
	var target := hit.get("collider") as Node
	return target != null and _is_terrain(target) and _damage_target(target) == null


func _ricochet(hit: Dictionary) -> void:
	var impact := Vector2(hit.get("position", global_position))
	var normal := Vector2(hit.get("normal", Vector2.ZERO))
	if normal.is_zero_approx():
		# Shape overlaps carry no normal: probe the surface along the travel direction.
		var probe := PhysicsRayQueryParameters2D.create(
			impact - _direction * 24.0, impact + _direction * 24.0, TERRAIN_COLLISION_BIT
		)
		var surface := get_world_2d().direct_space_state.intersect_ray(probe)
		normal = Vector2(surface.get("normal", -_direction))
		impact = Vector2(surface.get("position", impact))
	normal = normal.normalized()
	_physics_point_traversed(impact)
	bounces += 1
	_direction = _direction.bounce(normal).normalized()
	if _direction.dot(normal) <= 0.05:
		_direction = normal
	rotation = _direction.angle()
	global_position = impact + normal * 10.0  # Clear of the surface for the shape query.
	_record_physics_point(global_position)
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	ArsenalFx.spawn_rings(parent, impact, 34.0, ECHO_COLOR, 0.28, 2)
	GameJuice.play_sfx(&"echo_bounce", &"beam_ricochet")


func _gate_impact(position: Vector2, normal: Vector2) -> void:
	_spawn_impact(position, &"grate", normal)


func _impact(position: Vector2, reaction: StringName, normal: Vector2) -> void:
	_spawn_impact(position, reaction, normal)


func visual_signature() -> StringName:
	match damage_kind:
		&"ice":
			return &"bubble_snare"
		&"wave":
			return &"echo_pulse"
		_:
			return &"base_authored_core"


func core_atlas_path() -> String:
	match damage_kind:
		&"ice":
			return "res://assets/sprites/effects/ice_core.png"
		&"wave":
			return "res://assets/sprites/effects/wave_core.png"
		_:
			return "res://assets/sprites/effects/base_core.png"


func core_kernel_local_position() -> Vector2:
	return _core.position + _core_anchor() - CORE_FRAME_SIZE * 0.5


func traversed_physics_points() -> PackedVector2Array:
	return _traversed_physics_points.duplicate()


func trail_physics_points() -> PackedVector2Array:
	return _trail.get_physics_points()


func trail_history_seconds() -> float:
	return _trail.history_seconds


func _record_physics_point(point: Vector2) -> void:
	if (
		not _traversed_physics_points.is_empty()
		and _traversed_physics_points[-1].is_equal_approx(point)
	):
		return
	_traversed_physics_points.append(point)
	while _traversed_physics_points.size() > MAX_RECORDED_PHYSICS_POINTS:
		_traversed_physics_points.remove_at(0)
	if is_node_ready() and _has_trail():
		_trail.record_physics_point(point)


func _has_trail() -> bool:
	return damage_kind in [&"beam", &"base", &"wave"]


func _procedural_kind() -> bool:
	return damage_kind in [&"ice", &"wave"]


func _draw() -> void:
	match damage_kind:
		&"ice":
			_draw_bubble()
		&"wave":
			_draw_echo()


func _draw_bubble() -> void:
	var wobble := Vector2(
		1.0 + 0.08 * sin(_visual_age * 26.0), 1.0 - 0.08 * sin(_visual_age * 26.0)
	)
	draw_set_transform(Vector2.ZERO, 0.0, wobble)
	draw_circle(Vector2.ZERO, 13.0, Color(BUBBLE_COLOR, 0.16))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 28, Color(BUBBLE_COLOR, 0.9), 2.2, true)
	draw_arc(Vector2.ZERO, 11.0, PI * 0.1, PI * 0.9, 12, Color(1.0, 0.75, 0.95, 0.5), 1.6, true)
	draw_circle(Vector2(-4.5, -5.0), 3.2, Color(1.0, 1.0, 1.0, 0.85))
	draw_set_transform(Vector2.ZERO)
	for index in 3:
		var t := fmod(_visual_age * 3.0 + float(index) * 0.33, 1.0)
		draw_circle(
			Vector2(-18.0 - t * 34.0, sin(float(index) * 2.1 + _visual_age * 9.0) * 6.0),
			3.0 * (1.0 - t),
			Color(BUBBLE_COLOR, 0.55 * (1.0 - t))
		)


func _draw_echo() -> void:
	# Wavefront: nested arcs opening forward, pulsing like a sound ring.
	var pulse := 0.5 + 0.5 * sin(_visual_age * 40.0)
	for index in 3:
		var radius := 8.0 + float(index) * 7.0 + pulse * 2.0
		var alpha := 0.95 - float(index) * 0.28
		draw_arc(
			Vector2(-float(index) * 7.0, 0.0),
			radius,
			-0.95,
			0.95,
			14,
			Color(ECHO_COLOR, alpha * 0.4),
			6.0,
			true
		)
		draw_arc(
			Vector2(-float(index) * 7.0, 0.0),
			radius,
			-0.95,
			0.95,
			14,
			Color(ECHO_CORE, alpha),
			2.2,
			true
		)
	draw_circle(Vector2.ZERO, 4.5, Color(ECHO_CORE, 0.95))


func _apply_visual_profile() -> void:
	_core.visible = not _procedural_kind()
	queue_redraw()
	_core.texture = _core_texture()
	_core.hframes = 8 if damage_kind == &"wave" else 4
	_core.frame = 0
	_core.position = -(_core_anchor() - CORE_FRAME_SIZE * 0.5)
	_trail.history_scale = 2.2 if damage_kind == &"wave" else 1.0
	var echo := damage_kind == &"wave"
	_trail.outer_color = Color(ECHO_COLOR, 0.2) if echo else SEED_TRAIL_OUTER
	_trail.inner_color = Color(ECHO_CORE, 0.8) if echo else SEED_TRAIL_INNER
	_trail.set_long_history(_long_beam_enabled)
	_trail.clear_points()
	_trail.set_active(_has_trail())
	if _has_trail():
		_trail.record_physics_point(global_position)


func _core_texture() -> Texture2D:
	match damage_kind:
		&"ice":
			return ICE_TEXTURE
		&"wave":
			return WAVE_TEXTURE
		_:
			return BASE_TEXTURE


func _core_anchor() -> Vector2:
	match damage_kind:
		&"ice":
			return ICE_CORE_ANCHOR
		&"wave":
			return WAVE_CORE_ANCHOR
		_:
			return BASE_CORE_ANCHOR


func _spawn_impact(position: Vector2, reaction: StringName, normal: Vector2) -> void:
	if _procedural_kind():
		var fx_parent := (
			get_tree().current_scene if get_tree().current_scene != null else get_tree().root
		)
		if damage_kind == &"ice":
			ArsenalFx.spawn_bubble_pop(fx_parent, position, 14.0)
		else:
			ArsenalFx.spawn_rings(fx_parent, position, 40.0, ECHO_COLOR, 0.3, 2)
		return
	var effect := IMPACT_SCENE.instantiate() as BeamFxImpact
	if effect == null:
		return
	effect.configure(damage_kind, rotation, reaction, normal)
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(effect)
	effect.global_position = position
