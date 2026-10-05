extends RefCounted
## Progress record of the playtest agent's campaign mode (harness:
## docs/features/playtest-agent.md): objective attempts in order with their times, deaths, damage and stalls, rooms
## in the order first entered, deaths with the shrine the player came back at, and where and why
## the run stopped. An objective that takes longer than OBJECTIVE_TIMEOUT game seconds is recorded
## as failed and set aside while another objective is ready; a second timeout ends the run. An
## optional one gets its route budget (`seconds`) and is left behind after one timeout.

const Route = preload("res://tools/playtest_route.gd")
const OBJECTIVE_TIMEOUT := 300.0
## An optional upgrade on the route (tools/playtest/campaign_route.py) gets less time and is left
## behind after one timeout (tools/playtest_route.gd `next_index`).
const OPTIONAL_TIMEOUT := 120.0
const MAX_TIMEOUTS := 2

## Index of the objective being played, -1 before the first update.
var current := -1
## Finished attempts: index, target, objective, kind, room, start, end, seconds, outcome
## (done, timeout, switched, unfinished), deaths, damage, stuck_seconds, no_progress_seconds,
## start_steps, best_steps.
var attempts: Array = []
var timeouts: Dictionary = {}
var rooms: Array = []
var respawns: Array = []
var _now := 0.0
var _open: Dictionary = {}
var _deaths_seen := 0
var _hits_seen := 0
var _best_at := 0.0


## Once per physics frame. `steps` is the navigator's distance to the current objective (-1 when
## unknown). Returns a run end reason, or "".
func update(now: float, route: Route, telemetry: RefCounted, steps: int, ending: bool) -> String:
	_now = now
	_track_rooms(telemetry)
	_track_deaths(telemetry)
	var index := route.next_index(ending, timeouts)
	if not _open.is_empty() and index != current:
		var done := Route.is_done(route.objectives[current], ending)
		_close("done" if done else "switched", telemetry)
	current = index
	if index < 0:
		return "goal_ending" if ending else "route_done"
	if _open.is_empty():
		_start(route.objectives[index], telemetry, steps)
	_track_steps(steps)
	if now - float(_open["start"]) < time_budget(route.objectives[index]):
		return ""
	timeouts[index] = int(timeouts.get(index, 0)) + 1
	_close("timeout", telemetry)
	if int(timeouts[index]) >= MAX_TIMEOUTS:
		return "objective_failed"
	return ""


## Game seconds `objective` gets before it times out.
static func time_budget(objective: Dictionary) -> float:
	if not objective.get("optional", false):
		return OBJECTIVE_TIMEOUT
	return float(objective.get("seconds", OPTIONAL_TIMEOUT))


## Objectives reached so far.
func done_count(route: Route, ending: bool) -> int:
	return (
		route.objectives.filter(func(o: Dictionary) -> bool: return Route.is_done(o, ending)).size()
	)


func seconds_on_current() -> float:
	return _now - float(_open.get("start", _now))


## Closes the running attempt ("unfinished") and returns the campaign record for the report.
func finish(
	route: Route, telemetry: RefCounted, ending: bool, reason: String, where: Dictionary
) -> Dictionary:
	var stopped_on: Dictionary = _open.duplicate() if not _open.is_empty() else {}
	_close("unfinished", telemetry)
	var objectives: Array = []
	for objective in route.objectives:
		var index := int(objective["index"])
		var tries := attempts.filter(func(a: Dictionary) -> bool: return int(a["index"]) == index)
		var reached := Route.is_done(objective, ending)
		(
			objectives
			. append(
				{
					"index": index,
					"objective": Route.describe(objective),
					"kind": objective["kind"],
					"target": objective["target"],
					"room": objective["room"],
					"reached": reached,
					"reached_at": tries[-1]["end"] if reached and not tries.is_empty() else null,
					"attempts": tries.size(),
					"seconds": snappedf(_sum(tries, "seconds"), 0.1),
					"deaths": int(_sum(tries, "deaths")),
					"damage": int(_sum(tries, "damage")),
					"stuck_seconds": snappedf(_sum(tries, "stuck_seconds"), 0.1),
					"no_progress_seconds": snappedf(_max(tries, "no_progress_seconds"), 0.1),
				}
			)
		)
	return {
		"reached_ending": ending,
		"objectives_done": done_count(route, ending),
		"objectives_total": route.objectives.size(),
		"objectives": objectives,
		"attempts": attempts,
		"rooms_visited": rooms,
		"deaths": respawns,
		"end":
		{
			"reason": reason,
			"t": snappedf(_now, 0.1),
			"room": where.get("room", ""),
			"cell": where.get("cell", []),
			"objective": stopped_on.get("objective", ""),
		},
	}


func _start(objective: Dictionary, telemetry: RefCounted, steps: int) -> void:
	_open = {
		"index": int(objective["index"]),
		"target": objective["target"],
		"objective": Route.describe(objective),
		"kind": objective["kind"],
		"room": objective["room"],
		"start": _now,
		"deaths": 0,
		"damage": 0,
		"stuck_before": _stuck_total(telemetry),
		"start_steps": steps,
		"best_steps": steps,
		"no_progress_seconds": 0.0,
		"rooms": [],
	}
	_best_at = _now


func _close(outcome: String, telemetry: RefCounted) -> void:
	if _open.is_empty():
		return
	var record := _open.duplicate()
	record["end"] = snappedf(_now, 0.1)
	record["start"] = snappedf(float(record["start"]), 0.1)
	record["seconds"] = snappedf(_now - float(_open["start"]), 0.1)
	record["outcome"] = outcome
	record["stuck_seconds"] = snappedf(_stuck_total(telemetry) - float(_open["stuck_before"]), 0.1)
	record["no_progress_seconds"] = snappedf(
		maxf(float(_open["no_progress_seconds"]), _now - _best_at), 0.1
	)
	record.erase("stuck_before")
	attempts.append(record)
	_open = {}


func _track_steps(steps: int) -> void:
	if steps < 0:
		return
	var best := int(_open["best_steps"])
	if best < 0 or steps < best:
		_open["no_progress_seconds"] = maxf(float(_open["no_progress_seconds"]), _now - _best_at)
		_open["best_steps"] = steps
		_best_at = _now


func _track_rooms(telemetry: RefCounted) -> void:
	var room := String(telemetry.get("room"))
	if room.is_empty():
		return
	if rooms.is_empty() or not rooms.any(func(r: Dictionary) -> bool: return r["room"] == room):
		rooms.append({"room": room, "t": snappedf(_now, 0.1)})
	if not _open.is_empty() and not (_open["rooms"] as Array).has(room):
		_open["rooms"].append(room)


func _track_deaths(telemetry: RefCounted) -> void:
	var deaths: Array = telemetry.get("deaths")
	for index in range(_deaths_seen, deaths.size()):
		var death: Dictionary = deaths[index].duplicate()
		death["respawn_room"] = String(GameState.checkpoint.get("room", ""))
		death["objective"] = _open.get("objective", "")
		respawns.append(death)
		if not _open.is_empty():
			_open["deaths"] += 1
	_deaths_seen = deaths.size()
	var hits: Array = telemetry.get("hits")
	for index in range(_hits_seen, hits.size()):
		if not _open.is_empty():
			_open["damage"] += int(hits[index]["amount"])
	_hits_seen = hits.size()


static func _stuck_total(telemetry: RefCounted) -> float:
	var total := 0.0
	for episode in telemetry.get("stuck_episodes"):
		total += float(episode["seconds"])
	return total


static func _sum(items: Array, field: String) -> float:
	var total := 0.0
	for item in items:
		total += float(item[field])
	return total


static func _max(items: Array, field: String) -> float:
	var best := 0.0
	for item in items:
		best = maxf(best, float(item[field]))
	return best
