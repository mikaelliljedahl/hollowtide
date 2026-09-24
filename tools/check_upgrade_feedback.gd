extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BOMB_SCENE: PackedScene = preload("res://scenes/combat/bomb.tscn")
const CRAWLER_SCENE: PackedScene = preload("res://scenes/enemies/crawler.tscn")
const FLOOR_Y := 900.0

var failures: Array[String] = []
var _world: Node2D
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	_world = Node2D.new()
	add_child(_world)
	_add_floor()
	await _spawn_player()
	await _test_actual_undertow_lifecycle()
	await _test_vertical_aim_and_shot_suppression()
	await _test_reset_cleanup()
	await _test_bomb_detonation()
	await _test_crawler_death_fx()
	await _capture_visual_proof()
	_release_inputs()
	Weapons.reset_runtime()
	if is_instance_valid(_world):
		_world.queue_free()
	await get_tree().physics_frame
	if failures.is_empty():
		print("PASS: actual undertow lifecycle, bomb detonation FX, and crawler death FX")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _test_actual_undertow_lifecycle() -> void:
	# D19: `undertow_dash` is the Undertow Dash; the spin jump no longer attacks.
	GameState.reset_progress()
	GameState.unlock_ability(&"undertow_dash")
	_player.reset_for_spawn(Vector2(320.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_right")
	Input.action_press("jump")
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	await get_tree().physics_frame
	_check(_player.is_spinning, "horizontal grounded jump starts real spin")
	_check(not _player.dash_active, "spin jump is not an attack")
	Input.action_release("jump")
	_release_movement()
	await _physics_frames(40)
	_check(not _player.is_spinning, "landing deactivates spin")
	Input.action_press("dash")
	await _physics_frames(2)
	Input.action_release("dash")
	_check(_player.dash_active, "dash input starts Undertow Dash")
	await _physics_frames(20)
	_check(not _player.dash_active, "dash ends after its burst")


func _test_vertical_aim_and_shot_suppression() -> void:
	GameState.reset_progress()
	GameState.acquire_beam()
	GameState.unlock_ability(&"undertow_dash")
	_player.reset_for_spawn(Vector2(320.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_right")
	Input.action_press("move_up")
	Input.action_press("jump")
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	await get_tree().physics_frame
	_check(not _player.is_spinning, "vertical aim suppresses spin")
	Input.action_release("jump")
	Input.action_release("move_up")
	_release_movement()
	await _physics_frames(4)

	_player.reset_for_spawn(Vector2(320.0, FLOOR_Y))
	await _settle_player()
	Input.action_press("move_right")
	Input.action_press("jump")
	_player._jump_buffer_timer = PlayerConfig.JUMP_BUFFER
	await get_tree().physics_frame
	_check(_player.is_spinning, "second real jump spins")
	Input.action_press("fire_beam")
	await get_tree().process_frame
	_player._handle_weapon_input()
	await get_tree().physics_frame
	_check(not _player.is_spinning, "shooting deactivates spin")
	Input.action_release("fire_beam")
	Input.action_release("jump")
	_release_movement()
	await _physics_frames(3)


func _test_reset_cleanup() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"undertow_dash")
	_player.reset_for_spawn(Vector2(320.0, FLOOR_Y))
	await _settle_player()
	_check(_player.start_dash(1), "reset test starts a dash")
	_player.reset_for_spawn(Vector2(340.0, FLOOR_Y))
	_release_inputs()
	_check(not _player.is_spinning and not _player.dash_active, "reset clears spin and dash state")
	await _physics_frames(2)


func _test_bomb_detonation() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"bombs")
	Weapons.reset_runtime()
	var bomb := BOMB_SCENE.instantiate() as Bomb
	_world.add_child(bomb)
	bomb.global_position = Vector2(640.0, 700.0)
	await _physics_frames(40)
	_check(is_instance_valid(bomb), "bomb remains through 0.75 second fuse")
	_check(not _has_transient_feedback(), "bomb placement creates no explosion FX")
	await _physics_frames(10)
	_check(not is_instance_valid(bomb), "bomb detonates at fuse expiry")
	_check(_has_transient_feedback(), "bomb detonation spawns shared transient FX")
	_check(
		(
			_playing_sfx_count(
				&"pulse_burst" if Audio.SFX_PATHS.has(&"pulse_burst") else &"bomb_explode"
			)
			== 1
		),
		"one pulse detonation cue starts"
	)
	await _physics_frames(24)
	_check(not _has_transient_feedback(), "bomb FX cleans within compact lifetime")


func _test_crawler_death_fx() -> void:
	var crawler := CRAWLER_SCENE.instantiate() as Crawler
	_world.add_child(crawler)
	crawler.global_position = Vector2(1100.0, 700.0)
	crawler.set_physics_process(false)
	await get_tree().physics_frame
	crawler.take_damage(105, &"missile")
	var collision := crawler.get_node("CollisionShape2D") as CollisionShape2D
	_check(collision.disabled, "crawler hurt collision disables immediately on death")
	_check(_has_transient_feedback(), "crawler death spawns real shared FX")
	await _physics_frames(40)
	_check(not is_instance_valid(crawler), "crawler death source cleans up")
	_check(not _has_transient_feedback(), "crawler death FX cleans up")


func _capture_visual_proof() -> void:
	if DisplayServer.get_name() == "headless":
		print("Upgrade feedback visual capture skipped: active renderer is headless dummy")
		return
	await _capture_spin_viewport()
	await _capture_combat_viewport()


func _capture_spin_viewport() -> void:
	var viewport := _make_proof_viewport()
	var world := viewport.get_child(0) as Node2D
	var normal := PLAYER_SCENE.instantiate() as Player
	var undertow := PLAYER_SCENE.instantiate() as Player
	world.add_child(normal)
	world.add_child(undertow)
	normal.global_position = Vector2(480.0, 570.0)
	undertow.global_position = Vector2(1440.0, 570.0)
	normal.set_physics_process(false)
	undertow.set_physics_process(false)
	normal._camera.enabled = false
	undertow._camera.enabled = false
	normal.is_spinning = true
	normal._update_animation()
	GameState.unlock_ability(&"undertow_dash")
	undertow._start_spin()
	undertow._update_animation()
	await _proof_frames(2)
	var image := viewport.get_texture().get_image()
	_check(image != null, "actual Godot viewport returns spin proof image")
	if image != null:
		_check(
			image.save_png("/tmp/hollowtide-undertow-vs-normal-spin.png") == OK,
			"undertow versus normal spin proof saved"
		)
		print("Undertow proof: /tmp/hollowtide-undertow-vs-normal-spin.png")
	viewport.queue_free()
	await get_tree().process_frame


func _capture_combat_viewport() -> void:
	var viewport := _make_proof_viewport()
	var world := viewport.get_child(0) as Node2D
	var bomb := BOMB_SCENE.instantiate() as Bomb
	world.add_child(bomb)
	bomb.global_position = Vector2(480.0, 540.0)
	bomb._explode()
	var crawler := CRAWLER_SCENE.instantiate() as Crawler
	world.add_child(crawler)
	crawler.global_position = Vector2(1440.0, 540.0)
	crawler.set_physics_process(false)
	crawler.take_damage(105, &"missile")
	await _proof_frames(1)
	for age in [0, 8, 16]:
		var image := viewport.get_texture().get_image()
		_check(image != null, "actual Godot viewport returns combat proof image")
		if image != null:
			var path := "/tmp/hollowtide-combat-feedback-%02d.png" % age
			_check(image.save_png(path) == OK, "combat proof age %d saved" % age)
			print("Combat proof: ", path)
		await _proof_frames(8)
	viewport.queue_free()
	await get_tree().process_frame


func _make_proof_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array(
		[Vector2.ZERO, Vector2(1920.0, 0.0), Vector2(1920.0, 1080.0), Vector2(0.0, 1080.0)]
	)
	background.color = Color("08101c")
	background.z_index = -10
	world.add_child(background)
	return viewport


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_world.add_child(_player)
	_player.global_position = Vector2(320.0, FLOOR_Y)
	await _physics_frames(3)


func _add_floor() -> void:
	var floor := StaticBody2D.new()
	floor.position = Vector2(960.0, FLOOR_Y + 32.0)
	floor.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1920.0, 64.0)
	collision.shape = shape
	floor.add_child(collision)
	_world.add_child(floor)


func _settle_player() -> void:
	await _physics_frames(3)


func _has_transient_feedback() -> bool:
	for transient in get_tree().get_nodes_in_group(&"transient"):
		if transient is CombatFeedback or transient is ArsenalFx:
			return true
	return false


func _playing_sfx_count(name: StringName) -> int:
	var stream := load(Audio.SFX_PATHS[name]) as AudioStream
	var count := 0
	for player in Audio.get_children():
		if player is AudioStreamPlayer and player.playing and player.stream == stream:
			count += 1
	return count


func _proof_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _release_movement() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _release_inputs() -> void:
	_release_movement()
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("jump")
	Input.action_release("fire_beam")
	Input.action_release("fire_missile")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
