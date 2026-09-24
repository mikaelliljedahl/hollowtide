extends Node2D
class_name DevRoom

signal entered(room_id: String)
signal subcell_entered(subcell_id: String)

var room_id := ""
var room_kind := ""
var room_size := Vector2i(32, 20)
var _trigger: Area2D
var _subcells: Array = []
var _subcell_triggers: Array = []


func configure(id: String, kind: String, origin: Vector2, _color: Color) -> void:
	room_id = id
	room_kind = kind
	position = origin
	_trigger = Area2D.new()
	_trigger.name = "RoomDiscovery"
	_trigger.collision_layer = 0
	_trigger.collision_mask = 2
	_trigger.monitoring = true
	_trigger.monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1984, 240)
	shape.shape = rectangle
	shape.position = Vector2(1024, 1032)
	_trigger.add_child(shape)
	_trigger.body_entered.connect(_on_body_entered)
	add_child(_trigger)
	add_to_group("dev_owned")
	add_to_group("dev_room")


func configure_subcells(definitions: Array) -> void:
	_subcells = definitions.duplicate(true)
	for child in _subcell_triggers:
		if is_instance_valid(child):
			child.queue_free()
	_subcell_triggers.clear()
	for definition in _subcells:
		var rectangle: Rect2 = definition.get("rect", Rect2())
		if rectangle.size.x <= 0.0 or rectangle.size.y <= 0.0:
			continue
		var trigger := Area2D.new()
		trigger.name = "SubcellDiscovery_" + String(definition.get("id", ""))
		trigger.collision_layer = 0
		trigger.collision_mask = 2
		trigger.monitoring = true
		trigger.monitorable = false
		var shape := CollisionShape2D.new()
		var shape_rect := RectangleShape2D.new()
		shape_rect.size = rectangle.size
		shape.shape = shape_rect
		shape.position = rectangle.position + rectangle.size * 0.5
		trigger.add_child(shape)
		var subcell_id := String(definition.get("id", ""))
		trigger.body_entered.connect(func(body: Node2D): _on_subcell_body_entered(body, subcell_id))
		add_child(trigger)
		_subcell_triggers.append(trigger)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		entered.emit(room_id)


func _on_subcell_body_entered(body: Node2D, subcell_id: String) -> void:
	if body.is_in_group("player") and not subcell_id.is_empty():
		subcell_entered.emit(subcell_id)
