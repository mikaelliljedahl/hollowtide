extends RefCounted
## Boss attack answers for the playtest agent (docs/features/playtest-agent.md, "Candidates"):
## while a boss telegraphs an attack with a known answer, `dodge:<attack>` waits for the moment
## that answer needs and plays it. The answers come from dodge probes in the real vaults_03 arena
## (real player, forced stage 3 attacks, 17 start times per response, 2026-09-29): a jump in
## place clears Fault Slam and Boulder Volley when it starts 0.15 to 0.9 s before the shockwave
## or the rock arrives, a step of about 110 px clears Rockfall, and running away clears Shoulder
## Charge; against the low roof at the west end the body is pinned, and there Rockfall is cleared
## by rolling under the roof and the charge by standing still (it stops short of the pocket). The
## Cinder Warden probe in kiln_03 (player at cell 26, boss 6 tiles east, stage 3): curling in place
## clears the Ember Fan at any start (15/17), standing still clears the Heat Ring (17/17), running
## away clears the Scuttle Rush when started within 0.9 s (10/17). The Tidal Heart's answers are
## in tools/playtest_tide.gd. Enemy shots flying at her are dodged too: `duck_shot` and
## `incoming_projectile` find the shot a curl or a dash answers.

const Programs = preload("res://tools/playtest_programs.gd")
const Tide = preload("res://tools/playtest_tide.gd")
const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
## Shot speeds and origins of scripts/enemies/boss_attacks.gd (`emissions`).
const SLAM_SPEED := 430.0
const SLAM_ORIGIN := 70.0
const SLAM_PAIR_GAP := 0.85
const VOLLEY_SPEED := 360.0
const VOLLEY_ORIGIN := 60.0
## Seconds from release until the last rock has landed, and until the last fire pillar is out.
const ROCK_FALL := 0.9
const PILLAR_TIME := 1.0
## A column's circle is 120 px wide; the body is 56: a centre this close to a column is hit.
const COLUMN_CLEAR := 92.0
## Clearance kept from the boss body's centre (body radius plus half the player plus a margin).
const BODY_CLEAR := 140.0
const SPOT_SCAN := 320
const SPOT_STEP := 8
const SETTLE_FRAMES := 12
## A walk stops this close (px) to its spot; walking stops in about 20 px.
const STEP_TOLERANCE := 24.0
## Probe (px) below a step's spot for her floor.
const FLOOR_PROBE := 8.0
## Ember Fan (scripts/enemies/boss_attacks.gd): speed, origin, the second fan's delay in
## desperation, and the seconds a curled ball waits after the fan reaches her column.
const FAN_SPEED := 380.0
const FAN_ORIGIN := 60.0
const FAN_REPEAT := 0.3
const FAN_PASS := 0.35
## Seconds after release a player standing still waits while the Heat Ring passes her.
const RING_PASS := 1.0
## Seconds Lanternjaw's Undertow Pull drags once released (scripts/enemies/mini/lanternjaw.gd).
const PULL_SECONDS := 1.2
const DESPERATION_STAGE := 4
## Armored guard (scripts/enemies/enemy_ai.gd): sight, charge speed, and the seconds before the
## charge reaches her at which the jump toward it starts (the probe cleared 0.72 to 0.97 s).
const GUARD_SIGHT := 520.0
const GUARD_LEVEL := 150.0
const GUARD_SPEED := 540.0
const GUARD_LEAD := 0.85
## Half the body width plus a shot's radius: a shot this close to the body's centre line hits.
const REACH := 40.0
## The chest, where an aimed rock meets a standing body.
const CHEST := Vector2(0, -88)
## Seconds before arrival at which the jump starts: the probes cleared 0.15 to 0.9 s.
const JUMP_LEAD := 0.45
const JUMP_HOLD := 40
const DOUBLE_JUMP_HOLD := 20
const RUN_FRAMES := 60
## The run from a Shoulder Charge stops this far (px) inside the arena's edge.
const CHARGE_EDGE := 60.0
## Rolling frames under a low roof behind a pinned player (about 90 px), and the most frames the
## roll back out may take.
const ROLL_IN_FRAMES := 16
const ROLL_OUT_LIMIT := 60
## A standing body blocked this close behind (away from the boss) is pinned.
const PINNED_PROBE := 40.0
const FPS := 60.0
## Jumping over a boss body (radius BODY_RADIUS) on the way to a refill: the air above its top that
## must be free, the centre distance at which a running jump takes off (the Updraft Cloak rises
## past the body's top in about 0.14 s, 100 px at a run), how long jump is held, and a cap.
const BODY_RADIUS := 92.0
const JUMP_OVER_ROOM := 240.0
const JUMP_OVER_TAKEOFF := 230.0
const JUMP_OVER_HOLD := 40
const JUMP_OVER_LIMIT := 180
## An enemy shot this close (px) and flying at her is incoming (`dash_through`).
const PROJECTILE_ALERT := 420.0
## A shot this close (px) that will cross the player's column between DUCK_CLEAR and DUCK_REACH
## px above the feet flies over a curled ball (56 px tall) and would hit the standing body (176).
const DUCK_RANGE := 300.0
const DUCK_CLEAR := 80.0
const DUCK_REACH := 200.0


## The dodge candidate for the boss's current attack, or {} when none is known or it is too late.
static func candidate(boss: Dictionary, player: Player, grounded: bool) -> Dictionary:
	var attack := String(boss.get("attack", ""))
	var phase := String(boss.get("attack_state", ""))
	if not grounded or player.is_ball:
		return {}
	# The Tidal Heart's shots keep flying through its recovery; they are all in `shots_rel`.
	if Tide.answers(StringName(attack)):
		return Tide.candidate(boss, player)
	# The embers keep flying through the fan's punish window.
	if phase not in ["telegraph", "active"] and not (attack == "ember_fan" and phase == "recover"):
		return {}
	var rel := Vector2(float(boss["rel"][0]), float(boss["rel"][1]))
	var away := -1 if rel.x > 0.0 else 1
	var pinned := player.test_move(player.global_transform, Vector2(away * PINNED_PROBE, 0))
	# Seconds until the attack is released; negative once it is out.
	var release := (
		float(boss.get("attack_left", 0.0))
		if phase == "telegraph"
		else -float(boss.get("attack_elapsed", 0.0))
	)
	var desperate := int(boss.get("stage", 1)) >= DESPERATION_STAGE
	var program: Array = []
	var label := ""
	# Every charge, the main bosses' and the mini-bosses', stops 128 px short of the first wall.
	var kind := "charge" if Patterns.is_charge(StringName(attack)) else attack
	match kind:
		"fault_slam":
			var travel := maxf(absf(rel.x) - SLAM_ORIGIN - REACH, 0.0) / SLAM_SPEED
			program = _jumps(release + travel, SLAM_PAIR_GAP if desperate else 0.0)
			label = "jump in place over the Fault Slam shockwave (it runs to both walls; no retreat outruns it)"
		"boulder_volley":
			var distance := maxf((rel - CHEST).length() - VOLLEY_ORIGIN - REACH, 0.0)
			program = _jumps(release + distance / VOLLEY_SPEED, 0.0)
			label = "jump in place over the Boulder Volley's aim line as the rocks arrive"
		"rockfall", "vent_burst":
			var landed := release + (ROCK_FALL if attack == "rockfall" else PILLAR_TIME)
			if landed < 0.0:
				return {}
			var name := "Rockfall" if attack == "rockfall" else "Vent Burst"
			var frames := roundi(landed * FPS) + SETTLE_FRAMES
			var spot: Variant = safe_spot(boss.get("columns_rel", []), rel.x, player)
			if spot is float:
				var step := StepTo.new(player, float(spot), frames)
				return _entry(
					attack, "step to the gap between the %s circles and wait" % name, step
				)
			if pinned:
				var roll := RollUnder.new(player, away, frames)
				return _entry(
					attack, "curl and roll under the low roof until the %s is over" % name, roll
				)
		"ember_fan":
			# Curl where she stands and stay curled until the fan (both fans in desperation) passed.
			var reach := maxf(rel.length() - FAN_ORIGIN, 0.0) / FAN_SPEED
			var passed := release + reach + FAN_PASS + (FAN_REPEAT if desperate else 0.0)
			if phase == "recover":
				passed = embers_left(player)
			if passed < 0.0:
				return {}
			program = Programs.hold([&"slipstream"], 2)
			program.append_array(Programs.hold([], roundi(passed * FPS)))
			program.append_array(Programs.hold([&"slipstream"], 2))
			program.append_array(Programs.hold([], Programs.SLIP_FRAMES))
			label = "curl into a ball where she stands until the Ember Fan has flown over"
		"undertow_pull":
			# Lanternjaw's current drags her toward the jaw while it is active: run against it
			# until it ends (round 10 probe in depths_08: the loop's approach walked into the jaw).
			var left := release + PULL_SECONDS
			if left <= 0.0:
				return {}
			program = Programs.run(away, roundi(left * FPS))
			label = "run away from the jaw against the Undertow Pull until it ends"
		"heat_ring":
			if phase != "telegraph":
				return {}
			program = Programs.hold([], roundi((release + RING_PASS) * FPS))
			label = "stand still: the Heat Ring's gap is aimed at her"
		"charge":
			if phase != "telegraph":
				return {}
			if pinned:
				program = Programs.hold([], int((release + 0.6) * FPS))
				label = "stand still in the pocket: the charge stops short of it"
			else:
				# Run to the wall's pocket but not out of the arena (the boss stops fighting there).
				var arena = boss.get("arena_rel")
				var edge := float(arena[2 if away > 0 else 0]) if arena is Array else away * 720.0
				var run := StepTo.new(player, edge - away * CHARGE_EDGE, RUN_FRAMES, true)
				return _entry(
					attack, "run away from the %s into the wall's pocket" % attack.capitalize(), run
				)
	if program.is_empty():
		return {}
	return _entry(attack, label, program)


## `dodge:<id>` for an armored guard winding up its charge on her floor: jump toward it so the
## charge runs under her. Guard probe on the vaults_01 floor (guard 384 px away, 9 start times):
## a jump toward it started 0.05 to 0.3 s into the 0.42 s wind-up cleared 6 of 9, standing or
## curling 0 of 9. Jev round 3 took 621 damage from guards in vaults_01/02 while it shot other
## ambush enemies.
static func guard_candidate(enemy: Dictionary, grounded: bool) -> Dictionary:
	if enemy["type"] != "armored_guard" or not grounded or not enemy.has("wind_up_left"):
		return {}
	var rel := Vector2(float(enemy["rel"][0]), float(enemy["rel"][1]))
	if absf(rel.x) > GUARD_SIGHT or absf(rel.y) > GUARD_LEVEL:
		return {}
	var arrival := float(enemy["wind_up_left"]) + maxf(absf(rel.x) - REACH, 0.0) / GUARD_SPEED
	var frames := Programs.hold([], maxi(roundi((arrival - GUARD_LEAD) * FPS), 0))
	frames.append_array(Programs.jump(-1 if rel.x < 0.0 else 1, JUMP_HOLD))
	return {
		"key": "dodge:%s" % enemy["id"],
		"kind": "dodge",
		"label": "jump over the armored guard's charge (%s)" % enemy["id"],
		"program": frames,
	}


static func _entry(attack: String, label: String, program: Variant) -> Dictionary:
	return {"key": "dodge:%s" % attack, "kind": "dodge", "label": label, "program": program}


## True for a dodge that keeps her standing where she is (its label starts "stand still"), so a
## shot fired in place loses nothing.
static func stays_put(entry: Dictionary) -> bool:
	return (
		entry.get("kind") == "dodge" and String(entry.get("label", "")).begins_with("stand still")
	)


## The feet x offset nearest the player that keeps clear of every locked column and of the boss
## body, on her floor, with nothing solid in the way on the walk there; null when there is none.
static func safe_spot(columns: Array, boss_x: float, player: Player) -> Variant:
	if columns.is_empty():
		return null
	for distance in range(0, SPOT_SCAN + 1, SPOT_STEP):
		for side in [-1, 1]:
			var x := float(distance * side)
			if absf(x - boss_x) < BODY_CLEAR:
				continue
			if columns.any(func(c: int) -> bool: return absf(x - float(c)) < COLUMN_CLEAR):
				continue
			if distance > 0 and player.test_move(player.global_transform, Vector2(x, 0)):
				continue
			# The probed step stays on her floor: off the vaults_03 alcove roof it fell to the
			# floor beside the Guardian and touched it.
			var spot := Transform2D(0.0, player.global_position + Vector2(x, 0))
			if not player.test_move(spot, Vector2(0, FLOOR_PROBE)):
				continue
			return x
	return null


## Seconds until the last enemy shot still flying at her has passed her column, plus FAN_PASS;
## negative when none is. The fan's embers fly on through its punish window.
static func embers_left(player: Player) -> float:
	var left := -1.0
	for node in player.get_tree().get_nodes_in_group(&"enemy_shot"):
		var shot := node as EnemyProjectile
		if shot == null or shot.is_queued_for_deletion():
			continue
		var dx := player.global_position.x - shot.global_position.x
		var closing := shot.direction.x * shot.speed * signf(dx)
		if closing > 1.0:
			left = maxf(left, (absf(dx) - REACH) / closing + FAN_PASS)
	return left


## Waits until JUMP_LEAD before `arrival` (seconds from now), then jumps in place; with a `gap`,
## lands and jumps again for the second shockwave. [] when the shot has already arrived.
static func _jumps(arrival: float, gap: float) -> Array:
	if arrival < 0.1:
		return []
	var wait := maxi(roundi((arrival - JUMP_LEAD) * FPS), 0)
	var frames := Programs.hold([], wait)
	if gap <= 0.0:
		frames.append_array(Programs.jump(0, JUMP_HOLD))
		return frames
	frames.append_array(Programs.hold([&"jump"], DOUBLE_JUMP_HOLD))
	frames.append_array(Programs.hold([], roundi(gap * FPS) - DOUBLE_JUMP_HOLD))
	frames.append_array(Programs.jump(0, DOUBLE_JUMP_HOLD))
	return frames


## A live boss standing on the floor between the player and `goal`, or {}.
static func boss_between(enemies: Array, goal: Vector2) -> Dictionary:
	for enemy in enemies:
		if not enemy["is_boss"]:
			continue
		var rel := Vector2(float(enemy["rel"][0]), float(enemy["rel"][1]))
		if rel.x * goal.x > 0.0 and absf(rel.x) < absf(goal.x) and absf(rel.y) < 200.0:
			return enemy
	return {}


## True when nothing solid hangs within JUMP_OVER_ROOM px above the top of a boss body at `rel`
## (from the feet), so a running jump clears it. Under the vaults_03 west platform it does not.
static func headroom(player: Player, rel: Vector2) -> bool:
	var top := player.global_position + rel - Vector2(0, BODY_RADIUS)
	var query := PhysicsRayQueryParameters2D.create(top, top - Vector2(0, JUMP_OVER_ROOM), 1)
	return player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


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
		var rel := _vec2(shot["rel"])
		var velocity := _vec2(shot["vel"])
		if rel.length() > DUCK_RANGE or absf(velocity.x) < 1.0 or rel.x * velocity.x >= 0.0:
			continue
		var height := -(rel.y + velocity.y * (-rel.x / velocity.x))
		if height >= DUCK_CLEAR and height <= DUCK_REACH:
			return shot
	return {}


## Nearest enemy shot flying at the player, or {}.
static func incoming_projectile(state: Dictionary) -> Dictionary:
	for shot in state.get("projectiles", []):
		var rel := _vec2(shot["rel"]) + Vector2(0, 90)
		var velocity := _vec2(shot["vel"])
		if rel.length() <= PROJECTILE_ALERT and velocity.dot(-rel) > 0.0:
			return shot
	return {}


static func _vec2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


## Runs toward `goal` (relative to the feet when built) and, once the boss body at `boss` is
## JUMP_OVER_TAKEOFF px ahead, jumps and keeps running over it, then steers on to the goal.
class JumpOver:
	extends RefCounted

	var finished := false
	var _player: Player
	var _goal := Vector2.ZERO
	var _boss_x := 0.0
	var _direction := 1
	var _jump := -1
	var _frame := 0

	func _init(player: Player, goal: Vector2, boss: Vector2) -> void:
		_player = player
		_goal = player.global_position + goal
		_boss_x = player.global_position.x + boss.x
		_direction = -1 if goal.x < 0.0 else 1

	func next() -> Array:
		_frame += 1
		var move := Programs.move_action(_direction)
		var ahead := (_boss_x - _player.global_position.x) * _direction
		if _jump < 0 and ahead <= JUMP_OVER_TAKEOFF and _player.is_on_floor():
			_jump = _frame
		if _jump >= 0 and _frame - _jump < JUMP_OVER_HOLD:
			return [move, &"run", &"jump"]
		var past := (_goal.x - _player.global_position.x) * _direction <= Programs.NEAR_TARGET
		finished = _frame >= JUMP_OVER_LIMIT or (past and _player.is_on_floor())
		return [move, &"run"]


## Walks (or runs) to `offset` px from where she stands, then holds still until frame `until`.
class StepTo:
	extends RefCounted

	var finished := false
	var _player: Player
	var _target := 0.0
	var _until := 0
	var _frame := 0
	var _running := false

	func _init(player: Player, offset: float, until: int, running := false) -> void:
		_player = player
		_target = player.global_position.x + offset
		_until = until
		_running = running

	func next() -> Array:
		_frame += 1
		finished = _frame >= _until
		var gap := _target - _player.global_position.x
		if absf(gap) < STEP_TOLERANCE:
			return []
		var move := Programs.move_action(-1 if gap < 0.0 else 1)
		return [move, &"run"] if _running else [move]


## Curls, rolls `toward` under the roof, stays curled until the rocks have landed, rolls back
## out to the spot she stood on (under the roof she cannot stand up) and stands up.
class RollUnder:
	extends RefCounted

	var finished := false
	var _player: Player
	var _toward := 1
	var _start_x := 0.0
	var _landed := 0
	var _frame := 0
	var _out_from := -1

	func _init(player: Player, toward: int, landed: int) -> void:
		_player = player
		_toward = toward
		_start_x = player.global_position.x
		_landed = landed

	func next() -> Array:
		_frame += 1
		if _frame <= 2:
			return [&"slipstream"]
		if _frame <= 2 + ROLL_IN_FRAMES:
			return [Programs.move_action(_toward)]
		if _frame < _landed:
			return []
		var back := (_start_x - _player.global_position.x) * _toward >= 0.0
		if _out_from < 0 and not back and _frame < _landed + ROLL_OUT_LIMIT:
			return [Programs.move_action(-_toward)]
		if _out_from < 0:
			_out_from = _frame
		var since := _frame - _out_from
		if since < 2:
			return [&"slipstream"]
		finished = since >= 2 + Programs.SLIP_FRAMES
		return []
