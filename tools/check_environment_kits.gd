extends Node
## Env check on the real dev world: five natural area kits, exact area boundaries, visual-only
## terrain (collision untouched), no steel-facility override, grounded hazards.

const LEVEL_SCENE = preload("res://scenes/levels/level_01.tscn")
const AREAS: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]
const MATERIAL_ROLES: Array[StringName] = [
	&"fill", &"top", &"bottom", &"side_l", &"side_r", &"top_cap_l", &"top_cap_r"
]
const FLOOR_SURFACE_Y := 1152.0

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := LEVEL_SCENE.instantiate()
	get_tree().root.add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	var visuals := level.get_node_or_null("CaveVisuals") as CaveVisuals
	var tiles := level.get_node_or_null("CaveTiles") as TileMapLayer
	if visuals == null or tiles == null:
		_fail("real level lacks CaveVisuals or CaveTiles")
	else:
		_test_kits()
		_test_boundaries(visuals)
		_test_terrain(visuals, tiles)
		_test_hazards()
	_test_no_facility_override()
	level.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ENVIRONMENT_KITS=PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("ENVIRONMENT_KITS=FAIL")
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


func _fail(message: String) -> void:
	failures.append(message)


func _test_kits() -> void:
	var fills: Dictionary = {}
	for id in AREAS:
		var kit := EnvironmentKit.load_for(id)
		for role in MATERIAL_ROLES:
			if kit.texture(role) == null:
				_fail("%s kit lacks material %s" % [id, role])
		if kit.texture(&"far") == null:
			_fail("%s kit lacks far background" % id)
		if kit.mid_parallax <= kit.far_parallax:
			_fail("%s mid parallax must exceed far parallax" % id)
		if kit.texture(&"fill") != null:
			fills[kit.texture(&"fill").resource_path] = id
	if fills.size() != AREAS.size():
		_fail("areas share terrain fill textures; each area needs its own material")


func _test_boundaries(visuals: CaveVisuals) -> void:
	var samples := [0.0, 5887.0, 5888.0, 9983.0, 9984.0, 14079.0, 14080.0, 18175.0, 18176.0]
	var answers: Array[StringName] = [
		&"fringe", &"fringe", &"nexus", &"nexus", &"vaults", &"vaults", &"kiln", &"kiln", &"depths"
	]
	for index in samples.size():
		if visuals.area_for_world_x(samples[index]) != answers[index]:
			_fail("dev area boundary wrong at x=%s" % samples[index])
	if visuals.fixed_area() != &"":
		_fail("dev world must not use a fixed area")


func _test_terrain(visuals: CaveVisuals, tiles: TileMapLayer) -> void:
	var snapshot := visuals.collision_cells_snapshot()
	if snapshot.size() != tiles.get_used_cells().size():
		_fail("visual terrain collision snapshot differs from TileMap")
	if not visuals.terrain_visual_coverage_is_complete():
		_fail("terrain visual coverage incomplete")
	var faces := visuals.face_counts()
	for role in [&"top", &"bottom", &"left", &"right"]:
		if int(faces.get(role, 0)) <= 0:
			_fail("dev world has no %s faces" % role)
	if tiles.tile_set.tile_size != Vector2i(64, 64):
		_fail("collision grid is not 64 px")


func _test_hazards() -> void:
	var lava := 0
	for hazard in get_tree().get_nodes_in_group("dev_hazard"):
		var rect: Rect2 = Rect2(
			hazard.global_position - hazard.get("hazard_size") * 0.5, hazard.get("hazard_size")
		)
		if StringName(hazard.get("kind")) == &"lava_surface":
			lava += 1
			if not hazard.is_in_group(&"visual_fluid"):
				_fail("lava hazard is not registered as a visual fluid")
			if rect.position.y < FLOOR_SURFACE_Y - 1.0:
				_fail("lava sits above the floor surface instead of in a basin")
	if lava < 3:
		_fail("expected the three Kiln lava basins")


func _test_no_facility_override() -> void:
	for path in [
		"res://scripts/world/cave_visuals.gd", "res://scripts/world/cave_background_renderer.gd"
	]:
		var source := FileAccess.get_file_as_string(path)
		if source.contains("terrain/facility") or source.contains("steel_"):
			_fail("%s still draws steel-facility terrain" % path)
