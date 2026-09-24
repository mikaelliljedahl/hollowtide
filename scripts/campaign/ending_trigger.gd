extends Area2D

## Walking into the open light after the Tidal Heart falls ends the campaign.

@export var trigger_size := Vector2(128, 192)
@export var required_flag := "boss:tidal_heart"

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = trigger_size
	shape.shape = rectangle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _fired or not body.is_in_group(&"player"):
		return
	if not required_flag.is_empty() and not GameState.has_world_flag(required_flag):
		return
	_fired = true
	var root := get_tree().get_first_node_in_group(&"campaign_root")
	if root != null and root.has_method("play_ending"):
		root.call("play_ending")
