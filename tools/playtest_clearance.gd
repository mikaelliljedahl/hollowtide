extends RefCounted
## Boss-body clearance of the playtest agent's moves (docs/features/playtest-agent.md, "Harness
## round 9"): from a boss attack's telegraph to the end of its recovery, a move whose predicted
## path touches the boss's contact area is not offered, and during a charge (before its recovery)
## no move toward it is.
## The probed dodge (tools/playtest_dodge.gd) and standing still stay. Round 8: in both minimum-kit
## runs Jev picked `jump:right` from the vaults_03 alcove roof during the Rockfall telegraph after
## the Fault Slam dodge and landed on the Stone Guardian (2 of its 3 contact hits per run), and
## `jump_over` from the alcove during the Shoulder Charge telegraph (the third); a first round 9
## run, filtering the telegraph only, jumped off the roof onto it while the rocks fell; the Warden's
## Scuttle Rush hits in r8-min-s1 came from `approach` walking into the running rush. Every charge
## counts, the mini-bosses' included (scripts/enemies/boss_patterns.gd `is_charge`).

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
## The boss's contact area (scenes/enemies/boss.tscn, PlayerDetector).
const CONTACT_RADIUS := 112.0
## An attack from its telegraph to the end of its recovery: the body stands (a charge runs).
const ATTACK_PHASES := ["telegraph", "active", "recover"]
## A move whose path ends more than this far (px) closer to a charging boss walks into the charge.
const CHARGE_TOWARD := 32.0
## Kinds always kept: standing still and the probed answer.
const KEPT := ["idle", "dodge"]
## Frames of a program predicted, and of falling after it ends.
const PATH_LIMIT := 150
## Probe (px) below the feet for the floor while walking.
const FLOOR_PROBE := 4.0
const FPS := 60.0


## `candidates` without the moves that meet an attacking boss's body. Unchanged when no engaged
## boss attacks, or when she already touches it (nothing then would be safer).
static func keep_clear(candidates: Array, state: Dictionary, player: Player) -> Array:
	var boss := _threat(state["enemies"])
	if boss.is_empty():
		return candidates
	var rel := Vector2(float(boss["rel"][0]), float(boss["rel"][1]))
	var feet := player.global_position
	var centre := feet + rel
	if touches(feet, centre):
		return candidates
	var charge: bool = (
		Patterns.is_charge(StringName(boss["attack"])) and boss["attack_state"] != "recover"
	)
	var toward := 1.0 if rel.x > 0.0 else -1.0
	return candidates.filter(
		func(entry: Dictionary) -> bool:
			if entry["kind"] in KEPT or not entry["program"] is Array:
				return true
			var points := path(player, entry["program"])
			if points.is_empty():
				return true
			if charge and (points[points.size() - 1].x - feet.x) * toward > CHARGE_TOWARD:
				return false
			for point in points:
				if touches(point, centre):
					return false
			return true
	)


## The engaged boss in an attack (ATTACK_PHASES); {} otherwise.
static func _threat(enemies: Array) -> Dictionary:
	for enemy: Dictionary in enemies:
		if not enemy["is_boss"] or not bool(enemy.get("engaged", true)):
			continue
		if String(enemy.get("attack_state", "")) in ATTACK_PHASES:
			return enemy
	return {}


## True when a standing body with its feet at `feet` overlaps the contact circle at `centre`.
static func touches(feet: Vector2, centre: Vector2) -> bool:
	var half := PlayerConfig.STANDING_WIDTH * 0.5
	var nearest := Vector2(
		clampf(centre.x, feet.x - half, feet.x + half),
		clampf(centre.y, feet.y - PlayerConfig.STANDING_HEIGHT, feet.y)
	)
	return nearest.distance_to(centre) < CONTACT_RADIUS


## The feet positions, frame by frame, of the frame program `program` (an Array of held-action
## sets) played from where she stands, until she lands after it or PATH_LIMIT frames, as
## scripts/player/player.gd moves her: ground and air acceleration with the turn boost and apex
## easing, a jump pressed while grounded or within coyote time of leaving the floor (a held press
## fires on landing, as the jump buffer does), the jump cut-off and gravity, with rock stopping her
## (her own collision shape and mask).
static func path(player: Player, program: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	var pos := player.global_position
	var velocity := player.velocity
	var grounded := player.is_on_floor()
	var delta := 1.0 / FPS
	var airborne := 0.0 if grounded else PlayerConfig.COYOTE_TIME + delta
	var jumped := false
	var cut := false
	for index in PATH_LIMIT:
		if index >= program.size() and grounded:
			break
		var held: Array = program[index] if index < program.size() else []
		var input := int(held.has(&"move_right")) - int(held.has(&"move_left"))
		var top := PlayerConfig.RUN_MAX if held.has(&"run") else PlayerConfig.WALK_MAX
		var accel := PlayerConfig.GROUND_ACCEL if grounded else PlayerConfig.AIR_ACCEL
		if not grounded and absf(velocity.y) < PlayerConfig.APEX_THRESHOLD:
			accel *= PlayerConfig.APEX_ACCEL_MUL
		if input != 0:
			if velocity.x != 0.0 and signf(input) != signf(velocity.x):
				accel *= PlayerConfig.TURN_BOOST
			velocity.x = move_toward(velocity.x, input * top, accel * delta)
		else:
			var friction := PlayerConfig.GROUND_FRICTION if grounded else PlayerConfig.AIR_FRICTION
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if held.has(&"jump") and not jumped and airborne <= PlayerConfig.COYOTE_TIME:
			velocity.y = -PlayerConfig.JUMP_VELOCITY
			grounded = false
			jumped = true
			cut = false
		elif not held.has(&"jump") and velocity.y < 0.0 and not cut:
			velocity.y *= PlayerConfig.JUMP_CUTOFF
			cut = true
		if not grounded:
			var gravity := (
				PlayerConfig.GRAVITY_RISING if velocity.y < 0.0 else PlayerConfig.GRAVITY_FALLING
			)
			if absf(velocity.y) < PlayerConfig.APEX_THRESHOLD:
				gravity *= PlayerConfig.APEX_GRAVITY_MUL
			velocity.y = minf(velocity.y + gravity * delta, PlayerConfig.TERMINAL_VELOCITY)
		var motion := velocity * delta
		if player.test_move(Transform2D(0.0, pos), Vector2(motion.x, 0.0)):
			velocity.x = 0.0
			motion.x = 0.0
		pos.x += motion.x
		if grounded:
			grounded = player.test_move(Transform2D(0.0, pos), Vector2(0.0, FLOOR_PROBE))
		elif motion.y != 0.0 and player.test_move(Transform2D(0.0, pos), Vector2(0.0, motion.y)):
			grounded = motion.y > 0.0
			velocity.y = 0.0
			motion.y = 0.0
		pos.y += motion.y
		airborne = 0.0 if grounded else airborne + delta
		if grounded and jumped:
			# A press still held on landing does not jump again until it is released.
			jumped = held.has(&"jump")
		points.append(pos)
	return points
