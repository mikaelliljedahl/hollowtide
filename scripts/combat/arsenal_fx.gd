class_name ArsenalFx
extends Node2D
## Procedural effects for the D19 arsenal: expanding resonance/echo rings, bubble pops, sparks and
## grit. Self-cleaning, group `transient` so room changes and resets remove them.

const UNSHADED = preload("res://resources/combat/fx_unshaded.tres")

var age := 0.0
var lifetime := 0.4
var start_radius := 8.0
var end_radius := 64.0
var width := 4.0
var tint := Color.WHITE
var rings := 1
var kind: StringName = &"ring"
var _droplets: Array[Vector2] = []


func _ready() -> void:
	add_to_group(&"transient")
	material = UNSHADED
	queue_redraw()


func _process(delta: float) -> void:
	age += delta
	queue_redraw()
	if age >= lifetime:
		queue_free()


func _draw() -> void:
	var progress := clampf(age / lifetime, 0.0, 1.0)
	match kind:
		&"pop":
			_draw_pop(progress)
		_:
			_draw_rings(progress)


func _draw_rings(progress: float) -> void:
	for index in rings:
		var delay := float(index) * 0.18
		var local := clampf((progress - delay) / maxf(1.0 - delay, 0.01), 0.0, 1.0)
		if local <= 0.0:
			continue
		var radius := lerpf(start_radius, end_radius, ease(local, 0.35))
		var alpha := tint.a * (1.0 - local) * (1.0 if index == 0 else 0.6)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(tint, alpha * 0.35), width * 2.6, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(tint, alpha), width, true)
		draw_arc(
			Vector2.ZERO,
			radius - width,
			0.0,
			TAU,
			48,
			Color(1.0, 1.0, 1.0, alpha * 0.55),
			maxf(width * 0.35, 1.0),
			true
		)


func _draw_pop(progress: float) -> void:
	var alpha := 1.0 - progress
	var radius := lerpf(start_radius, end_radius, ease(progress, 0.3))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(tint, alpha * 0.8), 2.0, true)
	for droplet in _droplets:
		var point := droplet * lerpf(start_radius, end_radius * 1.25, ease(progress, 0.4))
		point.y += 60.0 * progress * progress
		draw_circle(point, 3.2 * (1.0 - progress * 0.6), Color(tint.lightened(0.3), alpha))


static func spawn_rings(
	parent: Node, position: Vector2, radius: float, color: Color, duration := 0.45, count := 2
) -> ArsenalFx:
	if not is_instance_valid(parent):
		return null
	var effect := ArsenalFx.new()
	effect.kind = &"ring"
	effect.lifetime = duration
	effect.start_radius = radius * 0.12
	effect.end_radius = radius
	effect.width = clampf(radius * 0.05, 2.0, 6.0)
	effect.tint = color
	effect.rings = count
	effect.z_index = 6
	parent.add_child(effect)
	effect.global_position = position
	return effect


static func spawn_bubble_pop(parent: Node, position: Vector2, radius: float) -> ArsenalFx:
	if not is_instance_valid(parent):
		return null
	var effect := ArsenalFx.new()
	effect.kind = &"pop"
	effect.lifetime = 0.42
	effect.start_radius = radius * 0.9
	effect.end_radius = radius * 1.35
	effect.tint = Color(0.78, 0.95, 1.0, 0.9)
	effect.z_index = 6
	for index in 14:
		effect._droplets.append(Vector2.RIGHT.rotated(TAU * index / 14.0 + randf() * 0.2))
	parent.add_child(effect)
	effect.global_position = position
	return effect


static func spawn_sparks(
	parent: Node, position: Vector2, normal: Vector2, count: int, color: Color
) -> void:
	if not is_instance_valid(parent):
		return
	var base := normal.normalized() if not normal.is_zero_approx() else Vector2.UP
	for index in count:
		var spark := CombatFx.Spark.new()
		parent.add_child(spark)
		spark.global_position = position
		var direction := base.rotated(randf_range(-1.1, 1.1))
		spark.configure(
			direction * randf_range(220.0, 520.0), randf_range(0.14, 0.26), 12.0, 2.2, color, 900.0
		)


static func spawn_grit(parent: Node, position: Vector2, normal: Vector2, count := 4) -> void:
	if not is_instance_valid(parent):
		return
	var base := normal.normalized() if not normal.is_zero_approx() else Vector2.UP
	for index in count:
		var puff := CombatFx.Puff.new()
		parent.add_child(puff)
		puff.global_position = position
		puff.configure(
			base.rotated(randf_range(-0.8, 0.8)) * randf_range(40.0, 110.0),
			randf_range(0.35, 0.55),
			3.0,
			12.0,
			Color(0.62, 0.58, 0.52, 0.55),
			3.0
		)
