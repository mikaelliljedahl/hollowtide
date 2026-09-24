extends Node

## Assist options (D22): damage scaling, game speed under hit-stop, and skipping ambushes.
## godot --headless --path . res://tools/check_assist.tscn -- --test-mode

const Assist = preload("res://scripts/progression/assist.gd")
const Testbed = preload("res://tools/worldfx_testbed.gd")
const TILE := 64.0

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_defaults()
	_damage_scaling()
	_game_speed()
	await _player_damage()
	await _skip_ambush()
	Assist.forced.clear()
	Engine.time_scale = 1.0
	for failure in _failures:
		print("FAIL ", failure)
	print("assist: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _defaults() -> void:
	Assist.forced.clear()
	_check(Assist.game_speed() == 1.0, "test runs use full game speed")
	_check(Assist.damage_taken() == 1.0, "test runs take full damage")
	_check(not Assist.skip_ambushes(), "test runs keep ambushes")


func _damage_scaling() -> void:
	Assist.forced = {Assist.DAMAGE_TAKEN: 0.5}
	_check(Assist.scale_damage(10) == 5, "half damage halves a hit")
	_check(Assist.scale_damage(1) == 1, "a scaled hit never rounds down to nothing")
	Assist.forced = {Assist.DAMAGE_TAKEN: 0.0}
	_check(Assist.scale_damage(40) == 0, "zero damage setting blocks every hit")
	Assist.forced = {Assist.DAMAGE_TAKEN: 3.0}
	_check(Assist.scale_damage(10) == 10, "damage setting is capped at full damage")


func _game_speed() -> void:
	Assist.forced = {Assist.GAME_SPEED: 0.1}
	_check(Assist.game_speed() == Assist.MIN_GAME_SPEED, "game speed never drops below the floor")
	Assist.forced = {Assist.GAME_SPEED: 0.7}
	Assist.apply_game_speed()
	_check(is_equal_approx(Engine.time_scale, 0.7), "game speed sets the engine base speed")
	Engine.time_scale = 0.2
	GameJuice._hit_stop_until_msec = 0
	GameJuice._release_hit_stop()
	_check(is_equal_approx(Engine.time_scale, 0.7), "hit-stop release returns to the assist speed")
	Assist.forced.clear()
	Assist.apply_game_speed()


func _room() -> Array:
	GameState.reset_progress()
	var grid: Array = []
	for row in 12:
		grid.append("#" + ".".repeat(22) + "#" if row in range(1, 10) else "#".repeat(24))
	var room := Testbed.build_room(self, &"fringe", grid)
	var player := Testbed.spawn_player(self, room, Vector2i(4, 9))
	await _frames(4)
	return [room, player]


func _clear_room() -> void:
	for child in get_children():
		child.queue_free()
	for node in get_tree().get_nodes_in_group(&"transient"):
		node.queue_free()
	await _frames(2)


func _player_damage() -> void:
	var made := await _room()
	var player: Player = made[1]
	Assist.forced = {Assist.DAMAGE_TAKEN: 0.5}
	var before := GameState.health
	player.take_damage(20, player.global_position + Vector2(64, 0))
	_check(GameState.health == before - 10, "player hits are scaled by damage taken")
	await _clear_room()
	made = await _room()
	player = made[1]
	Assist.forced = {Assist.DAMAGE_TAKEN: 0.0}
	before = GameState.health
	player.take_damage(20, player.global_position + Vector2(64, 0))
	_check(GameState.health == before, "zero damage leaves health untouched")
	Assist.forced.clear()
	await _clear_room()


func _arena(room: CampaignRoom) -> AmbushArena:
	var arena := AmbushArena.new()
	arena.arena_size = Vector2(22 * TILE, 9 * TILE)
	arena.wave = PackedStringArray(["hopper"])
	arena.spawn_offsets = PackedVector2Array([Vector2(-448, 192)])
	arena.flag_id = "assist_test"
	arena.position = Vector2(12 * TILE, 5.5 * TILE)
	Testbed.entities(room).add_child(arena)
	return arena


func _skip_ambush() -> void:
	var made := await _room()
	GameState.unlock_ability(&"beam")
	var arena := _arena(made[0])
	Assist.forced = {Assist.SKIP_AMBUSHES: true}
	await _frames(20)
	_check(arena.state == AmbushArena.State.ARMED, "skip ambushes keeps the arena open")
	_check(arena.enemies.is_empty(), "skip ambushes spawns nothing")
	Assist.forced.clear()
	await _frames(20)
	_check(arena.state != AmbushArena.State.ARMED, "without skip the same arena seals")
	await _clear_room()
