extends RefCounted
## Tollwing (nexus, nexus_09): a bell-shaped resonant crystal (docs/features/mini-bosses.md 3.2).
## Stage 1: Toll Ring, Shard Drop, Swoop. Stage 2 adds Peal Lane. Data and the three emissions the
## shared boss_attacks.gd does not know: the ring with its gap, the shard columns and the low chime
## lane. Swoop is a charge and plans through the shared lane plan.

const ID := &"tollwing"
const MAX_HEALTH := 130
const CONTACT_DAMAGE := 16
const ACCENT := Color(1.0, 0.76, 0.24, 1.0)
const CHARGE_SPEED := 640.0
const RING_COUNT := 8
## Width of the safe gap toward the player, in degrees.
const RING_GAP_DEGREES := 60.0
const RING_SPEED := 360.0
const SHARD_OFFSET := 224.0
const SHARD_SPEED := 640.0
const SHARD_TOP_MARGIN := 24.0
const PEAL_SPEED := 520.0
const PEAL_BEADS := 3
const PEAL_SECOND_STREAM := 0.6
## Timings follow the spec table except for longer telegraphs, a longer swoop and longer punish
## windows, which keep the fight near 30 s of perfect play without shortening any read time.
const TIMING := {
	&"toll_ring": {"telegraph": 0.8, "active": 0.1, "punish": 1.4},
	&"shard_drop": {"telegraph": 0.9, "active": 0.3, "punish": 1.5},
	&"swoop": {"telegraph": 0.85, "active": 1.2, "punish": 1.6},
	&"peal_lane": {"telegraph": 1.0, "active": 0.1, "punish": 1.7},
}
const CHARGES: Array[StringName] = [&"swoop"]
const MOVE_SPEEDS: Array[float] = [130.0, 160.0]
## The boss opens only after the last attack of a chain, so chain length sets the pace: stage 1 runs
## chains of four attacks, stage 2 opens with one long chain and then single attacks
## (perfect Harpoon play: about 26 s; the spec's bare rotation measured about 13 s).
const ROTATIONS := [
	[
		[&"toll_ring", &"shard_drop", &"swoop", &"toll_ring"],
		[&"swoop", &"toll_ring", &"shard_drop", &"swoop"],
		[&"shard_drop", &"toll_ring", &"swoop"],
	],
	[
		[&"peal_lane", &"toll_ring", &"swoop", &"shard_drop", &"toll_ring"],
		[&"swoop"],
		[&"peal_lane"],
		[&"toll_ring"],
		[&"shard_drop"],
		[&"swoop"],
	],
]


static func plan(
	boss: Node2D, attack: StringName, result: Dictionary, target: Vector2, helpers
) -> void:
	var lane: Vector2 = result["lane"]
	var floor_y: float = result["floor_y"]
	var marks: Array = result["marks"]
	match attack:
		&"toll_ring":
			# Eight radial drops spread over the circle minus a gap centred on the player.
			var directions: Array = result["directions"]
			var aim: Vector2 = result["aim"]
			var gap := deg_to_rad(RING_GAP_DEGREES)
			var step := (TAU - gap) / float(RING_COUNT - 1)
			for index in RING_COUNT:
				directions.append(aim.rotated(gap * 0.5 + step * float(index)))
		&"shard_drop":
			var columns: Array[float] = []
			var drops: Array[float] = []
			var bounds: Rect2 = boss.get("arena_bounds")
			var top := floor_y - 560.0
			if bounds.size != Vector2.ZERO:
				top = maxf(top, bounds.position.y + SHARD_TOP_MARGIN)
			for offset in [0.0, -1.0, 1.0]:
				var x := clampf(target.x + offset * SHARD_OFFSET, lane.x, lane.y)
				if not columns.has(x):
					columns.append(x)
					marks.append({"kind": &"floor", "at": Vector2(x, floor_y), "width": 120.0})
					drops.append(_ceiling_y(boss, x, top, target.y - 40.0))
			result["columns"] = columns
			result["drop_ys"] = drops
		&"peal_lane":
			var from_right := target.x < (lane.x + lane.y) * 0.5
			var start_x := lane.y if from_right else lane.x
			var end_x := lane.x if from_right else lane.y
			var y := floor_y - float(helpers.LOW_LANE_HEIGHT)
			marks.append(helpers._lane_mark(Vector2(start_x, y), Vector2(end_x, y)))
			result["start_x"] = start_x
			result["direction"] = Vector2.LEFT if from_right else Vector2.RIGHT


static func emissions(
	_boss: Node2D, attack: StringName, locked: Dictionary, _helpers
) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var floor_y: float = locked["floor_y"]
	match attack:
		&"toll_ring":
			var core: Vector2 = locked["core"]
			for direction: Vector2 in locked["directions"]:
				shots.append(_shot(0.0, core + direction * 60.0, direction, RING_SPEED, 1.6, 3.0))
		&"shard_drop":
			var drops: Array = locked["drop_ys"]
			var index := 0
			for x: float in locked["columns"]:
				var y: float = drops[index]
				var life := (floor_y - y) / SHARD_SPEED + 0.4
				shots.append(
					_shot(0.08 * index, Vector2(x, y), Vector2.DOWN, SHARD_SPEED, 2.0, life)
				)
				index += 1
		&"peal_lane":
			var lane: Vector2 = locked["lane"]
			var direction: Vector2 = locked["direction"]
			var start_x: float = locked["start_x"]
			var y: float = ((locked["marks"] as Array)[0] as Dictionary)["from"].y
			var life := (lane.y - lane.x) / PEAL_SPEED + 0.2
			for stream in 2:
				for bead in PEAL_BEADS:
					var at := PEAL_SECOND_STREAM * float(stream) + 0.07 * float(bead)
					shots.append(_shot(at, Vector2(start_x, y), direction, PEAL_SPEED, 2.0, life))
	return shots


## Where a shard column starts: the arena roof, or just under an overhang above the player.
static func _ceiling_y(boss: Node2D, x: float, top: float, stop_y: float) -> float:
	if not boss.is_inside_tree() or stop_y <= top:
		return top
	var query := PhysicsRayQueryParameters2D.create(
		Vector2(x, top), Vector2(x, stop_y), 1, [boss.call(&"get_rid")]
	)
	var hit := boss.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return top
	return (hit["position"] as Vector2).y + 28.0


static func _shot(
	at: float, origin: Vector2, direction: Vector2, speed: float, scale: float, lifetime: float
) -> Dictionary:
	return {
		"at": at,
		"origin": origin,
		"direction": direction,
		"speed": speed,
		"scale": scale,
		"lifetime": lifetime,
	}
