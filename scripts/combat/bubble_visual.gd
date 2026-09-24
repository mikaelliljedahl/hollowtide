class_name BubbleVisual
extends Node2D
## Bubble Snare (D19) air bubble drawn over a trapped enemy or a boss core: translucent
## thin-film sphere with a highlight, a wobbling rim and tiny rising bubbles. Attach with
## `BubbleVisual.attach(host, local_rect)` and free it when the status ends.

const RIM := Color(0.8, 0.96, 1.0, 0.85)
const FILL := Color(0.62, 0.88, 1.0, 0.13)
const FILM_A := Color(1.0, 0.7, 0.92, 0.45)
const FILM_B := Color(0.6, 1.0, 0.9, 0.4)

var rect := Rect2(-40.0, -40.0, 80.0, 80.0)
## 0..1: how close the bubble is to popping (rim trembles and thins).
var warning := 0.0
var _age := 0.0


static func attach(host: Node, local_rect: Rect2, z := 2) -> BubbleVisual:
	var bubble := BubbleVisual.new()
	bubble.name = "BubbleSnare"
	bubble.rect = local_rect
	bubble.z_index = z
	host.add_child(bubble)
	return bubble


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	var center := rect.get_center()
	# Mostly round: a bubble only hints at the trapped silhouette's aspect.
	var mean := (rect.size.x + rect.size.y) * 0.25
	var radii := Vector2(lerpf(mean, rect.size.x * 0.5, 0.25), lerpf(mean, rect.size.y * 0.5, 0.25))
	var wobble := 0.03 + 0.05 * warning
	var squash := Vector2(1.0 + wobble * sin(_age * 5.3), 1.0 + wobble * sin(_age * 5.3 + PI * 0.5))
	var tremble := Vector2(sin(_age * 61.0), cos(_age * 53.0)) * 2.0 * warning
	draw_set_transform(center + tremble, 0.0, radii * squash / 64.0)
	# Unit circle of radius 64 scaled into the ellipse.
	draw_circle(Vector2.ZERO, 64.0, FILL)
	draw_circle(Vector2(0.0, 10.0), 52.0, Color(FILL, FILL.a * 0.6))
	var rim_width := lerpf(4.0, 2.2, warning)
	draw_arc(Vector2.ZERO, 64.0, 0.0, TAU, 56, Color(RIM, RIM.a * 0.35), rim_width * 3.0, true)
	draw_arc(Vector2.ZERO, 63.0, 0.0, TAU, 56, RIM, rim_width, true)
	# Thin-film sheen bands.
	var swirl := _age * 0.6
	draw_arc(Vector2.ZERO, 56.0, swirl, swirl + 1.6, 20, FILM_A, 5.0, true)
	draw_arc(Vector2.ZERO, 50.0, swirl + PI, swirl + PI + 1.2, 16, FILM_B, 4.0, true)
	# Specular highlight top-left plus a soft bottom-right bounce.
	draw_circle(Vector2(-26.0, -30.0), 11.0, Color(1.0, 1.0, 1.0, 0.8))
	draw_circle(Vector2(-14.0, -40.0), 5.0, Color(1.0, 1.0, 1.0, 0.65))
	draw_arc(Vector2.ZERO, 50.0, 0.35, 1.25, 14, Color(1.0, 1.0, 1.0, 0.3), 3.0, true)
	draw_set_transform(Vector2.ZERO)
	# Little bubbles rising from the top.
	for index in 4:
		var t := fmod(_age * 0.7 + float(index) * 0.25, 1.0)
		var x := center.x + sin(float(index) * 2.4 + _age * 2.0) * radii.x * 0.4
		var y := rect.position.y - t * 60.0
		draw_arc(Vector2(x, y), 4.0 - 2.0 * t, 0.0, TAU, 10, Color(RIM, 0.7 * (1.0 - t)), 1.5, true)
