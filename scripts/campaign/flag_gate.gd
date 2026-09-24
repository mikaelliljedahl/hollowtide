extends StaticBody2D

## Sealed iris that opens once every required world flag is set (boss shortcuts, final gate).
## One seal light per flag shows how many conditions are already met; no text is shown.

const LEAF_TEXTURE_PATH := "res://assets/sprites/devmode/undertow_gate.png"
const FRAME_TEXTURE_PATH := "res://assets/sprites/devmode/passage_arch.png"
const FRAME_MARGIN := Vector2(64.0, 64.0)
const SEAL_TINT := Color(1.0, 0.78, 0.42)
const LIGHT_ON := Color(1.0, 0.86, 0.45)
const LIGHT_OFF := Color(0.18, 0.16, 0.14)

@export var required_flags := PackedStringArray()
@export var gate_size := Vector2(64, 192)

var is_open := false
var _shape: CollisionShape2D
var _leaf: Sprite2D
var _frame: Sprite2D
var _open_tween: Tween


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group(&"campaign_flag_gate")
	_shape = CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = gate_size
	_shape.shape = rectangle
	add_child(_shape)
	_frame = _sprite(FRAME_TEXTURE_PATH, 2)
	if _frame.texture != null:
		_frame.scale = (gate_size + FRAME_MARGIN) / Vector2(_frame.texture.get_size())
	_leaf = _sprite(LEAF_TEXTURE_PATH, 3)
	if _leaf.texture != null:
		var crop := Vector2(400.0, 400.0)
		if gate_size.y > gate_size.x:
			crop = Vector2(480.0 * gate_size.x / gate_size.y, 480.0)
		elif gate_size.x > gate_size.y:
			crop = Vector2(480.0, 480.0 * gate_size.y / gate_size.x)
		_leaf.region_enabled = true
		_leaf.region_rect = Rect2((Vector2(_leaf.texture.get_size()) - crop) * 0.5, crop)
		_leaf.scale = gate_size / crop
		_leaf.modulate = SEAL_TINT
	if not GameState.state_changed.is_connected(refresh):
		GameState.state_changed.connect(refresh)
	refresh(false)


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(refresh):
		GameState.state_changed.disconnect(refresh)


func met_count() -> int:
	var count := 0
	for flag in required_flags:
		if GameState.has_world_flag(flag):
			count += 1
	return count


func refresh(animate := true) -> void:
	var should_open := met_count() == required_flags.size()
	queue_redraw()
	if should_open == is_open:
		return
	is_open = should_open
	_shape.set_deferred("disabled", is_open)
	collision_layer = 0 if is_open else 1
	if not is_open:
		_leaf.visible = true
		_leaf.modulate.a = 1.0
		return
	if not animate or not is_inside_tree():
		_leaf.visible = false
		return
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.call("play_sfx", &"weapon_pickup")
	if _open_tween != null:
		_open_tween.kill()
	_open_tween = create_tween()
	_open_tween.tween_property(_leaf, "modulate:a", 0.0, 0.8)
	_open_tween.tween_callback(func(): _leaf.visible = false)


func _draw() -> void:
	if is_open or required_flags.is_empty():
		return
	var met := met_count()
	var horizontal := gate_size.x > gate_size.y
	var count := required_flags.size()
	for index in count:
		var t := (float(index) + 1.0) / float(count + 1)
		var point := (
			Vector2(-gate_size.x * 0.5 + gate_size.x * t, -gate_size.y * 0.5 - 22.0)
			if horizontal
			else Vector2(-gate_size.x * 0.5 - 22.0, -gate_size.y * 0.5 + gate_size.y * t)
		)
		draw_circle(point, 11.0, Color(0.05, 0.05, 0.05, 0.9))
		draw_circle(point, 8.0, LIGHT_ON if index < met else LIGHT_OFF)


func _sprite(path: String, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = z
	sprite.texture = load(path) as Texture2D
	add_child(sprite)
	return sprite
