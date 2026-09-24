class_name EchoScanPulse
extends Node2D

const MARKER_SCRIPT = preload("res://scripts/effects/flux/flux_scan_marker.gd")
const RADIUS := 900.0
const DURATION := 1.5
const FRAME_COUNT := 4
const FPS := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
var _age := 0.0
var _markers: Array[Node2D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"transient")
	add_to_group(&"flux_echo_scan")
	_sprite.hframes = FRAME_COUNT
	_sprite.frame = 0
	_sprite.scale = Vector2.ONE * (RADIUS * 2.0 / 256.0)
	_reveal_targets()


func _process(delta: float) -> void:
	_age += delta
	_sprite.frame = int(_age * FPS) % FRAME_COUNT
	_sprite.modulate.a = clampf(0.68 - _age * 0.32, 0.0, 0.68)
	if _age >= DURATION:
		queue_free()


func _reveal_targets() -> void:
	var seen: Array[Node2D] = []
	for group in [
		&"enemies",
		&"bosses",
		&"ability_gates",
		&"dev_pickup",
		&"dev_checkpoint",
		&"dev_refill",
		&"dev_optional_fixture"
	]:
		for candidate in get_tree().get_nodes_in_group(group):
			var target := candidate as Node2D
			if target == null or seen.has(target) or not is_instance_valid(target):
				continue
			if target.global_position.distance_to(global_position) > RADIUS:
				continue
			seen.append(target)
			_add_marker(target)
	for candidate in get_tree().get_nodes_in_group(&"pickups"):
		var target := candidate as Node2D
		if (
			target != null
			and not seen.has(target)
			and target.global_position.distance_to(global_position) <= RADIUS
		):
			_add_marker(target)


func _add_marker(target: Node2D) -> void:
	var marker := MARKER_SCRIPT.new() as Node2D
	if marker == null:
		return
	target.add_child(marker)
	marker.position = Vector2.ZERO
	marker.call("configure", target, DURATION)
	_markers.append(marker)
