class_name EnemyProjectile extends Area2D

var direction := Vector2.RIGHT
var speed := 360.0
var lifetime := 3.0
var damage := 10
var age := 0.0
var arena_bounds := Rect2()
## Visual family chosen by the shooter: orb, acid, shard, bolt, rock, fire, water.
var style: StringName = &"orb"
## Bosses fire bigger projectiles.
var size_scale := 1.0
var _trail: Array[Vector2] = []

const STYLE_COLORS := {
	&"orb": [Color(1.0, 0.55, 0.3), Color(1.0, 0.9, 0.7)],
	&"acid": [Color(0.62, 0.9, 0.22), Color(0.9, 1.0, 0.6)],
	&"shard": [Color(0.3, 0.85, 1.0), Color(0.85, 1.0, 1.0)],
	&"bolt": [Color(0.25, 0.9, 1.0), Color(0.9, 1.0, 1.0)],
	&"rock": [Color(1.0, 0.6, 0.22), Color(1.0, 0.88, 0.55)],
	&"fire": [Color(1.0, 0.42, 0.1), Color(1.0, 0.86, 0.45)],
	&"water": [Color(0.3, 0.75, 1.0), Color(0.88, 0.98, 1.0)],
}


func _ready() -> void:
	add_to_group(&"transient")
	add_to_group(&"enemy_shot")
	collision_layer = 0
	collision_mask = 1 | 2
	monitoring = true
	monitorable = false


func launch(new_direction: Vector2, new_damage: int) -> void:
	direction = Vector2.RIGHT if new_direction.is_zero_approx() else new_direction.normalized()
	damage = new_damage
	rotation = direction.angle()


func configure_arena(bounds: Rect2) -> void:
	arena_bounds = bounds


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	var start := global_position
	var finish := start + direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(start, finish, collision_mask, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target := hit.get("collider") as Node
		var impact_position: Vector2 = hit.get("position", global_position)
		if target != null and target.has_method(&"try_deflect"):
			if target.call(&"try_deflect", self):
				return
		if target != null and target.has_method(&"take_damage"):
			target.call(&"take_damage", damage, impact_position)
		_pop(impact_position)
		queue_free()
		return
	if arena_bounds.size != Vector2.ZERO and not arena_bounds.has_point(finish):
		_pop(global_position)
		queue_free()
		return
	global_position = finish
	_trail.push_front(global_position)
	if _trail.size() > 7:
		_trail.pop_back()
	queue_redraw()


func _colors() -> Array:
	return STYLE_COLORS.get(style, STYLE_COLORS[&"orb"])


func _pop(at: Vector2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var colors := _colors()
	CombatFeedback.spawn_hit(parent, at, false, direction, false, Color(colors[0], 0.95))


func _draw() -> void:
	var colors := _colors()
	var main: Color = colors[0]
	var core: Color = colors[1]
	var radius := 7.0 * size_scale
	# Trail in local space (node is rotated toward travel direction).
	var inverse := global_transform.affine_inverse()
	for index in range(_trail.size() - 1, 0, -1):
		var fade := 1.0 - float(index) / float(_trail.size())
		var point: Vector2 = inverse * _trail[index]
		draw_circle(point, radius * (0.35 + 0.5 * fade), Color(main, 0.38 * fade))
	var pulse := 1.0 + 0.12 * sin(age * 30.0)
	draw_circle(Vector2.ZERO, radius * 1.9 * pulse, Color(main, 0.18))
	match style:
		&"shard", &"bolt":
			var length := radius * (2.6 if style == &"bolt" else 2.1)
			var points := PackedVector2Array(
				[
					Vector2(length, 0.0),
					Vector2(0.0, radius * 0.7),
					Vector2(-length * 0.6, 0.0),
					Vector2(0.0, -radius * 0.7),
				]
			)
			draw_colored_polygon(points, main)
			draw_line(Vector2(-length * 0.4, 0.0), Vector2(length * 0.85, 0.0), core, 2.0, true)
		&"rock":
			var rock := PackedVector2Array()
			for index in 7:
				var angle := TAU * float(index) / 7.0 + age * 9.0
				var jag := 0.75 + 0.25 * float((index * 5) % 3) / 2.0
				rock.append(Vector2.RIGHT.rotated(angle) * radius * 1.25 * jag)
			draw_colored_polygon(rock, Color(0.32, 0.3, 0.3))
			draw_circle(Vector2.ZERO, radius * 0.55, main)
		&"acid":
			draw_circle(Vector2.ZERO, radius * pulse, main)
			draw_circle(Vector2(-radius * 0.9, radius * 0.3), radius * 0.45, Color(main, 0.8))
			draw_circle(Vector2(radius * 0.25, -radius * 0.3), radius * 0.35, core)
		_:
			draw_circle(Vector2.ZERO, radius * pulse, main)
			draw_circle(Vector2.ZERO, radius * 0.55, core)
