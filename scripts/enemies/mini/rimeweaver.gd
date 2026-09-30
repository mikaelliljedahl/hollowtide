extends RefCounted
## Rimeweaver (vaults, vaults_08): a pale long-legged limestone weaver (docs/features/mini-bosses.md 3.3).
## Stage 1: Needle Line, Icicle Drop, Wall Skitter. Stage 2 adds Frost Ring. Needle Line, Icicle Drop
## and Frost Ring plan and emit here; Wall Skitter is a charge (the shared charge lane and pocket rule).
## Chains run up to five attacks (stage 2 keeps exactly one chain, as the shared suite requires)
## so a perfect-play kill takes 25 to 40 s.

const ID := &"rimeweaver"
const MAX_HEALTH := 150
const CONTACT_DAMAGE := 18
const ACCENT := Color(0.62, 0.86, 1.0, 1.0)
const CHARGE_SPEED := 600.0
const DROP_SPACING := 160.0
const DROP_HEIGHT := 560.0
const NEEDLE_COUNT := 3
## The ring telegraph draws twelve dots; two fall inside the 77 degree gap, leaving ten shards.
const RING_DOTS := 12
const RING_GAP := 1.3439
const TIMING := {
	&"needle_line": {"telegraph": 0.7, "active": 0.2, "punish": 1.2},
	&"icicle_drop": {"telegraph": 0.9, "active": 0.4, "punish": 1.3},
	&"wall_skitter": {"telegraph": 0.8, "active": 1.1, "punish": 1.5},
	&"frost_ring": {"telegraph": 0.9, "active": 0.1, "punish": 1.5},
}
const CHARGES: Array[StringName] = [&"wall_skitter"]
const MOVE_SPEEDS: Array[float] = [130.0, 160.0]
const ROTATIONS := [
	[
		[&"needle_line", &"icicle_drop", &"wall_skitter", &"needle_line", &"icicle_drop"],
		[&"wall_skitter", &"needle_line", &"icicle_drop", &"wall_skitter", &"needle_line"],
		[&"icicle_drop", &"wall_skitter"],
	],
	[
		[&"frost_ring"],
		[&"wall_skitter"],
		[&"icicle_drop", &"needle_line", &"wall_skitter", &"frost_ring", &"needle_line"],
		[&"needle_line"],
	],
]


## Locks the aim line, the three drop columns or the ring gap while the telegraph starts.
static func plan(
	_boss: Node2D, attack: StringName, result: Dictionary, target: Vector2, _helpers
) -> void:
	var marks: Array = result["marks"]
	match attack:
		&"needle_line":
			var directions: Array = result["directions"]
			directions.append(result["aim"])
		&"icicle_drop":
			var lane: Vector2 = result["lane"]
			var floor_y: float = result["floor_y"]
			var columns: Array[float] = []
			for offset in [0.0, -1.0, 1.0]:
				var x := clampf(target.x + offset * DROP_SPACING, lane.x, lane.y)
				if not columns.has(x):
					columns.append(x)
					marks.append({"kind": &"floor", "at": Vector2(x, floor_y), "width": 120.0})
			result["columns"] = columns
		&"frost_ring":
			var aim: Vector2 = result["aim"]
			marks.append(
				{
					"kind": &"ring",
					"center": result["core"],
					"gap": aim.angle(),
					"gap_width": RING_GAP,
					"count": RING_DOTS,
				}
			)


static func emissions(
	boss: Node2D, attack: StringName, locked: Dictionary, helpers
) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var core: Vector2 = locked["core"]
	match attack:
		&"needle_line":
			var aim: Vector2 = locked["aim"]
			for index in NEEDLE_COUNT:
				shots.append(helpers._shot(0.1 * float(index), core + aim * 60.0, aim, 620.0, 1.3))
		&"icicle_drop":
			var floor_y: float = locked["floor_y"]
			var top := floor_y - DROP_HEIGHT
			var bounds: Rect2 = boss.get("arena_bounds")
			if bounds.size != Vector2.ZERO:
				top = maxf(top, bounds.position.y + 24.0)
			var index := 0
			for x: float in locked["columns"]:
				var shot: Dictionary = helpers._shot(
					0.08 * float(index), Vector2(x, top), Vector2.DOWN, 640.0, 2.0
				)
				shot["lifetime"] = 1.6
				shots.append(shot)
				index += 1
		&"frost_ring":
			var mark: Dictionary = locked["marks"][0]
			var gap: float = mark["gap"]
			var step := TAU / float(RING_DOTS)
			# Dots sit at gap + step * (index + 0.5); the two nearest the gap are dropped.
			for index in RING_DOTS:
				var angle := gap + step * (float(index) + 0.5)
				if absf(wrapf(angle - gap, -PI, PI)) < RING_GAP * 0.5:
					continue
				var direction := Vector2.RIGHT.rotated(angle)
				shots.append(helpers._shot(0.0, core + direction * 60.0, direction, 330.0))
	return shots
