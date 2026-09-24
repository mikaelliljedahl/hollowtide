extends Area2D

@export var damage := 24


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method(&"take_damage"):
		body.call(&"take_damage", damage, get_parent().global_position)
