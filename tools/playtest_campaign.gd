extends RefCounted
## Campaign mode of the playtest agent (harness: docs/features/playtest-agent.md): one
## continuous run from a new game to the ending. Owns the route planner (tools/playtest_route.gd),
## the navigator (tools/playtest_nav.gd) and the progress record (tools/playtest_progress.gd).
## Each decision it adds the current goal to the state and offers the route candidates:
## `go_to_objective`, `go_to_door:<edge:target>`, `open_gate:<flag>` and `fast_travel:<station>`.
## The policy chooses among them and the fight options; this class only sets goals.

const Route = preload("res://tools/playtest_route.gd")
const Nav = preload("res://tools/playtest_nav.gd")
const Progress = preload("res://tools/playtest_progress.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const Aim = preload("res://tools/playtest_aim.gd")
const Travel = preload("res://tools/playtest_travel.gd")
const State = preload("res://tools/playtest_state.gd")
const Boss = preload("res://tools/playtest_boss.gd")
const Floaters = preload("res://tools/playtest_floaters.gd")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const TILE := 64.0
## Frames one `go_to_objective` program follows the route before the policy decides again.
const FOLLOW_FRAMES := 30
## Cells around the feet searched for the route when the player stands off it.
const REJOIN_RADIUS := 4
const MAX_DOORS := 3
## Gate opening: fire from at most this far, dash from at most this close, pulse this level.
const GATE_SHOT_RANGE := 520.0
## A gate's centre within this of the crossbow's height counts as level for a shot or a dash.
const GATE_SHOT_LEVEL := 160.0
const GATE_DASH_RANGE := 200.0
const GATE_PULSE_RANGE := 360.0
const GATE_PULSE_LEVEL := 128.0
const GATE_KIND_NAMES := {
	"missile": "harpoon socket",
	"bomb": "cracked crystal",
	"wave": "resonant membrane",
	"undertow": "undertow barrier",
}

var route: Route = Route.new()
var nav: Nav.Navigator
var progress: Progress = Progress.new()
var travel: Travel
var _root: Node
var _player: Player


## Loads the route from `directory`; returns an error or "".
func setup(directory: String, root: Node, player: Player) -> String:
	_root = root
	_player = player
	var problem := route.load_dir(directory)
	nav = Nav.Navigator.new(route)
	travel = Travel.new(route)
	return problem


func ending() -> bool:
	return _root != null and _root.get("_ending") == true


## Once per physics frame: progress bookkeeping. Returns a run end reason or "".
func update(now: float, telemetry: RefCounted) -> String:
	return progress.update(now, route, telemetry, nav.steps, ending())


## The objective being played now, or {}.
func objective() -> Dictionary:
	var index := progress.current
	return route.objectives[index] if index >= 0 and index < route.objectives.size() else {}


## The `goal` entry of the exported state.
func goal(state: Dictionary) -> Dictionary:
	var current := objective()
	if current.is_empty() or state.get("room") == null:
		return {}
	var where := Nav.Navigator.locate(_root, _player)
	nav.refresh(where, int(current["index"]))
	var room := String(state["room"]["id"])
	var doors := Route.door_route(room, String(current["room"]))
	var gate := nav.gate_ahead(where, _player.get_tree())
	return {
		"objective": Route.describe(current),
		"kind": current["kind"],
		"target": current["target"],
		"room": current["room"],
		"index": current["index"],
		"count": route.objectives.size(),
		"done": progress.done_count(route, ending()),
		"steps": nav.steps,
		"route_status": nav.status,
		"doors": doors,
		"heading": _heading(where),
		"gate_ahead": _gate_fact(gate, where) if gate != null else null,
		"seconds_on_objective": snappedf(progress.seconds_on_current(), 0.1),
	}


## Route candidates for this decision, in priority order.
func candidates(state: Dictionary) -> Array:
	var current := objective()
	if current.is_empty() or state.get("room") == null:
		return []
	var index := int(current["index"])
	var where := Nav.Navigator.locate(_root, _player)
	var result: Array = []
	var gate := nav.gate_ahead(where, _player.get_tree())
	if gate != null:
		var opener := _open_gate(gate, state)
		if not opener.is_empty():
			result.append(opener)
	var freeze := _freeze(where)
	if not freeze.is_empty():
		result.append(freeze)
	# While the gate or the floater the route needs can be handled from here, following the route
	# cannot get past it, so it is not offered.
	var follow := _follow(current, where, index) if result.is_empty() else {}
	if not follow.is_empty():
		result.append(follow)
	result.append_array(_doors(state, current, follow))
	result.append_array(travel.candidates(_root, _player, index, where))
	return result


func _follow(current: Dictionary, where: Dictionary, index: int) -> Dictionary:
	var status := nav.refresh(where, index)
	var label := "follow the route to %s" % Route.describe(current)
	if status in ["on_field", "airborne"]:
		return _entry(
			"go_to_objective",
			"go_to_objective",
			"%s (%s)" % [label, _next_hint(where, current)],
			Nav.Follow.new(nav, _root, _player, index, FOLLOW_FRAMES)
		)
	if status != "off_field" or where.is_empty():
		return {}
	var cell := route.nearest_on_field(
		index, String(where["room"]), where["cell"], bool(where["ball"]), REJOIN_RADIUS
	)
	if cell.x >= 0:
		var spot := (Vector2(cell) + Vector2(0.5, 1.0)) * TILE - Vector2(where["local"])
		return _entry(
			"go_to_objective",
			"go_to_objective",
			"%s (step back onto the route first)" % label,
			Programs.steer(_player, spot, false)
		)
	var doors := Route.door_route(String(where["room"]), String(current["room"]))
	var door := _door(String(where["room"]), doors[0] if not doors.is_empty() else "")
	if door.is_empty():
		return {}
	return _entry(
		"go_to_objective",
		"go_to_objective",
		"%s (off the planned path; head for the %s door)" % [label, doors[0]],
		Programs.steer(_player, _door_rel(door, where), true)
	)


## One `go_to_door` per open door of the room, the route's door first. While the route can be
## followed, the route's door plays the route itself: a straight steer at a door far below turns
## back and forth under it (jev-c1 spent 580 s in fringe_04 above its bomb floor that way).
func _doors(state: Dictionary, current: Dictionary, follow: Dictionary) -> Array:
	var room := String(state["room"]["id"])
	if not Rooms.ROOMS.has(room):
		return []
	var where := Nav.Navigator.locate(_root, _player)
	var doors := Route.door_route(room, String(current["room"]))
	var on_route := String(doors[0]) if not doors.is_empty() else ""
	var result: Array = []
	for door in Rooms.ROOMS[room]["doors"]:
		var id := "%s:%s" % [door["edge"], door["target"]]
		if not Route.door_open(door) or result.size() >= MAX_DOORS:
			continue
		var entry := _entry(
			"go_to_door:%s" % id,
			"go_to_door",
			"head for the %s exit" % id,
			Programs.steer(_player, _door_rel(door, where), true)
		)
		if id == on_route:
			entry["label"] += " (on the route to %s)" % current["room"]
			if not follow.is_empty():
				entry["program"] = follow["program"]
			result.push_front(entry)
		else:
			result.append(entry)
	return result


## `freeze:<cell>` for the farthest floater the next hops stand on, while the Snare is owned.
func _freeze(where: Dictionary) -> Dictionary:
	if where.is_empty() or not GameState.has_ability(&"ice_beam"):
		return {}
	var floaters := Floaters.needed(
		_player.get_tree(), where["room_node"], nav.landings(where), _player.global_position
	)
	if floaters.is_empty():
		return {}
	var floater: Node2D = floaters[0]
	var home: Vector2 = (
		Vector2(floater.get("_home_position")) - (where["room_node"] as Node2D).global_position
	)
	var label := "%d_%d" % [floori(home.x / TILE), floori(home.y / TILE)]
	return Floaters.candidate(floater, _player, label)


## The candidate that opens `gate` with the kit from where the player stands, or {} when nothing
## owned opens it now or it is out of reach (the route then leads closer first).
func _open_gate(gate: AbilityGate, state: Dictionary) -> Dictionary:
	var kind := String(gate.gate_kind)
	var rel := gate.global_position - _player.global_position
	var me: Dictionary = state["player"]
	var facing := int(me["facing"])
	var toward := -1 if rel.x < 0.0 else 1
	var name: String = GATE_KIND_NAMES.get(kind, kind)
	var key := "open_gate:%s" % gate.flag_id
	var level := absf(rel.y - Aim.EYE.y) <= GATE_SHOT_LEVEL
	match kind:
		"missile":
			if not State.harpoons_ready() or absf(rel.x) > GATE_SHOT_RANGE or not level:
				return {}
			return _entry(
				key,
				"open_gate",
				"fire a harpoon at the %s to open it" % name,
				Programs.shoot(toward, _gate_aim(rel, me), &"fire_missile", facing)
			)
		"wave":
			if (
				not GameState.has_ability(&"wave_beam")
				or absf(rel.x) > GATE_SHOT_RANGE
				or not level
			):
				return {}
			if String(GameState.active_beam) != "wave":
				var owned := Boss.owned_beams()
				var taps := owned.find("wave") - owned.find(String(GameState.active_beam))
				return _entry(
					key,
					"open_gate",
					"switch the crossbow to the Echo (wave) bolt to open the %s" % name,
					Programs.cycle_beam(taps, owned.size())
				)
			return _entry(
				key,
				"open_gate",
				"fire the Echo bolt at the %s to open it" % name,
				Programs.shoot(toward, _gate_aim(rel, me), &"fire_beam", facing)
			)
		"bomb":
			if (
				not GameState.has_ability(&"bombs")
				or not GameState.has_slipstream
				or absf(rel.x) > GATE_PULSE_RANGE
				or absf(rel.y) > GATE_PULSE_LEVEL
			):
				return {}
			return _entry(
				key,
				"open_gate",
				"roll to the %s and drop a Resonance Pulse on it" % name,
				Programs.pulse(rel.x, me["form"] == "ball")
			)
		"undertow":
			if (
				not GameState.has_ability(&"undertow_dash")
				or not bool(me["dash_ready"])
				or absf(rel.x) > GATE_DASH_RANGE
				or not level
			):
				return {}
			return _entry(
				key, "open_gate", "dash through the %s to break it" % name, Programs.dash(toward)
			)
	return {}


## The aim that lines a bolt up with a gate's centre from here, level when none does.
func _gate_aim(rel: Vector2, me: Dictionary) -> String:
	var aim := Aim.line_up(rel, bool(me["grounded"]), Aim.GRATE_RADIUS, GATE_SHOT_RANGE * 1.5)
	return aim if not aim.is_empty() else "forward"


func _gate_fact(gate: AbilityGate, where: Dictionary) -> Dictionary:
	var kind := String(gate.gate_kind)
	return {
		"kind": kind,
		"name": GATE_KIND_NAMES.get(kind, kind),
		"rel": State.rel(_player.global_position, gate.global_position),
		"opens_with": Route.GATE_ABILITY.get(kind, kind),
		"owned": GameState.has_ability(StringName(Route.GATE_ABILITY.get(kind, kind))),
		"room": where.get("room", ""),
	}


## Rough direction of the next hop cell: "left", "right", "up", "down" or combinations.
func _heading(where: Dictionary) -> String:
	if nav.hop.is_empty() or where.is_empty():
		return ""
	var step: Array = nav.hop[mini(nav.progress, nav.hop.size() - 1)]
	var cell: Vector2i = where["cell"]
	if step[0] != where["room"]:
		return "through the door"
	var parts: Array = []
	if int(step[2]) < cell.y:
		parts.append("up")
	elif int(step[2]) > cell.y:
		parts.append("down")
	if int(step[1]) < cell.x:
		parts.append("left")
	elif int(step[1]) > cell.x:
		parts.append("right")
	return " and ".join(parts) if not parts.is_empty() else "here"


func _next_hint(where: Dictionary, current: Dictionary) -> String:
	if String(where.get("room", "")) == String(current["room"]):
		return "%d steps, in this room" % nav.steps
	var doors := Route.door_route(String(where.get("room", "")), String(current["room"]))
	return "%d steps, next door %s" % [nav.steps, doors[0] if not doors.is_empty() else "unknown"]


func _door(room: String, id: String) -> Dictionary:
	if id.is_empty() or not Rooms.ROOMS.has(room):
		return {}
	for door in Rooms.ROOMS[room]["doors"]:
		if "%s:%s" % [door["edge"], door["target"]] == id:
			return door
	return {}


func _door_rel(door: Dictionary, where: Dictionary) -> Vector2:
	var from: Vector2i = door["from"]
	var to: Vector2i = door["to"]
	var center := (Vector2(from + to) * 0.5 + Vector2(0.5, 1.0)) * TILE
	return center - Vector2(where["local"])


static func _entry(key: String, kind: String, label: String, program: Variant) -> Dictionary:
	return {"key": key, "kind": kind, "label": label, "program": program}
