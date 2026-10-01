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
	var glide_pose := await _spin_jump_animation(true)
	var fall_pose := await _spin_jump_animation(false)
	_check(
		not String(glide_pose).begins_with("spin"), "glide shows the upright pose: %s" % glide_pose
	)
	_check(
		String(fall_pose).begins_with("spin"),
		"a spin jump without glide keeps the spin: %s" % fall_pose
	)
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


## The sprite animation while falling from a spin jump, holding jump (gliding) or not.
func _spin_jump_animation(hold_jump: bool) -> StringName:
	GameState.reset_progress()
	GameState.unlock_ability(&"high_jump")
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector2(400.0, 0.0)
	if hold_jump:
		Input.action_press("jump")
	for frame in 50:
		player.is_spinning = true
		await get_tree().physics_frame
	await get_tree().process_frame
	var animation := (player.get("_sprite") as AnimatedSprite2D).animation
	Input.action_release("jump")
	player.queue_free()
	await get_tree().physics_frame
	return animation


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
