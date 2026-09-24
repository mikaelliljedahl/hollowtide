extends Node

const CRAWLER_SCENE: PackedScene = preload("res://scenes/enemies/crawler.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const FLOOR_Y := 600.0
const TEST_TIMEOUT_SECONDS := 8.0

var failures: Array[String] = []
var _sandbox: Node2D
var _player: Player
var _timed_out := false
var _finished := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(TEST_TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	await _setup_world()
	if not _timed_out:
		await _test_crouched_base_beam_hits_ground_enemy()
	if not _timed_out:
		await _test_crouched_wave_beam_hits_from_left()
	if not _timed_out:
		await _test_shooting_away_is_negative_control()
	if not _timed_out:
		await _test_crawler_immunity_and_missile_hit()
	if not _timed_out:
		await _test_armored_guard_ice_freeze()
	if not _timed_out:
		await _test_ceiling_diver_visible_tail_hit()

	if _timed_out:
		failures.append("FAIL: test exceeded %.1f second timeout" % TEST_TIMEOUT_SECONDS)
	if failures.is_empty():
		print("PASS: crouched ground shots hit real enemies in both directions")
	else:
		for failure in failures:
			push_error(failure)
	await _cleanup()
	await _finish(0 if failures.is_empty() else 1)


func _setup_world() -> void:
	GameState.reset_progress()
	GameState.acquire_beam()
	GameState.unlock_ability(&"wave_beam")
	GameState.unlock_ability(&"ice_beam")
	GameState.acquire_missiles(5)
	Weapons.reset_runtime()

	_sandbox = Node2D.new()
	_sandbox.name = "CrouchGroundHitSandbox"
	add_child(_sandbox)
	_add_static_rect(Vector2(300.0, FLOOR_Y + 32.0), Vector2(1800.0, 64.0))

	_player = PLAYER_SCENE.instantiate() as Player
	_sandbox.add_child(_player)
	_player.dev_invulnerable = true
	_player.reset_for_spawn(Vector2(300.0, FLOOR_Y))
	await _physics_frames(8)
	_check(_player.is_on_floor(), "actual Player settles on test floor")
	_check(not _player.is_crouching, "actual Player starts standing")


func _test_crouched_base_beam_hits_ground_enemy() -> void:
	var target := await _spawn_factory_enemy(&"spitter", Vector2(700.0, FLOOR_Y - 25.0))
	if target == null:
		return
	var initial_health := int(target.get("health"))
	_player.facing = 1
	GameState.set_active_beam(&"base")
	await _crouch_and_fire_x()
	await _physics_frames(12)
	_check(int(target.get("health")) < initial_health, "base X shot damages right ground enemy")

	for _shot_index in 2:
		Weapons.reset_runtime()
		await _physics_frames(2)
		await _crouch_and_fire_x()
		await _physics_frames(12)
	_check(int(target.get("health")) == 0, "base crouched shots defeat right ground enemy")
	target.queue_free()
	await _physics_frames(2)


func _test_crouched_wave_beam_hits_from_left() -> void:
	var target := await _spawn_factory_enemy(&"spitter", Vector2(-100.0, FLOOR_Y - 25.0))
	if target == null:
		return
	var initial_health := int(target.get("health"))
	_player.facing = -1
	GameState.set_active_beam(&"wave")
	await _crouch_and_fire_x()
	await _physics_frames(12)
	_check(int(target.get("health")) < initial_health, "Wave X shot damages left ground enemy")
	target.queue_free()
	await _physics_frames(2)


func _test_shooting_away_is_negative_control() -> void:
	var target := await _spawn_factory_enemy(&"spitter", Vector2(700.0, FLOOR_Y - 25.0))
	if target == null:
		return
	var initial_health := int(target.get("health"))
	_player.facing = -1
	GameState.set_active_beam(&"base")
	await _crouch_and_fire_x()
	await _physics_frames(12)
	_check(
		int(target.get("health")) == initial_health,
		"crouched X shot aimed away does not damage right ground enemy",
	)
	target.queue_free()
	await _physics_frames(2)


func _test_crawler_immunity_and_missile_hit() -> void:
	var immune_target := await _spawn_crawler(Vector2(700.0, FLOOR_Y - 16.0), -1)
	if immune_target == null:
		return
	_check(
		immune_target.call("is_vulnerable_to", &"beam") == false,
		"real crawler declares beam immunity",
	)
	var immune_health := int(immune_target.get("health"))
	_player.facing = 1
	GameState.set_active_beam(&"base")
	await _crouch_and_fire_x()
	await _physics_frames(12)
	_check(
		int(immune_target.get("health")) == immune_health,
		"crouched X shot does not damage beam-immune crawler",
	)
	immune_target.queue_free()
	await _physics_frames(2)

	var missile_target := await _spawn_crawler(Vector2(-100.0, FLOOR_Y - 16.0), 1)
	if missile_target == null:
		return
	var initial_health := int(missile_target.get("health"))
	_player.facing = -1
	await _crouch_and_fire_c()
	await _physics_frames(30)  # The harpoon (D19) is slower than the old missile.
	_check(
		int(missile_target.get("health")) < initial_health,
		"crouched C harpoon damages real crawler from the left",
	)
	missile_target.queue_free()
	await _physics_frames(2)


func _test_armored_guard_ice_freeze() -> void:
	var target := await _spawn_factory_enemy(&"armored_guard", Vector2(700.0, FLOOR_Y - 25.0))
	if target == null:
		return
	var initial_health := int(target.get("health"))
	_player.facing = 1
	GameState.set_active_beam(&"ice")
	await _crouch_and_fire_x()
	await _physics_frames(12)
	_check(bool(target.get("is_frozen")), "Ice X shot freezes the damage-immune armored guard")
	_check(
		int(target.get("health")) == initial_health,
		"freezing the armored guard preserves its health",
	)
	target.queue_free()
	await _physics_frames(2)


func _test_ceiling_diver_visible_tail_hit() -> void:
	# The shot crosses the visible lower silhouette while missing the compact
	# 50x50 movement body. This guards the sprite-derived flying-enemy hurtbox.
	var target := await _spawn_factory_enemy(&"ceiling_diver", Vector2(700.0, 576.0))
	if target == null:
		return
	target.call(&"configure_arena", Rect2(600.0, 500.0, 200.0, 200.0))
	var initial_health := int(target.get("health"))
	_player.facing = 1
	GameState.set_active_beam(&"base")
	await _crouch_and_fire_x()
	await _physics_frames(24)
	_check(
		int(target.get("health")) < initial_health,
		"beam damages the ceiling diver through its visible lower silhouette",
	)
	target.queue_free()
	await _physics_frames(2)


func _spawn_factory_enemy(runtime_id: StringName, position: Vector2) -> Node2D:
	var enemy := EnemyFactory.create(runtime_id)
	_check(enemy != null, "EnemyFactory creates %s" % runtime_id)
	if enemy == null:
		return null
	_sandbox.add_child(enemy)
	enemy.global_position = position
	await _physics_frames(3)
	_check(enemy.is_in_group(&"enemies"), "%s joins enemies group on normal spawn" % runtime_id)
	_check(
		enemy.is_in_group(&"damageable"), "%s joins damageable group on normal spawn" % runtime_id
	)
	_check(
		(enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D).disabled == false,
		"%s normal body hurtbox is enabled" % runtime_id,
	)
	return enemy


func _spawn_crawler(position: Vector2, direction: int) -> Crawler:
	var crawler := CRAWLER_SCENE.instantiate() as Crawler
	_check(crawler != null, "actual crawler scene instantiates")
	if crawler == null:
		return null
	crawler.travel_direction = direction
	crawler.move_speed = 60.0
	_sandbox.add_child(crawler)
	crawler.global_position = position
	await _physics_frames(5)
	_check(crawler.has_surface_contact(), "real crawler attaches to test floor")
	_check(
		crawler.surface_normal().dot(Vector2.UP) > 0.94,
		"real crawler hurtbox follows the floor normal",
	)
	_check(crawler.is_in_group(&"damageable"), "real crawler joins damageable group")
	_check(
		(crawler.get_node_or_null("CollisionShape2D") as CollisionShape2D).disabled == false,
		"crawler normal body hurtbox is enabled",
	)
	return crawler


func _crouch_and_fire_x() -> void:
	_release_inputs()
	_parse_key(KEY_DOWN, true)
	await _physics_frames(2)
	_check(_player.is_crouching, "Down reaches live Player crouch state")
	_parse_key(KEY_X, true)
	await _physics_frames(1)
	_parse_key(KEY_X, false)
	await _physics_frames(1)
	_parse_key(KEY_DOWN, false)


func _crouch_and_fire_c() -> void:
	_release_inputs()
	_parse_key(KEY_DOWN, true)
	await _physics_frames(2)
	_check(_player.is_crouching, "Down reaches live Player crouch state for missile")
	_parse_key(KEY_C, true)
	await _physics_frames(1)
	_parse_key(KEY_C, false)
	await _physics_frames(1)
	_parse_key(KEY_DOWN, false)


func _parse_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_inputs() -> void:
	_parse_key(KEY_DOWN, false)
	_parse_key(KEY_X, false)
	_parse_key(KEY_C, false)


func _add_static_rect(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = position
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	_sandbox.add_child(body)
	return body


func _physics_frames(count: int) -> void:
	for _frame in count:
		if _timed_out:
			return
		await get_tree().physics_frame


func _on_timeout() -> void:
	if not _finished:
		_timed_out = true


func _cleanup() -> void:
	_release_inputs()
	Weapons.reset_runtime()
	GameState.reset_progress()
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
		await get_tree().physics_frame
	await get_tree().process_frame


func _finish(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	await TestShutdown.finish(get_tree(), exit_code)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
