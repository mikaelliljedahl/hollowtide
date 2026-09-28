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
## In campaign mode a shot this close (px) to a grounded player is jumped over.
const DODGE_DISTANCE := 220.0
## In campaign mode a refill farther than this (px, x and y from the feet) is not walked to.
const REFILL_REACH := Vector2(512.0, 192.0)
## Close-in attempts without progress before a target is ignored for IGNORE_SECONDS.
const GIVE_UP_ATTEMPTS := 2
const IGNORE_SECONDS := 15.0
## Non-fight goals in order; the campaign kinds only appear in campaign mode, which leaves the
## arena, pickups and doors to the route.
const OBJECTIVES := [
	"open_gate",
	"freeze",
	"fast_travel",
	"go_to_objective",
	"go_to_ambush",
	"pick_up",
	"go_to_exit",
	"go_to_door",
]
## In campaign mode an enemy farther than this is left alone unless it is a boss or the arena is
## sealed: the route is the goal, not every enemy on screen.
const CAMPAIGN_ENGAGE_DISTANCE := 400.0

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
		keys[entry["key"]] = entry["key"]
	if keys.has("dash_through"):
		return keys["dash_through"]
	if stuck:
		if keys.has("wall_jump"):
			return keys["wall_jump"]
		_stuck_flip = -_stuck_flip
		return "jump:right" if _stuck_flip > 0 else "jump:left"
	if state.get("room") == null:
		return "idle"
	var dodge := _dodge(state)
	if not dodge.is_empty():
		return dodge
	var target := Actions.primary_target(state["enemies"])
	var winding_up := (
		not target.is_empty()
		and bool(target["telegraph"])
		and float(target["dist"]) < TELEGRAPH_DISTANCE
	)
	if keys.has("go_to_refill") and not winding_up and _refill_wanted(state, keys["go_to_refill"]):
		return keys["go_to_refill"]
	var objective := ""
	for kind in OBJECTIVES:
		if keys.has(kind):
			objective = keys[kind]
			break
	if not target.is_empty() and (_engage(state, target) or objective.is_empty()):
		var move := _fight(state, target, keys)
		if not move.is_empty() or objective.is_empty():
			return move if not move.is_empty() else keys["approach"]
	return objective if not objective.is_empty() else "idle"


## In campaign mode, a jump over an enemy shot about to reach a grounded player (there is no dash
## to turn it early in the game); "" otherwise. Room mode keeps its earlier behaviour.
func _dodge(state: Dictionary) -> String:
	if not state.has("goal") or not bool(state["player"]["grounded"]):
		return ""
	var shot := Actions.incoming_projectile(state)
	if shot.is_empty() or Vector2(shot["rel"][0], shot["rel"][1]).length() > DODGE_DISTANCE:
		return ""
	return "jump:left" if float(shot["rel"][0]) < 0.0 else "jump:right"


## Outside campaign mode every offered refill is taken. In campaign mode a refill run is for low
## health, or for Harpoons when the objective is a boss or a harpoon socket blocks the route; a
## detour for spare bolts otherwise costs more than it gives.
func _refill_wanted(state: Dictionary, key: String) -> bool:
	var goal = state.get("goal")
	if not goal is Dictionary or (goal as Dictionary).is_empty():
		return true
	# The refill run steers straight at it; one out of that reach is left to the route (a death
	# respawns at the last shrine with full health anyway).
	var refill := _refill_for(state, key.get_slice(":", 1))
	if (
		refill.is_empty()
		or absf(float(refill["rel"][0])) > REFILL_REACH.x
		or absf(float(refill["rel"][1])) > REFILL_REACH.y
	):
		return false
	if key.contains("energy") or key.ends_with(":refill") or key.ends_with(":save"):
		var me: Dictionary = state["player"]
		if float(me["health"]) < float(me["max_health"]) / 3.0:
			return true
	var gate = goal.get("gate_ahead")
	return goal.get("kind") == "boss" or (gate is Dictionary and gate["kind"] == "missile")


## Fight a target that is visible and not given up on, and always fight a sealed arena's enemies.
func _engage(state: Dictionary, target: Dictionary) -> bool:
	var now := float(state["t"])
	if float(_ignored.get(target["id"], -1.0)) > now:
		return false
	var arena = state["ambush"]
	if arena != null and arena["state"] in ["sealing", "fighting", "intermission"]:
		return true
	if (
		state.has("goal")
		and not bool(target["is_boss"])
		and (
			float(target["dist"]) > CAMPAIGN_ENGAGE_DISTANCE
			or bool(target.get("frozen", false))
			or (target["type"] == "frost_floater" and float(target["dist"]) > RUSHER_DISTANCE)
		)
	):
		# A frozen enemy is harmless for a while; frost floaters are the route's platforms once
		# frozen, and shooting them down loses them.
		return false
	return bool(target["visible"])


## The fight move against `target`. In campaign mode, against an ordinary enemy outside a sealed
## arena, only moves made where the player stands (a shot, a jump over a rusher, a dodge) are
## taken; "" hands back to the route rather than chasing it across the room.
func _fight(state: Dictionary, target: Dictionary, keys: Dictionary) -> String:
	var move := _fight_move(state, target, keys)
	if not _roaming(state, target) or move.is_empty():
		return move
	var kind := move.split(":")[0]
	if kind in ["approach", "harpoon"] and float(target["dist"]) > RUSHER_DISTANCE * 2.0:
		return ""
	return move


## True for an ordinary enemy in campaign mode outside a sealed arena.
func _roaming(state: Dictionary, target: Dictionary) -> bool:
	var arena = state["ambush"]
	return (
		state.has("goal")
		and not bool(target["is_boss"])
		and not (arena != null and arena["state"] in ["sealing", "fighting", "intermission"])
	)


func _fight_move(state: Dictionary, target: Dictionary, keys: Dictionary) -> String:
	var now := float(state["t"])
	_track_progress(target, now)
	var distance := float(target["dist"])
	var hurt_by: Array = target["hurt_by"]
	var away: String = keys.get("retreat", keys["approach"])
	if target["is_boss"]:
		var move := _boss_move(target, keys)
		if not move.is_empty():
			return move
	elif distance < RUSHER_DISTANCE and bool(state["player"]["grounded"]):
		return keys.get("jump_over", away)
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
	var switch := "select_beam:%s" % target.get("switch_to", "")
	if keys.has(switch):
		return switch
	if keys.has("pulse"):
		return keys["pulse"]
	if hurt_by.any(func(kind: String) -> bool: return kind in BEAM_KINDS):
		for kind in ["shoot", "jump_shoot"]:
			if keys.has(kind):
				return keys[kind]
	return keys["approach"]


## A boss's own rules, before the generic shooting: dodge a close wind-up, open the shell (switch
## to the opener's beam, walk to where it lines up, fire it), harpoon it while open, and keep
## BOSS_SPACING while nothing hurts it. "" hands over to the generic fight.
func _boss_move(boss: Dictionary, keys: Dictionary) -> String:
	var distance := float(boss["dist"])
	if bool(boss["telegraph"]) and distance < TELEGRAPH_DISTANCE:
		return keys.get("jump_over", keys.get("retreat", "idle"))
	for kind in ["open_boss", "harpoon"]:
		if keys.has(kind):
			return keys[kind]
	var opener = boss.get("opener")
	if not bool(boss.get("open", true)) and opener is Dictionary and opener["owned"]:
		var beam := "select_beam:%s" % opener["beam"]
		if keys.has(beam):
			return beam
		if opener["via"] != "punish":
			# Walk to where the opener lines up (Actions.boss_goal), keeping out of its body.
			return keys["approach"]
	if not (boss["hurt_by"] as Array).is_empty():
		return ""
	var switch := "select_beam:%s" % boss.get("switch_to", "")
	if keys.has(switch):
		return switch
	if distance < BOSS_SPACING:
		return keys.get("retreat", keys["approach"])
	return keys["approach"]


static func _refill_for(state: Dictionary, kind: String) -> Dictionary:
	for refill in state.get("refills", []):
		if refill["kind"] == kind:
			return refill
	return {}


func _track_progress(target: Dictionary, now: float) -> void:
	var health := int(target["health"])
	# A Snare shot does no damage; freezing the target is its progress.
	if target["id"] != _target or health < _target_health or bool(target.get("frozen", false)):
		_progress_at = now
		_futile_attempts = 0
	_target = target["id"]
	_target_health = health
