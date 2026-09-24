class_name ProjectileGrate extends StaticBody2D

@export var relay: NodePath
@export var allowed_kind: StringName = &"wave"


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group(&"projectile_grate")


func can_pass_projectile(kind: StringName) -> bool:
	return kind == allowed_kind


func allows_projectile(kind: StringName) -> bool:
	if not can_pass_projectile(kind):
		return false
	var target := get_node_or_null(relay)
	if target != null and is_instance_valid(target) and target.has_method(&"open_wave_window"):
		target.call(&"open_wave_window")
	return true
