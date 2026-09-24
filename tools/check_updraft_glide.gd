extends Node
## Updraft Cloak glide: fall speed is capped only with the ability, only while holding jump.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var glide := await _fall_speed(true, true)
	var no_hold := await _fall_speed(true, false)
	var no_ability := await _fall_speed(false, true)
	_check(absf(glide - UpdraftCloak.GLIDE_FALL_SPEED) < 1.0, "glide caps fall at %.1f" % glide)
	_check(no_hold > UpdraftCloak.GLIDE_FALL_SPEED + 200.0, "no cap without holding jump")
	_check(no_ability > UpdraftCloak.GLIDE_FALL_SPEED + 200.0, "no cap without the cloak")
	print("Updraft glide: glide=%.1f no_hold=%.1f no_ability=%.1f" % [glide, no_hold, no_ability])
	GameState.reset_progress()
	if failures.is_empty():
		print("Updraft glide check passed")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _fall_speed(owned: bool, hold_jump: bool) -> float:
	GameState.reset_progress()
	if owned:
		GameState.unlock_ability(&"high_jump")
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector2(400.0, 0.0)
	if hold_jump:
		Input.action_press("jump")
	for frame in 50:
		await get_tree().physics_frame
	var speed := player.velocity.y
	Input.action_release("jump")
	player.queue_free()
	await get_tree().physics_frame
	return speed


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
