class_name WaveGrate
extends StaticBody2D

@export var grate_size := Vector2(32, 256)
@export var relay: NodePath

const FRAME_TEXTURE_PATH := "res://assets/sprites/devmode/passage_arch.png"
## D19: shown as a resonant membrane (Echo Shot passes); legacy grate art is the fallback.
const GRATE_TEXTURE_PATH := "res://assets/sprites/devmode/wave_grate.png"
const MEMBRANE_TEXTURE_PATH := "res://assets/sprites/arsenal/resonant_membrane.png"
const FRAME_MARGIN := Vector2(128.0, 160.0)

var _relay_target: Node
var _frame: Sprite2D
var _visual: Sprite2D


func _ready():
	collision_layer = 1
	collision_mask = 0
	add_to_group(&"projectile_grate")
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = grate_size
	collision.shape = rectangle
	add_child(collision)
	_frame = _create_architecture_frame()
	add_child(_frame)
	_visual = _create_grate_leaf()
	add_child(_visual)


func set_relay(target: Node) -> void:
	_relay_target = target
	relay = get_path_to(target) if target != null and is_inside_tree() else NodePath()


func can_pass_projectile(kind: StringName) -> bool:
	var target := _relay_target_node()
	if target != null and StringName(target.get("enemy_id")) == &"tidal_heart":
		if int(target.get("phase")) == 1:
			return kind in [&"ice", &"missile", &"wave"]
		if (
			kind == &"missile"
			and target.has_method(&"is_vulnerable_to")
			and target.call(&"is_vulnerable_to", &"missile")
		):
			return true
	return kind == &"wave"


func allows_projectile(kind: StringName):
	if not can_pass_projectile(kind):
		return false
	var target := _relay_target_node()
	if kind == &"wave" and target != null and target.has_method(&"open_wave_window"):
		target.call(&"open_wave_window")
	return true


func _relay_target_node() -> Node:
	if is_instance_valid(_relay_target):
		return _relay_target
	return get_node_or_null(relay)


func aperture_rect():
	return Rect2(-grate_size * 0.5, grate_size)


func _create_grate_leaf():
	var sprite := Sprite2D.new()
	sprite.name = "WaveGrateVisual"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = 3
	var path := (
		MEMBRANE_TEXTURE_PATH
		if ResourceLoader.exists(MEMBRANE_TEXTURE_PATH)
		else GRATE_TEXTURE_PATH
	)
	sprite.texture = load(path) as Texture2D
	if sprite.texture == null:
		return sprite
	var crop_size := Vector2(480.0 * grate_size.x / grate_size.y, 480.0)
	sprite.region_enabled = true
	sprite.region_rect = Rect2((Vector2(sprite.texture.get_size()) - crop_size) * 0.5, crop_size)
	sprite.scale = grate_size / crop_size
	return sprite


func _create_architecture_frame():
	var frame := Sprite2D.new()
	frame.name = "WaveGrateFrameVisual"
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.z_index = 2
	frame.texture = load(FRAME_TEXTURE_PATH) as Texture2D
	if frame.texture != null:
		frame.scale = (grate_size + FRAME_MARGIN) / Vector2(frame.texture.get_size())
	return frame
