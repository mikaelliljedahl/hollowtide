extends Node

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/pickup.tscn")
const LOOT_SCRIPT = preload("res://scripts/pickups/combat_loot.gd")
const REWARDS = preload("res://scripts/enemies/defeat_rewards.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")

var _failures: Array[String] = []
var _level: Node2D
var _player: Node2D


class DropSource:
	extends Node2D
	var enemy_id: StringName = &"hopper"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(OS.get_cmdline_user_args().has("--dev-mode"), "test must run in isolated dev mode")
	_level = LEVEL_SCENE.instantiate() as Node2D
	get_tree().root.add_child(_level)
	await _physics_frames(3)
	_player = _level.get_node_or_null("PlayerSpawn/Player") as Node2D
	_expect(_player != null, "level exposes Player for collision route")
	if _player != null:
		await _test_real_pickup_route()
		await _test_loot_bounds_and_reset()
		await _test_safe_boss_approach()
	await _test_enemy_roster_and_telegraphs()
	_level.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("check_playability_repair: PASS")
		await TestShutdown.finish(get_tree(), 0)
		return
	for failure in _failures:
		push_error(failure)
	await TestShutdown.finish(get_tree(), 1)


func _test_real_pickup_route() -> void:
	GameState.reset_progress()
	await _collect_runtime_pickup("S1.ability.slipstream")
	await _collect_runtime_pickup("S1.ability.high_jump")
	await _collect_runtime_pickup("S1.capacity.energy_01")
	_expect(
		GameState.has_ability(&"high_jump"), "High Jump is physically available before test pockets"
	)
	_expect(
		GameState.max_health == 200 and GameState.health == 200,
		"body collision raises health 100 to 200"
	)
	await _collect_runtime_pickup("S2.ability.beam")
	await _collect_runtime_pickup("S2.capacity.missile_01")
	await _collect_runtime_pickup("S3.ability.bombs")
	await _collect_runtime_pickup("S4.ability.pressure_seal")
	_expect(
		GameState.has_ability(&"pressure_seal"),
		"Pressure Seal is physically available before boss route"
	)
	_expect(GameState.has_ability(&"bombs"), "Bombs precede S3 bomb test")
	_expect(GameState.max_missiles == 5, "missile tank establishes finite ammo capacity")

	var route_anchor := Vector2(_player.global_position.x, 1152.0)
	for id in [
		"S2.capacity.missile_02",
		"S3.capacity.missile_04",
		"S4.capacity.missile_06",
		"S5.capacity.missile_08",
		"S6.capacity.missile_10",
		"S7.capacity.missile_11",
	]:
		await _collect_runtime_pickup(id)
		_player.global_position = route_anchor
		_player.set("velocity", Vector2.ZERO)
		await _physics_frames(6)
		_expect(_player.is_on_floor(), "return to main route after " + id)

	GameState.refill_missiles(999)
	_expect(
		GameState.max_missiles == 35 and GameState.missile_count == 35,
		"ammo refill never raises capacity"
	)

	var duplicate := PICKUP_SCENE.instantiate() as Area2D
	duplicate.set("instance_id", "S4.duplicate.pressure_seal")
	duplicate.set("kind", &"pressure_seal")
	duplicate.global_position = _player.global_position
	_level.add_child(duplicate)
	await _physics_frames(3)
	_expect(
		GameState.collected_pickup_ids.has("S4.duplicate.pressure_seal"),
		"owned ability collision consumes duplicate ID rather than leaving fake pickup"
	)
	_expect(
		GameState.has_ability(&"pressure_seal"), "duplicate ability does not alter owned loadout"
	)

	GameState.spend_missile()
	GameState.spend_missile()
	var loot := LOOT_SCRIPT.new() as Area2D
	loot.configure(&"missile_refill", _player.global_position)
	_level.add_child(loot)
	await _physics_frames(16)
	_expect(
		GameState.missile_count <= GameState.max_missiles, "loot refill clamps at ammo capacity"
	)
	_expect(GameState.max_missiles == 35, "loot refill grants no missile capacity")

	for gate in _level.get_tree().get_nodes_in_group("dev_gate"):
		if gate is AbilityGate:
			var size: Vector2 = gate.get("gate_size")
			var center: Vector2 = gate.global_position
			_expect(center.y + size.y * 0.5 < 900.0, "ability gate stays in optional upper pocket")


func _collect_runtime_pickup(id: String) -> void:
	var pickup: Node2D
	for node in _level.get_tree().get_nodes_in_group("dev_pickup"):
		if node.get("instance_id") == id:
			pickup = node as Node2D
			break
	_expect(pickup != null, "runtime pickup exists: " + id)
	if pickup == null:
		return
	var target_position := pickup.global_position
	if pickup.get("kind") == &"missile_tank":
		var points := _find_standing_collection_points(pickup)
		_expect(points.size() == 2, "missile has standing collection point and retreat: " + id)
		if points.size() == 2:
			target_position = points[0]
	_player.global_position = target_position
	_player.set("velocity", Vector2.ZERO)
	await _physics_frames(4)
	_expect(GameState.collected_pickup_ids.has(id), "actual player collision collects: " + id)


func _find_standing_collection_points(pickup: Node2D) -> Array[Vector2]:
	var player := _player as Player
	var standing := player.get_node("StandingCollisionShape2D") as CollisionShape2D
	var points: Array[Vector2] = []
	for x_offset in range(-128, 129, 16):
		for y_offset in range(-128, 401, 8):
			var probe_feet := pickup.global_position + Vector2(x_offset, y_offset)
			var ray := PhysicsRayQueryParameters2D.create(
				probe_feet + Vector2(0.0, -4.0), probe_feet + Vector2(0.0, 12.0), 1
			)
			var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				continue
			var feet := hit["position"] as Vector2
			if (
				not _standing_clear(standing, feet)
				or not _pickup_overlaps_standing(pickup.global_position, feet)
			):
				continue
			for direction in [-1.0, 1.0]:
				var retreat := feet + Vector2(96.0 * direction, 0.0)
				if _has_support(retreat) and _standing_clear(standing, retreat):
					return [feet, retreat]
	return []


func _has_support(feet: Vector2) -> bool:
	var player := _player as Player
	var ray := PhysicsRayQueryParameters2D.create(
		feet + Vector2(0.0, -3.0), feet + Vector2(0.0, 8.0), 1
	)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and absf((hit["position"] as Vector2).y - feet.y) <= 1.0


func _standing_clear(standing: CollisionShape2D, feet: Vector2) -> bool:
	var player := _player as Player
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = standing.shape
	query.transform = Transform2D(0.0, feet + Vector2(0.0, -89.0))
	query.collision_mask = 1 | 8
	query.collide_with_bodies = true
	query.collide_with_areas = true
	return player.get_world_2d().direct_space_state.intersect_shape(query, 8).is_empty()


func _pickup_overlaps_standing(pickup_position: Vector2, feet: Vector2) -> bool:
	var local := pickup_position - (feet + Vector2(0.0, -88.0))
	var dx := maxf(absf(local.x) - 28.0, 0.0)
	var dy := maxf(absf(local.y) - 88.0, 0.0)
	return dx * dx + dy * dy <= 20.0 * 20.0


func _test_loot_bounds_and_reset() -> void:
	REWARDS.set_test_seed(0x1A2B3C)
	var sources: Array[DropSource] = []
	for index in 32:
		var source := DropSource.new()
		source.enemy_id = Catalog.ENEMY_IDS[index % Catalog.ENEMY_IDS.size()]
		source.global_position = Vector2(420 + index * 19, 720)
		_level.add_child(source)
		sources.append(source)
		REWARDS.spawn_for_defeat(source, false)
	await _physics_frames(2)
	var loot_count := 0
	for node in _level.get_tree().get_nodes_in_group("transient"):
		if node is CombatLoot:
			loot_count += 1
			_expect(
				node.kind in [&"energy_refill", &"missile_refill"], "loot only refills resources"
			)
	_expect(
		loot_count > 0 and loot_count < sources.size(),
		"weighted loot is occasional, not guaranteed"
	)
	_level.call("_clear_transients")
	await _physics_frames(1)
	_expect(
		_level.get_tree().get_nodes_in_group("transient").is_empty(), "reset removes transient loot"
	)
	for source in sources:
		source.queue_free()


func _test_safe_boss_approach() -> void:
	GameState.reset_health()
	var boss: Node2D
	for node in _level.get_tree().get_nodes_in_group("dev_boss"):
		boss = node as Node2D
		break
	_expect(boss != null, "S8 starts with one boss")
	if boss == null:
		return
	var bounds: Rect2 = boss.get("arena_bounds")
	var checkpoint := bounds.position + Vector2(-156, 608)
	_expect(not bounds.has_point(checkpoint), "S8 checkpoint approach is outside live boss bounds")
	_player.global_position = checkpoint
	await _physics_frames(50)
	_expect(GameState.health == GameState.max_health, "boss does not attack across safe approach")
	_player.global_position = bounds.position + Vector2(30, bounds.size.y - 52)
	await _physics_frames(16)
	_expect(
		GameState.health == GameState.max_health,
		"boss telegraph gives full-health player reaction time"
	)


func _test_enemy_roster_and_telegraphs() -> void:
	_expect(Catalog.ENEMY_IDS.size() == 13, "catalog contains all thirteen ordinary enemies")
	var test_bounds := Rect2(Vector2(5600, 120), Vector2(900, 760))
	_player.global_position = Vector2(6300, 700)
	var turret := EnemyFactory.create(&"shard_turret")
	_expect(
		turret != null and turret.get("runtime_id") == &"shard_turret",
		"factory creates shard turret"
	)
	if turret != null:
		turret.global_position = Vector2(5900, 700)
		_level.add_child(turret)
		turret.call("configure_arena", test_bounds)
		await _physics_frames(2)
		_expect(
			float(turret.get("_telegraph_remaining")) > 0.0, "shard turret telegraphs before burst"
		)
		turret.queue_free()

	var burrower := EnemyFactory.create(&"burrower")
	_expect(
		burrower != null and burrower.get("runtime_id") == &"burrower", "factory creates burrower"
	)
	if burrower != null:
		burrower.global_position = Vector2(6000, 700)
		_level.add_child(burrower)
		burrower.call("configure_arena", test_bounds)
		await _physics_frames(2)
		_expect(
			not burrower.call("is_vulnerable_to", &"beam"),
			"burrower warning mound has no damage window"
		)
		await _physics_frames(96)
		_expect(
			burrower.call("is_vulnerable_to", &"beam"), "burrower exposes a bounded damage window"
		)
		burrower.queue_free()


func _physics_frames(count: int) -> void:
	for _frame in count:
		await get_tree().physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
