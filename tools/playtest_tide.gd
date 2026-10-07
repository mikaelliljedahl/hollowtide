extends RefCounted
## Tidal Heart attack answers for the playtest agent (docs/features/playtest-agent.md, section 20).
## Every Tidal Heart shot is a point that flies a straight line (scripts/combat/enemy_projectile.gd
## hits by raycast), and the plan locks every line when the telegraph starts, so the state carries
## the shots (`shots_rel`) and a spot is safe when no line reaches the body there before rock
## stops it. Dodge probe in the real depths_02 arena (real player, forced stage 3 and 4 attacks, 14
## responses at 17 start times each, six positions): curling in place clears Tide Ring, Crosscurrent
## and Maelstrom wherever the ball is off every line (17/17 at most spots), Surge Lance is cleared
## only by leaving its line (a step or a run, 9 to 17 of 17), and a far boss's Maelstrom only by
## moving (run or roll away 17/17). A low Crosscurrent lane is jumped when its beads arrive.
## The mini-bosses' shot attacks (docs/features/mini-bosses.md) are lines of the same kind and get
## the same answer (round 10 probe in their real rooms, docs/features/playtest-agent.md section 29).

const Programs = preload("res://tools/playtest_programs.gd")
const Attacks = preload("res://scripts/enemies/boss_attacks.gd")
const ATTACKS: Array[StringName] = [&"tide_ring", &"surge_lance", &"crosscurrent", &"maelstrom"]
const MINI_ATTACKS: Array[StringName] = [
	&"spore_lob",
	&"root_burst",
	&"toll_ring",
	&"shard_drop",
	&"peal_lane",
	&"needle_line",
	&"icicle_drop",
	&"frost_ring",
	&"cinder_rain",
	&"lure_pulse",
	&"dark_lance",
]
## The standing and curled bodies (scenes/player/player.tscn): 56 px wide, 176 and 56 px tall
## above the feet, and the clearance kept from every line.
const HALF_WIDTH := 28.0
const STAND_HEIGHT := 176.0
const BALL_HEIGHT := 56.0
const CLEARANCE := 2.0
## A walk stops within Programs.NEAR_TARGET of its spot, so a spot away from her feet must stay
## safe this far either side of it.
const SPOT_SLACK := 24.0
const SPOT_SCAN := 320
const SPOT_STEP := 8
## Clearance from a low boss body at a spot she walks to, and how low counts (feet to centre).
const BODY_CLEAR := 140.0
const BODY_LOW := 300.0
## Seconds after the last line has passed her before she moves again, and the longest wait.
const PASS_MARGIN := 0.3
const MAX_WAIT := 7.0
## A lane jump starts this long before its first bead arrives and holds jump this many frames:
## the three beads of one lane pass her in about 0.25 s, and a jump started 0.45 s early (the
## Fault Slam lead) landed on the third one in the check. A high lane after it is curled under
## as soon as she lands.
const JUMP_LEAD := 0.2
const JUMP_HOLD := 40
const BEAD_SPREAD := 0.14
## A lane jump that first stands still this many frames counts as standing still: a Harpoon shot
## takes about 8 frames, and the next decision offers the jump again.
const STAND_SPARE_FRAMES := 30
const FPS := 60.0
## A horizontal shot this many seconds from her body is answered on the way to a spot: below
## LANE_SPLIT px above the feet by a jump, above it (standing) by curling under.
const LANE_LEAD := 0.2
const LANE_SPLIT := 80.0
const LOW_LANE := 1
const HIGH_LANE := 2
## Shots in flight farther than this from her feet are left out of the lines.
const IN_FLIGHT := 1600.0
## A spot keeps her feet this far (px) inside the boss's arena: outside it the boss drops its chain
## and opens no punish window (scripts/enemies/boss.gd). Round 13: the nexus_09 Shard Drop step
## took her to x 47 in the west door, 17 px out of the Tollwing's arena, and in a probe the
## fight never opened again after its first window (r12: Tollwing timed out in every full run).
const ARENA_KEEP := 32.0


## True for an attack answered by its lines: the Tidal Heart's and the mini-bosses' shot attacks.
static func answers(attack: StringName) -> bool:
	return attack in ATTACKS or attack in MINI_ATTACKS


## The lines of the current line attack (`answers`), each [origin x, origin y relative to `feet`,
## direction x, y, seconds from now until it flies (0 once out), speed, lifetime]: while it
## telegraphs, every shot of the locked plan (scripts/enemies/boss_attacks.gd `emissions` only reads
## the plan); once released, the shots still to come and every enemy shot in flight within
## IN_FLIGHT px. [] for any other attack, or when nothing is coming.
static func shots(boss: Node2D, feet: Vector2) -> Array:
	var attack := StringName(boss.get("_attack_id"))
	var plan = boss.get("_attack_plan")
	var state := StringName(boss.get("_attack_state"))
	if not answers(attack) or not plan is Dictionary or (plan as Dictionary).is_empty():
		return []
	var result: Array = []
	if state == &"telegraph":
		var release := float(boss.get("_telegraph_remaining"))
		for shot: Dictionary in Attacks.emissions(boss, attack, plan):
			result.append(_line(shot, release + float(shot["at"]), shot["lifetime"], feet))
	elif state == &"active":
		var elapsed := float(boss.get("_active_elapsed"))
		for shot: Dictionary in boss.get("_emissions"):
			result.append(
				_line(shot, maxf(float(shot["at"]) - elapsed, 0.0), shot["lifetime"], feet)
			)
	# Shots of an earlier link still fly through the next telegraph and after the recovery: the
	# desperation Crosscurrent's lanes cross the arena for about 4 s (round 11 probe).
	for node in boss.get_tree().get_nodes_in_group(&"enemy_shot"):
		var flying := node as EnemyProjectile
		if flying == null or flying.global_position.distance_to(feet) > IN_FLIGHT:
			continue
		var shot := {
			"origin": flying.global_position,
			"direction": flying.direction,
			"speed": flying.speed,
		}
		result.append(_line(shot, 0.0, flying.lifetime - flying.age, feet))
	return result


static func _line(shot: Dictionary, delay: float, lifetime: float, feet: Vector2) -> Array:
	var origin: Vector2 = shot["origin"] - feet
	var direction: Vector2 = shot["direction"]
	return [
		roundi(origin.x),
		roundi(origin.y),
		snappedf(direction.x, 0.001),
		snappedf(direction.y, 0.001),
		snappedf(delay, 0.01),
		roundi(float(shot["speed"])),
		snappedf(lifetime, 0.01),
	]


## The dodge for the line attack whose lines are in `boss["shots_rel"]`, or {} when no answer is
## found or nothing is coming.
static func candidate(boss: Dictionary, player: Player) -> Dictionary:
	var attack := String(boss.get("attack", ""))
	# Only a line still to cross the floor she could reach matters.
	var reach := Rect2(
		-SPOT_SCAN - HALF_WIDTH,
		-STAND_HEIGHT - CLEARANCE,
		2.0 * (SPOT_SCAN + HALF_WIDTH),
		STAND_HEIGHT + CLEARANCE
	)
	var lines: Array = (boss.get("shots_rel", []) as Array).filter(
		func(line: Array) -> bool:
			return _passed([line]) > PASS_MARGIN and _enter_line(line, reach) >= 0.0
	)
	if lines.is_empty():
		return {}
	var until := roundi(minf(_passed(lines), MAX_WAIT) * FPS)
	var spot: Variant = safe_spot(lines, player, boss)
	var crossing := lines.filter(func(line: Array) -> bool: return absf(float(line[3])) > 0.01)
	if spot == null and not crossing.is_empty() and crossing.size() < lines.size():
		# No spot clears both a lane and a crossing line (a Surge Lance while an earlier
		# Crosscurrent's lanes still fly): leave the crossing lines; Shelter answers the lanes.
		spot = safe_spot(crossing, player, boss)
	if spot is Array:
		var offset := float(spot[0])
		var curl := bool(spot[1])
		if is_zero_approx(offset) and not curl:
			return _entry(attack, "stand still: no %s line reaches her here" % _name(attack), until)
		var move := (
			"curl up where she stands"
			if is_zero_approx(offset)
			else (
				"step %d px %s and %s"
				% [
					absf(offset),
					"left" if offset < 0.0 else "right",
					"curl up" if curl else "stand"
				]
			)
		)
		return _entry(
			attack,
			"%s until the %s has passed (off every line)" % [move, _name(attack)],
			Shelter.new(player, offset, curl, until)
		)
	var jump: Variant = _lane_jump(lines, player)
	if jump == null:
		return {}
	var label := "jump the low %s lane as its beads arrive" % _name(attack)
	# Waiting for far beads is standing still (Dodge.stays_put): a Harpoon fired first loses
	# nothing. Round 13: the Tollwing's Peal Lane beads cross nexus_09 in about 3 s, and its
	# stage 2 Harpoon window (1.7 s) passed while the jump waited, every time.
	if (jump as LaneJump).wait_frames() >= STAND_SPARE_FRAMES:
		label = "stand still, then %s" % label
	return _entry(attack, label, jump)


## [offset px, curl] for the spot nearest her feet where no line reaches the standing body (or,
## failing that and with the Slipstream owned, the curled one), with nothing solid on the walk
## there; null when none.
static func safe_spot(lines: Array, player: Player, boss: Dictionary) -> Variant:
	var boss_rel := Vector2(float(boss["rel"][0]), float(boss["rel"][1]))
	var low := boss_rel.y > -BODY_LOW
	for distance in range(0, SPOT_SCAN + 1, SPOT_STEP):
		for side in [-1, 1] if distance > 0 else [1]:
			var x := float(distance * side)
			if distance > 0 and player.test_move(player.global_transform, Vector2(x, 0)):
				continue
			if distance > 0 and not in_arena(boss, x):
				continue
			# Never past or into a low body: it floats down to 92 px above the floor.
			var past := (x - boss_rel.x) * -boss_rel.x < 0.0
			if low and distance > 0 and (past or absf(x - boss_rel.x) < BODY_CLEAR):
				continue
			# Curling needs the Slipstream (a round 10 probe without it curled in vain).
			var heights := (
				[STAND_HEIGHT, BALL_HEIGHT] if GameState.has_slipstream else [STAND_HEIGHT]
			)
			for height in heights:
				if _clear(lines, player, x, height, distance > 0):
					return [x, height == BALL_HEIGHT]
	return null


## True when feet `x` px beside hers stay ARENA_KEEP inside `boss`'s arena (or it has none).
static func in_arena(boss: Dictionary, x: float) -> bool:
	var arena = boss.get("arena_rel")
	if not arena is Array:
		return true
	return x >= float(arena[0]) + ARENA_KEEP and x <= float(arena[2]) - ARENA_KEEP


## True when no line reaches a body `height` tall with its feet `x` px beside hers (a spot she
## walks to must stay clear SPOT_SLACK px either side).
static func _clear(lines: Array, player: Player, x: float, height: float, slack: bool) -> bool:
	var spread := SPOT_SLACK if slack else 0.0
	var body := Rect2(
		x - HALF_WIDTH - CLEARANCE - spread,
		-height - CLEARANCE,
		2.0 * (HALF_WIDTH + CLEARANCE + spread),
		height + CLEARANCE
	)
	for line: Array in lines:
		if _reaches(line, body, player):
			return false
	return true


## True when `line` enters `body` (relative to the feet) before rock stops it.
static func _reaches(line: Array, body: Rect2, player: Player) -> bool:
	var enter := _enter_line(line, body)
	if enter < 0.0:
		return false
	var from := player.global_position + Vector2(float(line[0]), float(line[1]))
	var to := from + Vector2(float(line[2]), float(line[3])) * enter
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Distance along `line` (a `shots` entry) at which it enters `rect`, or -1.
static func _enter_line(line: Array, rect: Rect2) -> float:
	var origin := Vector2(float(line[0]), float(line[1]))
	var direction := Vector2(float(line[2]), float(line[3]))
	return _enter(origin, direction, float(line[5]) * float(line[6]), rect)


## Distance along the ray at which it enters `rect` within `length`, or -1 (slab method).
static func _enter(origin: Vector2, direction: Vector2, length: float, rect: Rect2) -> float:
	var near := 0.0
	var far := length
	for axis in 2:
		var o := origin[axis]
		var d := direction[axis]
		var low := rect.position[axis]
		var high := rect.end[axis]
		if absf(d) < 0.000001:
			if o < low or o > high:
				return -1.0
			continue
		var t1 := (low - o) / d
		var t2 := (high - o) / d
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
		if near > far:
			return -1.0
	return near


## Seconds from now until the last line has flown past her, plus a margin.
static func _passed(lines: Array) -> float:
	var last := 0.0
	for line: Array in lines:
		var reach := Vector2(float(line[0]), float(line[1]) + STAND_HEIGHT * 0.5).length()
		var flight := minf(reach / float(line[5]), float(line[6]))
		last = maxf(last, float(line[4]) + flight)
	return last + PASS_MARGIN


## A jump in place over the low horizontal lanes that reach even the curled body, timed to their
## first bead, then a curl under any high lane that follows; null when a line other than a lane
## reaches her curled or the beads have arrived.
static func _lane_jump(lines: Array, player: Player) -> Variant:
	var ball := Rect2(
		-HALF_WIDTH - CLEARANCE,
		-BALL_HEIGHT - CLEARANCE,
		2.0 * (HALF_WIDTH + CLEARANCE),
		BALL_HEIGHT + CLEARANCE
	)
	var low_arrival := INF
	var high_passed := -1.0
	for line: Array in lines:
		var gap := maxf(absf(float(line[0])) - HALF_WIDTH, 0.0)
		var arrival := float(line[4]) + gap / float(line[5])
		if _reaches(line, ball, player):
			if absf(float(line[3])) > 0.01:
				return null
			low_arrival = minf(low_arrival, arrival)
		elif not _clear([line], player, 0.0, STAND_HEIGHT, false):
			high_passed = maxf(high_passed, arrival + BEAD_SPREAD)
	if low_arrival == INF or low_arrival < JUMP_LEAD * 0.5:
		return null
	var jump_at := maxi(roundi((low_arrival - JUMP_LEAD) * FPS), 0)
	var stand_at := roundi((high_passed + PASS_MARGIN) * FPS) if high_passed >= 0.0 else -1
	return LaneJump.new(player, jump_at, stand_at)


static func _name(attack: String) -> String:
	return attack.capitalize()


static func _entry(attack: String, label: String, program: Variant) -> Dictionary:
	if program is int:
		program = Programs.hold([], program)
	return {"key": "dodge:%s" % attack, "kind": "dodge", "label": label, "program": program}


## Walks to `offset` px from where she stands, curls up there when `curl`, holds until frame
## `until`, then stands up. A horizontal shot about to reach her on the way or there (a Crosscurrent
## lane of an earlier link) is jumped when low and curled under when high: round 11 probe in
## depths_02, stage 4 Crosscurrent then Surge Lance, the lanes answered so and the Lance by leaving
## its line cleared every probed spot.
class Shelter:
	extends RefCounted

	var finished := false
	var _player: Player
	var _target := 0.0
	var _curl := false
	var _until := 0
	var _frame := 0
	var _curled_at := -1
	var _stand_at := -1
	var _jump_left := 0

	func _init(player: Player, offset: float, curl: bool, until: int) -> void:
		_player = player
		_target = player.global_position.x + offset
		_curl = curl
		_until = until

	func next() -> Array:
		_frame += 1
		if _stand_at >= 0:
			finished = _frame - _stand_at >= 2 + Programs.SLIP_FRAMES
			return [&"slipstream"] if _frame - _stand_at < 2 else []
		var gap := _target - _player.global_position.x
		var walk: Array = []
		if absf(gap) >= Programs.NEAR_TARGET and _frame < _until:
			walk = [Programs.move_action(-1 if gap < 0.0 else 1)]
		var lane := _lane()
		if _jump_left > 0 or (lane == LOW_LANE and _player.is_on_floor()):
			_jump_left = JUMP_HOLD if _jump_left <= 0 else _jump_left - 1
			return walk + [&"jump"]
		if lane == HIGH_LANE and not _player.is_ball and _curled_at < 0:
			_curl = true
		if _curled_at >= 0 and _frame - _curled_at < 2:
			return [&"slipstream"]
		if (_curled_at < 0 or _player.is_ball) and not walk.is_empty() and lane != HIGH_LANE:
			return walk
		if _curl and _curled_at < 0:
			_curled_at = _frame
			return [&"slipstream"]
		if _frame < _until:
			return walk if _player.is_ball else []
		if _curl:
			_stand_at = _frame
			return [&"slipstream"]
		finished = true
		return []

	## LOW_LANE or HIGH_LANE when a horizontal enemy shot reaches her body within LANE_LEAD s at
	## that height above the feet; 0 otherwise.
	func _lane() -> int:
		var feet := _player.global_position
		for node in _player.get_tree().get_nodes_in_group(&"enemy_shot"):
			var shot := node as EnemyProjectile
			if shot == null or absf(shot.direction.y) > 0.01:
				continue
			var dx := shot.global_position.x - feet.x
			var gap := absf(dx) - HALF_WIDTH
			if dx * shot.direction.x >= 0.0 or gap > shot.speed * LANE_LEAD:
				continue
			var height := feet.y - shot.global_position.y
			if height < 0.0 or height > STAND_HEIGHT:
				continue
			if height < LANE_SPLIT:
				return LOW_LANE
			if not _player.is_ball:
				return HIGH_LANE
		return 0


## Waits until frame `jump_at`, jumps in place, and when `stand_at` is set, curls up on landing
## and stands up again at that frame (the desperation Crosscurrent's high lane follows the low one
## by 1.0 s).
class LaneJump:
	extends RefCounted

	var finished := false
	var _player: Player
	var _jump_at := 0
	var _stand_at := -1
	var _frame := 0
	var _curled_at := -1
	var _up_at := -1

	func _init(player: Player, jump_at: int, stand_at: int) -> void:
		_player = player
		_jump_at = jump_at
		_stand_at = stand_at

	## Frames it stands still before the jump.
	func wait_frames() -> int:
		return _jump_at

	func next() -> Array:
		_frame += 1
		if _frame < _jump_at:
			return []
		if _frame < _jump_at + JUMP_HOLD:
			return [&"jump"]
		var landed := _player.is_on_floor()
		if _stand_at < 0:
			finished = landed
			return []
		if _curled_at < 0:
			if landed:
				_curled_at = _frame
			return [&"slipstream"] if landed else []
		if _frame - _curled_at < 2:
			return [&"slipstream"]
		if _frame < _stand_at:
			return []
		if _up_at < 0:
			_up_at = _frame
		finished = _frame - _up_at >= 2 + Programs.SLIP_FRAMES
		return [&"slipstream"] if _frame - _up_at < 2 else []
