extends RefCounted

## Player map pins: pure rules shared by the map screen, the painter and GameState's save
## validation. A pin is {"room": String, "x": int, "y": int, "kind": String}, with x/y a local
## cell of a discovered room. Every function returns a new array; callers hand the result to
## GameState.set_map_pins. Design: docs/features/map-pins.md.

const MAX_PINS := 12
## Cycle order when a pin is activated again.
const KINDS: Array[String] = ["return", "danger", "item"]
const MAX_CELL := 1024
const PIN_KEYS := ["room", "x", "y", "kind"]


static func index_at(pins: Array, room: String, cell: Vector2i) -> int:
	for index in pins.size():
		var pin: Dictionary = pins[index]
		if pin["room"] == room and pin["x"] == cell.x and pin["y"] == cell.y:
			return index
	return -1


## True when a new pin may go on this cell: a discovered room, inside its bounds, a free slot.
static func can_place(
	pins: Array, discovered: Array, room: String, room_size: Vector2i, cell: Vector2i
) -> bool:
	return (
		discovered.has(room)
		and pins.size() < MAX_PINS
		and Rect2i(Vector2i.ZERO, room_size).has_point(cell)
		and index_at(pins, room, cell) < 0
	)


## Place a "return" pin on a free cell, or advance the kind of the pin already there.
static func activated(
	pins: Array, discovered: Array, room: String, room_size: Vector2i, cell: Vector2i
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(pins.duplicate(true))
	var index := index_at(result, room, cell)
	if index >= 0:
		var next := (KINDS.find(String(result[index]["kind"])) + 1) % KINDS.size()
		result[index]["kind"] = KINDS[next]
	elif can_place(result, discovered, room, room_size, cell):
		result.append({"room": room, "x": cell.x, "y": cell.y, "kind": KINDS[0]})
	return result


static func removed(pins: Array, room: String, cell: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(pins.duplicate(true))
	var index := index_at(result, room, cell)
	if index >= 0:
		result.remove_at(index)
	return result


## Save-data validation: {"pins": Array[Dictionary]} with integer cells, or {} when invalid.
## Rooms must be in `discovered`; room bounds are not checked here (GameState has no room index).
static func validated(value: Variant, discovered: Array) -> Dictionary:
	if not value is Array or (value as Array).size() > MAX_PINS:
		return {}
	var pins: Array[Dictionary] = []
	for entry in value:
		if not entry is Dictionary or (entry as Dictionary).size() != PIN_KEYS.size():
			return {}
		for key in PIN_KEYS:
			if not (entry as Dictionary).has(key):
				return {}
		var room: Variant = entry["room"]
		var kind: Variant = entry["kind"]
		if not room is String or not discovered.has(room):
			return {}
		if not kind is String or not KINDS.has(kind):
			return {}
		if not _valid_cell(entry["x"]) or not _valid_cell(entry["y"]):
			return {}
		var cell := Vector2i(int(entry["x"]), int(entry["y"]))
		if index_at(pins, room, cell) >= 0:
			return {}
		pins.append({"room": room, "x": cell.x, "y": cell.y, "kind": kind})
	return {"pins": pins}


static func _valid_cell(value: Variant) -> bool:
	# JSON loads every number as float; accept only whole values in range.
	if value is int:
		return value >= 0 and value < MAX_CELL
	if value is float:
		return is_finite(value) and floorf(value) == value and value >= 0.0 and value < MAX_CELL
	return false
