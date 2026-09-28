extends RefCounted
## Fast travel for the playtest agent's campaign mode (harness:
## docs/features/playtest-agent.md; the game's rules are docs/features/fast-travel.md). Offers
## `fast_travel:<station>` while the player stands on an activated save shrine and another
## activated shrine lies much closer to the current objective on the route's flow field. The trip
## goes through the real inputs: move_up on the shrine opens the travel map (the tree pauses), then
## move_right steps to the target and jump confirms. The map reads input while paused, so those
## presses are sent from timers that run during the pause.

const Route = preload("res://tools/playtest_route.gd")
const FastTravel = preload("res://scripts/campaign/fast_travel.gd")
const TILE := 64.0
## A trip must save at least this many weighted solver steps toward the objective.
const MIN_GAIN := 150
## Feet this close to a shrine's anchor stand on it (its trigger is 112 px wide).
const ON_SHRINE_PX := 48.0
const OPEN_FRAMES := 3
const PRESS_SECONDS := 0.05
const MAP_WAIT_SECONDS := 1.0

var route: Route
## Trips started and confirmed, for the progress record.
var trips: Array = []


func _init(planner: Route) -> void:
	route = planner


## [] or one `fast_travel:<station>` candidate.
func candidates(root: Node, player: Player, index: int, where: Dictionary) -> Array:
	if where.is_empty() or not bool(where["grounded"]) or bool(where["ball"]):
		return []
	var room := String(where["room"])
	var from := FastTravel.station_near(room, where["local"], ON_SHRINE_PX)
	if from.is_empty() or not GameState.activated_stations.has(from):
		return []
	var targets: Array = root.call("travel_targets", from)
	if targets.is_empty():
		return []
	var here := route.steps(index, room, where["cell"], false)
	var best: Dictionary = {}
	var best_steps := -1
	for target in targets:
		var steps := route.steps(index, String(target["room"]), _cell(target["position"]), false)
		if steps >= 0 and (best_steps < 0 or steps < best_steps):
			best = target
			best_steps = steps
	if best.is_empty() or (here >= 0 and here - best_steps < MIN_GAIN):
		return []
	var presses := posmod(targets.find(best) - _first_selection(from, targets), targets.size())
	return [
		{
			"key": "fast_travel:%s" % best["id"],
			"kind": "fast_travel",
			"label":
			(
				"fast travel from this shrine to the shrine in %s (%d steps from the objective instead of %d)"
				% [best["room"], best_steps, here]
			),
			"program": Trip.new(self, player, from, String(best["id"]), presses),
		}
	]


## The selection the travel map starts on: the target nearest the origin shrine
## (scripts/campaign/campaign_map_travel.gd).
static func _first_selection(from: String, targets: Array) -> int:
	var origin := FastTravel.station(from)
	var index := 0
	var best := INF
	for position in targets.size():
		var distance: float = (targets[position]["tile"] as Vector2).distance_to(origin["tile"])
		if distance < best:
			best = distance
			index = position
	return index


static func _cell(feet: Vector2) -> Vector2i:
	return Vector2i(floori(feet.x / TILE), floori((feet.y - 1.0) / TILE))


## Live program: holds move_up on the shrine, then (from timers that run while the tree is
## paused) steps the travel map to the target and confirms with jump.
class Trip:
	extends RefCounted

	var finished := false
	var _travel: RefCounted
	var _player: Player
	var _from := ""
	var _to := ""
	var _presses := 0
	var _frame := 0

	func _init(owner: RefCounted, player: Player, from: String, to: String, presses: int) -> void:
		_travel = owner
		_player = player
		_from = from
		_to = to
		_presses = presses

	func next() -> Array:
		_frame += 1
		if _frame == 1:
			_drive()
		if _frame > OPEN_FRAMES:
			finished = true
			return []
		return [&"move_up"]

	func _drive() -> void:
		var tree := _player.get_tree()
		var record := {"from": _from, "to": _to, "confirmed": false}
		_travel.get("trips").append(record)
		var waited := 0.0
		while not tree.paused and waited < MAP_WAIT_SECONDS:
			await tree.create_timer(PRESS_SECONDS, true).timeout
			waited += PRESS_SECONDS
		if not tree.paused:
			return
		for _press in _presses:
			await _tap(tree, &"move_right")
		await _tap(tree, &"jump")
		record["confirmed"] = true

	func _tap(tree: SceneTree, action: StringName) -> void:
		for pressed in [true, false]:
			var event := InputEventAction.new()
			event.action = action
			event.pressed = pressed
			event.strength = 1.0 if pressed else 0.0
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await tree.create_timer(PRESS_SECONDS, true).timeout
