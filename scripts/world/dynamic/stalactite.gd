class_name Stalactite
extends Node2D
## A ceiling spike that rattles when the player passes beneath, falls, hurts what it hits and
## shatters on the floor, then regrows. Shooting it drops it early (it can crush enemies too).
## Position is the ceiling attachment point (the rock surface); the spike hangs downward.
## Looks: icicle (vaults), basalt spike (kiln), wet stone (fringe), crystal (nexus), mineral (depths).

enum State { ARMED, SHAKING, FALLING, GONE, REGROWING }

const HitResult = preload("res://scripts/combat/hit_result.gd")
const SHAKE_SECONDS := 0.55
const GRAVITY := 2600.0
const MAX_FALL := 1900.0
const REGROW_SECONDS := 0.9
const REARM_SECONDS := 0.8
const ENEMY_DAMAGE := 40
## Until dedicated art lands in assets/worldfx/stalactites.png, reuse the env kit's hanging props
## (single dominant spikes) with an area tint.
const PROP_FALLBACK := {
	&"fringe":
	["res://assets/environment/areas/vaults/vaults_prop_01.png", Color(0.62, 0.68, 0.74)],
	&"nexus": ["res://assets/environment/areas/nexus/nexus_prop_01.png", Color.WHITE],
	&"vaults": ["res://assets/environment/areas/vaults/vaults_prop_01.png", Color.WHITE],
	&"kiln": ["res://assets/environment/areas/kiln/kiln_prop_00.png", Color.WHITE],
	&"depths": ["res://assets/environment/areas/nexus/nexus_prop_00.png", Color(0.62, 0.45, 1.0)],
}
const CEILING_OVERLAP := 22.0

@export var length := 128.0
@export var width := 96.0
@export var damage := 18
@export var trigger_half_width := 110.0
@export var trigger_depth := 1100.0
@export var respawn_seconds := 5.0
@export var area_override: StringName = &""

var state := State.ARMED
var _timer := 0.0
var _velocity := 0.0
var _drop := 0.0
var _grow := 1.0
var _area: StringName = &"fringe"
var _hitbox: Area2D
var _hurtbox: Area2D
var _shape_points := PackedVector2Array()
var _hit_bodies: Array[Node] = []
var _texture: Texture2D
var _region := Rect2()
var _tint := Color.WHITE
var _dedicated := false


func _ready() -> void:
	add_to_group(&"worldfx_stalactite")
	# Just behind the terrain so the ceiling's surface strip hides the spike's root.
	z_index = -6
	_area = WorldFx.area_for(self, area_override)
	_pick_art()
	_shape_points = _outline()
	_hitbox = Area2D.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = WorldFx.PLAYER_LAYER | 8
	_hitbox.monitoring = false
	_hitbox.monitorable = false
	_hitbox.add_child(_capsule(width * 0.3, length * 0.6))
	add_child(_hitbox)
	_hurtbox = Area2D.new()
	_hurtbox.collision_layer = 8
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	_hurtbox.monitorable = true
	_hurtbox.add_to_group(&"projectile_hurtbox")
	_hurtbox.add_child(_capsule(width * 0.4, length * 0.8))
	add_child(_hurtbox)
	_hitbox.body_entered.connect(_on_body_entered)
	_place_boxes()


## Chooses the sprite and derives the spike length from its aspect at the configured width.
func _pick_art() -> void:
	var art := WorldFx.sheet_region("stalactites", _area)
	if not art.is_empty() and art["texture"] != null:
		_texture = art["texture"]
		_region = art["region"]
		_dedicated = true
	else:
		var fallback: Array = PROP_FALLBACK.get(_area, PROP_FALLBACK[&"vaults"])
		if ResourceLoader.exists(fallback[0]):
			_texture = load(fallback[0]) as Texture2D
			_tint = fallback[1]
			if _texture != null:
				_region = Rect2(Vector2.ZERO, _texture.get_size())
	if _texture != null and _region.size.x > 0.0:
		length = width * _region.size.y / _region.size.x - CEILING_OVERLAP


func _capsule(radius: float, height: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(radius * 1.4, height)
	shape.shape = rectangle
	return shape


func _place_boxes() -> void:
	_hitbox.position = Vector2(0, _drop + length * 0.62)
	_hurtbox.position = Vector2(0, _drop + length * 0.45)


func tip_global() -> Vector2:
	return global_position + Vector2(0, _drop + length)


## Projectiles hit the hurtbox; any hit knocks the spike loose immediately.
func receive_hit(_amount: int, _kind: StringName, _context := {}) -> HitResult.Reaction:
	if state in [State.ARMED, State.SHAKING]:
		_start_fall()
		return HitResult.Reaction.TRIGGERED
	return HitResult.Reaction.PASS


func take_damage(amount: int, kind: StringName) -> void:
	receive_hit(amount, kind)


func is_vulnerable_to(_kind: StringName) -> bool:
	return state in [State.ARMED, State.SHAKING]


func _physics_process(delta: float) -> void:
	match state:
		State.ARMED:
			queue_redraw()
			_timer = maxf(_timer - delta, 0.0)
			if _timer <= 0.0 and _player_below():
				state = State.SHAKING
				_timer = SHAKE_SECONDS
				WorldFx.play(self, &"world_crack", tip_global(), -3.0, randf_range(1.05, 1.2))
				var colors := WorldFx.palette(_area)
				WorldFx.dust(
					get_parent(),
					global_position + Vector2(0, 6),
					Vector2(20, 4),
					colors["dust"],
					10,
					20.0
				)
		State.SHAKING:
			_timer -= delta
			queue_redraw()
			if _timer <= 0.0:
				_start_fall()
		State.FALLING:
			_fall(delta)
		State.GONE:
			_timer -= delta
			if _timer <= 0.0:
				state = State.REGROWING
				_timer = REGROW_SECONDS
				_drop = 0.0
				_place_boxes()
				visible = true
		State.REGROWING:
			_timer -= delta
			_grow = clampf(1.0 - _timer / REGROW_SECONDS, 0.0, 1.0)
			queue_redraw()
			if _timer <= 0.0:
				_grow = 1.0
				state = State.ARMED
				_timer = REARM_SECONDS
				_hurtbox.set_deferred("monitorable", true)


func _player_below() -> bool:
	var player := WorldFx.player_of(self)
	if player == null:
		return false
	var offset := player.global_position - global_position
	if absf(offset.x) > trigger_half_width or offset.y < length * 0.5 or offset.y > trigger_depth:
		return false
	var query := PhysicsRayQueryParameters2D.create(
		tip_global() + Vector2(0, 4),
		player.global_position + Vector2(0, -150),
		WorldFx.TERRAIN_LAYER
	)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _start_fall() -> void:
	state = State.FALLING
	_velocity = 120.0
	_hit_bodies.clear()
	_hitbox.set_deferred("monitoring", true)
	_hurtbox.set_deferred("monitorable", false)
	queue_redraw()


func _fall(delta: float) -> void:
	_velocity = minf(_velocity + GRAVITY * delta, MAX_FALL)
	var step := _velocity * delta
	var from := tip_global()
	var query := PhysicsRayQueryParameters2D.create(
		from - Vector2(0, 2), from + Vector2(0, step + 2), WorldFx.TERRAIN_LAYER
	)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_drop += maxf(Vector2(hit["position"]).y - from.y, 0.0)
		_shatter(Vector2(hit["position"]))
		return
	_drop += step
	_place_boxes()
	queue_redraw()
	if _drop > 4000.0:
		_shatter(tip_global())


func _on_body_entered(body: Node) -> void:
	if state != State.FALLING or _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	if WorldFx.is_player(body):
		if body.has_method("take_damage"):
			body.call("take_damage", damage, tip_global() + Vector2(0, -40))
		_shatter(tip_global())
	elif body.is_in_group(&"enemies") and body.has_method("take_damage"):
		body.call("take_damage", ENEMY_DAMAGE, &"missile")
		_shatter(tip_global())


func _shatter(at: Vector2) -> void:
	state = State.GONE
	_timer = respawn_seconds
	_hitbox.set_deferred("monitoring", false)
	visible = false
	_grow = 0.0
	var colors := WorldFx.palette(_area)
	WorldFx.dust(get_parent(), at + Vector2(0, -12), Vector2(22, 8), colors["dust"], 18, 260.0)
	var shards := CPUParticles2D.new()
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.amount = 14
	shards.lifetime = 0.8
	shards.direction = Vector2.UP
	shards.spread = 75.0
	shards.initial_velocity_min = 180.0
	shards.initial_velocity_max = 520.0
	shards.gravity = Vector2(0, 2400)
	shards.angular_velocity_min = -540.0
	shards.angular_velocity_max = 540.0
	shards.scale_amount_min = 4.0
	shards.scale_amount_max = 9.0
	shards.color = (
		colors["spike_edge"] if _area in [&"vaults", &"nexus"] else colors["spike"].lightened(0.25)
	)
	shards.z_index = 6
	get_parent().add_child(shards)
	shards.global_position = at + Vector2(0, -8)
	shards.emitting = true
	shards.finished.connect(shards.queue_free)
	var sound := &"world_shatter_ice" if _area in [&"vaults", &"nexus"] else &"world_shatter"
	WorldFx.play(self, sound, at, -1.0, randf_range(0.92, 1.08))
	WorldFx.shake(self, 3.0, 0.15)


func _outline() -> PackedVector2Array:
	# Jagged cone from the ceiling to the tip, deterministic per position.
	var noise := RandomNumberGenerator.new()
	noise.seed = int(absf(position.x) * 13.0 + absf(position.y) * 7.0) + 1
	var half := width * 0.5
	var points := PackedVector2Array()
	var steps := 5
	for index in steps:
		var t := float(index) / float(steps)
		var along := half * (1.0 - t) * noise.randf_range(0.85, 1.1)
		points.append(Vector2(-along, length * t))
	points.append(Vector2(noise.randf_range(-3, 3), length))
	for index in range(steps - 1, -1, -1):
		var t := float(index) / float(steps)
		var along := half * (1.0 - t) * noise.randf_range(0.85, 1.1)
		points.append(Vector2(along, length * t + noise.randf_range(-4, 4) * t))
	return points


func _draw() -> void:
	if state == State.GONE:
		return
	if _texture != null:
		_draw_sprite()
		return
	var colors := WorldFx.palette(_area)
	var shake := Vector2.ZERO
	if state == State.SHAKING:
		var t := 1.0 - _timer / SHAKE_SECONDS
		shake = Vector2(randf_range(-1, 1) * (1.5 + 3.0 * t), 0)
	var scale_y := _grow if state == State.REGROWING else 1.0
	if scale_y < 0.06:
		return
	var xf := Transform2D(0.0, Vector2(1.0, scale_y), 0.0, Vector2(0, _drop) + shake)
	var body := PackedVector2Array()
	for point in _shape_points:
		body.append(xf * point)
	var base: Color = colors["spike"]
	var edge: Color = colors["spike_edge"]
	var tip := xf * Vector2(0, length)
	var translucent := _area in [&"vaults", &"nexus"]
	var fill := base
	if translucent:
		fill.a = 0.82
	draw_colored_polygon(body, fill)
	# Lit facet: right half, lighter; shadow facet: left third, darker.
	# Right-hand points run from near the tip back up to the top-right corner.
	var mid := _shape_points.size() / 2
	var lit := PackedVector2Array([xf * Vector2(0, 0), tip])
	for index in range(mid + 1, body.size()):
		lit.append(body[index])
	var lit_color := base.lerp(edge, 0.35)
	lit_color.a = fill.a
	if lit.size() >= 3:
		draw_colored_polygon(lit, lit_color)
	var highlight := edge
	highlight.a = 0.85 if translucent else 0.55
	draw_line(xf * Vector2(width * 0.12, 4), tip + Vector2(1, -8), highlight, 2.0)
	if _area == &"kiln" or _area == &"depths":
		# Glowing mineral vein.
		var vein := edge
		vein.a = 0.8
		draw_polyline(
			PackedVector2Array(
				[
					xf * Vector2(-width * 0.18, 8),
					xf * Vector2(-width * 0.05, length * 0.35),
					xf * Vector2(-width * 0.1, length * 0.6),
					tip + Vector2(0, -14),
				]
			),
			vein,
			2.5
		)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, Color(0, 0, 0, 0.55), 1.5)
	if state != State.FALLING:
		# Rock collar where the spike grows from the ceiling.
		var collar := base.darkened(0.35)
		draw_circle(Vector2(-width * 0.35, 2) + shake, width * 0.32, collar)
		draw_circle(Vector2(width * 0.3, 1) + shake, width * 0.28, collar)
		draw_circle(Vector2(0, 4) + shake, width * 0.4, collar.lightened(0.05))


func _draw_sprite() -> void:
	var shake := 0.0
	var loose := 0.35 + 0.15 * sin(Time.get_ticks_msec() * 0.004 + position.x)
	if state == State.SHAKING:
		var t := 1.0 - _timer / SHAKE_SECONDS
		shake = randf_range(-1, 1) * (1.5 + 3.5 * t)
		loose = 0.6 + 0.4 * t
	var scale_y := _grow if state == State.REGROWING else 1.0
	if scale_y < 0.04:
		return
	var height := length + CEILING_OVERLAP
	draw_set_transform(Vector2(shake, _drop), 0.0, Vector2(1.0, scale_y))
	draw_texture_rect_region(
		_texture, Rect2(-width * 0.5, -CEILING_OVERLAP, width, height), _region, _tint
	)
	if state in [State.ARMED, State.SHAKING] and not _dedicated:
		# A glowing fracture across the root marks the spike as loose (unlike decor).
		var accent: Color = WorldFx.palette(_area)["accent"]
		accent.a = loose
		var y := 30.0
		var crack := PackedVector2Array(
			[
				Vector2(-width * 0.34, y),
				Vector2(-width * 0.12, y + 5.0),
				Vector2(width * 0.05, y - 1.0),
				Vector2(width * 0.2, y + 4.0),
				Vector2(width * 0.34, y)
			]
		)
		draw_polyline(crack, Color(0, 0, 0, 0.7), 4.0)
		draw_polyline(crack, accent, 2.0)
	draw_set_transform(Vector2.ZERO)
