extends RefCounted
## Campaign route planner for the playtest agent (harness:
## docs/features/playtest-agent.md). Reads the route that tools/playtest/campaign_route.py plans with the campaign graph
## solver: objectives in progression order, and per objective a flow field over the solver's
## movement graph. From the live GameState it picks the current objective, routes between rooms
## over the door graph and answers "where next from this cell". It only sets goals; the policy
## chooses the moves. Read-only: it never changes game state.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const TILE := 64.0
const FORMAT := 1
## The ability that opens each ability gate kind (GATE_NEEDS in tools/check_campaign_graph.py).
const GATE_ABILITY := {
	"missile": "missiles", "bomb": "bombs", "wave": "wave_beam", "undertow": "undertow_dash"
}
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const OBJECTIVE_NAMES := {
	"slipstream": "the Slipstream",
	"beam": "the Seed Crossbow",
	"missiles": "a Bolt Quiver",
	"energy_tank": "an energy tank",
	"long_beam": "the Long Beam",
	"tide_socket": "a Tide Socket",
	"bombs": "the Resonance Pulse",
	"ice_beam": "the Bubble Snare",
	"high_jump": "the Updraft Cloak",
	"pressure_seal": "the Pressure Seal",
	"wave_beam": "the Echo Shot",
	"undertow_dash": "the Undertow Dash",
	"stone_guardian": "the Stone Guardian",
	"furnace_mother": "the Cinder Warden",
	"tidal_heart": "the Tidal Heart",
}

## Objectives in play order: {index, kind (pickup, boss, mini, visit, ending), target, room, cells,
## grants, abilities, flags, steps, optional, seconds (an optional one's time budget), field}.
var objectives: Array = []
var directory := ""
var _fields: Dictionary = {}


## Reads `route.json` from `path` (an absolute or res:// directory); returns an error or "".
func load_dir(path: String) -> String:
	directory = path
	var text := FileAccess.get_file_as_string(path.path_join("route.json"))
	var data = JSON.parse_string(text) if not text.is_empty() else null
	if not data is Dictionary or int(data.get("format", 0)) != FORMAT:
		return "no route (format %d) in %s" % [FORMAT, path]
	objectives = data["objectives"]
	return "" if not objectives.is_empty() else "the route in %s is empty" % path


## True once `objective` is reached in the live game: the pickup collected, the boss or mini-boss
## flag set, the room entered (`visit`), the ending playing (`ending`).
static func is_done(objective: Dictionary, ending: bool) -> bool:
	match String(objective["kind"]):
		"pickup":
			return GameState.collected_pickup_ids.has(String(objective["target"]))
		"boss":
			return GameState.has_world_flag("boss:%s" % objective["target"])
		"mini":
			return GameState.has_world_flag("mini:%s" % objective["target"])
		"visit":
			return GameState.discovered_rooms.has(String(objective["target"]))
	return ending


## True when the kit and flags the solver planned `objective` with are all owned now; a flag in
## `waived` is not needed.
static func is_ready(objective: Dictionary, waived: Dictionary = {}) -> bool:
	for ability in objective["abilities"]:
		if not GameState.has_ability(StringName(ability)):
			return false
	for flag in objective["flags"]:
		if not GameState.has_world_flag(String(flag)) and not waived.has(String(flag)):
			return false
	return true


## Index of the objective to play now: the first in route order that is not done, is ready and
## not `skipped` (objectives that timed out); then the first skipped one that is ready again, never
## an `optional` one (a nearby upgrade); -1 when every objective is done or none is ready.
## A required objective never waits on a mini-boss fight that was left behind: its `mini:` flag
## is waived (the planner lists none on required objectives; r10-run1 and run2 had every
## objective after the timed-out Tollwing listing `mini:tollwing`, and the run ended there).
func next_index(ending: bool, skipped: Dictionary) -> int:
	var waived := {}
	for objective in objectives:
		if objective["kind"] == "mini" and skipped.has(int(objective["index"])):
			waived[String(objective["grants"])] = true
	var fallback := -1
	for objective in objectives:
		if is_done(objective, ending):
			continue
		var index := int(objective["index"])
		var optional: bool = objective.get("optional", false)
		var ready := is_ready(objective, {} if optional else waived)
		if ready and not skipped.has(index):
			return index
		# An optional upgrade that timed out is left behind for good.
		if fallback < 0 and not optional and (ready or skipped.has(index)):
			fallback = index
	return fallback


## True while a required objective is not done: with no objective to play, the run is blocked
## rather than through the route.
func required_open(ending: bool) -> bool:
	return objectives.any(
		func(o: Dictionary) -> bool: return not o.get("optional", false) and not is_done(o, ending)
	)


## Plain-language objective ("collect the Slipstream in fringe_02").
static func describe(objective: Dictionary) -> String:
	var target := String(objective["target"])
	match String(objective["kind"]):
		"pickup":
			var grants := String(objective["grants"])
			var name: String = OBJECTIVE_NAMES.get(grants, target)
			if grants.begins_with("glyph_"):
				name = "a Tide Glyph"
			return "collect %s in %s" % [name, objective["room"]]
		"boss":
			return "defeat %s in %s" % [OBJECTIVE_NAMES.get(target, target), objective["room"]]
		"mini":
			var mini: String = Catalog.DISPLAY_NAMES.get(StringName(target), target)
			return "defeat the mini-boss %s in %s (optional)" % [mini, objective["room"]]
		"visit":
			return "explore %s (optional)" % target
	return "walk into the light in %s (the ending)" % objective["room"]


## The flow field entry for a resting player: [steps, hop] or [] when the solver has no path from
## there. `hop` lists [room, x, y, ball, rising] cells to the next resting spot.
func entry(index: int, room_id: String, cell: Vector2i, ball: bool) -> Array:
	var data := field(index)
	var found = data.get("%s:%d:%d:%d" % [room_id, cell.x, cell.y, int(ball)])
	return found if found is Array else []


## Solver steps from a resting cell to objective `index`, or -1.
func steps(index: int, room_id: String, cell: Vector2i, ball: bool) -> int:
	var found := entry(index, room_id, cell, ball)
	return int(found[0]) if not found.is_empty() else -1


## The nearest resting cell in `room_id` with a field entry, within `radius` cells of `cell`
## (Chebyshev), fewest steps first; Vector2i(-1, -1) when none.
func nearest_on_field(
	index: int, room_id: String, cell: Vector2i, ball: bool, radius: int
) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var probe := cell + Vector2i(dx, dy)
			var found := entry(index, room_id, probe, ball)
			if found.is_empty():
				continue
			var score := maxi(absi(dx), absi(dy)) * 1000.0 + float(found[0])
			if score < best_score:
				best_score = score
				best = probe
	return best


func field(index: int) -> Dictionary:
	if _fields.has(index):
		return _fields[index]
	var data: Dictionary = {}
	if index >= 0 and index < objectives.size():
		var text := FileAccess.get_file_as_string(
			directory.path_join(String(objectives[index]["field"]))
		)
		var parsed = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary:
			data = parsed
	# Only the current and the next field stay in memory.
	for cached in _fields.keys():
		if absi(int(cached) - index) > 1:
			_fields.erase(cached)
	_fields[index] = data
	return data


## Door ids ("edge:target") from `from_room` to `to_room` over the room index's doors, fewest
## rooms first; [] when already there or no route. A door whose ability gate is closed counts only
## when the kit opens it; a door behind a flag gate only when its flags are set.
static func door_route(from_room: String, to_room: String) -> Array:
	if from_room == to_room or not Rooms.ROOMS.has(from_room) or not Rooms.ROOMS.has(to_room):
		return []
	var previous := {from_room: {}}
	var queue: Array = [from_room]
	while not queue.is_empty():
		var room: String = queue.pop_front()
		if room == to_room:
			break
		for door in Rooms.ROOMS[room]["doors"]:
			var target := String(door["target"])
			if previous.has(target) or not door_open(door):
				continue
			previous[target] = {"room": room, "id": "%s:%s" % [door["edge"], target]}
			queue.append(target)
	if not previous.has(to_room):
		return []
	var path: Array = []
	var room := to_room
	while room != from_room:
		var step: Dictionary = previous[room]
		path.push_front(step["id"])
		room = step["room"]
	return path


## True when the player can pass `door` (a room index door) with the live kit and flags.
static func door_open(door: Dictionary) -> bool:
	var gate := String(door["gate"])
	if gate.is_empty():
		return true
	if gate == "flag":
		for flag in String(door["gate_flag"]).split(",", false):
			if not GameState.has_world_flag(flag):
				return false
		return true
	if GameState.has_world_flag(String(door["gate_flag"])):
		return true
	return GameState.has_ability(StringName(GATE_ABILITY.get(gate, gate)))
