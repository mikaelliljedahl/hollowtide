extends Area2D
class_name DevRefillPad

@export var refill_health := true
@export var refill_missiles := true
@export var refill_flux := false

const VISUAL_WIDTH := 208.0
const FLOOR_OFFSET_Y := 38.0

var _cooldown := 0.0
var _visual: Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(112, 48)
	shape.shape = rectangle
	add_child(shape)
	_visual = Sprite2D.new()
	_visual.name = "RefillShrineVisual"
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_visual.z_index = 1
	var texture_path := (
		"res://assets/sprites/devmode/flux_shrine.png"
		if refill_flux
		else "res://assets/sprites/devmode/refill_shrine.png"
	)
	_visual.texture = load(texture_path) as Texture2D
	if _visual.texture != null:
		_visual.scale = Vector2.ONE * VISUAL_WIDTH / _visual.texture.get_width()
		_anchor_visible_base_to_floor(_visual)
	add_child(_visual)
	body_entered.connect(_on_body_entered)
	add_to_group("dev_owned")
	add_to_group("dev_refill")


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _visual != null:
		_visual.modulate = Color("405b5c") if _cooldown > 0.0 else Color.WHITE


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
	if _cooldown > 0.0 or not body.is_in_group("player"):
		return
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	if refill_health:
		state.call("reset_health")
	if refill_missiles:
		state.call("refill_missiles", 9999)
	if refill_flux:
		state.call("refill_flux", 9999)
	_cooldown = 0.5
	if _visual != null:
		_visual.modulate = Color("405b5c")
