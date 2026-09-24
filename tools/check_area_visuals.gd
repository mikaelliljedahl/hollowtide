extends Node
## Env check: CaveVisuals renders arbitrary campaign-style rooms with set_fixed_area().
## Headless: asserts API behaviour. Windowed with --out=<dir>: also saves one PNG per area.

const AREAS: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]
const ROOM := Vector2i(44, 26)

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_dir = argument.trim_prefix("--out=")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for area in AREAS:
		var room := Node2D.new()
		viewport.add_child(room)
		var tiles := _build_room()
		room.add_child(tiles)
		var visuals := CaveVisuals.new()
		room.add_child(visuals)
		visuals.set_fixed_area(area)
		visuals.configure(tiles)
		var camera := Camera2D.new()
		camera.position = Vector2(ROOM) * 64.0 * Vector2(0.5, 0.6)
		camera.zoom = Vector2.ONE * 0.62
		room.add_child(camera)
		camera.make_current()
		for frame in 4:
			await get_tree().process_frame
		_check(visuals.fixed_area() == area, "%s: fixed area not stored" % area)
		_check(visuals.area_for_world_x(99999.0) == area, "%s: world-x boundary leaks" % area)
		_check(
			visuals.get_loaded_kit_ids() == [area],
			"%s: loaded kits %s" % [area, visuals.get_loaded_kit_ids()]
		)
		_check(
			visuals.terrain_visual_coverage_is_complete(), "%s: terrain coverage incomplete" % area
		)
		var faces := visuals.face_counts()
		for role in [&"top", &"bottom", &"left", &"right"]:
			_check(int(faces.get(role, 0)) > 0, "%s: no %s faces" % [area, role])
		_check(
			visuals.collision_cells_snapshot().size() == tiles.get_used_cells().size(),
			"%s: collision snapshot mismatch" % area
		)
		if out_dir != "" and DisplayServer.get_name() != "headless":
			for frame in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(out_dir)
			viewport.get_texture().get_image().save_png("%s/room_%s.png" % [out_dir, area])
		room.queue_free()
		await get_tree().process_frame
	if failures.is_empty():
		print("AREA_VISUALS=PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("AREA_VISUALS=FAIL")
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("shutdown"):
		await audio.call("shutdown")
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _build_room() -> TileMapLayer:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(64, 64)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/sprites/tileset_cave.png") as Texture2D
	source.texture_region_size = Vector2i(64, 64)
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, 0)
	var tiles := TileMapLayer.new()
	tiles.tile_set = tile_set
	var solid := func(x: int, y: int) -> void: tiles.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	for x in ROOM.x:
		for y in 2:
			solid.call(x, y)
			solid.call(x, ROOM.y - 1 - y)
	for y in ROOM.y:
		for x in 2:
			solid.call(x, y)
			solid.call(ROOM.x - 1 - x, y)
	# Door gap in the left wall, a raised ledge, a thin platform, a 1-high slipstream tunnel,
	# a pillar, a 1-wide shaft and a stepped slope.
	for y in range(ROOM.y - 6, ROOM.y - 2):
		tiles.erase_cell(Vector2i(0, y))
		tiles.erase_cell(Vector2i(1, y))
	for x in range(6, 14):
		solid.call(x, 17)
	for x in range(18, 24):
		solid.call(x, 12)
	for x in range(26, 38):
		solid.call(x, ROOM.y - 3)
		solid.call(x, ROOM.y - 5)
	for x in range(26, 38):
		for y in range(ROOM.y - 9, ROOM.y - 5):
			solid.call(x, y)
	for y in range(2, 10):
		solid.call(30, y)
		solid.call(32, y)
	for step in 4:
		for x in range(38 + step, 42):
			solid.call(x, ROOM.y - 3 - step)
	return tiles
