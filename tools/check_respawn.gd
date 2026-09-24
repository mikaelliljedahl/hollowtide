extends Node

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01.tscn")
const PROTOTYPE_SPAWN := Vector2(3360.0, 448.0)
const RESPAWN_WAIT := 0.7

var _failures: Array[String] = []
var _level: Node2D
var _controller: Node
var _player: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_level = LEVEL_SCENE.instantiate() as Node2D
	if _level == null:
		_fail("level_01.tscn could not be instantiated")
		_finish()
		return
	add_child(_level)
	await _wait_frames(2)
	_controller = _level
	_player = _level.get_node_or_null("PlayerSpawn/Player") as Node2D
	if _player == null:
		_fail("PlayerSpawn/Player is missing")
	else:
		await _test_normal_respawn()
		if _dev_enabled():
			await _test_dev_checkpoint_wins_over_save()
	_level.free()
	await get_tree().process_frame
	_finish()


func _test_normal_respawn() -> void:
	GameState.reset_progress()
	_player.call("reset_for_spawn", PROTOTYPE_SPAWN)
	await _wait_frames(1)
	_player.set("is_ball", true)
	_player.call("_set_ball_form", true)
	_player.set("is_spinning", true)
	_player.set("dash_active", true)
	GameState.apply_damage(999)
	await _wait_seconds(RESPAWN_WAIT)
	_check(GameState.health == GameState.max_health, "normal death restores full health")
	_check(_player.global_position == PROTOTYPE_SPAWN, "normal death uses actual PlayerSpawn")
	_check(not bool(_player.get("_dead")), "normal player leaves dead state")
	_check(not bool(_player.get("is_ball")), "respawn resets slip form")
	_check(not bool(_player.get("is_spinning")), "respawn resets spin")
	_check(not bool(_player.get("dash_active")), "respawn resets dash state")
	_check(_player.velocity == Vector2.ZERO, "respawn resets velocity before next physics tick")

	var before := _player.global_position.x
	Input.action_press("move_right")
	await _wait_frames(8)
	Input.action_release("move_right")
	_check(_player.global_position.x > before, "movement input resumes after respawn")

	get_tree().paused = true
	GameState.apply_damage(999)
	_controller.call("_on_player_died")
	await _wait_seconds(RESPAWN_WAIT)
	_check(get_tree().paused, "respawn does not silently unpause paused tree")
	_check(GameState.health == GameState.max_health, "paused death still restores full health")
	_check(not bool(_player.get("_dead")), "paused death leaves player controllable")
	get_tree().paused = false
	await _wait_frames(2)


func _test_dev_checkpoint_wins_over_save() -> void:
	GameState.reset_progress()
	_controller.call("_teleport_station", 1)
	GameState.unlock_ability(&"beam")
	var old_checkpoint: Dictionary = GameState.checkpoint.duplicate(true)
	var save_result: Error = SaveStore.save_game()
	_check(save_result == OK, "dev test writes old checkpoint only to isolated SaveStore")

	_controller.call("_teleport_station", 9)
	GameState.unlock_ability(&"slipstream")
	GameState.apply_damage(999)
	await _wait_seconds(RESPAWN_WAIT)
	_check(
		GameState.checkpoint.get("room", "") == "S9", "latest dev station checkpoint survives death"
	)
	_check(GameState.checkpoint != old_checkpoint, "new checkpoint differs from old disk snapshot")
	_check(
		GameState.has_ability(&"slipstream"), "death keeps progress acquired after explicit save"
	)
	_check(GameState.health == GameState.max_health, "dev death restores full health")
	var room_origins: Dictionary = _controller.get("_room_origins")
	var expected_s9: Vector2 = room_origins["S9"] + Vector2(960, 1114)
	_check(
		(
			GameState.checkpoint.get("x", 0.0) == expected_s9.x
			and GameState.checkpoint.get("y", 0.0) == expected_s9.y
		),
		"entry safe marker updates dev checkpoint"
	)
	_check(
		(
			is_equal_approx(_player.global_position.x, expected_s9.x)
			and _player.global_position.y >= expected_s9.y
		),
		"dev respawn uses safe checkpoint marker"
	)


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _dev_enabled() -> bool:
	return OS.get_cmdline_args().has("--dev-mode") or OS.get_cmdline_user_args().has("--dev-mode")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("check_respawn: PASS")
		await TestShutdown.finish(get_tree(), 0)
		return
	for failure in _failures:
		push_error("check_respawn: " + failure)
	await TestShutdown.finish(get_tree(), 1)
