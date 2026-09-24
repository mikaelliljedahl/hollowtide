class_name BeamFxImpact extends Node2D

const BASE_TEXTURE = preload("res://assets/sprites/effects/base_impact.png")
const ICE_TEXTURE = preload("res://assets/sprites/effects/ice_impact.png")
const WAVE_TEXTURE = preload("res://assets/sprites/effects/wave_impact.png")
const GLOW_MATERIAL = preload("res://resources/combat/beam_glow_add.tres")
const NEUTRAL_MATERIAL = preload("res://resources/combat/beam_neutral_ricochet.tres")

const BASE_FRAMES := 4
const WAVE_FRAMES := 8
const BASE_FPS := 22.0
const WAVE_FPS := 30.0

@onready var _sprite: Sprite2D = $Sprite2D

var beam_kind: StringName = &"beam"
var reaction: StringName = &"wall"
var impact_normal := Vector2.ZERO
var _incoming_angle := 0.0
var _age := 0.0
var _duration := float(BASE_FRAMES) / BASE_FPS
var _base_scale := Vector2.ONE


func configure(
	kind: StringName,
	angle: float,
	new_reaction: StringName = &"wall",
	normal: Vector2 = Vector2.ZERO,
) -> void:
	beam_kind = kind
	reaction = new_reaction
	impact_normal = normal
	_incoming_angle = angle
	if is_node_ready():
		_apply_profile()


func _ready() -> void:
	add_to_group(&"transient")
	_apply_profile()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	var frame_count := WAVE_FRAMES if beam_kind == &"wave" else BASE_FRAMES
	var fps := WAVE_FPS if beam_kind == &"wave" else BASE_FPS
	_sprite.frame = mini(int(_age * fps), frame_count - 1)
	var progress := _age / _duration
	match reaction:
		&"vulnerable":
			scale = _base_scale * lerpf(1.0, 0.68, progress)
		&"immune":
			scale = _base_scale * lerpf(0.82, 0.48, progress)
		&"freeze":
			scale = _base_scale * Vector2(lerpf(0.8, 1.12, progress), lerpf(1.1, 0.72, progress))
		&"triggered":
			scale = _base_scale * lerpf(0.72, 1.24, progress)
		&"grate":
			scale = Vector2(_base_scale.x * lerpf(0.72, 1.18, progress), _base_scale.y)
		_:
			scale = _base_scale * lerpf(0.82, 1.0, progress)
	modulate.a = 1.0 - progress


func atlas_path() -> String:
	match beam_kind:
		&"ice":
			return "res://assets/sprites/effects/ice_impact.png"
		&"wave":
			return "res://assets/sprites/effects/wave_impact.png"
		_:
			return "res://assets/sprites/effects/base_impact.png"


func _apply_profile() -> void:
	if _sprite == null:
		return
	_sprite.texture = _texture_for_kind()
	_sprite.hframes = WAVE_FRAMES if beam_kind == &"wave" else BASE_FRAMES
	_sprite.frame = 0
	_duration = float(_sprite.hframes) / (WAVE_FPS if beam_kind == &"wave" else BASE_FPS)
	_sprite.material = NEUTRAL_MATERIAL if reaction == &"immune" else GLOW_MATERIAL
	rotation = impact_normal.angle() if not impact_normal.is_zero_approx() else _incoming_angle
	match reaction:
		&"wall":
			_base_scale = Vector2(0.82, 0.50)
		&"grate":
			_base_scale = Vector2(0.72, 0.34)
			_duration = minf(_duration, 0.17)
		&"immune":
			_base_scale = Vector2(0.72, 0.52)
		&"freeze":
			_base_scale = Vector2(0.88, 1.08)
		&"triggered":
			_base_scale = Vector2(0.76, 0.76)
		_:
			_base_scale = Vector2.ONE
	scale = _base_scale


func _texture_for_kind() -> Texture2D:
	match beam_kind:
		&"ice":
			return ICE_TEXTURE
		&"wave":
			return WAVE_TEXTURE
		_:
			return BASE_TEXTURE
