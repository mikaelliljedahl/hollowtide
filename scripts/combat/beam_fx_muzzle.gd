class_name BeamFxMuzzle extends Node2D

const BASE_TEXTURE = preload("res://assets/sprites/effects/base_core.png")
const ICE_TEXTURE = preload("res://assets/sprites/effects/ice_core.png")
const WAVE_TEXTURE = preload("res://assets/sprites/effects/wave_muzzle.png")
const GLOW_MATERIAL = preload("res://resources/combat/beam_glow_add.tres")

const BASE_ANCHOR := Vector2(88.0, 32.0)
const ICE_ANCHOR := Vector2(88.0, 31.0)
const FRAME_SIZE := Vector2(96.0, 64.0)
const FRAME_COUNT := 4
const FPS := 28.0
const DURATION := float(FRAME_COUNT) / FPS

@onready var _sprite: Sprite2D = $Sprite2D

var beam_kind: StringName = &"beam"
var _direction_angle := 0.0
var _age := 0.0


func configure(kind: StringName, direction: Vector2) -> void:
	beam_kind = kind
	_direction_angle = (Vector2.RIGHT if direction.is_zero_approx() else direction).angle()
	if is_node_ready():
		_apply_profile()


func _ready() -> void:
	add_to_group(&"beam_fx")
	call_deferred("add_to_group", &"transient")
	_apply_profile()


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	_sprite.frame = mini(int(_age * FPS), FRAME_COUNT - 1)
	var progress := _age / DURATION
	modulate.a = 1.0 - progress * progress
	if beam_kind == &"wave":
		scale = Vector2.ONE * lerpf(0.72, 1.0, progress)
	else:
		scale = Vector2.ONE * lerpf(0.48, 0.62, progress)


func atlas_path() -> String:
	match beam_kind:
		&"ice":
			return "res://assets/sprites/effects/ice_core.png"
		&"wave":
			return "res://assets/sprites/effects/wave_muzzle.png"
		_:
			return "res://assets/sprites/effects/base_core.png"


func _apply_profile() -> void:
	if _sprite == null:
		return
	rotation = _direction_angle
	_sprite.material = GLOW_MATERIAL
	_sprite.texture = _texture_for_kind()
	_sprite.hframes = FRAME_COUNT
	_sprite.frame = 0
	if beam_kind == &"wave":
		_sprite.position = Vector2.ZERO
	else:
		var anchor := ICE_ANCHOR if beam_kind == &"ice" else BASE_ANCHOR
		_sprite.position = -(anchor - FRAME_SIZE * 0.5)


func _texture_for_kind() -> Texture2D:
	match beam_kind:
		&"ice":
			return ICE_TEXTURE
		&"wave":
			return WAVE_TEXTURE
		_:
			return BASE_TEXTURE
