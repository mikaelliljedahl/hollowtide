extends Area2D
class_name DevCheckpointPad

signal player_entered
signal player_left

const VISUAL_WIDTH := 224.0
const FLOOR_OFFSET_Y := 38.0

var _visual: Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(128, 64)
	shape.shape = rectangle
	add_child(shape)
	_visual = Sprite2D.new()
	_visual.name = "CheckpointShrineVisual"
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_visual.z_index = 1
	_visual.texture = load("res://assets/sprites/devmode/checkpoint_shrine.png") as Texture2D
	if _visual.texture != null:
		_visual.scale = Vector2.ONE * VISUAL_WIDTH / _visual.texture.get_width()
		_anchor_visible_base_to_floor(_visual)
	add_child(_visual)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	add_to_group("dev_owned")
	add_to_group("dev_checkpoint")


func visual_bounds():
	if _visual == null or _visual.texture == null:
		return Rect2()
	var image := _visual.texture.get_image()
	if image == null:
		return Rect2(
			_visual.position - Vector2(VISUAL_WIDTH, VISUAL_WIDTH) * 0.5, Vector2.ONE * VISUAL_WIDTH
		)
	var used_rect := image.get_used_rect()
	var texture_center := Vector2(_visual.texture.get_size()) * 0.5
	return Rect2(
		_visual.position + (Vector2(used_rect.position) - texture_center) * _visual.scale,
		Vector2(used_rect.size) * _visual.scale
	)


func _anchor_visible_base_to_floor(sprite: Sprite2D) -> void:
	var image := sprite.texture.get_image()
	if image == null:
		sprite.position.y = FLOOR_OFFSET_Y - VISUAL_WIDTH * 0.5
		return
	var used_rect := image.get_used_rect()
	var source_center_y := float(sprite.texture.get_height()) * 0.5
	sprite.position.y = FLOOR_OFFSET_Y - (float(used_rect.end.y) - source_center_y) * sprite.scale.y


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered.emit()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_left.emit()
