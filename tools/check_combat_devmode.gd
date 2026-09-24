extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const BEAM_SCENE: PackedScene = preload("res://scenes/combat/beam_shot.tscn")
const BOMB_SCENE: PackedScene = preload("res://scenes/combat/bomb.tscn")
const GRATE_SCENE: PackedScene = preload("res://scenes/combat/projectile_grate.tscn")
const WAVE_GRATE_SCRIPT = preload("res://scripts/world/wave_grate.gd")
const HitResult = preload("res://scripts/combat/hit_result.gd")

var failures: Array[String] = []


class BombProbe:
	extends CharacterBody2D
	var impulse_received := false

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 12.0
		shape.shape = circle
		add_child(shape)

	func apply_bomb_impulse(_origin: Vector2, _radius: float) -> void:
		impulse_received = true
		velocity.y = -Catalog.BOMB_LIFT_SPEED


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_weapon_runtime()
	await _test_factory_and_reactions()
	await _test_boss_motion()
	await _test_bomb_and_cleanup()
	await _test_swept_projectile()
	if failures.is_empty():
		print("PASS: combat devmode physics, reactions, bomb, cleanup, and sweep")
	else:
		for failure in failures:
			push_error(failure)
		await TestShutdown.finish(get_tree(), 1)
		return
	await TestShutdown.finish(get_tree())


func _test_weapon_runtime() -> void:
	var game_state := get_node("/root/GameState")
	var weapons := get_node("/root/Weapons")
	game_state.reset_progress()
	game_state.acquire_beam()
	weapons.reset_runtime()
	weapons.fire(&"beam", Vector2.ZERO, Vector2.RIGHT)
	_check(get_tree().get_nodes_in_group(&"transient").size() == 1, "beam spawns through Weapons")
	game_state.acquire_slipstream()
	game_state.unlock_ability(&"bombs")
	for _index in Catalog.MAX_ACTIVE_BOMBS:
		await _physics_frames(12)
		weapons.fire(&"bomb", Vector2.ZERO, Vector2.UP)
	_check(
		get_tree().get_nodes_in_group(&"bombs").size() <= Catalog.MAX_ACTIVE_BOMBS,
		"bomb cap is three"
	)
	game_state.acquire_missiles(1)
	var ammo: int = game_state.missile_count
	await _physics_frames(12)
	weapons.fire(&"missile", Vector2.ZERO, Vector2.RIGHT)
	_check(game_state.missile_count == ammo - 1, "Weapons spends one missile")
	weapons.fire(&"missile", Vector2.ZERO, Vector2.RIGHT)
	_check(game_state.missile_count >= 0, "missile ammo never goes negative")
	weapons.reset_runtime()
	await get_tree().physics_frame
	game_state.reset_progress()


func _test_factory_and_reactions() -> void:
	for runtime_id in Catalog.ENEMY_IDS:
		var enemy := EnemyFactory.create(runtime_id)
		_check(enemy != null, "factory creates %s" % runtime_id)
		if enemy == null:
			continue
		get_tree().root.add_child(enemy)
		enemy.global_position = Vector2(300, 300)
	await get_tree().physics_frame
	for runtime_id in Catalog.ENEMY_IDS:
		var enemy := _find_enemy(runtime_id)
		_check(enemy != null, "spawned %s" % runtime_id)
		if enemy == null:
			continue
		var hp := int(enemy.get("health"))
		if runtime_id == &"shooting_gargoyle":
			var folded = enemy.call(&"receive_hit", 10, &"beam")
			_check(folded == HitResult.Reaction.BLOCKED, "folded gargoyle blocks beam")
			_check(int(enemy.get("health")) == hp, "folded gargoyle preserves HP")
			enemy.set("_special_state", &"open")
		elif runtime_id == &"lava_monster":
			var submerged = enemy.call(&"receive_hit", 10, &"beam")
			_check(submerged == HitResult.Reaction.PASS, "submerged lava monster is a true miss")
			enemy.set("_special_state", &"surface")
			enemy.call("_set_lava_surface_active", true)
			var molten_undertow = enemy.call(&"receive_hit", 24, &"undertow")
			_check(
				molten_undertow == HitResult.Reaction.BLOCKED, "molten lava monster blocks Undertow"
			)
		if runtime_id == &"crawler":
			enemy.call("take_damage", 10, &"beam")
			_check(int(enemy.get("health")) == hp, "crawler rejects beam")
		elif runtime_id == &"armored_guard":
			enemy.call("take_damage", 10, &"beam")
			_check(int(enemy.get("health")) == hp, "armored guard rejects beam")
		else:
			var damage_result = enemy.call(&"receive_hit", 10, &"beam")
			_check(
				damage_result == HitResult.Reaction.DAMAGE, "%s reports beam damage" % runtime_id
			)
			_check(int(enemy.get("health")) < hp, "%s accepts beam" % runtime_id)
		if enemy.get("freeze_capable") == true:
			hp = int(enemy.get("health"))
			var freeze_result = enemy.call(&"receive_hit", 10, &"ice")
			_check(
				freeze_result == HitResult.Reaction.FREEZE,
				"%s atomically reports freeze" % runtime_id,
			)
			_check(enemy.get("is_frozen") == true, "%s freezes" % runtime_id)
			_check(int(enemy.get("health")) == hp, "%s freeze has no damage" % runtime_id)
	var freeze_sample := _find_enemy(&"hopper")
	var freeze_hp := int(freeze_sample.get("health")) if freeze_sample != null else -1
	await _physics_frames(250)
	if freeze_sample != null:
		_check(freeze_sample.get("is_frozen") == false, "frozen enemy thaws")
		_check(int(freeze_sample.get("health")) == freeze_hp, "thaw preserves HP")
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy != null:
			enemy.queue_free()
	var crawler := EnemyFactory.create(&"crawler")
	get_tree().root.add_child(crawler)
	await get_tree().physics_frame
	_check(int(crawler.get("health")) == 105, "crawler catalog health")
	var blocked = crawler.call(&"receive_hit", 35, &"beam")
	_check(blocked == HitResult.Reaction.BLOCKED, "crawler atomically reports blocked beam")
	_check(int(crawler.get("health")) == 105, "crawler rejects every beam")
	var frozen = crawler.call(&"receive_hit", 35, &"ice")
	_check(frozen == HitResult.Reaction.BLOCKED, "crawler atomically rejects Ice")
	_check(int(crawler.get("health")) == 105, "crawler rejects ice")
	var damaged = crawler.call(&"receive_hit", 35, &"missile")
	_check(damaged == HitResult.Reaction.DAMAGE, "crawler atomically reports missile damage")
	_check(int(crawler.get("health")) == 70, "crawler accepts missile")
	crawler.queue_free()
	await _test_expansion_enemy_states()
	await _test_bosses()


func _test_expansion_enemy_states() -> void:
	var grasshopper := EnemyFactory.create(&"grasshopper")
	get_tree().root.add_child(grasshopper)
	grasshopper.set("_pending_attack_direction", Vector2(620.0, -720.0))
	grasshopper.set("_telegraph_action", &"grasshopper_leap")
	grasshopper.call("_perform_telegraph_action")
	_check(grasshopper.get("_special_state") == &"airborne", "grasshopper enters locked leap")
	_check(grasshopper.get("velocity") == Vector2(620.0, -720.0), "grasshopper uses catalog leap")
	grasshopper.queue_free()

	var gargoyle := EnemyFactory.create(&"shooting_gargoyle")
	get_tree().root.add_child(gargoyle)
	gargoyle.set("_telegraph_action", &"gargoyle_wake")
	gargoyle.call("_perform_telegraph_action")
	_check(gargoyle.get("_special_state") == &"open", "gargoyle wake tell opens armor")
	var projectile_count := get_tree().get_nodes_in_group(&"transient").size()
	gargoyle.set("_pending_attack_direction", Vector2.LEFT)
	gargoyle.set("_telegraph_action", &"gargoyle_fire")
	gargoyle.call("_perform_telegraph_action")
	_check(gargoyle.get("_special_state") == &"recovering", "gargoyle enters recovery after shot")
	_check(
		get_tree().get_nodes_in_group(&"transient").size() > projectile_count,
		"gargoyle fires a real enemy projectile",
	)
	gargoyle.queue_free()

	var lava := EnemyFactory.create(&"lava_monster")
	get_tree().root.add_child(lava)
	await get_tree().physics_frame
	var body := lava.get_node_or_null("CollisionShape2D") as CollisionShape2D
	_check(body != null and body.disabled, "submerged lava monster has no target body")
	lava.set("_special_state", &"surface")
	lava.call("_set_lava_surface_active", true)
	await get_tree().physics_frame
	_check(body != null and not body.disabled, "surfaced lava monster enables target body")
	lava.queue_free()
	Weapons.reset_runtime()
	await get_tree().physics_frame


func _test_bosses() -> void:
	var stone := await _spawn_boss(&"stone_guardian")
	var stone_hp := int(stone.get("health"))
	stone.call("take_damage", 10, &"beam")
	_check(int(stone.get("health")) == stone_hp, "stone guardian phase 1 rejects beam")
	stone.call("take_damage", 35, &"missile")
	_check(int(stone.get("health")) < stone_hp, "stone guardian phase 1 accepts missile")
	stone.call("set_test_phase", 2)
	stone_hp = int(stone.get("health"))
	stone.call("take_damage", 35, &"missile")
	_check(int(stone.get("health")) == stone_hp, "stone mask closed rejects missile")
	await _physics_frames(65)
	stone.call("take_damage", 35, &"missile")
	_check(int(stone.get("health")) < stone_hp, "stone mask opening accepts missile")
	stone.queue_free()

	var furnace := await _spawn_boss(&"furnace_mother")
	var furnace_hp := int(furnace.get("health"))
	furnace.call("take_damage", 12, &"wave")
	_check(int(furnace.get("health")) < furnace_hp, "furnace phase 1 accepts wave")
	furnace.queue_free()

	var tidal := await _spawn_boss(&"tidal_heart")
	var tidal_hp := int(tidal.get("health"))
	tidal.call("take_damage", -1, &"ice")
	_check(not tidal.call("is_vulnerable_to", &"missile"), "negative ice damage is rejected")
	var triggered = tidal.call(&"receive_hit", 0, &"ice")
	_check(triggered == HitResult.Reaction.TRIGGERED, "tidal Ice opening reports trigger")
	_check(int(tidal.get("health")) == tidal_hp, "zero-damage ice opens without HP damage")
	tidal.call("take_damage", 35, &"missile")
	_check(int(tidal.get("health")) < tidal_hp, "tidal pulse opens missile window")
	var grate := WAVE_GRATE_SCRIPT.new()
	get_tree().root.add_child(grate)
	grate.call("set_relay", tidal)
	_check(grate.call("can_pass_projectile", &"ice"), "tidal phase 1 grate admits ice")
	_check(grate.call("can_pass_projectile", &"missile"), "tidal phase 1 grate admits missiles")
	tidal.call("set_test_phase", 2)
	_check(
		not tidal.call("is_vulnerable_to", &"missile"),
		"tidal phase 2 stays closed without wave relay"
	)
	_check(
		not grate.call("can_pass_projectile", &"missile"),
		"tidal phase 2 grate blocks missiles before a wave"
	)
	grate.call("allows_projectile", &"wave")
	_check(tidal.call("is_vulnerable_to", &"missile"), "tidal wave grate opens missile window")
	_check(
		grate.call("can_pass_projectile", &"missile"),
		"tidal phase 2 grate admits missiles during the wave window"
	)
	await _physics_frames(130)
	_check(
		not tidal.call("is_vulnerable_to", &"missile"),
		"tidal wave window expires after two seconds"
	)
	grate.queue_free()
	tidal.queue_free()
	await get_tree().physics_frame


func _test_boss_motion() -> void:
	var player_probe := Node2D.new()
	player_probe.add_to_group(&"player")
	player_probe.global_position = Vector2(900.0, 420.0)
	get_tree().root.add_child(player_probe)
	for runtime_id in [&"stone_guardian", &"furnace_mother", &"tidal_heart"]:
		var boss := EnemyFactory.create(runtime_id)
		boss.global_position = Vector2(500.0, 420.0)
		get_tree().root.add_child(boss)
		boss.call("configure_arena", Rect2(300.0, 180.0, 800.0, 720.0))
		var start := boss.global_position
		await _physics_frames(18)
		_check(
			boss.global_position.distance_to(start) > 8.0,
			"%s visibly moves while player is in its arena" % runtime_id,
		)
		var hurtbox := boss.get_node_or_null("Sprite2D/ProjectileHurtbox")
		_check(
			hurtbox != null and hurtbox.get_child_count() > 0,
			"%s authored silhouette receives projectiles" % runtime_id,
		)
		boss.queue_free()
		await get_tree().physics_frame
	player_probe.queue_free()
	await get_tree().physics_frame


func _test_bomb_and_cleanup() -> void:
	var probe := BombProbe.new()
	probe.add_to_group(&"player")
	get_tree().root.add_child(probe)
	probe.global_position = Vector2(20, 20)
	var bomb := BOMB_SCENE.instantiate()
	get_tree().root.add_child(bomb)
	bomb.global_position = Vector2.ZERO
	await _physics_frames(50)
	_check(probe.impulse_received, "bomb lifts player in radius")
	_check(
		is_equal_approx(probe.velocity.y, -Catalog.BOMB_LIFT_SPEED),
		"bomb impulse uses catalog speed"
	)
	probe.queue_free()
	get_node("/root/Weapons").reset_runtime()
	await get_tree().physics_frame
	_check(
		get_tree().get_nodes_in_group(&"transient").is_empty(),
		"runtime reset cleans transient nodes"
	)


func _test_swept_projectile() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var wall_box := RectangleShape2D.new()
	wall_box.size = Vector2(40.0, 40.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	get_tree().root.add_child(wall)
	await get_tree().physics_frame
	var blocked_shot := BEAM_SCENE.instantiate()
	get_tree().root.add_child(blocked_shot)
	blocked_shot.global_position = Vector2.ZERO
	blocked_shot.launch(Vector2.RIGHT)
	await get_tree().physics_frame
	_check(not is_instance_valid(blocked_shot), "origin-blocked projectile is consumed")
	wall.queue_free()
	var target := EnemyFactory.create(&"spitter")
	get_tree().root.add_child(target)
	target.global_position = Vector2(100, 0)
	await get_tree().physics_frame
	var shot := BEAM_SCENE.instantiate()
	get_tree().root.add_child(shot)
	shot.global_position = Vector2.ZERO
	shot.speed = 12000.0
	shot.launch(Vector2.RIGHT)
	var hp := int(target.get("health"))
	await get_tree().physics_frame
	_check(int(target.get("health")) < hp, "swept projectile hits fast target")
	if is_instance_valid(target):
		target.queue_free()
	if is_instance_valid(shot):
		shot.queue_free()


func _spawn_boss(runtime_id: StringName) -> Node2D:
	var boss := EnemyFactory.create(runtime_id)
	boss.global_position = Vector2(600, 300)
	get_tree().root.add_child(boss)
	await get_tree().physics_frame
	return boss


func _find_enemy(runtime_id: StringName) -> Node:
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy.get("enemy_id") == runtime_id:
			return enemy
	return null


func _physics_frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
