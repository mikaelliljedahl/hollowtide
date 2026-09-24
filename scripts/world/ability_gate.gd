class_name AbilityGate
extends StaticBody2D

signal opened(gate)

@export var gate_kind: StringName = &"missile"
@export var flag_id := ""
@export var gate_size := Vector2(64, 192)

const FRAME_TEXTURE_PATH := "res://assets/sprites/devmode/passage_arch.png"
const HitResult = preload("res://scripts/combat/hit_result.gd")
const FRAME_MARGIN := Vector2(64.0, 64.0)
const TEXTURE_BY_KIND: Dictionary[StringName, String] = {
	&"missile": "res://assets/sprites/devmode/missile_gate.png",
	&"wave": "res://assets/sprites/devmode/wave_grate.png",
	&"bomb": "res://assets/sprites/devmode/bomb_gate.png",
	&"undertow": "res://assets/sprites/devmode/undertow_gate.png",
}

## D19 restyle (kinds unchanged): missile -> harpoon socket, wave -> resonant membrane,
## bomb -> cracked crystal, undertow -> undertow barrier. Legacy art is the fallback.
const ARSENAL_TEXTURE_BY_KIND: Dictionary[StringName, String] = {
	&"missile": "res://assets/sprites/arsenal/harpoon_socket.png",
	&"wave": "res://assets/sprites/arsenal/resonant_membrane.png",
	&"bomb": "res://assets/sprites/arsenal/cracked_crystal.png",
	&"undertow": "res://assets/sprites/arsenal/undertow_barrier.png",
}
const OPEN_TINTS: Dictionary[StringName, Color] = {
	&"missile": Color(0.7, 1.0, 0.95, 0.9),
	&"wave": Color(0.72, 0.62, 1.0, 0.9),
	&"bomb": Color(1.0, 0.8, 0.4, 0.9),
	&"undertow": Color(0.4, 0.9, 0.85, 0.9),
}

var _is_open := false
var _flash := 0.0
var _shape: CollisionShape2D
var _frame: Sprite2D
var _visual: Sprite2D


func _ready():
	collision_layer = 1
	collision_mask = 0
	add_to_group("damageable")
	add_to_group("ability_gates")
	_shape = CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = gate_size
	_shape.shape = rectangle
	add_child(_shape)
	_frame = _create_architecture_frame()
	add_child(_frame)
	_visual = _create_door_leaf()
	add_child(_visual)
	if not flag_id.is_empty() and GameState.has_world_flag(flag_id):
		_open(false)


func is_vulnerable_to(kind: StringName):
	return not _is_open and kind == gate_kind


func receive_hit(amount: int, kind: StringName, _hit_context := {}) -> HitResult.Reaction:
	if _is_open:
		return HitResult.Reaction.PASS
	_flash = 0.2
	if _visual != null:
		_visual.modulate = Color(1.0, 0.65, 0.65)
	if not is_vulnerable_to(kind):
		Audio.play_sfx(&"beam_ricochet")
		return HitResult.Reaction.BLOCKED
	if amount <= 0 and kind != &"ice":
		return HitResult.Reaction.PASS
	_open(true)
	return HitResult.Reaction.TRIGGERED


func take_damage(amount: int, kind: StringName):
	receive_hit(amount, kind)


func aperture_rect():
	return Rect2(-gate_size * 0.5, gate_size)


func _open(persist: bool):
	_is_open = true
	_shape.set_deferred("disabled", true)
	collision_layer = 0
	if _visual != null:
		_visual.visible = false
	if persist and not flag_id.is_empty():
		GameState.set_world_flag(flag_id)
	if persist:
		_spawn_open_effect()
		Audio.play_sfx(&"weapon_pickup")
		opened.emit(self)
	queue_redraw()


func _spawn_open_effect() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var tint: Color = OPEN_TINTS.get(gate_kind, Color.WHITE)
	var reach := maxf(gate_size.x, gate_size.y) * 0.6
	ArsenalFx.spawn_rings(parent, global_position, reach, tint, 0.45, 2)
	for offset in [-0.35, 0.0, 0.35]:
		ArsenalFx.spawn_sparks(
			parent, global_position + Vector2(0.0, gate_size.y * offset), Vector2.UP, 5, tint
		)
	if gate_kind == &"undertow":
		GameJuice.play_sfx(&"barrier_break", &"dash_strike")


func _physics_process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta, 0.0)
	if _visual != null and _flash == 0.0:
		_visual.modulate = Color.WHITE


static func texture_path_for(kind: StringName) -> String:
	var arsenal_path: String = ARSENAL_TEXTURE_BY_KIND.get(kind, "")
	if not arsenal_path.is_empty() and ResourceLoader.exists(arsenal_path):
		return arsenal_path
	return TEXTURE_BY_KIND.get(kind, "")


func _create_door_leaf():
	var sprite := Sprite2D.new()
	sprite.name = "GateVisual"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = 3
	var path := texture_path_for(gate_kind)
	sprite.texture = load(path) as Texture2D if not path.is_empty() else null
	if sprite.texture == null:
		return sprite
	var crop_size := Vector2(400.0, 400.0)
	if gate_size.y > gate_size.x:
		crop_size.y = 480.0
		crop_size.x = crop_size.y * gate_size.x / gate_size.y
	sprite.region_enabled = true
	sprite.region_rect = Rect2((Vector2(sprite.texture.get_size()) - crop_size) * 0.5, crop_size)
	sprite.scale = gate_size / crop_size
	return sprite


func _create_architecture_frame():
	var frame := Sprite2D.new()
	frame.name = "GateFrameVisual"
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.z_index = 2
	frame.texture = load(FRAME_TEXTURE_PATH) as Texture2D
	if frame.texture != null:
		frame.scale = (gate_size + FRAME_MARGIN) / Vector2(frame.texture.get_size())
	return frame
