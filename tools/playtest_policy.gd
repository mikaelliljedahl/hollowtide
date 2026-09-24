extends RefCounted
## Playtest agent policies (docs/features/playtest-agent.md). A policy gets the exported state and
## the public candidate list and returns one candidate key. `heuristic` is rule-based and
## deterministic (it works offline and in CI); `random` is a seeded baseline. The external policy
## lives in playtest_bridge.gd and falls back to `heuristic`.

const Actions = preload("res://tools/playtest_actions.gd")
const HEURISTIC := "heuristic"
const RANDOM := "random"
const EXTERNAL := "external"
const NAMES := [HEURISTIC, RANDOM, EXTERNAL]
const BEAM_KINDS := ["beam", "ice", "wave"]
## Seconds of shooting one target without its health dropping before the heuristic walks closer.
const FUTILE_SECONDS := 2.5
const CLOSE_IN_SECONDS := 1.5
const RUSHER_DISTANCE := 130.0
const TELEGRAPH_DISTANCE := 320.0
const BOSS_SPACING := 360.0
## Close-in attempts without progress before a target is ignored for IGNORE_SECONDS.
const GIVE_UP_ATTEMPTS := 2
const IGNORE_SECONDS := 15.0
const OBJECTIVES := ["go_to_ambush", "pick_up", "go_to_exit"]

## Memory the heuristic keeps between decisions (target progress and stuck handling).
var _target := ""
var _target_health := -1
var _progress_at := 0.0
var _close_in_until := -1.0
var _futile_attempts := 0
var _ignored: Dictionary = {}
var _stuck_flip := 1
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	_rng.seed = seed_value


func random_choice(candidates: Array) -> String:
	return candidates[_rng.randi_range(0, candidates.size() - 1)]["key"]


## `stuck` is true while the host sees no progress; the heuristic then tries a different jump.
func heuristic(state: Dictionary, candidates: Array, stuck: bool) -> String:
	var keys := {}
	for entry in candidates:
		keys[entry["kind"]] = entry["key"]
	if keys.has("dash_through"):
		return keys["dash_through"]
	if stuck:
		if keys.has("wall_jump"):
			return keys["wall_jump"]
		_stuck_flip = -_stuck_flip
		return "jump:right" if _stuck_flip > 0 else "jump:left"
	if state.get("room") == null:
		return "idle"
	var target := Actions.primary_target(state["enemies"])
	var objective := ""
	for kind in OBJECTIVES:
		if keys.has(kind):
			objective = keys[kind]
			break
	if not target.is_empty() and (_engage(state, target) or objective.is_empty()):
		return _fight(state, target, keys)
	return objective if not objective.is_empty() else "idle"


## Fight a target that is visible and not given up on, and always fight a sealed arena's enemies.
func _engage(state: Dictionary, target: Dictionary) -> bool:
	var now := float(state["t"])
	if float(_ignored.get(target["id"], -1.0)) > now:
		return false
	var arena = state["ambush"]
	if arena != null and arena["state"] in ["sealing", "fighting", "intermission"]:
		return true
	return bool(target["visible"])


func _fight(state: Dictionary, target: Dictionary, keys: Dictionary) -> String:
	var now := float(state["t"])
	_track_progress(target, now)
	var distance := float(target["dist"])
	var hurt_by: Array = target["hurt_by"]
	if target["is_boss"]:
		if bool(target["telegraph"]) and distance < TELEGRAPH_DISTANCE:
			return keys.get("jump_over", keys.get("retreat", "idle"))
		if keys.has("harpoon"):
			return keys["harpoon"]
		if hurt_by.is_empty():
			return keys["retreat"] if distance < BOSS_SPACING else keys["approach"]
	elif distance < RUSHER_DISTANCE and bool(state["player"]["grounded"]):
		return keys.get("jump_over", keys["retreat"])
	if now < _close_in_until:
		return keys["approach"]
	if now - _progress_at > FUTILE_SECONDS:
		# Shots are not landing (a wall or ledge is in the way): walk closer for a while, and
		# after a few tries leave this target alone for a while.
		_futile_attempts += 1
		if _futile_attempts > GIVE_UP_ATTEMPTS:
			_ignored[target["id"]] = now + IGNORE_SECONDS
			_futile_attempts = 0
		_close_in_until = now + CLOSE_IN_SECONDS
		_progress_at = now
		return keys["approach"]
	if keys.has("harpoon"):
		return keys["harpoon"]
	if keys.has("shoot") and hurt_by.any(func(kind: String) -> bool: return kind in BEAM_KINDS):
		return keys["shoot"]
	return keys["approach"]


func _track_progress(target: Dictionary, now: float) -> void:
	var health := int(target["health"])
	if target["id"] != _target or health < _target_health:
		_progress_at = now
		_futile_attempts = 0
	_target = target["id"]
	_target_health = health
