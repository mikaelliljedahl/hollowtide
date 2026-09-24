extends RefCounted

## Fast travel between save shrines: pure rules shared by the campaign root, the save shrine, the
## map's travel mode and GameState's save validation. A station id is
## "<room_id>.save.<cell_x>_<cell_y>" (the shrine's layout cell), derived from the generated room
## index, so moving a shrine in a layout only forgets that one activation. Design:
## docs/features/fast-travel.md.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")

const TILE := 64.0
const MAX_STATIONS := 64
const MAX_ID_LENGTH := 160

static var _stations: Array[Dictionary] = []


static func station_id(room_id: String, feet: Vector2) -> String:
	return "%s.save.%d_%d" % [room_id, floori(feet.x / TILE), roundi(feet.y / TILE) - 1]


## Every save shrine in the campaign, ordered west to east (then top to bottom) so cycling the
## travel targets moves across the map. Each: id, room, position (local feet px), tile (world).
static func stations() -> Array[Dictionary]:
	if not _stations.is_empty():
		return _stations
	for room_id in Rooms.ROOMS:
		var data: Dictionary = Rooms.ROOMS[room_id]
		for feet in data["saves"]:
			(
				_stations
				. append(
					{
						"id": station_id(room_id, feet),
						"room": String(room_id),
						"position": feet,
						"tile": Vector2(data["origin"]) + feet / TILE,
					}
				)
			)
	_stations.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["tile"].x != b["tile"].x:
				return a["tile"].x < b["tile"].x
			return a["tile"].y < b["tile"].y
	)
	return _stations


## The station with this id, or {} when the index has no such shrine.
static func station(id: String) -> Dictionary:
	for entry in stations():
		if entry["id"] == id:
			return entry
	return {}


## The shrine in `room_id` whose feet anchor is within `radius` px of `local`, or "".
static func station_near(room_id: String, local: Vector2, radius := TILE) -> String:
	for entry in stations():
		if entry["room"] == room_id and (entry["position"] as Vector2).distance_to(local) <= radius:
			return entry["id"]
	return ""


## Stations the player can travel to from `from_id`: activated, known to the index, not `from_id`.
## Empty when `from_id` itself is not activated.
static func targets(activated: Array, from_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not activated.has(from_id):
		return result
	for entry in stations():
		if entry["id"] != from_id and activated.has(entry["id"]):
			result.append(entry)
	return result


static func can_travel(activated: Array, from_id: String, to_id: String) -> bool:
	return targets(activated, from_id).any(
		func(entry: Dictionary) -> bool: return entry["id"] == to_id
	)


## Save-data validation: {"stations": Array[String]} or {} when invalid. Ids must have the
## station format and be unique; ids the room index no longer knows are kept (a layout edit must
## not reject a save) and simply never become travel targets.
static func validated(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).size() > MAX_STATIONS:
		return {}
	var ids: Array[String] = []
	for entry in value:
		if not entry is String or not _valid_id(entry) or ids.has(entry):
			return {}
		ids.append(entry)
	return {"stations": ids}


static func _valid_id(id: String) -> bool:
	if id.length() > MAX_ID_LENGTH:
		return false
	var parts := id.split(".save.")
	if parts.size() != 2 or parts[0].is_empty():
		return false
	var cell := parts[1].split("_")
	return cell.size() == 2 and cell[0].is_valid_int() and cell[1].is_valid_int()
