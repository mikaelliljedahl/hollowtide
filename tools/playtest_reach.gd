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
