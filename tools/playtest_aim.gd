extends RefCounted
## Shot geometry for the playtest agent's candidates (docs/features/playtest-agent.md,
## "Candidates"): whether one of the crossbow's five aims sends a bolt within a radius of a point,
## where to stand so one does, and when to fire during a jump so a level bolt reaches a target
## above. Positions are relative to the player's feet (x right, y down). Pure functions.

## The crossbow fires from about this far above the feet.
const EYE := Vector2(0, -100)
## A boss body is a 92 px circle (scenes/enemies/boss.tscn); a bolt adds a little.
const BOSS_RADIUS := 100.0
## Half the height a shot may miss the Echo grate's centre by (it is 192 px tall).
const GRATE_RADIUS := 72.0
## Highest rise, in px above the take-off, at which a jump still fires; the apex is 256 px.
const MAX_JUMP_RISE := 240.0
## A level shot at a target this far or less from the aim line hits; used for jump shots.
const LEVEL_TOLERANCE := 80.0
## Where to stand from a boss that sits level with the crossbow.
const LEVEL_STANDOFF := 320.0
const MIN_STANDOFF := 160.0
const GROUNDED_AIMS := ["forward", "diag_up", "up"]
const AIRBORNE_AIMS := ["forward", "diag_up", "up", "diag_down", "down"]


## Unit direction of `aim` for a player facing `side` (-1 or 1).
static func direction(aim: String, side: int) -> Vector2:
	match aim:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"diag_up":
			return Vector2(side, -1).normalized()
		"diag_down":
			return Vector2(side, 1).normalized()
	return Vector2(side, 0)


## Distance from `rel` to the line of a bolt fired along `aim` toward it; INF when behind the
## crossbow or beyond `reach`.
static func miss(rel: Vector2, aim: String, reach: float) -> float:
	var offset := rel - EYE
	var way := direction(aim, -1 if offset.x < 0.0 else 1)
	var along := offset.dot(way)
	if along <= 0.0 or along > reach:
		return INF
	return absf(offset.cross(way))


## The aim whose bolt passes within `radius` of `rel` (the closest one), or "".
static func line_up(rel: Vector2, grounded: bool, radius: float, reach: float) -> String:
	var best := ""
	var best_miss := radius
	for aim in GROUNDED_AIMS if grounded else AIRBORNE_AIMS:
		var off := miss(rel, aim, reach)
		if off <= best_miss:
			best = aim
			best_miss = off
	return best


## Physics frame, counted from the jump press, at which the feet have risen `rise` px on a held
## jump taking off at `speed` px/s (the Updraft Cloak's is higher); -1 when that is out of reach.
static func jump_fire_frame(rise: float, speed := PlayerConfig.JUMP_VELOCITY) -> int:
	if rise <= 0.0 or rise > MAX_JUMP_RISE:
		return -1
	var gravity := PlayerConfig.GRAVITY_RISING
	var root := speed * speed - 2.0 * gravity * rise
	if root < 0.0:
		return -1
	var seconds := (speed - sqrt(root)) / gravity
	# The press frame itself already lifts her (measured: 152 px at 132 wanted with one more).
	return maxi(ceili(seconds * PlayerConfig.PHYSICS_TICKS_PER_SECOND), 1)


## Horizontal step (px, sign is the direction) from the feet to the spot where a grounded bolt
## lines up with `rel`: level targets from LEVEL_STANDOFF, higher ones along the 45 degree aim.
static func firing_step(rel: Vector2, radius: float) -> float:
	var height := -(rel - EYE).y
	var standoff := LEVEL_STANDOFF if height <= radius else maxf(height, MIN_STANDOFF)
	var side := -1.0 if rel.x < 0.0 else 1.0
	return rel.x - side * standoff
