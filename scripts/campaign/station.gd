extends Area2D

## Floor shrine. `save` refills, sets the checkpoint and writes the campaign slot; `refill` restores
## health and missiles; `missilerefill` restores missiles only (placed before missile-only locks
## and inside boss arenas so mandatory ammo never depends on random drops).
## A save shrine also opens the shrine menu (CampaignRoot.open_shrine): fast travel
## (docs/features/fast-travel.md) and Tide Sockets (docs/features/tide-modules.md). While it offers
## anything, an up chevron hovers over it and move_up opens it.

const FastTravel = preload("res://scripts/campaign/fast_travel.gd")
const VISUAL_WIDTH := {&"save": 224.0, &"refill": 208.0, &"missilerefill": 176.0}
const FLOOR_OFFSET_Y := 38.0
const PROMPT_Y := -230.0
const PROMPT_COLOR := Color("7fe3ff")
const PROMPT_FADE_SPEED := 5.0
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
var _player: CharacterBody2D
var _prompt: Node2D
var _prompt_time := 0.0


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
	# Default z: the player is added after the rooms, so she draws in front of the shrine.
	_visual.texture = load(TEXTURES.get(station_kind, TEXTURES[&"refill"])) as Texture2D
	if station_kind == &"missilerefill":
		_visual.self_modulate = Color(1.0, 0.72, 0.6)
	if _visual.texture != null:
		var width: float = VISUAL_WIDTH.get(station_kind, 208.0)
		_visual.scale = Vector2.ONE * width / _visual.texture.get_width()
		_anchor_to_floor(_visual)
	add_child(_visual)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if station_kind == &"save":
		_prompt = Node2D.new()
		_prompt.name = "ShrinePrompt"
		_prompt.z_index = 2
		_prompt.position.y = PROMPT_Y
		_prompt.modulate.a = 0.0
		_prompt.draw.connect(_draw_prompt)
		add_child(_prompt)


## This shrine's fast-travel id, or "" outside a campaign room.
func station_id() -> String:
	var room := get_parent().get_parent() as CampaignRoom if get_parent() != null else null
	if room == null:
		return ""
	return FastTravel.station_id(room.room_id, position + Vector2(0, FLOOR_OFFSET_Y))


func _physics_process(delta: float) -> void:
	_arming = maxf(_arming - delta, 0.0)
	if _prompt != null:
		_update_prompt(delta)
	if _cooldown <= 0.0:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _visual != null:
		_visual.modulate = Color(0.55, 0.8, 0.8) if _cooldown > 0.0 else Color.WHITE


func _update_prompt(delta: float) -> void:
	var available := _shrine_ready()
	_prompt.modulate.a = move_toward(
		_prompt.modulate.a, 1.0 if available else 0.0, PROMPT_FADE_SPEED * delta
	)
	_prompt_time += delta
	_prompt.queue_redraw()
	if available and Input.is_action_just_pressed(&"move_up"):
		_root().call("open_shrine", station_id())


func _shrine_ready() -> bool:
	if _player == null or not _player.is_on_floor() or bool(_player.get("is_ball")):
		return false
	var root := _root()
	if root == null or not root.has_method("shrine_options"):
		return false
	return not (root.call("shrine_options", station_id()) as Array).is_empty()


func _draw_prompt() -> void:
	# An up chevron, bobbing gently: the shrine offers travel or sockets (no text in the world).
	var bob := sin(_prompt_time * 3.0) * 5.0
	for index in 2:
		var y := bob - float(index) * 16.0
		var points := PackedVector2Array(
			[Vector2(-18, y + 10), Vector2(0, y - 8), Vector2(18, y + 10)]
		)
		var alpha := 1.0 if index == 0 else 0.55
		_prompt.draw_polyline(points, Color(0.01, 0.03, 0.05, 0.8 * alpha), 9.0, true)
		_prompt.draw_polyline(points, Color(PROMPT_COLOR, alpha), 5.0, true)


func _root() -> Node:
	return get_tree().get_first_node_in_group(&"campaign_root")


func _anchor_to_floor(sprite: Sprite2D) -> void:
	var image := sprite.texture.get_image()
	if image == null:
		return
	var used := image.get_used_rect()
	var center_y := float(sprite.texture.get_height()) * 0.5
	sprite.position.y = FLOOR_OFFSET_Y - (float(used.end.y) - center_y) * sprite.scale.y


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player = body as CharacterBody2D
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
