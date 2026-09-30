extends RefCounted
## Playtest agent macro actions (docs/features/playtest-agent.md). `candidates()` offers 5 to 14
## labelled options for the current state; each carries a program built by
## playtest_programs.gd: one Array of held input actions per physics frame.

const Aim = preload("res://tools/playtest_aim.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const Dodge = preload("res://tools/playtest_dodge.gd")
const MAX_CANDIDATES := 14
const SHOT_RANGE := 1100.0
const THREAT_RANGE := 420.0
const PROJECTILE_ALERT := 420.0
const MAX_EXITS := 3
## A grounded player cannot aim down: a target whose origin is more than this far below the feet
## is under every aim the crossbow has, so no shot is offered at it.
const GROUNDED_AIM_DROP := 160.0
## Kinds that are movement, for stuck detection: choosing one of these means "I want to move".
## `retreat` is not one: backed into a boss arena's pocket it holds her there on purpose, and a
## stall there made the heuristic jump into the Stone Guardian (jev-r1, round 3).
const MOVING_KINDS := [
	"approach",
	"go_to_exit",
	"go_to_ambush",
	"pick_up",
	"jump",
	"go_to_refill",
	"go_to_objective",
	"go_to_door",
]
## How far a retreat runs (12 frames at run speed, rounded up); a live boss's arena edge must be
## at least this far behind the player for `retreat` to be offered.
const RETREAT_REACH := 160.0
## How far a dash program carries the player (0.18 s at 1500 px/s, then 9 walking frames); a dash
## into a shot is not offered when it would leave a live boss's arena (a probe dashed out of the
## depths_02 door at the arena edge and lost the fight).
const DASH_REACH := 384.0
## A trigger this far (px) above or below the feet is not on her floor.
const AMBUSH_FLOOR := 160.0
## The boss approach stops this far (px) inside the arena's edge.
const ARENA_MARGIN := 48.0
## A shot this close (px) that will cross the player's column between DUCK_CLEAR and DUCK_REACH
## px above the feet flies over a curled ball (56 px tall) and would hit the standing body (176).
const DUCK_RANGE := 300.0
## A refill more than this far (px) above the feet is out of one jump's reach; the steer would
## only jump in place under it (jev-c3 did that below a vaults_02 shrine 600 px up for 320 s).
const REFILL_CLIMB := 320.0
## A shot at an ordinary enemy is offered when its bolt line passes this close (px) to the enemy's
## origin; a body is about a tile, and a hopper's origin sits 100 px under a level bolt.
const ENEMY_RADIUS := 120.0
const DUCK_CLEAR := 80.0
const DUCK_REACH := 200.0
## A boss whose centre is this far above the feet floats: jumping toward it lands in its body.
const FLOATING_ABOVE := 160.0
## A Resonance Pulse is offered at an enemy this close and this level with the player.
const PULSE_RANGE := 400.0
const PULSE_LEVEL := 96.0
const BEAM_NAMES := {"base": "seed bolt", "ice": "Snare (ice)", "wave": "Echo (wave)"}


## Returns [{key, kind, label, program}] for `state` (from playtest_state.gd). The first entry is
## always `idle` and the last two the plain jumps; the rest follow a fixed priority, cut to fit, so
## the list is deterministic. `route` holds campaign mode's candidates (tools/playtest_campaign.gd):
## they lead, except `go_to_door`, which takes the place of `go_to_exit`.
static func candidates(state: Dictionary, player: Player, route: Array = []) -> Array:
	var result: Array = [_entry("idle", "idle", "stand still", Programs.idle())]
	if state.get("room") == null:
		return result
	result.append_array(
		route.filter(func(entry: Dictionary) -> bool: return entry["kind"] != "go_to_door")
	)
	var me: Dictionary = state["player"]
	var abilities: Array = state["kit"]["abilities"]
	var enemies: Array = state["enemies"]
	for enemy in enemies:
		if enemy["is_boss"] and bool(enemy.get("engaged", true)):
			var dodge := Dodge.candidate(enemy, player, bool(me["grounded"]))
			if not dodge.is_empty():
				result.append(dodge)
			break
	var target := primary_target(enemies)
	# A frost floater the route is about to freeze is a platform, not a target: a bolt kills it
	# (jev-c2 shot the vaults_02 floaters down instead of freezing them, and stalled there).
	var platform := route.any(func(entry: Dictionary) -> bool: return entry["kind"] == "freeze")
	if not target.is_empty() and not (platform and target["type"] == "frost_floater"):
		result.append_array(_fight(state, target, player))
	var shot := incoming_projectile(state)
	if (
		not shot.is_empty()
		and abilities.has("undertow_dash")
		and bool(me["dash_ready"])
		and _boss_arenas_keep(enemies, _sign(float(shot["rel"][0])), DASH_REACH)
	):
		result.append(
			_entry(
				"dash_through",
				"dash_through",
				"dash into the incoming %s shot" % shot["style"],
				Programs.dash(_sign(float(shot["rel"][0])))
			)
		)
	var low := duck_shot(state)
	if not low.is_empty():
		result.append(
			_entry(
				"duck",
				"duck",
				"curl into a ball so the %s shot flies over" % low["style"],
				Programs.duck()
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
	# In campaign mode only on the trigger's own floor: the route reaches it otherwise, and a straight
	# steer at a trigger far below stood still on the ledge above it (jev-r3 spent 550 s in fringe_03).
	var trigger := _vec(arena["trigger_rel"]) if arena != null else Vector2.ZERO
	if (
		arena != null
		and arena["state"] == "armed"
		and not _near(trigger)
		and (route.is_empty() or absf(trigger.y) <= AMBUSH_FLOOR)
	):
		result.append(
			_entry(
				"go_to_ambush",
				"go_to_ambush",
				"walk into the arena",
				Programs.steer(player, trigger, false)
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
	if not route.is_empty():
		if not boss_alive:
			result.append_array(
				route.filter(func(entry: Dictionary) -> bool: return entry["kind"] == "go_to_door")
			)
		return result.slice(0, MAX_CANDIDATES - 2) + _jumps()
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
	var jumps := _jumps()
	return result.slice(0, MAX_CANDIDATES - jumps.size()) + jumps


static func _jumps() -> Array:
	return [
		_entry("jump:left", "jump", "jump left", Programs.jump(-1, Programs.JUMP_HOLD_FRAMES)),
		_entry("jump:right", "jump", "jump right", Programs.jump(1, Programs.JUMP_HOLD_FRAMES)),
	]


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
	# A boss fights, and can be hurt, only while the player is inside its arena (boss-rework,
	# section 4): from outside, the only fight move is to walk in. A kiln_03 probe stood east of
	# the arena step shooting into it for 280 s.
	var engaged := not is_boss or bool(target.get("engaged", true))
	var result: Array = []
	if is_boss:
		var goal := boss_goal(target)
		var step := Vector2(Aim.firing_step(goal[0], goal[1]), 0)
		var arena = target.get("arena_rel")
		if arena is Array:
			# The firing range may lie past the arena's edge (the vaults_03 east pocket is 260 px
			# deep); stepping out there disengages the boss, and walking back in re-engaged it, for
			# 180 s in a Jev probe. Stop inside instead.
			var low := float(arena[0]) + ARENA_MARGIN
			var high := float(arena[2]) - ARENA_MARGIN
			if low <= high:
				step.x = clampf(step.x, low, high)
		var spot := _opener_spot(target)
		if not engaged:
			step = rel
		elif not spot.is_empty():
			# Out of sight of the opener: climb to a spot it lines up from.
			step = _vec(spot)
		result.append(
			_entry(
				"approach:%s" % target["id"],
				"approach",
				(
					("move to firing range of %s" if engaged else "walk into the arena of %s")
					% target["type"]
				),
				Programs.steer(player, step, false)
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
	# No retreat from a threat out of reach, or into a wall: Jev at 10 health retreated from a bat
	# 500 px away into the vaults_02 east wall 2,600 times (jev-r2, round 3).
	var pinned := player.test_move(player.global_transform, Vector2(-toward * 24, 0))
	if (
		(not is_boss or stays_in_arena(target, -toward, RETREAT_REACH))
		and rel.length() <= THREAT_RANGE
		and not pinned
	):
		result.append(
			_entry(
				"retreat",
				"retreat",
				"run away from %s" % target["type"],
				Programs.run(-toward, Programs.STEP_FRAMES)
			)
		)
	if is_boss and not ball and engaged:
		result.append_array(_opener(target, kit, grounded, reach, int(me["facing"])))
	var aim := target_aim(target, grounded, reach)
	if abilities.has("beam") and not ball and engaged and rel.length() <= SHOT_RANGE:
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
	var harpoon := _harpoon_target(state["enemies"], kit)
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


## The boss's opener shot, when its shell is closed, its current opening is unspent, a Harpoon is
## left to follow it, the opener's beam is equipped and an aim from here lines up with the
## opener's point (its body or its Echo grate) in sight.
static func _opener(
	boss: Dictionary, kit: Dictionary, grounded: bool, reach: float, facing: int
) -> Array:
	var opener = boss.get("opener")
	if bool(boss.get("open", true)) or not opener is Dictionary or not bool(opener["owned"]):
		return []
	if not bool(boss.get("opening", true)) or int(kit.get("missiles", 0)) <= 0:
		return []
	if not bool(opener.get("visible", true)):
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


## Where to stand for a closed boss's opener that is out of sight from here ([] when it is in
## sight, spent, unusable, or no spot was found).
static func _opener_spot(boss: Dictionary) -> Array:
	var opener = boss.get("opener")
	if bool(boss.get("open", true)) or not bool(boss.get("opening", true)):
		return []
	if not opener is Dictionary or not bool(opener["owned"]) or bool(opener.get("visible", true)):
		return []
	return opener.get("spot_rel", [])


## `go_to_refill:<kind>` toward the nearest refill that restores what is short: Harpoons when
## none are left, health below a third; none that is out of a jump's reach above.
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
		if float(refill["rel"][1]) < -REFILL_CLIMB:
			continue
		var label := "go to the %s refill to restore %s" % [refill["kind"], " and ".join(wanted)]
		var program: Variant = Programs.steer(player, _vec(refill["rel"]), true)
		var boss := Dodge.boss_between(state["enemies"], _vec(refill["rel"]))
		if not boss.is_empty() and Dodge.headroom(player, _vec(boss["rel"])):
			label += ", jumping over %s on the way" % boss["type"]
			program = Dodge.JumpOver.new(player, _vec(refill["rel"]), _vec(boss["rel"]))
		return _entry("go_to_refill:%s" % refill["kind"], "go_to_refill", label, program)
	return {}


## Where a boss fight aims: the opener's point while the shell is closed, the opening unspent and
## the opener usable, else the boss body. [point relative to the feet, hit radius].
static func boss_goal(boss: Dictionary) -> Array:
	var opener = boss.get("opener")
	if (
		not bool(boss.get("open", true))
		and bool(boss.get("opening", true))
		and opener is Dictionary
		and bool(opener["owned"])
		and opener["via"] != "punish"
	):
		var radius := Aim.GRATE_RADIUS if opener["via"] == "grate" else Aim.BOSS_RADIUS
		return [_vec(opener["point_rel"]), radius]
	return [_vec(boss["rel"]), Aim.BOSS_RADIUS]


## False when a move of `reach` px toward `direction` would leave the boss's arena (the boss
## stops fighting outside it, and past it lies the door).
static func stays_in_arena(boss: Dictionary, direction: int, reach: float) -> bool:
	var arena = boss.get("arena_rel")
	if not arena is Array:
		return true
	if direction > 0:
		return float(arena[2]) >= reach
	return float(arena[0]) <= -reach


## True unless a move of `reach` px toward `direction` leaves a live boss's arena.
static func _boss_arenas_keep(enemies: Array, direction: int, reach: float) -> bool:
	return enemies.all(
		func(enemy: Dictionary) -> bool:
			return not enemy["is_boss"] or stays_in_arena(enemy, direction, reach)
	)


## Aim at `target`: a boss needs a bolt line within its body radius; other enemies use the
## quantised aim, minus a level shot that would fly under a target well above the crossbow, and
## minus any aim whose bolt line passes more than ENEMY_RADIUS from it (jev-c2 fired straight up
## 1,200 times at a vaults_01 ceiling diver 185 px to the side).
static func target_aim(target: Dictionary, grounded: bool, reach: float) -> String:
	var rel := _vec(target["rel"])
	if bool(target["is_boss"]):
		return Aim.line_up(rel, grounded, Aim.BOSS_RADIUS, reach)
	var aim := aim_for(rel, grounded)
	if aim == "forward" and (rel - Aim.EYE).y < -Aim.LEVEL_TOLERANCE:
		return ""
	if aim.is_empty() or Aim.miss(rel, aim, SHOT_RANGE) > ENEMY_RADIUS:
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


## The nearest shot about to cross the player's column at body height but above a curled ball,
## while Slipstream can curl a standing, grounded player; {} otherwise. Probe 2026-09-28
## (kiln_03, stage 3 Ember Fan from 10 tiles): curling in place cleared 17 of 17 start times,
## every jump or run 0 to 2 of 17, because the five-way fan leaves no gap a standing body fits.
static func duck_shot(state: Dictionary) -> Dictionary:
	var me: Dictionary = state["player"]
	if not (state["kit"]["abilities"] as Array).has("slipstream"):
		return {}
	if not bool(me["grounded"]) or me["form"] != "standing":
		return {}
	for shot in state.get("projectiles", []):
		var rel := _vec(shot["rel"])
		var velocity := _vec(shot["vel"])
		if rel.length() > DUCK_RANGE or absf(velocity.x) < 1.0 or rel.x * velocity.x >= 0.0:
			continue
		var height := -(rel.y + velocity.y * (-rel.x / velocity.x))
		if height >= DUCK_CLEAR and height <= DUCK_REACH:
			return shot
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


## The enemy a Harpoon is offered at: one in sight that it hurts and the bolt cannot. Never
## through rock, and never a second one at a boss while the first is still flying, since one
## opening takes one Harpoon (boss-rework R8).
static func _harpoon_target(enemies: Array, kit: Dictionary) -> Dictionary:
	if int(kit["missiles"]) <= 0:
		return {}
	for enemy in enemies:
		var kinds: Array = enemy["hurt_by"]
		if not kinds.has("missile") or not bool(enemy["visible"]):
			continue
		if enemy["is_boss"] and int(kit.get("harpoons_flying", 0)) > 0:
			continue
		if enemy["is_boss"] and not bool(enemy.get("engaged", true)):
			continue
		if enemy["is_boss"] or not _beam_hurts(kinds):
			return enemy
	return {}


## True when an equipped bolt damages it; the Snare only freezes (0 damage), so an enemy it
## alone reaches still gets the Harpoon or the Resonance Pulse offered.
static func _beam_hurts(kinds: Array) -> bool:
	return kinds.has("beam") or kinds.has("wave")


static func _entry(key: String, kind: String, label: String, program: Variant) -> Dictionary:
	return {"key": key, "kind": kind, "label": label, "program": program}


static func _sign(value: float) -> int:
	return -1 if value < 0.0 else 1


static func _near(rel: Vector2) -> bool:
	return absf(rel.x) < 48.0 and absf(rel.y) < 160.0


static func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
