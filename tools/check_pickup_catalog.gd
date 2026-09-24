extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/pickup.tscn")
const LOOT_SCRIPT = preload("res://scripts/pickups/combat_loot.gd")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/level_01.tscn")
const PANEL_SCRIPT = preload("res://scripts/ui/dev_panel.gd")

var _failures: Array[String] = []
var _player: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_catalog_and_generic_visuals()
	await _test_generic_collection_and_duplicates()
	_test_capacity_caps()
	await _test_combat_loot()
	await _test_panel_catalog()
	await _test_dev_station_persistence()
	if _failures.is_empty():
		print("check_pickup_catalog: PASS")
	else:
		for failure in _failures:
			push_error("check_pickup_catalog: " + failure)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _test_catalog_and_generic_visuals() -> void:
	_expect(Catalog.PICKUP_KINDS.size() == 14, "base catalog has fourteen pickup kinds")
	_expect(
		not Catalog.PICKUP_KINDS.any(func(kind): return Catalog.FLUX_PICKUP_KINDS.has(kind)),
		"base and Flux pickup kind partitions are disjoint"
	)
	for kind in Catalog.PICKUP_KINDS + Catalog.FLUX_PICKUP_KINDS:
		var path := Catalog.pickup_icon_path(kind)
		_expect(
			not path.is_empty() and ResourceLoader.exists(path), "%s has generated icon path" % kind
		)
		var texture := Catalog.pickup_texture(kind)
		_expect(texture != null, "%s icon texture loads" % kind)
		_expect(Catalog.pickup_sound_for_kind(kind) != &"", "%s has pickup sound category" % kind)

	var scene_pickup := PICKUP_SCENE.instantiate() as ProgressionPickup
	_expect(scene_pickup != null, "generic pickup instantiates")
	if scene_pickup == null:
		return
	scene_pickup.kind = &"high_jump"
	scene_pickup.instance_id = "test.visual.high_jump"
	add_child(scene_pickup)
	await get_tree().process_frame
	var icon := scene_pickup.get_node_or_null("Icon") as Sprite2D
	_expect(
		icon != null and icon.texture == Catalog.pickup_texture(&"high_jump"),
		"generic uses catalog icon"
	)
	_expect(icon != null and icon.hframes == 1 and icon.vframes == 1, "generic icon is not sliced")
	_expect(
		icon != null and icon.scale.x > 0.5 and icon.scale.x < 1.0,
		"generic icon has readable scale"
	)
	scene_pickup.queue_free()
	await get_tree().process_frame
	for kind in Catalog.PICKUP_KINDS:
		var mapped_pickup := PICKUP_SCENE.instantiate() as ProgressionPickup
		mapped_pickup.kind = kind
		mapped_pickup.instance_id = "test.visual." + String(kind)
		add_child(mapped_pickup)
		await get_tree().process_frame
		var mapped_icon := mapped_pickup.get_node_or_null("Icon") as Sprite2D
		_expect(
			mapped_icon != null and mapped_icon.texture != null, "%s runtime icon exists" % kind
		)
		_expect(
			mapped_icon != null and mapped_icon.hframes == 1 and mapped_icon.vframes == 1,
			"%s runtime frame configuration is static" % kind
		)
		mapped_pickup.queue_free()
		await get_tree().process_frame


func _test_generic_collection_and_duplicates() -> void:
	GameState.reset_progress()
	_player = Node2D.new()
	_player.add_to_group("player")
	add_child(_player)
	var pickup := PICKUP_SCENE.instantiate() as ProgressionPickup
	pickup.instance_id = "test.collection.slip"
	pickup.kind = &"slipstream"
	add_child(pickup)
	await get_tree().process_frame
	pickup.call("_on_body_entered", _player)
	await get_tree().process_frame
	_expect(GameState.has_ability(&"slipstream"), "body collection unlocks Slipstream")
	_expect(
		GameState.collected_pickup_ids.has("test.collection.slip"), "body collection records ID"
	)

	var duplicate_snapshot := GameState.snapshot()
	_expect(not GameState.collect_pickup("test.collection.slip", &"slipstream"), "same ID rejects")
	_expect(GameState.snapshot() == duplicate_snapshot, "same ID rejection is atomic")

	var duplicate := PICKUP_SCENE.instantiate() as ProgressionPickup
	duplicate.instance_id = "test.collection.slip.duplicate"
	duplicate.kind = &"slipstream"
	add_child(duplicate)
	await get_tree().process_frame
	duplicate.call("_on_body_entered", _player)
	await get_tree().process_frame
	_expect(
		GameState.collected_pickup_ids.has("test.collection.slip.duplicate"),
		"owned duplicate instance is consumed"
	)
	_expect(GameState.has_ability(&"slipstream"), "owned duplicate does not grant again")


func _test_capacity_caps() -> void:
	GameState.reset_progress()
	for index in Catalog.ENERGY_CONTENT_IDS.size():
		_expect(
			GameState.collect_pickup(Catalog.ENERGY_CONTENT_IDS[index], &"energy_tank"),
			"energy content instance %d collects" % (index + 1)
		)
	for index in Catalog.MISSILE_CONTENT_IDS.size():
		_expect(
			GameState.collect_pickup(Catalog.MISSILE_CONTENT_IDS[index], &"missile_tank"),
			"missile content instance %d collects" % (index + 1)
		)
	_expect(GameState.max_health == 700 and GameState.health == 700, "six energy tanks cap at 700")
	_expect(
		GameState.max_missiles == 60 and GameState.missile_count == 60,
		"twelve missile tanks cap at 60"
	)
	_expect(
		not GameState.collect_pickup("test.energy.overflow", &"energy_tank"),
		"energy tank overflow rejects"
	)
	_expect(
		not GameState.collect_pickup("test.missile.overflow", &"missile_tank"),
		"missile tank overflow rejects"
	)


func _test_combat_loot() -> void:
	GameState.reset_progress()
	GameState.apply_damage(50)
	var energy_loot := LOOT_SCRIPT.new() as CombatLoot
	energy_loot.configure(&"energy_refill", Vector2.ZERO)
	add_child(energy_loot)
	await get_tree().process_frame
	_expect(energy_loot.get("_sprite").texture != null, "energy loot uses generated refill art")
	energy_loot.call("_on_body_entered", _player)
	await get_tree().process_frame
	_expect(GameState.health == 75, "energy loot grants exact +25")
	GameState.reset_health()
	var full_energy_loot := LOOT_SCRIPT.new() as CombatLoot
	full_energy_loot.configure(&"energy_refill", Vector2.ZERO)
	add_child(full_energy_loot)
	await get_tree().process_frame
	full_energy_loot.call("_on_body_entered", _player)
	await get_tree().process_frame
	_expect(GameState.health == GameState.max_health, "energy loot clamps at max health")
	_expect(GameState.collected_pickup_ids.is_empty(), "energy loot has no persistent ID")

	GameState.collect_pickup("test.loot.missile_tank.01", &"missile_tank")
	GameState.collect_pickup("test.loot.missile_tank.02", &"missile_tank")
	GameState.spend_missile()
	GameState.spend_missile()
	var missile_loot := LOOT_SCRIPT.new() as CombatLoot
	missile_loot.configure(&"missile_refill", Vector2.ZERO)
	add_child(missile_loot)
	await get_tree().process_frame
	_expect(missile_loot.get("_sprite").texture != null, "missile loot uses generated refill art")
	missile_loot.call("_on_body_entered", _player)
	await get_tree().process_frame
	_expect(
		GameState.missile_count == 10,
		"missile loot grants exact +2 (got %d)" % GameState.missile_count
	)
	_expect(GameState.collected_pickup_ids.size() == 2, "missile loot adds no persistent ID")
	var full_missile_loot := LOOT_SCRIPT.new() as CombatLoot
	full_missile_loot.configure(&"missile_refill", Vector2.ZERO)
	add_child(full_missile_loot)
	await get_tree().process_frame
	full_missile_loot.call("_on_body_entered", _player)
	await get_tree().process_frame
	_expect(GameState.missile_count == GameState.max_missiles, "missile loot clamps at max ammo")

	var invalid_loot := LOOT_SCRIPT.new() as CombatLoot
	invalid_loot.configure(&"flux_shield", Vector2.ZERO)
	add_child(invalid_loot)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not is_instance_valid(invalid_loot), "invalid loot kind cleans up safely")


func _test_panel_catalog() -> void:
	var panel := PANEL_SCRIPT.new() as DevPanel
	add_child(panel)
	await get_tree().process_frame
	var enemy_option: OptionButton
	for option in panel.find_children("*", "OptionButton", true, false):
		var candidate := option as OptionButton
		if candidate != null and candidate.get_item_count() == Catalog.ENEMY_IDS.size():
			enemy_option = candidate
			break
	_expect(enemy_option != null, "dev panel exposes thirteen-enemy selector")
	if enemy_option != null:
		for index in Catalog.ENEMY_IDS.size():
			enemy_option.select(index)
			_expect(
				enemy_option.get_item_text(index) != "",
				"dev panel enemy %s has English label" % Catalog.ENEMY_IDS[index]
			)
		_expect(enemy_option.get_item_text(8) == "Shard Turret", "panel labels shard_turret")
		_expect(enemy_option.get_item_text(9) == "Burrower", "panel labels burrower")
	panel.queue_free()
	await get_tree().process_frame


func _test_dev_station_persistence() -> void:
	if not _dev_mode_requested():
		_failures.append("station persistence test requires --dev-mode")
		return
	GameState.reset_progress()
	var level := LEVEL_SCENE.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var controller := level as Node
	var panel := level.get_tree().get_first_node_in_group("dev_panel") as DevPanel
	var enemy_option: OptionButton
	if panel != null:
		for option in panel.find_children("*", "OptionButton", true, false):
			var candidate := option as OptionButton
			if candidate != null and candidate.get_item_count() == Catalog.ENEMY_IDS.size():
				enemy_option = candidate
				break
	_expect(enemy_option != null, "runtime dev panel has enemy selector")
	if enemy_option != null:
		for index in Catalog.ENEMY_IDS.size():
			enemy_option.select(index)
			controller.call("_on_panel_action", &"enemy", {"id": Catalog.ENEMY_IDS[index]})
			await get_tree().process_frame
			var spawned := level.get_tree().get_nodes_in_group("dev_enemy")
			_expect(
				spawned.size() >= 1 and spawned.back().get("enemy_id") == Catalog.ENEMY_IDS[index],
				"runtime panel selects %s" % Catalog.ENEMY_IDS[index]
			)
	_expect(
		level.get_tree().get_nodes_in_group("dev_pickup").size() >= 27,
		(
			"dev catalog pickups spawn (got %d)"
			% level.get_tree().get_nodes_in_group("dev_pickup").size()
		)
	)
	var energy_count := 0
	var missile_count := 0
	var flux_tank_count := 0
	var flux_ability_count := 0
	for node in level.get_tree().get_nodes_in_group("dev_pickup"):
		if node.get("kind") == &"energy_tank":
			energy_count += 1
		elif node.get("kind") == &"missile_tank":
			missile_count += 1
		elif node.get("kind") == &"flux_tank":
			flux_tank_count += 1
		elif node.get("kind") in Catalog.FLUX_ABILITY_IDS:
			flux_ability_count += 1
	_expect(energy_count == 6, "dev track has six energy tanks")
	_expect(missile_count == 12, "dev track has twelve missile tanks")
	_expect(flux_tank_count == 4, "dev track has four Flux tanks")
	_expect(flux_ability_count == 3, "dev track has three Flux ability pickups")
	_expect(
		(
			level.get_node_or_null("EarlyMissileTank01") != null
			and level.get_node_or_null("EarlyMissileTank02") != null
		),
		"prototype missile tanks remain in original cave"
	)
	await _check_missile_collection_geometry(level)
	controller.call("_on_panel_action", &"preset", {"id": &"start"})
	controller.call("_on_panel_action", &"station", {"index": 1})
	await get_tree().process_frame
	var target: Node
	for node in level.get_tree().get_nodes_in_group("dev_pickup"):
		if node.get("instance_id") == "S1.capacity.energy_01":
			target = node
			break
	_expect(target != null, "energy tank has stable station ID")
	if target != null:
		target.call("_on_body_entered", level.get_node("PlayerSpawn/Player"))
		await get_tree().process_frame
		controller.call("_on_panel_action", &"reset", {"all": false})
		await get_tree().process_frame
		_expect(
			(
				GameState.collected_pickup_ids.has("S1.capacity.energy_01")
				and GameState.max_health == 200
			),
			"station reset preserves collected tank capacity"
		)
	level.queue_free()
	await get_tree().process_frame
	GameState.reset_progress()


func _check_missile_collection_geometry(level: Node) -> void:
	var missile_tanks := level.get_tree().get_nodes_in_group("dev_pickup").filter(
		func(node: Node): return node.get("kind") == &"missile_tank"
	)
	_expect(missile_tanks.size() == 12, "dev track still spawns exactly twelve missile tanks")
	var player := level.get_node("PlayerSpawn/Player") as Player
	for pickup in missile_tanks:
		var points := _find_standing_collection_points(player, pickup as Node2D)
		_expect(
			points.size() == 2,
			"missile %s has standing collection point and clear retreat" % pickup.get("instance_id")
		)


func _find_standing_collection_points(player: Player, pickup: Node2D) -> Array[Vector2]:
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
			if not _standing_clear(player, standing, feet):
				continue
			if not _pickup_overlaps_standing(pickup.global_position, feet):
				continue
			for direction in [-1.0, 1.0]:
				var retreat := feet + Vector2(96.0 * direction, 0.0)
				if _has_support(player, retreat) and _standing_clear(player, standing, retreat):
					return [feet, retreat]
	return []


func _has_support(player: Player, feet: Vector2) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(
		feet + Vector2(0.0, -3.0), feet + Vector2(0.0, 8.0), 1
	)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and absf((hit["position"] as Vector2).y - feet.y) <= 1.0


func _standing_clear(player: Player, standing: CollisionShape2D, feet: Vector2) -> bool:
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


func _dev_mode_requested() -> bool:
	return OS.get_cmdline_args().has("--dev-mode") or OS.get_cmdline_user_args().has("--dev-mode")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
