extends RefCounted

## Pure data side of the campaign map and minimap. Everything the map shows is derived from the
## generated room index plus GameState (discovered rooms, collected pickups, world flags), so the
## save needs no extra keys: entering a room reveals its layout, its door openings and the items in
## it. Neighbours behind those doors are "known but unexplored" and only ever shown as a frame.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const AREAS: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]
const FINAL_GATE_PREFIX := "regional:"

static var _geometry: Dictionary = {}


## Local-tile geometry of one room: merged air rectangles, wall edge segments (pairs of points),
## gate cells and lava cells. Cached; the index is constant.
static func geometry(room_id: String) -> Dictionary:
	if _geometry.has(room_id):
		return _geometry[room_id]
	var result := {"air": [], "walls": PackedVector2Array(), "gates": [], "lava": []}
	if not Rooms.ROOMS.has(room_id):
		return result
	var data: Dictionary = Rooms.ROOMS[room_id]
	var mask: Array = data.get("map_mask", [])
	if mask.is_empty():
		# Older index without silhouettes: the whole room is one open box.
		var size := Vector2(data["size"])
		result["air"] = [Rect2(Vector2.ZERO, size)]
		result["walls"] = PackedVector2Array(
			[
				Vector2.ZERO,
				Vector2(size.x, 0),
				Vector2(size.x, 0),
				size,
				size,
				Vector2(0, size.y),
				Vector2(0, size.y),
				Vector2.ZERO
			]
		)
		_geometry[room_id] = result
		return result
	result["air"] = _merged_rects(mask, ".g~")
	result["gates"] = _merged_rects(mask, "g")
	result["lava"] = _merged_rects(mask, "~")
	result["walls"] = _wall_segments(mask)
	_geometry[room_id] = result
	return result


static func is_flag_open(flag: String) -> bool:
	if flag.is_empty():
		return true
	for part in flag.split(",", false):
		if not GameState.has_world_flag(part):
			return false
	return true


## Every door of a discovered room that leads into a room not yet entered.
## Each entry: room, target, edge, from, to (local cells), gate (kind or &""), blocked (bool).
static func unexplored_exits(discovered: Array) -> Array[Dictionary]:
	var exits: Array[Dictionary] = []
	for room_id in discovered:
		if not Rooms.ROOMS.has(room_id):
			continue
		for door in Rooms.ROOMS[room_id]["doors"]:
			var target := String(door["target"])
			if discovered.has(target):
				continue
			var gate := StringName(door.get("gate", &""))
			var blocked := gate != &"" and not is_flag_open(String(door.get("gate_flag", "")))
			(
				exits
				. append(
					{
						"room": String(room_id),
						"target": target,
						"edge": door["edge"],
						"from": door["from"],
						"to": door["to"],
						"gate": gate if blocked else &"",
						"blocked": blocked,
					}
				)
			)
	return exits


## Rooms seen through a door but never entered (drawn as a faint frame only).
static func ghost_rooms(discovered: Array) -> Array[String]:
	var result: Array[String] = []
	for exit in unexplored_exits(discovered):
		if not result.has(exit["target"]):
			result.append(exit["target"])
	return result


## Uncollected pickups inside discovered rooms: room, id, kind, cell.
static func seen_pickups(discovered: Array, collected: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room_id in discovered:
		if not Rooms.ROOMS.has(room_id):
			continue
		for pickup in Rooms.ROOMS[room_id].get("pickups", []):
			if collected.has(pickup["id"]):
				continue
			result.append(
				{
					"room": String(room_id),
					"id": pickup["id"],
					"kind": pickup["kind"],
					"cell": pickup["cell"]
				}
			)
	return result


## Unopened gates in discovered rooms: room, kind, flag, cell, size. Boss markers use kind boss
## and stay listed after the fight with defeated = true.
static func gate_markers(discovered: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room_id in discovered:
		if not Rooms.ROOMS.has(room_id):
			continue
		for gate in Rooms.ROOMS[room_id]["gates"]:
			var open := is_flag_open(gate["flag"])
			if gate["kind"] != &"boss" and open:
				continue
			(
				result
				. append(
					{
						"room": String(room_id),
						"kind": gate["kind"],
						"flag": gate["flag"],
						"cell": gate["cell"],
						"size": gate["size"],
						"final": String(gate["flag"]).begins_with(FINAL_GATE_PREFIX),
						"defeated": gate["kind"] == &"boss" and open,
					}
				)
			)
	return result


## Seals met for the final gate flag list ("regional:a,regional:b").
static func seal_progress(flag: String) -> Vector2i:
	var parts := flag.split(",", false)
	var met := 0
	for part in parts:
		if GameState.has_world_flag(part):
			met += 1
	return Vector2i(met, parts.size())


## area -> Vector2i(visited, total).
static func area_progress(discovered: Array) -> Dictionary:
	var result := {}
	for area in AREAS:
		result[area] = Vector2i.ZERO
	for room_id in Rooms.ROOMS:
		var area: StringName = Rooms.ROOMS[room_id]["area"]
		var value: Vector2i = result.get(area, Vector2i.ZERO)
		value.y += 1
		if discovered.has(room_id):
			value.x += 1
		result[area] = value
	return result


## World-tile bounds of the given rooms.
static func bounds_of(room_ids: Array) -> Rect2:
	var bounds := Rect2()
	var first := true
	for room_id in room_ids:
		if not Rooms.ROOMS.has(room_id):
			continue
		var data: Dictionary = Rooms.ROOMS[room_id]
		var rect := Rect2(Vector2(data["origin"]), Vector2(data["size"]))
		bounds = rect if first else bounds.merge(rect)
		first = false
	return bounds


static func _merged_rects(mask: Array, chars: String) -> Array:
	# Horizontal runs per row, merged downwards while the run below is identical.
	var open: Dictionary = {}
	var rects: Array = []
	for y in mask.size():
		var row := String(mask[y])
		var runs: Array[Vector2i] = []
		var x := 0
		while x < row.length():
			if chars.contains(row[x]):
				var start := x
				while x < row.length() and chars.contains(row[x]):
					x += 1
				runs.append(Vector2i(start, x - start))
			else:
				x += 1
		var next_open: Dictionary = {}
		for run in runs:
			if open.has(run):
				var rect: Rect2 = open[run]
				rect.size.y += 1
				next_open[run] = rect
				open.erase(run)
			else:
				next_open[run] = Rect2(run.x, y, run.y, 1)
		for run in open:
			rects.append(open[run])
		open = next_open
	for run in open:
		rects.append(open[run])
	return rects


static func _wall_segments(mask: Array) -> PackedVector2Array:
	# Edges between open cells and rock (inside the room). Open cells on the room boundary are
	# door openings and get no edge. Collinear unit edges are joined into long segments.
	var height := mask.size()
	var width := String(mask[0]).length() if height > 0 else 0
	var segments := PackedVector2Array()
	# Horizontal edges: between row y-1 and y.
	for y in range(1, height):
		var above := String(mask[y - 1])
		var below := String(mask[y])
		var start := -1
		var kind := 0
		for x in width + 1:
			var edge := 0
			if x < width:
				var rock_above := above[x] == "#"
				var rock_below := below[x] == "#"
				if rock_above != rock_below:
					edge = 1 if rock_above else 2
			if edge != kind:
				if kind != 0:
					segments.append(Vector2(start, y))
					segments.append(Vector2(x, y))
				start = x
				kind = edge
	# Vertical edges: between column x-1 and x.
	for x in range(1, width):
		var start := -1
		var kind := 0
		for y in height + 1:
			var edge := 0
			if y < height:
				var row := String(mask[y])
				var rock_left := row[x - 1] == "#"
				var rock_right := row[x] == "#"
				if rock_left != rock_right:
					edge = 1 if rock_left else 2
			if edge != kind:
				if kind != 0:
					segments.append(Vector2(x, start))
					segments.append(Vector2(x, y))
				start = y
				kind = edge
	return segments
