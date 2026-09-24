class_name Bomb extends Area2D
## Resonance Pulse (internal id `bombs`, D19): a charging amber crystal placed in Slipstream form
## that bursts as an expanding resonance ring; same radius, damage, block breaking and lift.

const PULSE_COLOR := Color(1.0, 0.78, 0.36, 1.0)
const CRYSTAL_COLOR := Color(0.98, 0.66, 0.22, 1.0)

const Catalog = preload("res://scripts/progression/content_catalog.gd")

## Weapons sets both from the Tide Glyph loadout before the pulse enters the tree.
var damage_amount := Catalog.BOMB_DAMAGE
var fuse_seconds := Catalog.BOMB_FUSE_SECONDS
var _age := 0.0
var _exploded := false


func _ready() -> void:
	add_to_group(&"transient")
	add_to_group(&"bombs")
	collision_layer = 16
	collision_mask = 9
	monitoring = false
	monitorable = false
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta
	queue_redraw()
	if _age >= fuse_seconds:
		_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	var parent := get_parent()
	ArsenalFx.spawn_rings(parent, global_position, Catalog.BOMB_RADIUS, PULSE_COLOR, 0.36, 3)
	ArsenalFx.spawn_sparks(parent, global_position, Vector2.UP, 8, PULSE_COLOR.lightened(0.3))
	GameJuice.shake(self, 3.5, 0.18)
	GameJuice.play_sfx(&"pulse_burst", &"bomb_explode")
	var state := get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = Catalog.BOMB_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 2 | 8 | 1
	query.exclude = [get_rid()]
	var seen: Array[Node] = []
	for hit in state.intersect_shape(query, 32):
		var target := hit.get("collider") as Node
		if target == null or seen.has(target):
			continue
		seen.append(target)
		if target.is_in_group(&"player"):
			if target.has_method(&"apply_bomb_impulse"):
				target.call(&"apply_bomb_impulse", global_position, Catalog.BOMB_RADIUS)
		elif target.has_method(&"receive_hit"):
			(
				target
				. call(
					&"receive_hit",
					damage_amount,
					&"bomb",
					{"position": global_position, "source": self},
				)
			)
		elif target.has_method(&"take_damage"):
			target.call(&"take_damage", damage_amount, &"bomb")
	queue_free()


func _draw() -> void:
	var charge := clampf(_age / fuse_seconds, 0.0, 1.0)
	var hum := 0.5 + 0.5 * sin(_age * lerpf(14.0, 46.0, charge))
	# Converging ring: the pulse gathers inward before it bursts.
	var gather := lerpf(44.0, 14.0, fmod(_age * 2.4, 1.0))
	draw_arc(
		Vector2.ZERO, gather, 0.0, TAU, 32, Color(PULSE_COLOR, 0.25 + 0.35 * charge), 2.0, true
	)
	draw_circle(Vector2.ZERO, 22.0 + 4.0 * hum, Color(PULSE_COLOR, 0.18 + 0.14 * charge))
	# Faceted crystal.
	var r := 14.0 + 2.0 * hum
	var facets := PackedVector2Array(
		[
			Vector2(0.0, -r * 1.3),
			Vector2(r * 0.8, -r * 0.2),
			Vector2(r * 0.5, r),
			Vector2(-r * 0.5, r),
			Vector2(-r * 0.8, -r * 0.2)
		]
	)
	draw_colored_polygon(facets, CRYSTAL_COLOR.darkened(0.25))
	draw_colored_polygon(
		PackedVector2Array([facets[0], facets[1], Vector2(0.0, r * 0.2), facets[4]]),
		CRYSTAL_COLOR.lightened(0.15 + 0.3 * hum)
	)
	var outline := facets.duplicate()
	outline.append(facets[0])
	draw_polyline(outline, Color(1.0, 0.93, 0.7, 0.9), 1.5, true)
	draw_arc(
		Vector2.ZERO,
		22.0,
		-PI * 0.5,
		-PI * 0.5 + TAU * charge,
		32,
		Color(PULSE_COLOR, 0.85),
		2.5,
		true
	)
