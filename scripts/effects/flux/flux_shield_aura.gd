class_name FluxShieldAura
extends Node2D

const FRAME_COUNT := 4
const FPS := 12.0

@onready var _sprite: Sprite2D = $Sprite2D
var _age := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"transient")
	_sprite.hframes = FRAME_COUNT
	_sprite.frame = 0


func _process(delta: float) -> void:
	_age += delta
	_sprite.frame = int(_age * FPS) % FRAME_COUNT
	_sprite.modulate.a = 0.72 + sin(_age * 7.0) * 0.12
