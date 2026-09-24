class_name FluxBurstProjectile
extends ProjectileBase

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/beam/beam_impact.tscn")

const FRAME_COUNT := 10
const FPS := 24.0

@onready var _sprite: Sprite2D = $Sprite2D
var _age_visual := 0.0


func _ready() -> void:
	speed = 1800.0
	lifetime = Catalog.BURST_BEAM_RANGE / speed
	damage_amount = Catalog.BURST_BEAM_DAMAGE
	damage_kind = &"beam"
	super._ready()
	_sprite.hframes = FRAME_COUNT
	_sprite.frame = 0


func _process(delta: float) -> void:
	_age_visual += delta
	_sprite.frame = int(_age_visual * FPS) % FRAME_COUNT


func _impact(position: Vector2, reaction: StringName, normal: Vector2) -> void:
	var effect := IMPACT_SCENE.instantiate() as BeamFxImpact
	if effect == null:
		return
	effect.configure(&"beam", rotation, reaction, normal)
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(effect)
	effect.global_position = position
