extends RefCounted
## Fernmaw (fringe, fringe_08): a squat moss-backed leaper (docs/features/mini-bosses.md 3.1).
## Stage 1: Spore Lob, Pounce. Stage 2 adds Root Burst. Data and the two emissions the shared
## boss_attacks.gd does not know: the spore arc and the root spikes.

const ID := &"fernmaw"
const MAX_HEALTH := 100
const CONTACT_DAMAGE := 14
const ACCENT := Color(0.55, 0.9, 0.3, 1.0)
const CHARGE_SPEED := 900.0
const SPORE_OFFSET := 192.0
const ROOT_OFFSET := 256.0
const SPORE_ARC_HEIGHT := 260.0
const TIMING := {
	&"spore_lob": {"telegraph": 0.6, "active": 0.1, "punish": 1.2},
	&"pounce": {"telegraph": 0.65, "active": 0.8, "punish": 1.4},
	&"root_burst": {"telegraph": 0.75, "active": 0.3, "punish": 1.4},
}
const CHARGES: Array[StringName] = [&"pounce"]
const MOVE_SPEEDS: Array[float] = [120.0, 150.0]
const ROTATIONS := [
	[[&"spore_lob"], [&"pounce"]],
	[[&"root_burst"], [&"pounce"], [&"spore_lob"], [&"pounce", &"spore_lob"]],
]


## Locks the target columns while the telegraph starts: player spot and one column either side.
static func plan(
	boss: Node2D, attack: StringName, result: Dictionary, target: Vector2, _helpers
) -> void:
	var lane: Vector2 = result["lane"]
	var floor_y: float = result["floor_y"]
	var spacing := SPORE_OFFSET if attack == &"spore_lob" else ROOT_OFFSET
	var columns: Array[float] = []
	var marks: Array = result["marks"]
	for offset in [0.0, -1.0, 1.0]:
		var x := clampf(target.x + offset * spacing, lane.x, lane.y)
		if not columns.has(x):
			columns.append(x)
			marks.append({"kind": &"floor", "at": Vector2(x, floor_y), "width": 120.0})
	result["columns"] = columns
	result["origin"] = boss.global_position


static func emissions(
	_boss: Node2D, attack: StringName, locked: Dictionary, _helpers
) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	if not locked.has("columns"):
		return shots
	var floor_y: float = locked["floor_y"]
	var index := 0
	for x: float in locked["columns"]:
		if attack == &"spore_lob":
			# A spore falls onto its locked mark (~0.45 s) and bursts where it lands.
			var drop_from := Vector2(x, floor_y - SPORE_ARC_HEIGHT)
			shots.append(_shot(0.05 * index, drop_from, Vector2.DOWN, 620.0, 2.0, 0.7))
		else:
			for spike in 3:
				shots.append(
					_shot(
						0.06 * index + 0.06 * spike,
						Vector2(x + (spike - 1) * 26.0, floor_y - 16.0),
						Vector2.UP,
						700.0,
						1.8,
						0.7
					)
				)
		index += 1
	return shots


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
