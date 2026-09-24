extends StaticBody2D
class_name DevFinalGate

var gate_size := Vector2(64, 192)
var _shape: CollisionShape2D
var _open := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = gate_size
	_shape.shape = rectangle
	add_child(_shape)
	add_to_group("dev_owned")
	add_to_group("dev_gate")
	refresh()


func refresh() -> void:
	_open = (
		GameState.has_world_flag("regional:stone_guardian")
		and GameState.has_world_flag("regional:furnace_mother")
	)
	if _shape != null:
		_shape.set_deferred("disabled", _open)
	collision_layer = 0 if _open else 1
	queue_redraw()


func _draw() -> void:
	if _open:
		return
	var color := Color("e2c36a")
	draw_rect(Rect2(-gate_size * 0.5, gate_size), Color("2c2514"), true)
	draw_rect(Rect2(-gate_size * 0.5, gate_size), color, false, 3.0)
	draw_circle(Vector2.ZERO, 22.0, color, false, 4.0)
	draw_line(Vector2(-18, 0), Vector2(18, 0), color, 3.0)
