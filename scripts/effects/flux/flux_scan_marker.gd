class_name FluxScanMarker
extends Node2D

var _age := 0.0
var _duration := 1.5
var _radius := 34.0
var _color := Color("69e0d0")


func configure(target: Node2D, duration: float) -> void:
	_duration = duration
	_radius = _marker_radius(target)
	_color = _marker_color(target)
	z_index = 40
	queue_redraw()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"transient")
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= _duration:
		queue_free()


func _draw() -> void:
	var progress := clampf(_age / _duration, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_age * 13.0)
	var radius := _radius * (0.86 + pulse * 0.16)
	var alpha := (1.0 - progress) * (0.46 + pulse * 0.24)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(_color, alpha), 3.0, true)
	draw_circle(Vector2.ZERO, radius * 0.22, Color(_color, alpha * 0.16))


func _marker_radius(target: Node2D) -> float:
	if target.is_in_group(&"bosses"):
		return 78.0
	if target.is_in_group(&"enemies"):
		return 46.0
	return 34.0


func _marker_color(target: Node2D) -> Color:
	if target.is_in_group(&"enemies") or target.is_in_group(&"bosses"):
		return Color("e7a66d")
	if target.is_in_group(&"ability_gates"):
		return Color("9aa8ff")
	return Color("69e0d0")
