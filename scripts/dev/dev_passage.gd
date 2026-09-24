class_name DevPassage
extends Node2D

const OUTER_SIZE := Vector2(384.0, 384.0)
const APERTURE_SIZE := Vector2(192.0, 224.0)
const FLOOR_Y := 0.0

var _visual: Sprite2D


func _ready() -> void:
	add_to_group(&"dev_owned")
	add_to_group(&"dev_passage")
	_visual = Sprite2D.new()
	_visual.name = "PassageArchVisual"
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_visual.z_index = -2
	_visual.texture = load("res://assets/sprites/devmode/passage_arch.png") as Texture2D
	if _visual.texture != null:
		_visual.scale = OUTER_SIZE / Vector2(_visual.texture.get_size())
		_anchor_visible_base_to_floor(_visual)
	add_child(_visual)


func visual_aperture_rect():
	return Rect2(Vector2(-APERTURE_SIZE.x * 0.5, FLOOR_Y - APERTURE_SIZE.y), APERTURE_SIZE)


func _anchor_visible_base_to_floor(sprite: Sprite2D) -> void:
	var image := sprite.texture.get_image()
	if image == null:
		sprite.position.y = -OUTER_SIZE.y * 0.5
		return
	var used_rect := image.get_used_rect()
	var source_center_y := float(sprite.texture.get_height()) * 0.5
	sprite.position.y = FLOOR_Y - (float(used_rect.end.y) - source_center_y) * sprite.scale.y
