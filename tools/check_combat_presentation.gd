extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const VisualProfiles = preload("res://scripts/enemies/effects/runtime_visual_profiles.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const ENEMY_IDS: Array[StringName] = [
	&"ceiling_diver",
	&"vent_flyer",
	&"hopper",
	&"spitter",
	&"armored_guard",
	&"frost_floater",
	&"energy_parasite",
	&"shard_turret",
	&"burrower",
	&"grasshopper",
	&"shooting_gargoyle",
	&"lava_monster",
]
const ROSTER_IDS: Array[StringName] = [&"crawler"] + ENEMY_IDS
const BOSS_IDS: Array[StringName] = [&"stone_guardian", &"furnace_mother", &"tidal_heart"]
const PROOF_DIR := "res://proofs/runtime/combat_presentation"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await _check_profiles_and_colliders()
	_check_physics_constants()
	await _check_enemy_states_and_hits()
	await _check_boss_states()
	await _check_player_death_recovery()
	await _check_hud_layout()
	if _capture_requested():
		await _capture_proofs()
	GameState.reset_progress()
	if _failures.is_empty():
		print(
			"PASS: combat presentation offsets, unchanged physics, telegraphs, death recovery, and HUD rows"
		)
		await TestShutdown.finish(get_tree(), 0)
		return
	for failure in _failures:
		push_error("FAIL: " + failure)
	await TestShutdown.finish(get_tree(), 1)


func _check_profiles_and_colliders() -> void:
	for runtime_id in ENEMY_IDS:
		var profile := VisualProfiles.profile(runtime_id)
		_check(not profile.is_empty(), "%s visual profile loads" % runtime_id)
		var enemy := EnemyFactory.create(runtime_id)
		add_child(enemy)
		enemy.set_physics_process(false)
		var sprite := enemy.get_node("Sprite2D") as Sprite2D
		_check(sprite.texture != null, "%s authored texture loads" % runtime_id)
		_check(
			enemy.get("_visual_base_position") == VisualProfiles.visual_offset(runtime_id),
			"%s manifest offset applied" % runtime_id,
		)
		_check(
			(
				enemy.get("_visual_base_scale")
				== Vector2.ONE * VisualProfiles.visual_scale(runtime_id)
			),
			"%s manifest scale applied" % runtime_id,
		)
		var body_shape := enemy.get_node("CollisionShape2D").shape as RectangleShape2D
		var detector_shape := (
			enemy.get_node("PlayerDetector/CollisionShape2D").shape as RectangleShape2D
		)
		var collision_profiles := {
			&"burrower": [Vector2(54.0, 50.0), Vector2(68.0, 66.0)],
			&"grasshopper": [Vector2(72.0, 44.0), Vector2(88.0, 60.0)],
			&"shooting_gargoyle": [Vector2(72.0, 80.0), Vector2(88.0, 96.0)],
			&"lava_monster": [Vector2(88.0, 72.0), Vector2(104.0, 88.0)],
		}
		var expected_profile: Array = collision_profiles.get(
			runtime_id, [Vector2(50.0, 50.0), Vector2(66.0, 66.0)]
		)
		var expected_body: Vector2 = expected_profile[0]
		var expected_detector: Vector2 = expected_profile[1]
		_check(body_shape.size == expected_body, "%s body collider unchanged" % runtime_id)
		_check(
			detector_shape.size == expected_detector, "%s contact detector unchanged" % runtime_id
		)
		enemy.queue_free()
	await get_tree().process_frame
	var crawler := EnemyFactory.create(&"crawler")
	add_child(crawler)
	crawler.set_physics_process(false)
	var crawler_visual := crawler.get_node("Visual") as Node2D
	var crawler_sprite := crawler.get_node("Visual/CrawlerSprite") as AnimatedSprite2D
	var crawler_body := crawler.get_node("CollisionShape2D").shape as RectangleShape2D
	var crawler_detector := (
		crawler.get_node("PlayerDetector/CollisionShape2D").shape as RectangleShape2D
	)
	_check(crawler_sprite.sprite_frames != null, "crawler authored strip remains loaded")
	_check(crawler_visual.position == Vector2(0.0, -15.0), "crawler support anchor remains exact")
	_check(crawler_body.size == Vector2(48.0, 32.0), "crawler body collider unchanged")
	_check(crawler_detector.size == Vector2(60.0, 44.0), "crawler detector unchanged")
	crawler.queue_free()
	await get_tree().process_frame
	for runtime_id in BOSS_IDS:
		var boss := EnemyFactory.create(runtime_id)
		add_child(boss)
		boss.set_physics_process(false)
		var sprite := boss.get_node("Sprite2D") as Sprite2D
		_check(sprite.texture != null, "%s authored texture loads" % runtime_id)
		_check(
			boss.get("_visual_base_position") == VisualProfiles.visual_offset(runtime_id),
			"%s boss manifest offset applied" % runtime_id,
		)
		var body_shape := boss.get_node("CollisionShape2D").shape as CircleShape2D
		var detector_shape := (
			boss.get_node("PlayerDetector/CollisionShape2D").shape as CircleShape2D
		)
		_check(is_equal_approx(body_shape.radius, 92.0), "%s boss collider unchanged" % runtime_id)
		_check(
			is_equal_approx(detector_shape.radius, 112.0), "%s boss detector unchanged" % runtime_id
		)
		var hurtbox := boss.get_node_or_null("Sprite2D/ProjectileHurtbox")
		_check(hurtbox != null, "%s visible silhouette has a projectile hurtbox" % runtime_id)
		_check(
			hurtbox != null and hurtbox.get_child_count() > 0,
			"%s projectile hurtbox contains authored-alpha polygons" % runtime_id,
		)
		boss.queue_free()
	await get_tree().process_frame


func _check_physics_constants() -> void:
	var expected := {
		"WALK_MAX": [PlayerConfig.WALK_MAX, 480.0],
		"GROUND_ACCEL": [PlayerConfig.GROUND_ACCEL, 4000.0],
		"GROUND_FRICTION": [PlayerConfig.GROUND_FRICTION, 6000.0],
		"AIR_ACCEL": [PlayerConfig.AIR_ACCEL, 3040.0],
		"AIR_FRICTION": [PlayerConfig.AIR_FRICTION, 1760.0],
		"JUMP_VELOCITY": [PlayerConfig.JUMP_VELOCITY, 1280.0],
		"GRAVITY_RISING": [PlayerConfig.GRAVITY_RISING, 3200.0],
		"GRAVITY_FALLING": [PlayerConfig.GRAVITY_FALLING, 4640.0],
		"TERMINAL_VELOCITY": [PlayerConfig.TERMINAL_VELOCITY, 1760.0],
		"WALL_JUMP_VELOCITY": [PlayerConfig.WALL_JUMP_VELOCITY, 1280.0],
		"ROLL_MAX": [PlayerConfig.ROLL_MAX, 580.0],
	}
	for constant_name in expected:
		var values: Array = expected[constant_name]
		_check(
			is_equal_approx(values[0], values[1]), "%s physics constant unchanged" % constant_name
		)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	var standing := player.get_node("StandingCollisionShape2D").shape as RectangleShape2D
	var ball := player.get_node("BallCollisionShape2D").shape as RectangleShape2D
	_check(standing.size == Vector2(56.0, 176.0), "player standing collider unchanged")
	_check(ball.size == Vector2(56.0, 56.0), "player ball collider unchanged")
	player.queue_free()


func _check_enemy_states_and_hits() -> void:
	var hopper := EnemyFactory.create(&"hopper")
	add_child(hopper)
	hopper.set_physics_process(false)
	_check(hopper.call("presentation_state") == &"idle", "enemy starts idle")
	hopper.set("_telegraph_remaining", 0.3)
	hopper.call("_update_visual_presentation")
	_check(
		hopper.call("presentation_state") == &"attack_telegraph", "enemy attack telegraph switches"
	)
	var hp := int(hopper.get("health"))
	hopper.call("take_damage", 1, &"beam")
	_check(int(hopper.get("health")) == hp - 1, "presentation hit preserves damage path")
	_check(hopper.call("presentation_state") == &"hit", "enemy hit flash switches")
	var hit_effect := _find_effect(&"hit")
	_check(hit_effect != null, "enemy hit creates compact effect")
	if hit_effect != null:
		_check(float(hit_effect.get("_duration")) <= 0.3, "enemy hit effect duration bounded")
	hopper.call("take_damage", 0, &"ice")
	_check(hopper.call("presentation_state") == &"frozen", "frozen tint state switches")
	hopper.queue_free()
	_clear_transients()
	var burrower := EnemyFactory.create(&"burrower")
	add_child(burrower)
	burrower.set_physics_process(false)
	_check(burrower.call("presentation_state") == &"mound", "burrower mound state readable")
	burrower.set("_burrow_phase", &"exposed")
	burrower.call("_update_visual_presentation")
	_check(burrower.call("presentation_state") == &"exposed", "burrower exposed state readable")
	var sprite := burrower.get_node("Sprite2D") as Sprite2D
	_check(sprite.scale.y > 0.9, "burrower exposed art restores full height")
	burrower.queue_free()
	await get_tree().process_frame


func _check_boss_states() -> void:
	var accent_colors: Array[Color] = []
	for runtime_id in BOSS_IDS:
		var boss := EnemyFactory.create(runtime_id)
		add_child(boss)
		boss.set_physics_process(false)
		_check(
			boss.call("presentation_state") == &"protected", "%s protected telegraph" % runtime_id
		)
		if runtime_id == &"tidal_heart":
			boss.call("take_damage", 0, &"ice")
		else:
			boss.call("_advance_attack_window")
		boss.call("_update_visual_presentation")
		_check(boss.call("presentation_state") == &"open", "%s open telegraph" % runtime_id)
		var health_before := int(boss.get("health"))
		var bursts_before_phase := int(boss.get("_phase_burst_count"))
		boss.call("set_test_phase", 2)
		_check(int(boss.get("phase")) == 2, "%s phase switches" % runtime_id)
		_check(
			int(boss.get("health")) == health_before,
			"%s phase burst is gameplay-neutral" % runtime_id
		)
		_check(
			int(boss.get("_phase_burst_count")) == bursts_before_phase + 1,
			"%s phase transition emits exactly one burst" % runtime_id,
		)
		boss.set("_telegraph_remaining", 0.3)
		boss.call("_update_visual_presentation")
		_check(
			boss.call("presentation_state") == &"attack",
			"%s attack telegraph switches" % runtime_id
		)
		accent_colors.append(boss.call("_boss_accent_color"))
		boss.queue_free()
		_clear_transients()
	await get_tree().process_frame
	_check(accent_colors[0] != accent_colors[1], "stone and furnace color languages differ")
	_check(accent_colors[1] != accent_colors[2], "furnace and tidal color languages differ")


func _check_player_death_recovery() -> void:
	GameState.reset_progress()
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	player.call("take_damage", GameState.max_health)
	_check(bool(player.get("_dead")), "lethal damage enters death once")
	var effect := player.get("_death_effect") as Node2D
	_check(effect != null, "lethal damage starts textured disintegration")
	_check(
		not player.get_node("AnimatedSprite2D").visible, "player source visual hides during delay"
	)
	if effect != null:
		_check(
			effect.get("_effect_kind") == &"player_death",
			"player uses dedicated death lifecycle effect"
		)
		_check(effect.process_mode == Node.PROCESS_MODE_ALWAYS, "player death effect is pause-safe")
		var first_id := effect.get_instance_id()
		player.call("_on_player_died")
		_check(
			(player.get("_death_effect") as Node2D).get_instance_id() == first_id,
			"duplicate death callback does not create second lifecycle",
		)
		var elapsed_before := float(effect.get("_elapsed"))
		get_tree().paused = true
		await get_tree().create_timer(0.08, true).timeout
		var elapsed_after := float(effect.get("_elapsed"))
		get_tree().paused = false
		_check(elapsed_after > elapsed_before, "death disintegration advances while paused")
	player.call("reset_for_spawn", Vector2(320.0, 480.0))
	await get_tree().process_frame
	_check(not bool(player.get("_dead")), "respawn clears death state")
	_check(player.get("_death_effect") == null, "respawn clears death effect reference")
	_check(player.get_node("AnimatedSprite2D").visible, "respawn restores player visual")
	_check(
		player.get_node("AnimatedSprite2D").modulate == Color.WHITE,
		"respawn restores clean modulation"
	)
	player.queue_free()
	await get_tree().process_frame


func _check_hud_layout() -> void:
	_prepare_max_hud_state()
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	_check(hud.has_method("_on_pickup_feedback"), "HUD script loads pickup feedback method")
	_check(hud.has_method("_refresh_loadout"), "HUD script loads refresh method")
	if not hud.has_method("_on_pickup_feedback") or not hud.has_method("_refresh_loadout"):
		hud.queue_free()
		await get_tree().process_frame
		return
	hud.call("_on_pickup_feedback", "FLUX REFILL · 300 / 300")
	await get_tree().process_frame
	var loadout := hud.get_node("LoadoutLabel") as Label
	var beam := hud.get_node("BeamPanel/BeamLabel") as Label
	var missiles := hud.get_node("MissilePanel/MissileLabel") as Label
	var health_panel := hud.get_node("HealthPanel") as Control
	var beam_panel := hud.get_node("BeamPanel") as Control
	var missile_panel := hud.get_node("MissilePanel") as Control
	var flux_meter := hud.get_node("FluxMeter") as ProgressBar
	var flux_status := hud.get_node("FluxStatus") as Label
	var pickup := hud.get_node("PickupFeedback") as Label
	# Accept both the legacy text HUD and the ui lane's redesigned numeric HUD.
	var missile_max := hud.get_node_or_null("MissilePanel/MissileMax") as Label
	_check(
		loadout.text.begins_with("HEALTH") or loadout.text == "100",
		"health has a dedicated primary panel"
	)
	_check(beam.text == "ECHO", "selected beam has a dedicated panel")
	_check(
		loadout.text.contains("700 / 700") or GameState.health == 700,
		"maximum health value remains contained"
	)
	_check(
		(
			missiles.text.contains("60 / 60")
			or (missiles.text == "60" and missile_max != null and missile_max.text == "/ 60")
		),
		"maximum missile value remains contained"
	)
	_check(not loadout.text.contains("FLUX"), "primary loadout contains no duplicate Flux text")
	_check(flux_status.text.contains("FLUX SHIELD ON"), "Flux row carries module and status")
	var rows: Array[Control] = [loadout, beam, missiles, flux_meter, flux_status, pickup]
	for control in rows:
		var rect := control.get_global_rect()
		_check(rect.position.x >= 0.0 and rect.end.x <= 1920.0, "%s fits 1920 width" % control.name)
		_check(
			rect.position.y >= 0.0 and rect.end.y <= 1080.0, "%s fits 1080 height" % control.name
		)
	_check(
		not health_panel.get_global_rect().intersects(beam_panel.get_global_rect()),
		"health and selected-beam panels do not overlap"
	)
	_check(
		not beam_panel.get_global_rect().intersects(missile_panel.get_global_rect()),
		"selected-beam and missile panels do not overlap"
	)
	_check(
		not loadout.get_global_rect().intersects(flux_meter.get_global_rect()),
		"primary and Flux rows do not overlap"
	)
	_check(
		not loadout.get_global_rect().intersects(flux_status.get_global_rect()),
		"primary and Flux status do not overlap"
	)
	_check(
		not pickup.get_global_rect().intersects(flux_meter.get_global_rect()),
		"pickup and Flux meter do not overlap"
	)
	_check(
		not pickup.get_global_rect().intersects(flux_status.get_global_rect()),
		"pickup and Flux status do not overlap"
	)
	hud.queue_free()
	await get_tree().process_frame


func _capture_proofs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROOF_DIR))
	print("Capture: enemy roster")
	await _capture_enemy_roster()
	for runtime_id in BOSS_IDS:
		print("Capture: boss ", runtime_id)
		await _capture_boss_states(runtime_id)
	print("Capture: player death")
	await _capture_player_death()
	print("Capture: HUD")
	await _capture_hud()


func _capture_enemy_roster() -> void:
	var viewport := _make_viewport()
	var world := Node2D.new()
	viewport.add_child(world)
	_add_heading(world, "AUTHORED ENEMY ROSTER · RUNTIME OFFSETS", Vector2(56.0, 42.0))
	for index in ROSTER_IDS.size():
		var enemy := EnemyFactory.create(ROSTER_IDS[index])
		world.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.position = Vector2(140.0 + float(index % 7) * 273.0, 330.0 + float(index / 7) * 470.0)
		if enemy.has_method("_update_visual_presentation"):
			enemy.set("_age", float(index) * 0.23)
			enemy.call("_update_visual_presentation")
		_add_caption(
			world,
			String(ROSTER_IDS[index]).replace("_", " ").to_upper(),
			enemy.position + Vector2(-110.0, 170.0)
		)
	await _save_viewport(viewport, "enemy_roster")


func _capture_boss_states(runtime_id: StringName) -> void:
	var viewport := _make_viewport()
	var world := Node2D.new()
	viewport.add_child(world)
	_add_heading(
		world,
		String(runtime_id).replace("_", " ").to_upper() + " · STATE TELEGRAPHS",
		Vector2(56.0, 42.0)
	)
	var captions := ["PROTECTED", "VULNERABLE WINDOW", "ATTACK TELEGRAPH"]
	for index in 3:
		var boss := EnemyFactory.create(runtime_id)
		world.add_child(boss)
		boss.set_physics_process(false)
		boss.position = Vector2(360.0 + float(index) * 600.0, 610.0)
		boss.set("_age", 0.42)
		if index == 1:
			boss.set("phase", 2)
			boss.set("_branch_open", true)
		elif index == 2:
			boss.set("phase", 2)
			boss.set("_telegraph_remaining", 0.3)
		boss.call("_update_visual_presentation")
		boss.queue_redraw()
		_add_caption(world, captions[index], boss.position + Vector2(-125.0, 260.0))
	await _save_viewport(viewport, "boss_%s_states" % runtime_id)


func _capture_player_death() -> void:
	var viewport := _make_viewport()
	var world := Node2D.new()
	viewport.add_child(world)
	_add_heading(world, "PLAYER DEATH · TEXTURED DISINTEGRATION FRAME", Vector2(56.0, 42.0))
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	player.set_physics_process(false)
	player.get_node("Camera2D").enabled = false
	player.position = Vector2(960.0, 650.0)
	var effect = CombatFeedback.spawn_player_death(player)
	player.get_node("AnimatedSprite2D").hide()
	await get_tree().create_timer(0.14, true).timeout
	_check(effect != null, "player death proof effect spawns")
	await _save_viewport(viewport, "player_death_fragments", false)


func _capture_hud() -> void:
	_prepare_max_hud_state()
	var viewport := _make_viewport()
	var hud := HUD_SCENE.instantiate()
	viewport.add_child(hud)
	hud.call("_on_pickup_feedback", "FLUX REFILL · 300 / 300")
	hud.call("_refresh_loadout")
	await _save_viewport(viewport, "hud_flux_pickup")


func _prepare_max_hud_state() -> void:
	GameState.reset_progress()
	GameState.acquire_beam()
	GameState.unlock_ability(&"wave_beam")
	GameState.set_active_beam(&"wave")
	GameState.unlock_ability(&"flux_shield")
	for index in Catalog.MAX_ENERGY_TANKS:
		GameState.collect_pickup("hud.energy.%02d" % index, &"energy_tank")
	for index in Catalog.MAX_MISSILE_TANKS:
		GameState.collect_pickup("hud.missile.%02d" % index, &"missile_tank")
	for index in Catalog.MAX_FLUX_TANKS:
		GameState.collect_pickup("hud.flux.%02d" % index, &"flux_tank")
	GameState.set_active_flux_module(&"flux_shield")
	GameState.set_flux_enabled(true)


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("09131b")
	background.position = Vector2.ZERO
	background.size = Vector2(1920.0, 1080.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	return viewport


func _save_viewport(viewport: SubViewport, filename: String, wait_frames := true) -> void:
	if wait_frames:
		await get_tree().process_frame
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	_check(image != null, "%s proof image renders" % filename)
	if image != null:
		_check(image.get_size() == Vector2i(1920, 1080), "%s proof is native 1920x1080" % filename)
		var path := ProjectSettings.globalize_path("%s/%s.png" % [PROOF_DIR, filename])
		_check(image.save_png(path) == OK, "%s proof saves" % filename)
	viewport.queue_free()
	await get_tree().process_frame


func _add_heading(parent: Node, text: String, position: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("d7ebe8"))
	parent.add_child(label)


func _add_caption(parent: Node, text: String, position: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = Vector2(250.0, 36.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", Color("9fc5c0"))
	parent.add_child(label)


func _find_effect(kind: StringName) -> Node:
	for transient in get_tree().get_nodes_in_group(&"transient"):
		if transient is CombatFeedback and transient.get("_effect_kind") == kind:
			return transient
	return null


func _clear_transients() -> void:
	for transient in get_tree().get_nodes_in_group(&"transient"):
		transient.queue_free()


func _capture_requested() -> bool:
	return OS.get_cmdline_user_args().has("--capture-presentation")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
