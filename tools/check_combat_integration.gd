extends Node

const BEAM_SCENE: PackedScene = preload("res://scenes/combat/beam_shot.tscn")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GRATE_SCRIPT = preload("res://scripts/world/wave_grate.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _setup_loadout()
	await _test_actual_ice_and_origin_hits()
	await _test_enemy_projectile_player_hit()
	await _test_wave_grate_wall_segment()
	await _test_boss_fights()
	if failures.is_empty():
		print("PASS: combat integration weapons, gates, physics, and boss phases")
	else:
		for failure in failures:
			push_error(failure)
		await TestShutdown.finish(get_tree(), 1)
		return
	await TestShutdown.finish(get_tree())


func _setup_loadout() -> void:
	GameState.reset_progress()
	GameState.acquire_beam()
	GameState.unlock_ability(&"ice_beam")
	GameState.unlock_ability(&"wave_beam")
	GameState.unlock_ability(&"slipstream")
	GameState.unlock_ability(&"bombs")
	GameState.acquire_missiles(1)
	for index in 12:
		GameState.collect_pickup("combat.integration.missile.%02d" % index, &"missile_tank")
	GameState.refill()
	Weapons.reset_runtime()
	await get_tree().physics_frame


func _test_actual_ice_and_origin_hits() -> void:
	GameState.set_active_beam(&"ice")
	var frozen := EnemyFactory.create(&"hopper")
	get_tree().root.add_child(frozen)
	frozen.global_position = Vector2(420, 200)
	await get_tree().physics_frame
	frozen.set_physics_process(false)
	var frozen_hp := int(frozen.get("health"))
	Weapons.fire(&"beam", Vector2(0, 200), Vector2.RIGHT)
	await _physics_frames(30)
	_check(frozen.get("is_frozen") == true, "actual ice beam freezes target")
	_check(int(frozen.get("health")) == frozen_hp, "actual ice beam preserves HP")
	GameState.set_active_beam(&"base")
	Weapons.reset_runtime()
	Weapons.fire(&"missile", Vector2(0, 200), Vector2.RIGHT)
	await _physics_frames(24)
	_check(int(frozen.get("health")) < frozen_hp, "missile damages target after actual freeze")

	var bomb_target := EnemyFactory.create(&"armored_guard")
	get_tree().root.add_child(bomb_target)
	bomb_target.global_position = Vector2(80, 200)
	await get_tree().physics_frame
	bomb_target.set_physics_process(false)
	GameState.set_active_beam(&"ice")
	Weapons.reset_runtime()
	Weapons.fire(&"beam", Vector2(0, 200), Vector2.RIGHT)
	await _physics_frames(20)
	var bomb_hp := int(bomb_target.get("health"))
	_check(bomb_target.get("is_frozen") == true, "actual ice freezes bomb target")
	GameState.set_active_beam(&"base")
	Weapons.reset_runtime()
	Weapons.fire(&"bomb", bomb_target.global_position, Vector2.UP)
	await _physics_frames(50)
	_check(int(bomb_target.get("health")) < bomb_hp, "bomb damages actual frozen target")

	var invalid_hp := int(bomb_target.get("health"))
	bomb_target.call("take_damage", -1, &"missile")
	_check(int(bomb_target.get("health")) == invalid_hp, "negative damage is rejected")
	if is_instance_valid(frozen):
		frozen.queue_free()
	if is_instance_valid(bomb_target):
		bomb_target.queue_free()

	var ice_immune := EnemyFactory.create(&"crawler")
	get_tree().root.add_child(ice_immune)
	ice_immune.global_position = Vector2(420, 200)
	await get_tree().physics_frame
	ice_immune.set_physics_process(false)
	var immune_hp := int(ice_immune.get("health"))
	GameState.set_active_beam(&"ice")
	Weapons.reset_runtime()
	Weapons.fire(&"beam", Vector2(0, 200), Vector2.RIGHT)
	await _physics_frames(20)
	_check(int(ice_immune.get("health")) == immune_hp, "actual Ice leaves crawler HP unchanged")
	_check(not ice_immune.get("is_frozen"), "actual Ice does not freeze crawler")
	ice_immune.queue_free()

	var origin_target := EnemyFactory.create(&"spitter")
	get_tree().root.add_child(origin_target)
	origin_target.global_position = Vector2.ZERO
	await get_tree().physics_frame
	var origin_hp := int(origin_target.get("health"))
	GameState.set_active_beam(&"base")
	Weapons.reset_runtime()
	Weapons.fire(&"beam", Vector2.ZERO, Vector2.RIGHT)
	await get_tree().physics_frame
	_check(int(origin_target.get("health")) < origin_hp, "damageable target at muzzle receives hit")
	origin_target.queue_free()

	var wall := _make_wall(Vector2.ZERO, Vector2(48, 48))
	await get_tree().physics_frame
	var ammo := GameState.missile_count
	Weapons.reset_runtime()
	Weapons.fire(&"missile", Vector2.ZERO, Vector2.RIGHT)
	_check(GameState.missile_count == ammo, "blocked missile muzzle keeps ammo atomic")
	wall.queue_free()
	await get_tree().physics_frame
	Weapons.fire(&"missile", Vector2.ZERO, Vector2.RIGHT)
	_check(GameState.missile_count == ammo - 1, "blocked missile does not consume cooldown")

	var origin_grate := GRATE_SCRIPT.new()
	get_tree().root.add_child(origin_grate)
	origin_grate.global_position = Vector2.ZERO
	origin_grate.grate_size = Vector2(32, 64)
	GameState.set_active_beam(&"wave")
	Weapons.reset_runtime()
	Weapons.fire(&"beam", Vector2.ZERO, Vector2.RIGHT)
	await get_tree().physics_frame
	_check(
		get_tree().get_nodes_in_group(&"transient").size() > 0, "origin grate accepts wave spawn"
	)
	origin_grate.queue_free()


func _test_enemy_projectile_player_hit() -> void:
	GameState.reset_health()
	var player := PLAYER_SCENE.instantiate()
	get_tree().root.add_child(player)
	player.global_position = Vector2(100, 0)
	await get_tree().physics_frame
	player.set_physics_process(false)
	var before := GameState.health
	var wall := _make_wall(Vector2(50, 0), Vector2(20, 80))
	var blocked := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	get_tree().root.add_child(blocked)
	blocked.global_position = Vector2.ZERO
	blocked.launch(Vector2.RIGHT, 7)
	await _physics_frames(30)
	_check(GameState.health == before, "enemy projectile stops at terrain")
	_check(not is_instance_valid(blocked), "enemy projectile terrain hit cleans up")
	wall.queue_free()

	var projectile := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	get_tree().root.add_child(projectile)
	projectile.global_position = Vector2.ZERO
	projectile.launch(Vector2.RIGHT, 7)
	await _physics_frames(30)
	_check(GameState.health < before, "enemy projectile damages actual Player collision")
	if is_instance_valid(projectile):
		projectile.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().physics_frame


func _test_wave_grate_wall_segment() -> void:
	var target := EnemyFactory.create(&"spitter")
	get_tree().root.add_child(target)
	target.global_position = Vector2(700, 0)
	var grate := GRATE_SCRIPT.new()
	get_tree().root.add_child(grate)
	grate.global_position = Vector2(300, 0)
	grate.grate_size = Vector2(32, 128)
	var wall := _make_wall(Vector2(500, 0), Vector2(24, 128))
	await _physics_frames(2)
	grate.set_relay(target)
	GameState.set_active_beam(&"wave")
	Weapons.reset_runtime()
	Weapons.fire(&"beam", Vector2.ZERO, Vector2.RIGHT)
	await _physics_frames(30)
	_check(
		int(target.get("health")) == int(target.get("max_health")),
		"wave stops at thin wall after grate"
	)
	wall.queue_free()
	grate.queue_free()
	target.queue_free()
	await get_tree().physics_frame


func _test_boss_fights() -> void:
	for runtime_id in [&"stone_guardian", &"furnace_mother"]:
		await _setup_boss_loadout()
		var boss := EnemyFactory.create(runtime_id)
		get_tree().root.add_child(boss)
		boss.global_position = Vector2(700, 300)
		await get_tree().physics_frame
		await _kill_with_missiles(boss)
		_check(
			int(boss.get("health")) == 0,
			"%s dies through both phases with real missiles" % runtime_id
		)
		boss.queue_free()
		await get_tree().physics_frame

	await _setup_boss_loadout()
	var tidal := EnemyFactory.create(&"tidal_heart")
	get_tree().root.add_child(tidal)
	tidal.global_position = Vector2(700, 300)
	await get_tree().physics_frame
	GameState.set_active_beam(&"ice")
	Weapons.reset_runtime()
	Weapons.fire(&"beam", Vector2(100, 300), Vector2.RIGHT)
	await _physics_frames(20)
	_check(tidal.call("is_vulnerable_to", &"missile"), "actual ice opens tidal phase one")
	var grate := GRATE_SCRIPT.new()
	get_tree().root.add_child(grate)
	grate.global_position = Vector2(400, 500)
	grate.set_relay(tidal)
	await _kill_tidal(tidal, grate)
	_check(int(tidal.get("health")) == 0, "tidal heart dies through both phases with real weapons")
	grate.queue_free()
	tidal.queue_free()
	await get_tree().physics_frame


func _setup_boss_loadout() -> void:
	GameState.reset_progress()
	GameState.acquire_beam()
	GameState.unlock_ability(&"ice_beam")
	GameState.unlock_ability(&"wave_beam")
	GameState.acquire_missiles(1)
	GameState.refill()
	Weapons.reset_runtime()
	await get_tree().physics_frame


func _kill_with_missiles(boss: Node) -> void:
	for _index in 80:
		if int(boss.get("health")) <= 0:
			return
		if GameState.missile_count == 0:
			GameState.refill_missiles(5)
		GameState.set_active_beam(&"base")
		Weapons.fire(&"missile", Vector2(0, 300), Vector2.RIGHT)
		await _physics_frames(24)


func _kill_tidal(tidal: Node, grate: Node) -> void:
	for _index in 100:
		if int(tidal.get("health")) <= 0:
			return
		if not tidal.call("is_vulnerable_to", &"missile"):
			if int(tidal.get("phase")) == 1:
				GameState.set_active_beam(&"ice")
				Weapons.reset_runtime()
				Weapons.fire(&"beam", Vector2(100, 300), Vector2.RIGHT)
				await _physics_frames(20)
			else:
				grate.global_position = Vector2(400, 300)
				GameState.set_active_beam(&"wave")
				Weapons.reset_runtime()
				Weapons.fire(&"beam", Vector2(0, 300), Vector2.RIGHT)
				await _physics_frames(14)
				_check(
					tidal.call("is_vulnerable_to", &"missile"),
					"explicit wave grate opens tidal phase two"
				)
		if GameState.missile_count == 0:
			GameState.refill_missiles(5)
		GameState.set_active_beam(&"base")
		var missile_origin := Vector2(500, 300) if int(tidal.get("phase")) == 2 else Vector2(0, 300)
		Weapons.fire(&"missile", missile_origin, Vector2.RIGHT)
		await _physics_frames(24)


func _make_wall(position: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	wall.global_position = position
	return wall


func _physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
