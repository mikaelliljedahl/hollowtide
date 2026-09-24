class_name SealSlab
extends Node2D
## A heavy slab that slams shut across an opening and later grinds back into the rock.
## Vertical openings are closed from above, horizontal ones from the side. Only the part inside
## the opening is drawn, so an open slab is hidden in the rock apart from a thin lip.
## Position is the centre of the opening.

signal closed

const DROP_SECONDS := 0.26
const RISE_SECONDS := 0.9
const LIP := 12.0

@export var size := Vector2(64, 192)
@export var area_id: StringName = &"fringe"

var is_closed := false
var _body: StaticBody2D
var _shape: CollisionShape2D
var _amount := 0.0
var _tween: Tween


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Tiled fill needs repeat; the delivered (non power-of-two) art sheet must not repeat.
	WorldFx.warm("slabs", area_id)
	texture_repeat = WorldFx.repeat_mode("slabs", area_id)
	z_index = 1
	_body = StaticBody2D.new()
	_body.collision_layer = 0
	_body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	_shape.shape = rectangle
	_shape.disabled = true
	_body.add_child(_shape)
	add_child(_body)


func close(animate := true) -> void:
	if is_closed:
		return
	is_closed = true
	_shape.set_deferred("disabled", false)
	_body.collision_layer = WorldFx.TERRAIN_LAYER
	if _tween != null:
		_tween.kill()
	if not animate:
		_set_amount(1.0)
		return
	_tween = create_tween()
	(
		_tween
		. tween_method(_set_amount, _amount, 1.0, DROP_SECONDS)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_tween.tween_callback(_on_slammed)


func open(animate := true) -> void:
	if not is_closed:
		return
	is_closed = false
	_shape.set_deferred("disabled", true)
	_body.collision_layer = 0
	if _tween != null:
		_tween.kill()
	if not animate:
		_set_amount(0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_amount, _amount, 0.0, RISE_SECONDS).set_trans(Tween.TRANS_SINE)


func _on_slammed() -> void:
	var colors := WorldFx.palette(area_id)
	var vertical := size.y >= size.x
	var edge := Vector2(0, size.y * 0.5 - 4) if vertical else Vector2(size.x * 0.5 - 4, 0)
	var extents := Vector2(size.x * 0.6, 4) if vertical else Vector2(4, size.y * 0.6)
	WorldFx.dust(get_parent(), global_position + edge, extents, colors["dust"], 22, 260.0)
	WorldFx.play(self, &"world_slam", global_position + edge, 0.0, randf_range(0.92, 1.02))
	WorldFx.shake(self, 7.0, 0.3)
	closed.emit()


func _set_amount(value: float) -> void:
	_amount = value
	queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	var opening := Rect2(-half, size)
	var vertical := size.y >= size.x
	var shown := maxf(_amount, 0.0)
	var full: Rect2
	if vertical:
		var height := maxf(size.y * shown, LIP)
		full = Rect2(Vector2(-half.x, -half.y - size.y + height), size)
	else:
		var width := maxf(size.x * shown, LIP)
		full = Rect2(Vector2(half.x - width, -half.y), size)
	WorldFx.draw_gate(self, full, full.intersection(opening), area_id, 0.35 + 0.5 * shown)
