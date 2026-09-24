extends RefCounted
## Playtest agent macro actions (docs/features/playtest-agent.md). `candidates()` offers 6 to 14
## labelled options for the current state; each carries a program built by
## playtest_programs.gd: one Array of held input actions per physics frame.

const Aim = preload("res://tools/playtest_aim.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const MAX_CANDIDATES := 14
const SHOT_RANGE := 1100.0
const THREAT_RANGE := 420.0
const PROJECTILE_ALERT := 420.0
const MAX_EXITS := 3
## A grounded player cannot aim down: a target whose origin is more than this far below the feet
## is under every aim the crossbow has, so no shot is offered at it.
const GROUNDED_AIM_DROP := 160.0
## Kinds that are movement, for stuck detection: choosing one of these means "I want to move".
const MOVING_KINDS := [
	"approach", "retreat", "go_to_exit", "go_to_ambush", "pick_up", "jump", "go_to_refill"
]
## How far a retreat runs (12 frames at run speed, rounded up); a live boss's arena edge must be
## at least this far behind the player for `retreat` to be offered.
const RETREAT_REACH := 160.0
## A boss whose centre is this far above the feet floats: jumping toward it lands in its body.
const FLOATING_ABOVE := 160.0
## A Resonance Pulse is offered at an enemy this close and this level with the player.
const PULSE_RANGE := 400.0
const PULSE_LEVEL := 96.0
const BEAM_NAMES := {"base": "seed bolt", "ice": "Snare (ice)", "wave": "Echo (wave)"}


## Returns [{key, kind, label, program}] for `state` (from playtest_state.gd). The first entry is
## always `idle` and the last two the plain jumps; the rest follow a fixed priority, cut to fit, so
## the list is deterministic.
static func candidates(state: Dictionary, player: Player) -> Array:
	var result: Array = [_entry("idle", "idle", "stand still", Programs.idle())]
	if state.get("room") == null:
		return result
	var me: Dictionary = state["player"]
	var abilities: Array = state["kit"]["abilities"]
	var enemies: Array = state["enemies"]
	var target := primary_target(enemies)
	if not target.is_empty():
		result.append_array(_fight(state, target, player))
	var shot := incoming_projectile(state)
	if not shot.is_empty() and abilities.has("undertow_dash") and bool(me["dash_ready"]):
		result.append(
			_entry(
				"dash_through",
				"dash_through",
				"dash into the incoming %s shot" % shot["style"],
				Programs.dash(_sign(float(shot["rel"][0])))
			)
		)
	if bool(me["on_wall"]):
		result.append(
			_entry(
				"wall_jump_up", "wall_jump", "wall jump up", Programs.wall_jump(int(me["facing"]))
			)
		)
	var refill := _refill(state, player)
	if not refill.is_empty():
		result.append(refill)
	var arena = state["ambush"]
	if arena != null and arena["state"] == "armed" and not _near(_vec(arena["trigger_rel"])):
		result.append(
			_entry(
				"go_to_ambush",
				"go_to_ambush",
				"walk into the arena",
				Programs.steer(player, _vec(arena["trigger_rel"]), false)
			)
		)
	for pickup in (state["pickups"] as Array).slice(0, 2):
		result.append(
			_entry(
				"pick_up:%s" % pickup["id"],
				"pick_up",
				"collect %s" % pickup["kind"],
				Programs.steer(player, _vec(pickup["rel"]), false)
			)
		)
	# A living boss makes its room the goal: leaving is never offered while it fights.
	var boss_alive := enemies.any(func(enemy: Dictionary) -> bool: return enemy["is_boss"])
	var exits := 0
	for door in state["exits"]:
		if boss_alive or bool(door["gated"]) or exits >= MAX_EXITS:
			continue
		exits += 1
		result.append(
			_entry(
				"go_to_exit:%s" % door["id"],
				"go_to_exit",
				"head for the %s exit" % door["id"],
				Programs.steer(player, _vec(door["rel"]), true)
			)
		)
	var jumps: Array = [
		_entry("jump:left", "jump", "jump left", Programs.jump(-1, Programs.JUMP_HOLD_FRAMES)),
		_entry("jump:right", "jump", "jump right", Programs.jump(1, Programs.JUMP_HOLD_FRAMES)),
	]
	return result.slice(0, MAX_CANDIDATES - jumps.size()) + jumps


## Fight options against `target`: approach, retreat, the boss opener, shots, pulse, beam switches
## and the jump over it.
static func _fight(state: Dictionary, target: Dictionary, player: Player) -> Array:
	var me: Dictionary = state["player"]
	var kit: Dictionary = state["kit"]
	var abilities: Array = kit["abilities"]
	var grounded := bool(me["grounded"])
	var ball: bool = me["form"] == "ball"
	var is_boss := bool(target["is_boss"])
	var rel := _vec(target["rel"])
	var toward := _sign(rel.x)
	var reach := shot_reach(abilities)
	var result: Array = []
	if is_boss:
		var goal := boss_goal(target)
		result.append(
			_entry(
				"approach:%s" % target["id"],
				"approach",
				"move to firing range of %s" % target["type"],
				Programs.steer(player, Vector2(Aim.firing_step(goal[0], goal[1]), 0), false)
			)
		)
	else:
		result.append(
			_entry(
				"approach:%s" % target["id"],
				"approach",
				"approach enemy %s (%s)" % [target["id"], target["type"]],
				Programs.steer(player, rel, false)
			)
		)
	if not is_boss or retreat_stays_in_arena(target, -toward):
		result.append(
			_entry(
				"retreat",
				"retreat",
				"run away from %s" % target["type"],
				Programs.run(-toward, Programs.STEP_FRAMES)
			)
		)
	if is_boss and not ball:
		result.append_array(_opener(target, kit, grounded, reach, int(me["facing"])))
	var aim := target_aim(target, grounded, reach)
	if abilities.has("beam") and not ball and rel.length() <= SHOT_RANGE:
		if not aim.is_empty():
			result.append(
				_entry(
					"shoot:%s:%s" % [target["id"], aim],
					"shoot",
					"fire the crossbow %s at %s" % [aim.replace("_", " "), target["type"]],
					Programs.shoot(toward, aim, &"fire_beam", int(me["facing"]))
				)
			)
		elif grounded and not is_boss:
			var take_off := PlayerConfig.JUMP_VELOCITY
			if abilities.has("high_jump"):
				take_off = Catalog.HIGH_JUMP_IMPULSE
			var frame := Aim.jump_fire_frame(-(rel - Aim.EYE).y, take_off)
			if frame > 0:
				result.append(
					_entry(
						"jump_shoot:%s" % target["id"],
						"jump_shoot",
						"jump and fire the crossbow level at %s above" % target["type"],
						Programs.jump_shoot(toward, frame, int(me["facing"]))
					)
				)
	var harpoon := _harpoon_target(state["enemies"], int(kit["missiles"]))
	if not harpoon.is_empty() and not ball:
		var hrel := _vec(harpoon["rel"])
		var haim := target_aim(harpoon, grounded, reach)
		if not haim.is_empty():
			result.append(
				_entry(
					"harpoon:%s:%s" % [harpoon["id"], haim],
					"harpoon",
					"fire a harpoon %s at %s" % [haim.replace("_", " "), harpoon["type"]],
					Programs.shoot(_sign(hrel.x), haim, &"fire_missile", int(me["facing"]))
				)
			)
	var kinds: Array = target["hurt_by"]
	if (
		kinds.has("bomb")
		and not _beam_hurts(kinds)
		and abilities.has("slipstream")
		and (grounded or ball)
		and rel.length() <= PULSE_RANGE
		and absf(rel.y) <= PULSE_LEVEL
	):
		result.append(
			_entry(
				"pulse:%s" % target["id"],
				"pulse",
				"roll in and drop a Resonance Pulse at %s" % target["type"],
				Programs.pulse(rel.x, ball)
			)
		)
	if not ball:
		result.append_array(_beam_switches(target, kit))
	var floating := is_boss and rel.y < -FLOATING_ABOVE
	if grounded and not floating and rel.length() <= THREAT_RANGE:
		result.append(
			_entry(
				"jump_over:%s" % target["id"],
				"jump_over",
				"jump over %s" % target["type"],
				Programs.jump(toward, Programs.JUMP_HOLD_FRAMES)
			)
		)
	return result


## The boss's opener shot, when its shell is closed, the opener's beam is equipped and an aim
## from here lines up with the opener's point (its body or its Echo grate).
static func _opener(
	boss: Dictionary, kit: Dictionary, grounded: bool, reach: float, facing: int
) -> Array:
	var opener = boss.get("opener")
	if bool(boss.get("open", true)) or not opener is Dictionary or not bool(opener["owned"]):
		return []
	if opener["via"] == "punish" or opener["beam"] != kit["beam"]:
		return []
	var goal := boss_goal(boss)
	var point: Vector2 = goal[0]
	var aim := Aim.line_up(point, grounded, goal[1], reach)
	if aim.is_empty():
		return []
	var through := "through the grate at" if opener["via"] == "grate" else "at"
	return [
		_entry(
			"open_boss:%s:%s" % [boss["id"], aim],
			"open_boss",
			(
				"fire the %s %s %s %s to open its shell"
				% [BEAM_NAMES[opener["beam"]], aim.replace("_", " "), through, boss["type"]]
			),
			Programs.shoot(_sign(point.x), aim, &"fire_beam", facing)
		)
	]


## One `select_beam:<beam>` per owned, unequipped beam; the label says when it hurts or opens
## `target`.
static func _beam_switches(target: Dictionary, kit: Dictionary) -> Array:
	var result: Array = []
	var owned: Array = kit.get("beams", [])
	var opener = target.get("opener")
	for beam in owned:
		if beam == kit["beam"]:
			continue
		var why := ""
		if target.get("switch_to", "") == beam:
			why = " (it hurts %s)" % target["type"]
		elif opener is Dictionary and opener["beam"] == beam and not bool(target.get("open", true)):
			why = " (it opens %s)" % target["type"]
		result.append(
			_entry(
				"select_beam:%s" % beam,
				"select_beam",
				"switch the crossbow to the %s bolt%s" % [BEAM_NAMES[beam], why],
				Programs.cycle_beam(owned.find(beam) - owned.find(kit["beam"]), owned.size())
			)
		)
	return result


## `go_to_refill:<kind>` toward the nearest refill that restores what is short: Harpoons when
## none are left, health below a third.
static func _refill(state: Dictionary, player: Player) -> Dictionary:
	var me: Dictionary = state["player"]
	var kit: Dictionary = state["kit"]
	var short: Array = []
	if int(kit.get("max_missiles", 0)) > 0 and int(kit["missiles"]) <= 0:
		short.append("harpoons")
	if float(me["health"]) < float(me["max_health"]) / 3.0:
		short.append("health")
	for refill in state.get("refills", []):
		var restores: Array = refill["restores"]
		var wanted := short.filter(func(need: String) -> bool: return restores.has(need))
		if wanted.is_empty() or _near(_vec(refill["rel"])):
			continue
		return _entry(
			"go_to_refill:%s" % refill["kind"],
			"go_to_refill",
			"go to the %s refill to restore %s" % [refill["kind"], " and ".join(wanted)],
			Programs.steer(player, _vec(refill["rel"]), true)
		)
	return {}


## Where a boss fight aims: the opener's point while the shell is closed and the opener can be
## used, else the boss body. [point relative to the feet, hit radius].
static func boss_goal(boss: Dictionary) -> Array:
	var opener = boss.get("opener")
	if (
		not bool(boss.get("open", true))
		and opener is Dictionary
		and bool(opener["owned"])
		and opener["via"] != "punish"
	):
		var radius := Aim.GRATE_RADIUS if opener["via"] == "grate" else Aim.BOSS_RADIUS
		return [_vec(opener["point_rel"]), radius]
	return [_vec(boss["rel"]), Aim.BOSS_RADIUS]


## False when a run of RETREAT_REACH px toward `direction` would leave the boss's arena (the
## boss stops fighting outside it, and past it lies the door).
static func retreat_stays_in_arena(boss: Dictionary, direction: int) -> bool:
	var arena = boss.get("arena_rel")
	if not arena is Array:
		return true
	if direction > 0:
		return float(arena[2]) >= RETREAT_REACH
	return float(arena[0]) <= -RETREAT_REACH


## Aim at `target`: a boss needs a bolt line within its body radius; other enemies use the
## quantised aim, minus a level shot that would fly under a target well above the crossbow.
static func target_aim(target: Dictionary, grounded: bool, reach: float) -> String:
	var rel := _vec(target["rel"])
	if bool(target["is_boss"]):
		return Aim.line_up(rel, grounded, Aim.BOSS_RADIUS, reach)
	var aim := aim_for(rel, grounded)
	if aim == "forward" and (rel - Aim.EYE).y < -Aim.LEVEL_TOLERANCE:
		return ""
	return aim


## Crossbow reach in px for the kit (the Long Beam stretches it).
static func shot_reach(abilities: Array) -> float:
	var stretch := Catalog.LONG_RANGE_MULTIPLIER if abilities.has("long_beam") else 1.0
	return Catalog.BEAM_RANGE * stretch


## The enemy the fight candidates aim at: the nearest visible one the kit can hurt (bosses always
## count), else the nearest visible one, else the nearest one; {} without enemies.
static func primary_target(enemies: Array) -> Dictionary:
	for enemy in enemies:
		if enemy["visible"] and (enemy["is_boss"] or not (enemy["hurt_by"] as Array).is_empty()):
			return enemy
	for enemy in enemies:
		if enemy["visible"]:
			return enemy
	return enemies[0] if not enemies.is_empty() else {}


## Candidates without programs, as sent to a policy.
static func public(candidates_list: Array) -> Array:
	return candidates_list.map(
		func(entry: Dictionary) -> Dictionary:
			return {"key": entry["key"], "kind": entry["kind"], "label": entry["label"]}
	)


static func find(candidates_list: Array, key: String) -> Dictionary:
	for entry in candidates_list:
		if entry["key"] == key:
			return entry
	return {}


## Nearest enemy shot flying at the player, or {}.
static func incoming_projectile(state: Dictionary) -> Dictionary:
	for shot in state.get("projectiles", []):
		var rel := _vec(shot["rel"]) + Vector2(0, 90)
		var velocity := _vec(shot["vel"])
		if rel.length() <= PROJECTILE_ALERT and velocity.dot(-rel) > 0.0:
			return shot
	return {}


## Aim name for a target at `rel` from the feet: the crossbow fires from about 100 px up. "" when
## no aim reaches it (grounded, with the target far below).
static func aim_for(rel: Vector2, grounded: bool) -> String:
	if grounded and rel.y > GROUNDED_AIM_DROP:
		return ""
	var offset := rel + Vector2(0, 100)
	if offset.y < -absf(offset.x) * 2.2:
		return "up"
	if offset.y < -absf(offset.x) * 0.45:
		return "diag_up"
	if not grounded and offset.y > absf(offset.x) * 2.2:
		return "down"
	if not grounded and offset.y > absf(offset.x) * 0.45:
		return "diag_down"
	return "forward"


static func _harpoon_target(enemies: Array, missiles: int) -> Dictionary:
	if missiles <= 0:
		return {}
	for enemy in enemies:
		var kinds: Array = enemy["hurt_by"]
		if kinds.has("missile") and (enemy["is_boss"] or not _beam_hurts(kinds)):
			return enemy
	return {}


static func _beam_hurts(kinds: Array) -> bool:
	return kinds.has("beam") or kinds.has("ice") or kinds.has("wave")


static func _entry(key: String, kind: String, label: String, program: Array) -> Dictionary:
	return {"key": key, "kind": kind, "label": label, "program": program}


static func _sign(value: float) -> int:
	return -1 if value < 0.0 else 1


static func _near(rel: Vector2) -> bool:
	return absf(rel.x) < 48.0 and absf(rel.y) < 160.0


static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
