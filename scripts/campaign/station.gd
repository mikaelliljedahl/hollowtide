extends Area2D

## Floor shrine. `save` refills, sets the checkpoint and writes the campaign slot; `refill` restores
## health and missiles; `missilerefill` restores missiles only (placed before missile-only locks
## and inside boss arenas so mandatory ammo never depends on random drops).

const VISUAL_WIDTH := {&"save": 224.0, &"refill": 208.0, &"missilerefill": 176.0}
const FLOOR_OFFSET_Y := 38.0
const TEXTURES := {
	&"save": "res://assets/sprites/devmode/checkpoint_shrine.png",
	&"refill": "res://assets/sprites/devmode/refill_shrine.png",
	&"missilerefill": "res://assets/sprites/devmode/refill_shrine.png",
}

@export var station_kind: StringName = &"save"

var _cooldown := 0.0
# Armed shortly after the room loads so spawning on a shrine (continue/respawn) does not re-save.
var _arming := 0.6
var _visual: Sprite2D
var _glow: PointLight2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	add_to_group(&"campaign_station")
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(112, 64)
	shape.shape = rectangle
	add_child(shape)
	_visual = Sprite2D.new()
	_visual.name = "StationVisual"
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_visual.z_index = 1
	_visual.texture = load(TEXTURES.get(station_kind, TEXTURES[&"refill"])) as Texture2D
	if station_kind == &"missilerefill":
		_visual.self_modulate = Color(1.0, 0.72, 0.6)
	if _visual.texture != null:
		var width: float = VISUAL_WIDTH.get(station_kind, 208.0)
		_visual.scale = Vector2.ONE * width / _visual.texture.get_width()
		_anchor_to_floor(_visual)
	add_child(_visual)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_arming = maxf(_arming - delta, 0.0)
	if _cooldown <= 0.0:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _visual != null:
		_visual.modulate = Color(0.55, 0.8, 0.8) if _cooldown > 0.0 else Color.WHITE


func _anchor_to_floor(sprite: Sprite2D) -> void:
	var image := sprite.texture.get_image()
	if image == null:
		return
	var used := image.get_used_rect()
	var center_y := float(sprite.texture.get_height()) * 0.5
	sprite.position.y = FLOOR_OFFSET_Y - (float(used.end.y) - center_y) * sprite.scale.y


func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0 or _arming > 0.0 or not body.is_in_group(&"player"):
		return
	_cooldown = 1.2 if station_kind == &"save" else 0.5
	if _visual != null:
		_visual.modulate = Color(0.55, 0.8, 0.8)
	match station_kind:
		&"save":
			GameState.refill()
			var root := get_tree().get_first_node_in_group(&"campaign_root")
			if root != null and root.has_method("save_at"):
				root.call("save_at", position + Vector2(0, FLOOR_OFFSET_Y))
		&"refill":
			GameState.reset_health()
			GameState.refill_missiles(9999)
		&"missilerefill":
			GameState.refill_missiles(9999)
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.call("play_sfx", &"weapon_pickup")
