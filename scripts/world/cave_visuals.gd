class_name CaveVisuals
extends Node2D
## Draws natural per-area terrain over a 64 px collision TileMapLayer and owns the parallax
## background renderer. Collision stays in the TileMap; everything here is visual only.
##
## Dev world: area follows world-x boundaries. Campaign rooms call set_fixed_area() so one area kit
## covers the whole TileMap regardless of position or size.

const TILE_SIZE := 64.0
const CHUNK_CELLS := 16
const BOUNDARIES: Array[float] = [5888.0, 9984.0, 14080.0, 18176.0]
const KIT_IDS: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]
## Dev world only: every empty cell at or below this row is treated as bedrock so nothing but rock
## shows under the station floors (row 18) and basins.
const DEV_BEDROCK_ROW := 19
const EXTERIOR_MARGIN := 24
const PROP_SCALE := 0.6
const AMBIENCE_SCRIPT = preload("res://scripts/world/environment_ambience.gd")
const BACKGROUND_RENDERER_SCRIPT = preload("res://scripts/world/cave_background_renderer.gd")
const LAYERS: Array[StringName] = [&"fill", &"shade", &"props", &"bottom", &"side", &"top"]

var _tiles: TileMapLayer
var _cells: Dictionary[Vector2i, bool] = {}
var _collision_snapshot: Array[Vector2i] = []
var _used := Rect2i()
var _fixed_area: StringName = &""
var _kits: Dictionary[StringName, EnvironmentKit] = {}
var _loaded_ids: Array[StringName] = []
var _camera_rect := Rect2()
var _last_camera_center := Vector2.INF
var _ambient: EnvironmentAmbience
var _background_renderer: CaveBackgroundRenderer
var _layer_nodes: Dictionary[StringName, Node2D] = {}
var _chunks: Dictionary = {}
var _fluid_rects: Array[Rect2] = []
var _face_counts: Dictionary[StringName, int] = {}
var _collision_overlay := false
var _rebuild_pending := false
var _last_prop: Texture2D


class DrawChunk:
	extends Node2D
	var commands: Array = []

	func _draw() -> void:
		for command in commands:
			draw_texture_rect_region(command[0], command[1], command[2], command[3])


# ------------------------------------------------------------------ public API


func configure(tiles: TileMapLayer) -> void:
	_tiles = tiles
	if _tiles.has_signal("changed"):
		var changed := Callable(self, "_on_tiles_changed")
		if not _tiles.is_connected("changed", changed):
			_tiles.connect("changed", changed)
	_tiles.self_modulate = Color(1, 1, 1, 0)
	z_index = -5
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rebuild()


## Forces one area kit for the whole TileMap (campaign rooms). Disables world-x area boundaries.
func set_fixed_area(area_id: StringName) -> void:
	if area_id not in KIT_IDS:
		push_warning("CaveVisuals.set_fixed_area: unknown area %s" % area_id)
		return
	if _fixed_area == area_id:
		return
	_fixed_area = area_id
	if _tiles != null:
		_rebuild()


func fixed_area() -> StringName:
	return _fixed_area


func area_for_world_x(world_x: float) -> StringName:
	if _fixed_area != &"":
		return _fixed_area
	for index in BOUNDARIES.size():
		if world_x < BOUNDARIES[index]:
			return KIT_IDS[index]
	return KIT_IDS.back()


func get_loaded_kit_ids() -> Array[StringName]:
	return _loaded_ids.duplicate()


func loaded_kit_ids() -> Array[StringName]:
	return get_loaded_kit_ids()


func collision_cells_snapshot() -> Array[Vector2i]:
	return _collision_snapshot.duplicate()


func face_counts() -> Dictionary:
	return _face_counts.duplicate()


func terrain_visual_coverage_is_complete() -> bool:
	for cell in _cells:
		var kit := _kit(_area_for_cell(cell))
		if kit == null or kit.texture(&"fill") == null:
			return false
	return true


func set_test_camera_center(world_x: float) -> void:
	set_test_camera_position(Vector2(world_x, 540.0))


func set_test_camera_position(center: Vector2) -> void:
	_camera_rect = Rect2(center - Vector2(960.0, 540.0), Vector2(1920.0, 1080.0))
	_update_background_kits()
	_sync_ambient()
	_ensure_background_renderer()
	_sync_background_renderer()


func set_collision_overlay(enabled: bool) -> void:
	_collision_overlay = enabled
	queue_redraw()


# ------------------------------------------------------------------ lifecycle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"cave_visuals")


func _on_tiles_changed() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_pending = false
	if _tiles != null and is_instance_valid(_tiles):
		_rebuild()


func _process(_delta: float) -> void:
	var current := _camera_center()
	if current.distance_to(_last_camera_center) < 0.01:
		return
	_last_camera_center = current
	_camera_rect = _visible_rect()
	_update_background_kits()
	_sync_ambient()
	_ensure_background_renderer()
	_sync_background_renderer()


func _camera_center() -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	return Vector2(_used.get_center()) * TILE_SIZE


func _visible_rect() -> Rect2:
	var camera := get_viewport().get_camera_2d()
	var size := get_viewport_rect().size
	if camera != null:
		size /= camera.zoom
	return Rect2(_camera_center() - size * 0.5, size)


func _draw() -> void:
	if not _collision_overlay or _tiles == null:
		return
	for cell in _cells:
		draw_rect(_cell_rect(cell), Color(1.0, 0.25, 0.1, 0.85), false, 2.0)


# ------------------------------------------------------------------ kits


func _kit(id: StringName) -> EnvironmentKit:
	var kit: EnvironmentKit = _kits.get(id)
	if kit == null:
		kit = EnvironmentKit.load_for(id)
		_kits[id] = kit
	return kit


func _area_for_cell(cell: Vector2i) -> StringName:
	return area_for_world_x(_tiles.to_global(Vector2(cell) * TILE_SIZE).x + TILE_SIZE * 0.5)


func _update_background_kits() -> void:
	var wanted: Array[StringName] = []
	if _fixed_area != &"":
		wanted.append(_fixed_area)
	else:
		var index := KIT_IDS.find(area_for_world_x(_camera_rect.get_center().x))
		for neighbor in range(maxi(index - 1, 0), mini(index + 2, KIT_IDS.size())):
			wanted.append(KIT_IDS[neighbor])
	for id in wanted:
		_kit(id)
	_loaded_ids = wanted


func _ensure_background_renderer() -> void:
	if is_instance_valid(_background_renderer):
		return
	_background_renderer = BACKGROUND_RENDERER_SCRIPT.new() as CaveBackgroundRenderer
	_background_renderer.name = "BackgroundRenderer"
	add_child(_background_renderer)
	move_child(_background_renderer, 0)
	_background_renderer.configure()


func _sync_background_renderer() -> void:
	if _background_renderer == null:
		return
	var kits: Dictionary = {}
	for id in _loaded_ids:
		kits[id] = _kit(id)
	var room := Rect2(Vector2(_used.position) * TILE_SIZE, Vector2(_used.size) * TILE_SIZE)
	if _tiles != null:
		room.position = _tiles.to_global(room.position)
	_background_renderer.sync(_camera_rect, kits, _fixed_area, room)


func _sync_ambient() -> void:
	if _fixed_area != &"":
		return
	var current := area_for_world_x(_camera_rect.get_center().x)
	if current == &"nexus":
		if _ambient == null or not is_instance_valid(_ambient):
			_ambient = AMBIENCE_SCRIPT.new() as EnvironmentAmbience
			if _ambient != null:
				_ambient.name = "NexusWaterAmbient"
				add_child(_ambient)
				_ambient.configure(&"water_loop", Vector2(7936.0, 640.0))
	elif _ambient != null:
		_ambient.queue_free()
		_ambient = null


# ------------------------------------------------------------------ topology


func _is_solid(cell: Vector2i) -> bool:
	# Outside the TileMap the boundary is extruded: closed walls continue as rock, while openings
	# on the edge (doorways, shafts leaving the room) continue as open passage.
	if not _used.has_point(cell):
		cell = Vector2i(
			clampi(cell.x, _used.position.x, _used.end.x - 1),
			clampi(cell.y, _used.position.y, _used.end.y - 1)
		)
	if _cells.has(cell):
		return true
	return _fixed_area == &"" and cell.y >= DEV_BEDROCK_ROW


func _rebuild() -> void:
	_cells.clear()
	_collision_snapshot.clear()
	for cell in _tiles.get_used_cells():
		_cells[cell] = true
		_collision_snapshot.append(cell)
	_collision_snapshot.sort()
	_used = _tiles.get_used_rect()
	_collect_fluids()
	for layer in _layer_nodes.values():
		layer.queue_free()
	_layer_nodes.clear()
	_chunks.clear()
	_face_counts.clear()
	for layer in LAYERS:
		var node := Node2D.new()
		node.name = "Terrain_" + String(layer)
		add_child(node)
		_layer_nodes[layer] = node
	_camera_rect = _visible_rect()
	_update_background_kits()
	_ensure_background_renderer()
	_build_fill()
	_build_shade()
	_build_faces()
	for key in _chunks:
		(_chunks[key] as DrawChunk).queue_redraw()
	_sync_ambient()
	_sync_background_renderer()
	queue_redraw()


func _collect_fluids() -> void:
	# Stepping stones inside fluid basins get a visual rock pillar down into the fluid.
	_fluid_rects.clear()
	for node in get_tree().get_nodes_in_group(&"visual_fluid"):
		if node is Node2D and node.has_method("fluid_rect"):
			_fluid_rects.append(node.call("fluid_rect"))


func _chunk(layer: StringName, cell: Vector2i) -> DrawChunk:
	var key := Vector3i(
		floori(float(cell.x) / CHUNK_CELLS), floori(float(cell.y) / CHUNK_CELLS), LAYERS.find(layer)
	)
	var chunk: DrawChunk = _chunks.get(key)
	if chunk == null:
		chunk = DrawChunk.new()
		chunk.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		chunk.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_layer_nodes[layer].add_child(chunk)
		_chunks[key] = chunk
	return chunk


func _emit(
	layer: StringName,
	cell: Vector2i,
	texture: Texture2D,
	dest: Rect2,
	src: Rect2,
	color := Color.WHITE
) -> void:
	if texture == null:
		return
	_chunk(layer, cell).commands.append([texture, dest, src, color])


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_tiles.to_global(Vector2(cell) * TILE_SIZE), Vector2.ONE * TILE_SIZE)


func _fill_color(kit: EnvironmentKit) -> Color:
	return Color(kit.tint.r, kit.tint.g, kit.tint.b, 1.0)


func _build_fill() -> void:
	# Horizontal runs of solid cells (including exterior/bedrock margin) split per chunk and area.
	var area := _used.grow(EXTERIOR_MARGIN)
	for y in range(area.position.y, area.end.y):
		var run_start := -1
		var run_area: StringName = &""
		for x in range(area.position.x, area.end.x + 1):
			var cell := Vector2i(x, y)
			var solid := x < area.end.x and _is_solid(cell)
			var cell_area: StringName = _area_for_cell(cell) if solid else &""
			var chunk_break := run_start >= 0 and posmod(x, CHUNK_CELLS) == 0
			if run_start >= 0 and (not solid or cell_area != run_area or chunk_break):
				_emit_fill_run(Vector2i(run_start, y), x - run_start, run_area)
				run_start = -1
			if solid and run_start < 0:
				run_start = x
				run_area = cell_area


func _emit_fill_run(first: Vector2i, count: int, area_id: StringName) -> void:
	var kit := _kit(area_id)
	var fill := kit.texture(&"fill")
	var dest := _cell_rect(first)
	dest.size.x = TILE_SIZE * count
	# Overlap by half a pixel to avoid hairline seams between runs under linear filtering.
	dest = dest.grow(0.5)
	_emit(&"fill", first, fill, dest, dest, _fill_color(kit))


func _build_shade() -> void:
	# Distance-to-air per solid cell, stored in a tiny image and drawn scaled with linear filtering.
	# Deep rock darkens smoothly so exposed faces read as the lit surface of a solid mass.
	var area := _used.grow(EXTERIOR_MARGIN)
	var size := area.size
	var distance := PackedInt32Array()
	distance.resize(size.x * size.y)
	var queue: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var cell := area.position + Vector2i(x, y)
			if _is_solid(cell):
				distance[y * size.x + x] = 99
			else:
				distance[y * size.x + x] = 0
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var next_distance := distance[current.y * size.x + current.x] + 1
		for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor := current + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.y:
				continue
			var index := neighbor.y * size.x + neighbor.x
			if distance[index] > next_distance:
				distance[index] = next_distance
				queue.append(neighbor)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var depth := distance[y * size.x + x]
			var alpha := 0.0
			if depth >= 2:
				alpha = clampf(0.22 + 0.14 * float(depth - 2), 0.0, 0.62)
			image.set_pixel(x, y, Color(0.0, 0.0, 0.02, alpha))
	var texture := ImageTexture.create_from_image(image)
	var node := Sprite2D.new()
	node.name = "DepthShade"
	node.texture = texture
	node.centered = false
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.scale = Vector2.ONE * TILE_SIZE
	node.global_position = _tiles.to_global(Vector2(area.position) * TILE_SIZE)
	_layer_nodes[&"shade"].add_child(node)


func _clearance(cell: Vector2i, step: Vector2i) -> int:
	var count := 0
	var probe := cell
	while count < 4 and not _is_solid(probe):
		count += 1
		probe += step
	return count


func _build_faces() -> void:
	var tops: Dictionary = {}
	var bottoms: Dictionary = {}
	var lefts: Dictionary = {}
	var rights: Dictionary = {}
	var area := _used.grow(1)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var air := Vector2i(x, y)
			if _is_solid(air):
				continue
			if _is_solid(air + Vector2i.DOWN):
				tops[air + Vector2i.DOWN] = _clearance(air, Vector2i.UP)
			if _is_solid(air + Vector2i.UP):
				bottoms[air + Vector2i.UP] = _clearance(air, Vector2i.DOWN)
			if _is_solid(air + Vector2i.LEFT):
				rights[air + Vector2i.LEFT] = _clearance(air, Vector2i.RIGHT)
			if _is_solid(air + Vector2i.RIGHT):
				lefts[air + Vector2i.RIGHT] = _clearance(air, Vector2i.LEFT)
	_face_counts = {
		&"top": tops.size(),
		&"bottom": bottoms.size(),
		&"left": lefts.size(),
		&"right": rights.size()
	}
	_build_fluid_pillars()
	for cell: Vector2i in bottoms:
		_emit_bottom(cell, bottoms[cell])
	for cell: Vector2i in lefts:
		_emit_side(cell, lefts[cell], true)
	for cell: Vector2i in rights:
		_emit_side(cell, rights[cell], false)
	for cell: Vector2i in tops:
		_emit_top(cell, tops[cell])
	_build_props(tops, bottoms)


func _emit_top(cell: Vector2i, clearance: int) -> void:
	var kit := _kit(_area_for_cell(cell))
	var texture := kit.texture(&"top")
	if texture == null:
		return
	var line := kit.strip_value("top_line", 32.0)
	var height := kit.strip_value("top_height", 128.0)
	var rect := _cell_rect(cell)
	# Tufts may rise above the walk line only where there is headroom; slipstream tunnels stay clear.
	var rise := line if clearance >= 2 else 6.0
	# The lip body must not hang below the collision of thin platforms (visual rock = real rock).
	var body := height - line
	if not _is_solid(cell + Vector2i.DOWN):
		body = minf(body, TILE_SIZE + 22.0)
	var dest := Rect2(rect.position.x, rect.position.y - rise, TILE_SIZE, body + rise)
	var src := Rect2(rect.position.x, line - rise, TILE_SIZE, dest.size.y)
	var color := Color(1, 1, 1)
	_emit(&"top", cell, texture, dest, src, color)
	var cap_width := kit.strip_value("cap_width", 32.0)
	for side in [-1, 1]:
		var neighbor := cell + Vector2i(side, 0)
		if _is_solid(neighbor) or _is_solid(neighbor + Vector2i.UP):
			continue
		var cap := kit.texture(&"top_cap_l" if side < 0 else &"top_cap_r")
		var cap_x := rect.position.x - cap_width if side < 0 else rect.end.x
		_emit(
			&"top",
			cell,
			cap,
			Rect2(cap_x, dest.position.y, cap_width, dest.size.y),
			Rect2(0, src.position.y, cap_width, src.size.y),
			color
		)


func _emit_bottom(cell: Vector2i, clearance: int) -> void:
	var kit := _kit(_area_for_cell(cell))
	var texture := kit.texture(&"bottom")
	if texture == null:
		return
	var line := kit.strip_value("bottom_line", 48.0)
	var height := kit.strip_value("bottom_height", 160.0)
	var hang := height - line
	if clearance <= 1:
		hang = 6.0
	elif clearance == 2:
		hang = minf(hang, 40.0)
	elif clearance == 3:
		hang = minf(hang, 80.0)
	var rect := _cell_rect(cell)
	var dest := Rect2(rect.position.x, rect.end.y - line, TILE_SIZE, line + hang)
	var src := Rect2(rect.position.x, 0, TILE_SIZE, line + hang)
	_emit(&"bottom", cell, texture, dest, src)
	var cap_width := kit.strip_value("cap_width", 32.0)
	for side in [-1, 1]:
		var neighbor := cell + Vector2i(side, 0)
		if _is_solid(neighbor) or _is_solid(neighbor + Vector2i.DOWN):
			continue
		var cap := kit.texture(&"bottom_cap_l" if side < 0 else &"bottom_cap_r")
		var cap_x := rect.position.x - cap_width if side < 0 else rect.end.x
		_emit(
			&"bottom",
			cell,
			cap,
			Rect2(cap_x, dest.position.y, cap_width, dest.size.y),
			Rect2(0, 0, cap_width, dest.size.y)
		)


func _emit_side(cell: Vector2i, clearance: int, faces_left: bool) -> void:
	var kit := _kit(_area_for_cell(cell))
	var texture := kit.texture(&"side_l" if faces_left else &"side_r")
	if texture == null:
		return
	var width := kit.strip_value("side_width", 128.0)
	var line := kit.strip_value("side_line", 96.0)
	var protrude := width - line if clearance >= 2 else 6.0
	# The strip's rock mass must not spill out of the far side of thin walls/pillars.
	var inward := Vector2i.RIGHT if faces_left else Vector2i.LEFT
	var depth := 1
	while depth < 2 and _is_solid(cell + inward * depth):
		depth += 1
	var mass := minf(line, float(depth) * TILE_SIZE - (0.0 if depth >= 2 else 20.0))
	var rect := _cell_rect(cell)
	var dest := Rect2()
	var src := Rect2()
	if faces_left:
		# Mirrored strip: face line sits at (width - line) from the texture's left edge.
		var face_in_texture := width - line
		dest = Rect2(rect.position.x - protrude, rect.position.y, protrude + mass, TILE_SIZE)
		# Offset the vertical phase so facing walls of a narrow shaft do not mirror each other.
		src = Rect2(face_in_texture - protrude, rect.position.y + 371.0, dest.size.x, TILE_SIZE)
	else:
		dest = Rect2(rect.end.x - mass, rect.position.y, mass + protrude, TILE_SIZE)
		src = Rect2(line - mass, rect.position.y, dest.size.x, TILE_SIZE)
	_emit(&"side", cell, texture, dest, src)


func _build_fluid_pillars() -> void:
	for fluid in _fluid_rects:
		var first := Vector2i((fluid.position / TILE_SIZE).floor())
		var last := Vector2i(((fluid.end - Vector2.ONE) / TILE_SIZE).floor())
		for x in range(first.x - 1, last.x + 2):
			# A solid cell directly above the fluid (stepping stone) gets rock down into the basin.
			var above := Vector2i(x, first.y - 1)
			if not _cells.has(above):
				continue
			var kit := _kit(_area_for_cell(above))
			var rect := _cell_rect(above)
			var dest := Rect2(
				rect.position.x + 6, rect.end.y, TILE_SIZE - 12, fluid.end.y - rect.end.y
			)
			_emit(&"side", above, kit.texture(&"fill"), dest, dest, _fill_color(kit).darkened(0.25))


func _build_props(tops: Dictionary, bottoms: Dictionary) -> void:
	# Sparse decor: only on long open runs, never near gameplay objects (pickups, gates, pads,
	# hazards, doors) so decoration can not be mistaken for something interactive.
	var blocked := _gameplay_rects()
	var placed: Array[Rect2] = []
	var top_cells: Array = tops.keys()
	top_cells.sort()
	for cell: Vector2i in top_cells:
		if tops[cell] < 4 or _stable_hash(cell, 3) % _prop_rate() != 0:
			continue
		_try_prop(cell, &"stand", tops, blocked, placed)
	var bottom_cells: Array = bottoms.keys()
	bottom_cells.sort()
	for cell: Vector2i in bottom_cells:
		if bottoms[cell] < 5 or _stable_hash(cell, 7) % _prop_rate() != 0:
			continue
		_try_prop(cell, &"hang", bottoms, blocked, placed)


func _prop_rate() -> int:
	# Campaign rooms are compact and hand-built, so they get a denser dressing than the long dev
	# corridors; spacing and the gameplay keep-out still limit the final count.
	return 3 if _fixed_area != &"" else 5


func _gameplay_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for fluid in _fluid_rects:
		rects.append(fluid.grow(96.0))
	if _fixed_area != &"":
		# Room exits: openings on the room boundary stay clear so doorways read as paths.
		for y in range(_used.position.y, _used.end.y):
			for x in range(_used.position.x, _used.end.x):
				var edge := (
					x == _used.position.x
					or y == _used.position.y
					or x == _used.end.x - 1
					or y == _used.end.y - 1
				)
				if edge and not _cells.has(Vector2i(x, y)):
					rects.append(_cell_rect(Vector2i(x, y)).grow(TILE_SIZE * 3.0))
	var root := get_parent()
	if root == null:
		return rects
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node == _tiles or node is CharacterBody2D or node is TileMapLayer:
			continue
		if node is CollisionObject2D or node.is_in_group(&"dev_passage"):
			var center := (node as Node2D).global_position
			rects.append(Rect2(center - Vector2(220, 220), Vector2(440, 440)))
	return rects


func _try_prop(
	cell: Vector2i, kind: StringName, faces: Dictionary, blocked: Array[Rect2], placed: Array[Rect2]
) -> void:
	var kit := _kit(_area_for_cell(cell))
	var candidates: Array[Texture2D] = []
	for prop in kit.props:
		if prop["kind"] == kind:
			candidates.append(prop["texture"])
	if candidates.is_empty():
		return
	var pick := _stable_hash(cell, 11) % candidates.size()
	if candidates.size() > 1 and candidates[pick] == _last_prop:
		# Neighbouring props should not be identical copies.
		pick = (pick + 1) % candidates.size()
	var texture := candidates[pick]
	var max_height := 190.0 if kind == &"stand" else 250.0
	var scale := minf(PROP_SCALE, max_height / float(texture.get_height()))
	var size := Vector2(texture.get_size()) * scale
	var rect := _cell_rect(cell)
	# The prop's footprint must lie on a continuous face of the same kind.
	var half_cells := ceili(size.x * 0.5 / TILE_SIZE)
	for offset in range(-half_cells, half_cells + 1):
		if not faces.has(cell + Vector2i(offset, 0)):
			return
	var center_x := rect.get_center().x
	var dest := Rect2()
	if kind == &"stand":
		dest = Rect2(center_x - size.x * 0.5, rect.position.y + 14.0 - size.y, size.x, size.y)
	else:
		dest = Rect2(center_x - size.x * 0.5, rect.end.y - 14.0, size.x, size.y)
	for other in blocked:
		if other.intersects(dest):
			return
	for other in placed:
		if other.grow(160.0).intersects(dest):
			return
	placed.append(dest)
	_last_prop = texture
	var src := Rect2(Vector2.ZERO, texture.get_size())
	_emit(&"props", cell, texture, dest, src, Color(0.82, 0.82, 0.86))


func _stable_hash(cell: Vector2i, salt: int) -> int:
	var value := (cell.x * 92837111) ^ (cell.y * 689287499) ^ (salt * 283923481)
	value = value ^ (value >> 13)
	return absi(value)
