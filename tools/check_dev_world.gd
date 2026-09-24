extends SceneTree

var _failures: Array[String] = []
var _level: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/levels/level_01.tscn") as PackedScene
	if packed == null:
		_fail("level_01.tscn could not be loaded")
		await _finish()
		return
	_level = packed.instantiate()
	root.add_child(_level)
	var level := _level
	await process_frame
	await process_frame
	if (
		not OS.get_cmdline_args().has("--dev-mode")
		and not OS.get_cmdline_user_args().has("--dev-mode")
	):
		if level.get_tree().get_nodes_in_group("dev_room").size() != 0:
			_fail("dev rooms were built without --dev-mode")
		await _finish()
		return
	var controller := level
	if controller.get_script() == null:
		_fail("DevController is missing")
	else:
		if controller.get("station_ids").size() != 11:
			_fail("S0-S10 are missing")
		if level.get_tree().get_nodes_in_group("dev_room").size() != 10:
			_fail("connected dev rooms are missing")
		var passages := level.get_tree().get_nodes_in_group("dev_passage")
		if passages.size() != 10:
			_fail("S0-S10 boundaries do not have exactly ten passages")
		else:
			for passage in passages:
				if (
					passage.get_node_or_null("CollisionShape2D") != null
					or passage.get_node_or_null("Area2D") != null
				):
					_fail("passage has collision or monitoring")
				var visual := passage.get_node_or_null("PassageArchVisual") as Sprite2D
				if (
					visual == null
					or visual.texture == null
					or not is_equal_approx(visual.scale.x, visual.scale.y)
				):
					_fail("passage lacks uniform authored visual")
		if level.get_tree().get_nodes_in_group("dev_pickup").size() < 10:
			_fail("ability pickups are missing")
		var dev_enemies := level.get_tree().get_nodes_in_group("dev_enemy")
		if dev_enemies.size() < 10:
			_fail("natural encounters and isolated catalog arena lack real instances")
		var map := level.get_node_or_null("DevMap")
		if map == null or map.get("rooms").size() != 11:
			_fail("world map lacks S0-S10 nodes")
		elif map.get("connections").size() != 10:
			_fail("world map lacks true route connections")
		else:
			var miniature := map.get_node_or_null("Miniature") as Control
			if miniature == null or miniature.position.x < 1000.0:
				_fail("world map overlaps the upper-left health/beam/missile HUD")
		if level.get_tree().get_nodes_in_group("dev_optional_fixture").size() < 2:
			_fail("S4/S10 optional hazard fixtures are missing")
		_check_authored_fixtures(level)
		await _run_control_checks(level, controller)
	if (
		level.get_node_or_null("EarlyMissileTank01") == null
		or level.get_node_or_null("EarlyMissileTank02") == null
	):
		_fail("missile containers before first crawler are missing")
	var cave := level.get_node_or_null("CaveTiles") as TileMapLayer
	if cave == null or cave.get_used_rect().size.x < 350:
		_fail("dev annex is not built in the same TileMapLayer")
	await _finish()


func _check_authored_fixtures(level: Node) -> void:
	for gate in level.get_tree().get_nodes_in_group("ability_gates"):
		var visual := gate.get_node_or_null("GateVisual") as Sprite2D
		var expected: String = gate.call("texture_path_for", gate.get("gate_kind"))
		if (
			visual == null
			or visual.texture == null
			or not visual.texture.resource_path.ends_with(expected)
		):
			_fail("ability gate lacks authored kind visual")
		elif not is_equal_approx(visual.scale.x, visual.scale.y):
			_fail("ability gate uses nonuniform visual scale")
	for grate in level.get_tree().get_nodes_in_group("dev_wave_grate"):
		var visual := grate.get_node_or_null("WaveGrateVisual") as Sprite2D
		var relay_target := grate.get("_relay_target") as Node
		var tidal_phase_one := (
			is_instance_valid(relay_target)
			and StringName(relay_target.get("enemy_id")) == &"tidal_heart"
			and int(relay_target.get("phase")) == 1
		)
		if (
			visual == null
			or visual.texture == null
			or not grate.can_pass_projectile(&"wave")
			or grate.can_pass_projectile(&"beam")
			or (tidal_phase_one and not grate.can_pass_projectile(&"ice"))
			or (tidal_phase_one and not grate.can_pass_projectile(&"missile"))
		):
			_fail("Wave grate visual or phase-aware pass semantics missing")
	for pad in level.get_tree().get_nodes_in_group("dev_checkpoint"):
		var visual := pad.get_node_or_null("CheckpointShrineVisual") as Sprite2D
		if visual == null or visual.texture == null:
			_fail("checkpoint shrine visual missing")
	for pad in level.get_tree().get_nodes_in_group("dev_refill"):
		var visual := pad.get_node_or_null("RefillShrineVisual") as Sprite2D
		var expected := "flux_shrine.png" if pad.get("refill_flux") else "refill_shrine.png"
		if (
			visual == null
			or visual.texture == null
			or not visual.texture.resource_path.ends_with(expected)
		):
			_fail("refill shrine visual missing")


func _run_control_checks(level: Node, controller: Node) -> void:
	var state := get_root().get_node_or_null("GameState")
	controller.call("_on_panel_action", &"preset", {"id": &"all"})
	if state == null or not bool(state.call("has_ability", &"undertow_dash")):
		_fail("all-abilities preset failed")
	for index in 11:
		controller.call("_on_panel_action", &"station", {"index": index})
		controller.call("_on_panel_action", &"reset", {"all": false})
	if level.get_tree().get_nodes_in_group("dev_enemy").size() < 10:
		_fail("repeated station resets left incorrect expanded arena state")
	controller.call("_on_panel_action", &"preset", {"id": &"start"})
	if state != null and bool(state.call("has_ability", &"beam")):
		_fail("start preset left beam unlocked")

	await _test_station_physics(level, controller)

	var bosses := level.get_tree().get_nodes_in_group("dev_boss")
	var default_grates := level.get_tree().get_nodes_in_group("dev_wave_grate")
	var tidal: Node = null
	for boss in bosses:
		if boss.get("enemy_id") == &"tidal_heart":
			tidal = boss
	if bosses.size() != 3 or default_grates.size() != 1 or tidal == null:
		_fail("S5/S7/S8 lack three natural bosses and one Tidal relay grate")
	elif default_grates[0].get("_relay_target") != tidal:
		_fail("S8 standard grate lacks Tidal relay")
	else:
		var player := level.get_node("PlayerSpawn/Player") as Node2D
		for boss in bosses:
			if player.global_position.distance_to(boss.global_position) < 300.0:
				_fail("natural boss overlaps player contact detector")
			if bool(boss.get_meta("dev_explicit_test", false)):
				_fail("natural boss was incorrectly marked disposable")
		state.set_world_flag("boss:tidal_heart")
		controller.call("_rebuild_runtime_content")
		if level.get_tree().get_nodes_in_group("dev_boss").size() != 2:
			_fail("defeated Tidal boss respawned or regional bosses disappeared")
		state.set_world_flag("boss:tidal_heart", false)
		controller.call("_rebuild_runtime_content")
		controller.call("_on_panel_action", &"station", {"index": 8})
		controller.call("_on_panel_action", &"reset", {"all": false})
		if level.get_tree().get_nodes_in_group("dev_boss").size() != 1:
			_fail("explicit S8 reset did not respawn test boss")
		elif not bool(
			level.get_tree().get_nodes_in_group("dev_boss")[0].get_meta("dev_explicit_test", false)
		):
			_fail("explicit S8 reset spawned persistent boss instead of test instance")
		state.set_world_flag("boss:tidal_heart", false)
		controller.call("_rebuild_runtime_content")
	for room_id in ["S4", "S10"]:
		var room_index := int(controller.get("station_ids").find(room_id))
		var floor_position: Vector2 = controller.call("_safe_station_spawn", room_index)
		if not bool(controller.call("_is_safe_teleport_position", floor_position)):
			_fail("%s main traversal intersects optional hazard" % room_id)
	var first_grate: Node = default_grates[0] if not default_grates.is_empty() else null
	for boss_id in [&"stone_guardian", &"furnace_mother", &"tidal_heart"]:
		controller.call("_on_panel_action", &"boss", {"id": boss_id, "phase": 0})
		if level.get_tree().get_nodes_in_group("dev_boss").size() != 1:
			_fail("boss selector runs multiple bosses at once")
		var grates := level.get_tree().get_nodes_in_group("dev_wave_grate")
		if boss_id == &"tidal_heart":
			var current_bosses := level.get_tree().get_nodes_in_group("dev_boss")
			if grates.size() != 1 or grates[0].get("_relay_target") != current_bosses[0]:
				_fail("F1 Tidal spawn lacks a fresh Wave relay")
		elif not grates.is_empty():
			_fail("non-Tidal boss received a Wave relay")

	for gate in level.get_tree().get_nodes_in_group("ability_gates"):
		var bottom: float = gate.global_position.y + gate.gate_size.y * 0.5
		if bottom > 900.0:
			_fail("optional ability gate blocks the safe main floor: %s" % bottom)

	controller.call("_on_panel_action", &"preset", {"id": &"start"})
	state.collect_pickup("station.integration.tank", &"missile_tank")
	var capacity: int = state.max_missiles
	controller.call("_on_panel_action", &"station", {"index": 8})
	controller.call("_on_panel_action", &"reset", {"all": false})
	if (
		state.max_missiles != capacity
		or not state.collected_pickup_ids.has("station.integration.tank")
	):
		_fail("station reset removed unique tank or capacity")
	var reset_grates := level.get_tree().get_nodes_in_group("dev_wave_grate")
	if reset_grates.size() != 1:
		_fail("station reset lacks a fresh S8 Wave relay")
	elif is_instance_valid(first_grate) and reset_grates[0] == first_grate:
		_fail("station reset reused an old Wave relay")

	state.reset_health()
	state.apply_damage(25)
	state.refill_missiles(9999)
	var ammo: int = state.missile_count
	var player := level.get_node("PlayerSpawn/Player")
	for pad in level.get_tree().get_nodes_in_group("dev_refill"):
		if pad.refill_health and not pad.refill_missiles:
			pad.call("_on_body_entered", player)
			break
	if state.health != state.max_health or state.missile_count != ammo:
		_fail("S4 health-only refill changed ammunition")


func _test_station_physics(level: Node, controller: Node) -> void:
	var state := get_root().get_node("GameState")
	var weapons := get_root().get_node("Weapons")
	state.acquire_beam()
	state.unlock_ability(&"ice_beam")
	var player := level.get_node("PlayerSpawn/Player")
	var freeze_sample: Node = null
	for enemy in level.get_tree().get_nodes_in_group("dev_freeze_test"):
		if enemy.get("enemy_id") == &"frost_floater":
			freeze_sample = enemy
			break
	if freeze_sample == null:
		_fail("S5 lacks representative freeze-target spawn")
	else:
		freeze_sample.set_physics_process(false)
		var freeze_hp: int = freeze_sample.get("health")
		state.set_active_beam(&"ice")
		weapons.reset_runtime()
		weapons.fire(&"beam", freeze_sample.global_position - Vector2(500, 0), Vector2.RIGHT)
		for _index in 24:
			await physics_frame
		if not freeze_sample.get("is_frozen"):
			_fail("S5 actual Ice does not hit a freezable platform")
		if int(freeze_sample.get("health")) != freeze_hp:
			_fail("S5 Ice changed platform enemy HP")
		if int(freeze_sample.get("collision_layer")) & 32 == 0:
			_fail("frozen S5 enemy lacks layer 6")
		state.set_active_beam(&"base")
		freeze_sample.set_physics_process(true)

	var origins: Dictionary = controller.get("_room_origins")
	var ids: Array = controller.get("station_ids")
	for index in range(1, ids.size()):
		var spawn: Vector2 = controller.call("_safe_station_spawn", index)
		var origin: Vector2 = origins.get(ids[index], Vector2.ZERO)
		if spawn.x < origin.x or spawn.x > origin.x + 2048.0:
			_fail("station %s teleport spawn %s is outside its room" % [ids[index], spawn])

	controller.call("_on_panel_action", &"station", {"index": 1})
	controller.call("_on_panel_action", &"ability", {"id": &"high_jump", "enabled": false})
	var base_peak: float = await _measure_jump(controller, player)
	controller.call("_on_panel_action", &"ability", {"id": &"high_jump", "enabled": true})
	var high_peak: float = await _measure_jump(controller, player)
	if high_peak <= base_peak + 80.0:
		_fail(
			"High Jump test pocket lacks a real higher jump: %.1f vs %.1f" % [base_peak, high_peak]
		)
	controller.call("_on_panel_action", &"ability", {"id": &"high_jump", "enabled": false})


func _measure_jump(controller: Node, player: Node2D) -> float:
	controller.call("_teleport_station", 1)
	for _index in 12:
		await physics_frame
	var start_y: float = player.global_position.y
	Input.action_press("jump")
	var peak_y: float = player.global_position.y
	for _index in 20:
		await physics_frame
		peak_y = minf(peak_y, player.global_position.y)
	Input.action_release("jump")
	for _index in 28:
		await physics_frame
		peak_y = minf(peak_y, player.global_position.y)
	return start_y - peak_y


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_level):
		_level.free()
	await process_frame
	if _failures.is_empty():
		print("check_dev_world: PASS")
		await TestShutdown.finish(self, 0)
		return
	for failure in _failures:
		push_error("check_dev_world: " + failure)
	await TestShutdown.finish(self, 1)
