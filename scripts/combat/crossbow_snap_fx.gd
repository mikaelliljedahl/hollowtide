class_name CrossbowSnapFx extends Node2D

## Seed Crossbow launch effect: the bow string snapping forward plus a small puff of leaves and
## green-turquoise sparks. Replaces the old sci-fi muzzle flash for every bolt the crossbow fires.
## Drawn procedurally in local space, where +x is the shot direction.

const DURATION := 0.24
const STRING_COLOR := Color(0.93, 0.88, 0.72, 0.95)
const LEAF_COLORS: Array[Color] = [
	Color(0.46, 0.78, 0.36, 1.0),
	Color(0.62, 0.86, 0.42, 1.0),
	Color(0.36, 0.66, 0.40, 1.0),
]
const SPARK_COLOR := Color(0.62, 1.0, 0.9, 1.0)

var _age := 0.0
var _heavy := false
var _leaf_count := 0
var _leaves: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []


static func spawn(
	parent: Node, origin: Vector2, direction: Vector2, heavy := false, leaves := true
):
	var effect := CrossbowSnapFx.new()
	effect._setup(direction, heavy, leaves)
	parent.add_child(effect)
	effect.global_position = origin
	return effect


func _setup(direction: Vector2, heavy: bool, leaves: bool) -> void:
	rotation = (Vector2.RIGHT if direction.is_zero_approx() else direction).angle()
	_heavy = heavy
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_leaf_count = (4 if heavy else 3) if leaves else 0
	for index in _leaf_count:
		var leaf := {
			"velocity":
			Vector2.from_angle(rng.randf_range(-1.1, 1.1)) * rng.randf_range(90.0, 170.0),
			"spin": rng.randf_range(-14.0, 14.0),
			"angle": rng.randf_range(0.0, TAU),
			"size": rng.randf_range(4.0, 6.5) * (1.2 if heavy else 1.0),
			"color": LEAF_COLORS[index % LEAF_COLORS.size()],
		}
		_leaves.append(leaf)
	for index in 7 if heavy else 5:
		var angle := rng.randf_range(-0.7, 0.7)
		var spark := {
			"velocity": Vector2.from_angle(angle) * rng.randf_range(160.0, 320.0),
			"size": rng.randf_range(1.2, 2.4),
		}
		_sparks.append(spark)


func _ready() -> void:
	add_to_group(&"crossbow_fx")
	call_deferred("add_to_group", &"transient")
	z_index = 5


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / DURATION
	var fade := 1.0 - t
	_draw_string_snap(t, fade)
	for leaf in _leaves:
		_draw_leaf(leaf, t, fade)
	for spark in _sparks:
		var velocity: Vector2 = spark["velocity"]
		var start := velocity * _age * 0.6
		var finish := velocity * _age
		draw_line(start, finish, Color(SPARK_COLOR, 0.9 * fade), float(spark["size"]), true)
	draw_circle(Vector2(4.0, 0.0), lerpf(5.0, 9.0, t), Color(SPARK_COLOR, 0.22 * fade))


func _draw_string_snap(t: float, fade: float) -> void:
	# Two string halves whip from drawn-back to straight across the limbs, then vibrate out.
	var half := 13.0 if _heavy else 10.0
	var snap := clampf(t * 5.0, 0.0, 1.0)
	var pull := lerpf(-11.0, 0.0, snap) + sin(t * 70.0) * 2.4 * fade
	var nock := Vector2(-16.0 + pull, 0.0)
	var top := Vector2(-16.0, -half)
	var bottom := Vector2(-16.0, half)
	var color := Color(STRING_COLOR, fade)
	draw_line(top, nock, color, 1.6, true)
	draw_line(nock, bottom, color, 1.6, true)
	if snap >= 1.0 and t < 0.6:
		draw_arc(
			Vector2(-12.0, 0.0), half + 3.0, -0.9, 0.9, 10, Color(STRING_COLOR, 0.4 * fade), 1.2
		)


func _draw_leaf(leaf: Dictionary, t: float, fade: float) -> void:
	var velocity: Vector2 = leaf["velocity"]
	# Drag: leaves slow down fast and drift slightly downward in screen space.
	var travel := velocity * (_age - 0.9 * _age * t)
	var gravity := Vector2.DOWN.rotated(-rotation) * 40.0 * _age * _age * 4.0
	var center := travel + gravity
	var angle := float(leaf["angle"]) + float(leaf["spin"]) * _age
	var size := float(leaf["size"])
	var axis := Vector2.from_angle(angle)
	var side := axis.orthogonal()
	var points := PackedVector2Array(
		[
			center - axis * size,
			center + side * size * 0.45,
			center + axis * size,
			center - side * size * 0.45,
		]
	)
	var color: Color = leaf["color"]
	draw_colored_polygon(points, Color(color, fade))
	draw_line(center - axis * size, center + axis * size, Color(0.2, 0.36, 0.2, 0.7 * fade), 1.0)
