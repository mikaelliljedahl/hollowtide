extends RefCounted
## Where the playtest agent's straight steer (tools/playtest_programs.gd `steer`) arrives: it runs
## at a point and jumps what blocks it, with no plan for a climb or a gap. The refill run is that
## steer, and so are a pickup and a room-mode exit, so a goal it cannot arrive at is not offered
## (docs/features/playtest-agent.md, section 5); otherwise the steer fails, the route brings her
## back in view of the goal, and she loops.

const Aim = preload("res://tools/playtest_aim.gd")
## A point more than this far (px) above the floor under her is out of one jump's reach; the steer
## would only jump in place under it (jev-c3 did that below a vaults_02 shrine 600 px up for
## 320 s). The floor, not the feet: in the air she climbs no higher than a jump from it, and
## min-jev-c wall-jumped in the vaults_02 shaft for 450 s at a shrine level with her feet there.
const CLIMB := 320.0
## A jump's apex above the feet (PlayerConfig: JUMP_VELOCITY squared over twice GRAVITY_RISING).
const JUMP_APEX := 256.0
## How far down (px) the floor under her is looked for.
const FLOOR_SCAN := 4096.0
## Spacing (px) of the floor samples along the way.
const FLOOR_STEP := 32.0
## A boss approach's stop moves toward the boss in STAND_SHIFT px shifts, at most STAND_SCAN
## times, until a standing body fits (probed STAND_PROBES px above the feet, up to her 176 px).
const STAND_SHIFT := 32.0
const STAND_SCAN := 6
const STAND_PROBES := [16.0, 88.0, 170.0]
## A body flush against rock still fits (px kept off each side).
const FLUSH := 2.0
## A low passage: rock this far ahead (px) above a curled ball's height (LOW_CLEAR px) but at a
## standing body's (STAND_PROBES).
const LOW_AHEAD := 48.0
const LOW_CLEAR := [16.0, 40.0]


## True when the steer from the feet arrives at `rel` (px from the feet): no more than CLIMB above
## the floor under her, in sight at crossbow height or at a jump's apex above both ends (a lower
## wall is jumped), and no gap on the way whose floor lies more than CLIMB below the point, which
## she would fall into and not climb out of toward it (min-jev-c ran from the vaults_02 upper
## floor into the shaft between it and the shrine, and the route climbed back up).
static func arrives(player: Player, rel: Vector2) -> bool:
	var feet := player.global_position
	var space := player.get_world_2d().direct_space_state
	var floor_y := _floor_under(space, feet, feet.y + FLOOR_SCAN)
	var drop := floor_y - feet.y if not is_nan(floor_y) else 0.0
	if rel.y - drop < -CLIMB:
		return false
	if not (
		_clear(space, feet + Aim.EYE, rel) or _clear(space, feet + Vector2(0, -JUMP_APEX), rel)
	):
		return false
	var start := feet + Vector2(0, drop)
	var goal := feet + rel
	var samples := floori(absf(goal.x - start.x) / FLOOR_STEP)
	for index in range(1, samples):
		var point := start.lerp(goal, float(index) / samples)
		if is_nan(_floor_under(space, point, goal.y + CLIMB)):
			return false
	return true


static func _clear(space: PhysicsDirectSpaceState2D, from: Vector2, rel: Vector2) -> bool:
	return space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + rel, 1)).is_empty()


## The height of the first floor below `point` down to `bottom`, NAN when there is none.
static func _floor_under(space: PhysicsDirectSpaceState2D, point: Vector2, bottom: float) -> float:
	if bottom <= point.y:
		return point.y
	var from := point + Vector2(0, -8)
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters2D.create(from, Vector2(point.x, bottom), 1)
	)
	return (hit["position"] as Vector2).y if not hit.is_empty() else NAN


## `step` moved toward the boss until her standing body fits there, or unchanged when it does
## not within STAND_SCAN shifts. Under a low roof she stays curled and fires nothing: r7-min-s1i
## rolled to and fro in the vaults_03 west alcove (a firing step 320 px from the Stone Guardian)
## through five stage 4 punish windows with 5 Harpoons, fired none, and died there. The body is
## fitted `level` px below her feet, on the boss's floor: on that alcove's roof, fitted at her
## own level, the step lay on the roof above the alcove, and the approach stood there for 550 s
## (round 9, once the jump off the roof onto the Guardian was no longer offered).
## With a `target` (px from her feet), the stop also needs a standing bolt from there that clears
## the rock on its way to it (`bolt_clear`): round 12, a Jev kiln_08 room run stood 240 s under
## the rock block over columns 20 to 24 firing 676 wave bolts at the Emberkite from a muzzle
## inside it.
static func standing_step(
	player: Player, step: float, toward: int, level := 0.0, target := Vector2.INF
) -> float:
	var space := player.get_world_2d().direct_space_state
	var feet := player.global_position + Vector2(0, level)
	for index in STAND_SCAN + 1:
		var shifted := step + toward * STAND_SHIFT * index
		var at := feet + Vector2(shifted, 0)
		if not _fits_standing(space, at):
			continue
		if target.is_finite():
			var rel := target - Vector2(shifted, level)
			var aim := Aim.line_up(rel, true, Aim.BOSS_RADIUS, INF)
			if not aim.is_empty() and not bolt_clear(player, at, rel, aim, Aim.BOSS_RADIUS):
				continue
		return shifted
	return step


## True when a standing bolt along `aim` from the muzzle of a body with its feet at `feet` (world)
## meets no rock before it comes within `radius` of `rel` (px from those feet; the body it hits),
## the muzzle itself not inside rock. The state's line of sight starts lower (Aim.EYE), under rock
## a standing bolt hits.
static func bolt_clear(
	player: Player, feet: Vector2, rel: Vector2, aim: String, radius := 0.0
) -> bool:
	if not Aim.MUZZLES.has(aim):
		return true
	var side := -1 if rel.x < 0.0 else 1
	var muzzle: Vector2 = Aim.MUZZLES[aim]
	var start := feet + Vector2(muzzle.x * side, muzzle.y)
	var way := Aim.direction(aim, side)
	var along := maxf((feet + rel - start).dot(way) - radius, 0.0)
	var query := PhysicsRayQueryParameters2D.create(start, start + way * along, 1)
	query.hit_from_inside = true
	var passable: Array[RID] = []
	for grate in player.get_tree().get_nodes_in_group(&"projectile_grate"):
		if grate is CollisionObject2D and grate.call(&"can_pass_projectile", &"missile"):
			passable.append((grate as CollisionObject2D).get_rid())
	query.exclude = passable
	return player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## True when the way `toward` (-1 or 1) is a passage a curled ball fits through and a standing body
## does not: round 12's kiln_08 slab over columns 20 to 24 hangs 128 px above the floor, and the
## boss approach's straight steer jumped into its underside from the east pocket.
## Looked for no farther than `reach` px: the vaults_03 approach stop flush with the alcove roof's
## end lies 32 px from her, short of the roof.
static func low_passage(player: Player, toward: int, reach: float) -> bool:
	var space := player.get_world_2d().direct_space_state
	var ahead := player.global_position + Vector2(toward * minf(LOW_AHEAD, reach), 0)
	for height in LOW_CLEAR:
		if _solid(space, ahead + Vector2(0, -height)):
			return false
	return not _fits_standing(space, ahead)


static func _solid(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not space.intersect_point(query, 1).is_empty()


## True when no rock overlaps a standing body with its feet at `feet`.
static func _fits_standing(space: PhysicsDirectSpaceState2D, feet: Vector2) -> bool:
	var half := PlayerConfig.STANDING_WIDTH * 0.5 - FLUSH
	for x in [-half, 0.0, half]:
		for height in STAND_PROBES:
			var query := PhysicsPointQueryParameters2D.new()
			query.position = feet + Vector2(x, -height)
			query.collision_mask = 1
			if not space.intersect_point(query, 1).is_empty():
				return false
	return true
