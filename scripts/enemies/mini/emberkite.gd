extends RefCounted
## Emberkite (kiln, kiln_08): a swept cinder flyer (docs/features/mini-bosses.md 3.4).
## Stage 1: Ember Fan (reused main attack), Flare Dive (charge), Vent Column (reused vent_burst).
## Stage 2 adds Cinder Rain: four ember columns fall across the room with one bright gap.

const ID := &"emberkite"
const MAX_HEALTH := 170
const CONTACT_DAMAGE := 20
const ACCENT := Color(1.0, 0.76, 0.24, 1.0)
const CHARGE_SPEED := 480.0
const RAIN_SPACING := 192.0
const RAIN_COLUMNS := 4
const RAIN_DROP_HEIGHT := 520.0
const TIMING := {
	&"ember_fan": {"telegraph": 0.6, "active": 0.1, "punish": 1.3},
	&"flare_dive": {"telegraph": 0.85, "active": 1.2, "punish": 2.2},
	&"vent_burst": {"telegraph": 0.8, "active": 0.3, "punish": 1.4},
	&"cinder_rain": {"telegraph": 1.1, "active": 0.8, "punish": 2.6},
}
const CHARGES: Array[StringName] = [&"flare_dive"]
const MOVE_SPEEDS: Array[float] = [110.0, 140.0]
## Pacing: perfect Harpoon play needs three openings per stage, so the first three chains of each
## stage carry the fight length; stage 1 chains four attacks, stage 2 has exactly one chain.
const ROTATIONS := [
	[
		[&"ember_fan", &"flare_dive", &"vent_burst", &"ember_fan"],
		[&"vent_burst", &"ember_fan", &"flare_dive", &"vent_burst"],
		[&"flare_dive", &"vent_burst", &"ember_fan", &"flare_dive"],
		[&"ember_fan"],
	],
	[
		[&"ember_fan", &"cinder_rain", &"flare_dive", &"vent_burst"],
		[&"cinder_rain"],
		[&"flare_dive"],
		[&"vent_burst"],
		[&"ember_fan"],
		[&"cinder_rain"],
	],
]


## Cinder Rain: columns 192 px apart, two either side of a bright gap at the player's spot. The gap
## (the space between the inner columns) is the answer; a wall-hugging player gets the gap shifted
## inward and the missing columns refilled on the open side.
static func plan(
	boss: Node2D, attack: StringName, result: Dictionary, target: Vector2, _helpers
) -> void:
	if attack != &"cinder_rain":
		return
	var lane: Vector2 = result["lane"]
	var floor_y: float = result["floor_y"]
	var marks: Array = result["marks"]
	var gap_x := clampf(target.x, lane.x + RAIN_SPACING, lane.y - RAIN_SPACING)
	var columns: Array[float] = []
	for offset: float in [-2.0, -1.0, 1.0, 2.0]:
		var x := gap_x + offset * RAIN_SPACING
		if x >= lane.x and x <= lane.y:
			columns.append(x)
	var step := 1.0 if gap_x - lane.x < lane.y - gap_x else -1.0
	var extra := 3.0
	while columns.size() < RAIN_COLUMNS and extra < 12.0:
		var x := gap_x + step * extra * RAIN_SPACING
		if x >= lane.x and x <= lane.y and not columns.has(x):
			columns.append(x)
		extra += 1.0
	for x: float in columns:
		marks.append({"kind": &"floor", "at": Vector2(x, floor_y), "width": 120.0})
	result["columns"] = columns
	result["gap_x"] = gap_x
	result["origin"] = boss.global_position


static func emissions(
	_boss: Node2D, attack: StringName, locked: Dictionary, _helpers
) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	if attack != &"cinder_rain" or not locked.has("columns"):
		return shots
	var floor_y: float = locked["floor_y"]
	var index := 0
	for x: float in locked["columns"]:
		for bead in 3:
			shots.append(
				{
					"at": 0.06 * float(index) + 0.1 * float(bead),
					"origin": Vector2(x, floor_y - RAIN_DROP_HEIGHT),
					"direction": Vector2.DOWN,
					"speed": 620.0,
					"scale": 1.8,
					"lifetime": 1.1,
				}
			)
		index += 1
	return shots
