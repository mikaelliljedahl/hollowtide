extends Node

const FLOOR_Y := 1152.0
const PASSAGE_APERTURE := Vector2(192.0, 224.0)
const PLAYER_HALF_WIDTH := 28.0
const PROOF_DIR := "res://proofs/runtime/presentation"

var _failures: Array[String] = []
var _level: Node
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/levels/level_01.tscn") as PackedScene
	if packed == null:
		_fail("level_01.tscn could not be loaded")
		await _finish()
		return
	_level = packed.instantiate()
	get_tree().root.add_child(_level)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _level.get_node_or_null("PlayerSpawn/Player") as Player
	var passages := get_tree().get_nodes_in_group(&"dev_passage")
	passages.sort_custom(func(a: Node, b: Node): return a.global_position.x < b.global_position.x)
	_check(passages.size() == 10, "dev world has exactly ten passages")
	if _player == null:
		_fail("real dev player is missing")
	else:
		_check_passage_structure(passages)
		_check_gate_architecture()
		_check_wave_grates()
		_check_shrine_stations()
		_check_wall_pose_metrics()
		await _test_real_wall_contact()
		await _test_bidirectional_route(passages)
	if DisplayServer.get_name() == "headless":
		print("Presentation native capture skipped: active renderer is headless dummy")
	else:
		await _capture_presentation(passages)
	await _finish()


func _check_passage_structure(passages: Array[Node]) -> void:
	var origins: Dictionary = _level.get("_room_origins")
	for index in range(1, 11):
		var room_id := "S%d" % index
		var expected_x: float = (origins[room_id] as Vector2).x
		var matches := passages.filter(
			func(node: Node): return is_equal_approx(node.global_position.x, expected_x)
		)
		_check(matches.size() == 1, "%s boundary has one passage" % room_id)
		if matches.is_empty():
			continue
		var passage := matches[0] as Node2D
		_check(
			is_equal_approx(passage.global_position.y, FLOOR_Y),
			"%s passage anchors to route floor" % room_id
		)
		_check(
			passage.find_children("*", "CollisionObject2D", true, false).is_empty(),
			"%s passage architecture has no collision or monitoring" % room_id
		)
		var visual := passage.get_node_or_null("PassageArchVisual") as Sprite2D
		_check(visual != null and visual.texture != null, "%s passage uses authored arch" % room_id)
		if visual == null or visual.texture == null:
			continue
		var displayed_size := Vector2(visual.texture.get_size()) * visual.scale
		_check(
			displayed_size.is_equal_approx(Vector2(384.0, 384.0)),
			"%s passage is full-height architecture" % room_id
		)
		var aperture: Rect2 = passage.call("visual_aperture_rect")
		_check(
			aperture.size.is_equal_approx(PASSAGE_APERTURE),
			"%s passage has readable full-height aperture" % room_id
		)
		_check(
			is_equal_approx(aperture.end.y, 0.0), "%s passage aperture meets floor route" % room_id
		)
		var image := visual.texture.get_image()
		var local_probe := aperture.get_center() - visual.position
		var source_probe := local_probe / visual.scale + Vector2(visual.texture.get_size()) * 0.5
		_check(
			image.get_pixelv(Vector2i(source_probe)).a < 0.1,
			"%s passage aperture visibly reveals continuation" % room_id
		)


func _check_gate_architecture() -> void:
	var gates := get_tree().get_nodes_in_group(&"ability_gates")
	_check(gates.size() == 5, "all five ability gate instances exist")
	for gate in gates:
		var frame := gate.get_node_or_null("GateFrameVisual") as Sprite2D
		var leaf := gate.get_node_or_null("GateVisual") as Sprite2D
		var size: Vector2 = gate.get("gate_size")
		_check(
			frame != null and frame.texture != null,
			"ability gate keeps authored jamb/arch/threshold frame"
		)
		_check(leaf != null and leaf.texture != null, "ability gate has authored door leaf")
		if leaf == null or leaf.texture == null:
			continue
		var leaf_size := leaf.region_rect.size * leaf.scale
		_check(leaf.region_enabled, "ability gate leaf uses authored crop")
		_check(leaf_size.is_equal_approx(size), "ability gate leaf exactly spans collider aperture")
		_check(
			is_equal_approx(leaf.scale.x, leaf.scale.y),
			"ability gate leaf keeps authored proportions"
		)
		gate.call("_open", false)
		_check(frame.visible, "ability gate frame remains after open")
		_check(not leaf.visible, "ability gate open hides only door leaf")
		gate.set("_is_open", false)
		gate.collision_layer = 1
		leaf.visible = true
		var collision := gate.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision != null:
			collision.set_deferred("disabled", false)


func _check_wave_grates() -> void:
	var grates := get_tree().get_nodes_in_group(&"projectile_grate")
	_check(grates.size() >= 2, "station and boss Wave Grates exist")
	for grate in grates:
		var frame := grate.get_node_or_null("WaveGrateFrameVisual") as Sprite2D
		var leaf := grate.get_node_or_null("WaveGrateVisual") as Sprite2D
		var size: Vector2 = grate.get("grate_size")
		_check(
			frame != null and frame.texture != null, "Wave Grate has authored architectural frame"
		)
		_check(leaf != null and leaf.texture != null, "Wave Grate has authored leaf")
		if leaf != null and leaf.texture != null:
			_check(leaf.region_enabled, "Wave Grate uses authored aperture crop")
			_check(
				(leaf.region_rect.size * leaf.scale).is_equal_approx(size),
				"Wave Grate visibly spans full aperture"
			)
		_check(grate.call("can_pass_projectile", &"wave"), "Wave Grate passes Wave")
		_check(not grate.call("can_pass_projectile", &"beam"), "Wave Grate blocks base beam")


func _check_shrine_stations() -> void:
	var shrines: Array[Node] = []
	shrines.append_array(get_tree().get_nodes_in_group(&"dev_checkpoint"))
	shrines.append_array(get_tree().get_nodes_in_group(&"dev_refill"))
	_check(shrines.size() == 12, "all checkpoint/refill/Flux stations exist")
	var bounds: Array[Rect2] = []
	for shrine in shrines:
		var local_bounds: Rect2 = shrine.call("visual_bounds")
		var world_bounds := Rect2(
			(shrine as Node2D).global_position + local_bounds.position, local_bounds.size
		)
		bounds.append(world_bounds)
		_check((shrine as CollisionObject2D).collision_layer == 0, "shrine adds no route collision")
		_check(
			absf(world_bounds.end.y - FLOOR_Y) <= 1.0,
			"shrine authored base integrates with actual floor"
		)
	for first_index in bounds.size():
		for second_index in range(first_index + 1, bounds.size()):
			_check(
				not bounds[first_index].intersects(bounds[second_index]),
				"shrine visual bounds remain distinct at actual stations"
			)


func _check_wall_pose_metrics() -> void:
	var run_texture := load("res://assets/sprites/player_run.png") as Texture2D
	var slide_texture := load("res://assets/sprites/player_wall_slide.png") as Texture2D
	var jump_texture := load("res://assets/sprites/player_wall_jump.png") as Texture2D
	if run_texture == null or slide_texture == null or jump_texture == null:
		_fail("run and wall pose textures load")
		return
	var run_image := run_texture.get_image()
	var slide_rect := slide_texture.get_image().get_used_rect()
	var jump_rect := jump_texture.get_image().get_used_rect()
	var max_run_height := 0
	for frame_index in 8:
		var frame := run_image.get_region(Rect2i(frame_index * 256, 0, 256, 256))
		max_run_height = maxi(max_run_height, frame.get_used_rect().size.y)
	var slide_height := float(slide_rect.size.y) * Player.WALL_POSE_SCALE
	var jump_height := float(jump_rect.size.y) * Player.WALL_POSE_SCALE
	_check(
		slide_height >= float(max_run_height) * 0.75 and slide_height <= float(max_run_height),
		"wall-slide body scale is comparable to run"
	)
	_check(
		jump_height >= float(max_run_height) * 0.6 and jump_height <= float(max_run_height),
		"wall-jump body scale is comparable to run"
	)
	var authored_left_edge := (
		Player.WALL_SLIDE_CONTACT_OFFSET_X
		+ (float(slide_rect.position.x) - 128.0) * Player.WALL_POSE_SCALE
	)
	_check(
		absf(authored_left_edge + PLAYER_HALF_WIDTH) <= 2.0,
		"wall-slide authored hand anchors to collision contact"
	)


func _test_real_wall_contact() -> void:
	var origins: Dictionary = _level.get("_room_origins")
	var wall_right_x: float = (origins["S9"] as Vector2).x + 13.0 * 64.0
	_player.reset_for_spawn(Vector2(wall_right_x + PLAYER_HALF_WIDTH, 850.0))
	await get_tree().physics_frame
	var left_cast := _player.get_node("WallCastLeft") as RayCast2D
	left_cast.force_raycast_update()
	_check(left_cast.is_colliding(), "wall pose contact uses real S9 wall")


func _test_bidirectional_route(passages: Array[Node]) -> void:
	for index in passages.size():
		var passage := passages[index] as Node2D
		_player.reset_for_spawn(Vector2(passage.global_position.x - 240.0, FLOOR_Y))
		await _settle()
		await _walk(&"move_right")
		_check(
			_player.global_position.x > passage.global_position.x + 64.0,
			"S%d passage traverses left to right" % (index + 1)
		)
		_player.reset_for_spawn(Vector2(passage.global_position.x + 240.0, FLOOR_Y))
		await _settle()
		await _walk(&"move_left")
		_check(
			_player.global_position.x < passage.global_position.x - 64.0,
			"S%d passage traverses right to left" % (index + 1)
		)
	_release_inputs()


func _walk(action: StringName) -> void:
	Input.action_press(action)
	for _frame in 45:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _settle() -> void:
	for _frame in 8:
		await get_tree().physics_frame


func _capture_presentation(passages: Array[Node]) -> void:
	var viewport := SubViewport.new()
	viewport.name = "PresentationRuntimeViewport"
	viewport.size = Vector2i(1920, 1080)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var parent := _level.get_parent()
	parent.remove_child(_level)
	viewport.add_child(_level)
	_player.set_physics_process(false)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.position_smoothing_enabled = false
	_hide_test_ui()
	var passage := passages[4] as Node2D
	await _capture_subject(passage.global_position, &"boundary_passage")
	var gates := get_tree().get_nodes_in_group(&"ability_gates")
	gates.sort_custom(func(a: Node, b: Node): return a.global_position.x < b.global_position.x)
	var kind_counts := {}
	for gate in gates:
		var kind := String(gate.get("gate_kind"))
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		var suffix := "_%02d" % kind_counts[kind] if kind == "missile" else ""
		var label_base := "gate_%s%s" % [kind, suffix]
		var leaf := gate.get_node("GateVisual") as Sprite2D
		leaf.visible = true
		await _capture_subject(gate.global_position, StringName(label_base + "_closed"))
		gate.call("_open", false)
		await _capture_subject(gate.global_position, StringName(label_base + "_open"))
	var grates := get_tree().get_nodes_in_group(&"projectile_grate")
	grates.sort_custom(func(a: Node, b: Node): return a.global_position.x < b.global_position.x)
	for index in grates.size():
		await _capture_subject(
			(grates[index] as Node2D).global_position, StringName("wave_grate_%02d" % (index + 1))
		)
	await _capture_isolated_shrine(_first_checkpoint(), &"shrine_checkpoint")
	await _capture_isolated_shrine(_first_refill(false), &"shrine_refill")
	await _capture_isolated_shrine(_first_refill(true), &"shrine_flux")
	await _capture_wall_contact()
	_player.set_physics_process(true)
	viewport.remove_child(_level)
	parent.add_child(_level)
	viewport.queue_free()
	await get_tree().process_frame


func _capture_subject(subject_position: Vector2, label: StringName) -> void:
	_player.global_position = Vector2(subject_position.x - 280.0, FLOOR_Y)
	await _save_capture(label)


func _capture_isolated_shrine(shrine: Node2D, label: StringName) -> void:
	if shrine == null:
		_fail("missing isolated shrine capture target: %s" % label)
		return
	var fixtures: Array[Node] = []
	for group_name in [
		&"dev_checkpoint",
		&"dev_refill",
		&"dev_gate",
		&"dev_passage",
		&"dev_pickup",
		&"dev_optional_fixture",
		&"dev_enemy",
	]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not fixtures.has(node):
				fixtures.append(node)
	for fixture in fixtures:
		_set_fixture_visible(fixture, fixture == shrine)
	await _capture_subject(shrine.global_position, label)
	for fixture in fixtures:
		_set_fixture_visible(fixture, true)


func _set_fixture_visible(fixture: Node, show: bool) -> void:
	if fixture is CanvasItem:
		(fixture as CanvasItem).visible = show
	for child in fixture.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = show


func _capture_wall_contact() -> void:
	var origins: Dictionary = _level.get("_room_origins")
	var wall_right_x: float = (origins["S9"] as Vector2).x + 13.0 * 64.0
	_player.global_position = Vector2(wall_right_x + PLAYER_HALF_WIDTH, 850.0)
	_player.facing = 1
	_player.set("_wall_sliding", true)
	_player.set("_wall_side", -1)
	_player.set("_wall_jump_pose_timer", 0.0)
	_player.call("_update_animation")
	await _save_capture(&"wall_pose_real_contact")


func _save_capture(label: StringName) -> void:
	for _frame in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image := _level.get_viewport().get_texture().get_image()
	if image == null:
		_fail("capture failed: %s" % label)
		return
	_check(image.get_size() == Vector2i(1920, 1080), "%s capture is native 1920x1080" % label)
	_check(
		_count_clear_color_samples(image) == 0,
		"%s capture has no exposed viewport clear color" % label
	)
	var directory := ProjectSettings.globalize_path(PROOF_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	_check(image.save_png("%s/%s.png" % [directory, label]) == OK, "%s capture saves" % label)


func _count_clear_color_samples(image: Image) -> int:
	var clear := Color(77.0 / 255.0, 77.0 / 255.0, 77.0 / 255.0, 1.0)
	var count := 0
	for y in range(16, image.get_height(), 64):
		for x in range(16, image.get_width(), 64):
			var color := image.get_pixel(x, y)
			if (
				absf(color.r - clear.r) < 0.002
				and absf(color.g - clear.g) < 0.002
				and absf(color.b - clear.b) < 0.002
			):
				count += 1
	return count


func _hide_test_ui() -> void:
	for node in _level.find_children("*", "CanvasLayer", true, false):
		if node.name in [&"DevPanel", &"DevMap", &"DevOverlay"]:
			(node as CanvasLayer).visible = false


func _first_checkpoint():
	var checkpoints := get_tree().get_nodes_in_group(&"dev_checkpoint")
	return checkpoints[0] as Node2D if not checkpoints.is_empty() else null


func _first_refill(flux: bool):
	for node in get_tree().get_nodes_in_group(&"dev_refill"):
		if bool(node.get("refill_flux")) == flux:
			return node as Node2D
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _release_inputs() -> void:
	for action in [&"move_left", &"move_right", &"jump", &"run"]:
		Input.action_release(action)


func _finish() -> void:
	_release_inputs()
	if is_instance_valid(_level):
		_level.free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("check_passages: PASS")
		await TestShutdown.finish(get_tree(), 0)
		return
	for failure in _failures:
		push_error("check_passages: " + failure)
	await TestShutdown.finish(get_tree(), 1)
