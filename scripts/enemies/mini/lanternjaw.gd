extends RefCounted
## Lanternjaw (depths, depths_08): a blind deepwater predator with one violet lure
## (docs/features/mini-bosses.md 3.5). Stage 1: Lure Pulse, Bite Lunge, Dark Lance. Stage 2 adds
## Undertow Pull. Lure Pulse and Dark Lance are the radial drops and the bolt line of the main
## `tide_ring` and `surge_lance`, but under their own ids so the main bosses' timing stays untouched.

const ID := &"lanternjaw"
const MAX_HEALTH := 190
const CONTACT_DAMAGE := 22
const ACCENT := Color(0.72, 0.42, 1.0, 1.0)
const CHARGE_SPEED := 600.0
const PULSE_COUNT := 8
const LANCE_BOLTS := 3
const PULL_SPEED := 300.0
## How far above the floor the pull still drags (dash out, or jump clear, to escape it).
const PULL_HEIGHT := 240.0
const TIMING := {
	&"lure_pulse": {"telegraph": 0.6, "active": 0.1, "punish": 1.2},
	&"bite_lunge": {"telegraph": 0.7, "active": 0.9, "punish": 1.5},
	&"dark_lance": {"telegraph": 0.65, "active": 0.3, "punish": 1.2},
	&"undertow_pull": {"telegraph": 0.8, "active": 1.2, "punish": 1.5},
}
const CHARGES: Array[StringName] = [&"bite_lunge"]
const MOVE_SPEEDS: Array[float] = [130.0, 170.0]
## Stage 1 plays long chains (each ends in one punish window) so the fight runs near half a minute
## without extra openings; the opening budget is fixed by the framework. Stage 2 keeps the shared
## rule of one multi-attack chain per cycle and puts it inside its first three openings.
const ROTATIONS := [
	[
		[&"lure_pulse", &"dark_lance", &"bite_lunge", &"lure_pulse", &"dark_lance", &"bite_lunge"],
		[&"bite_lunge", &"lure_pulse", &"dark_lance", &"bite_lunge", &"dark_lance", &"lure_pulse"],
		[&"dark_lance", &"lure_pulse", &"bite_lunge"],
	],
	[
		[&"undertow_pull"],
		[&"dark_lance"],
		[&"bite_lunge", &"dark_lance", &"undertow_pull", &"lure_pulse", &"bite_lunge"],
		[&"undertow_pull"],
		[&"bite_lunge"],
		[&"dark_lance"],
	],
]


## Locks the aim, the radial fan or the pull lane while the telegraph starts.
static func plan(
	boss: Node2D, attack: StringName, result: Dictionary, target: Vector2, _helpers
) -> void:
	var directions: Array = result["directions"]
	var marks: Array = result["marks"]
	match attack:
		&"lure_pulse":
			# Every second pulse is offset by half a step so the gaps move.
			var uses: int = int(boss.get_meta(&"lure_uses", 0))
			boss.set_meta(&"lure_uses", uses + 1)
			var offset_step := 0.5 if uses % 2 == 1 else 0.0
			for index in PULSE_COUNT:
				var angle := TAU * (float(index) + offset_step) / float(PULSE_COUNT)
				directions.append(Vector2.RIGHT.rotated(angle))
		&"dark_lance":
			directions.append(result["aim"])
		&"undertow_pull":
			var lane: Vector2 = result["lane"]
			var floor_y: float = result["floor_y"]
			var side := signf(target.x - boss.global_position.x)
			if is_zero_approx(side):
				side = float(boss.get("_facing"))
			var start_x := lane.y if side > 0.0 else lane.x
			var y := floor_y - 40.0
			marks.append(
				{
					"kind": &"lane",
					"from": Vector2(start_x, y),
					"to": Vector2(boss.global_position.x, y),
				}
			)
			result["pull_from_x"] = start_x
			result["pull_floor_y"] = floor_y


static func emissions(
	boss: Node2D, attack: StringName, locked: Dictionary, helpers
) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var core: Vector2 = locked["core"]
	match attack:
		&"lure_pulse":
			for direction: Vector2 in locked["directions"]:
				shots.append(helpers._shot(0.0, core + direction * 60.0, direction, 360.0))
		&"dark_lance":
			var aim: Vector2 = locked["aim"]
			for index in LANCE_BOLTS:
				shots.append(helpers._shot(0.12 * float(index), core + aim * 60.0, aim, 620.0, 1.3))
		&"undertow_pull":
			# Only a released attack drags; planning or probing it must stay free of side effects.
			if boss.get("_attack_state") == &"active":
				var pull := Pull.new()
				pull.boss = boss
				pull.from_x = float(locked["pull_from_x"])
				pull.floor_y = float(locked["pull_floor_y"])
				pull.remaining = float(TIMING[&"undertow_pull"]["active"])
				boss.add_child(pull)
	return shots


## The current of Undertow Pull: drags the player toward the jaw for the attack's active time.
class Pull:
	extends Node
	var boss: Node2D
	var from_x := 0.0
	var floor_y := 0.0
	var remaining := 1.2

	func _physics_process(delta: float) -> void:
		remaining -= delta
		if remaining <= 0.0 or not is_instance_valid(boss):
			queue_free()
			return
		var player := get_tree().get_first_node_in_group(&"player") as CharacterBody2D
		if player == null or GameState.health <= 0:
			return
		var mouth_x := boss.global_position.x
		var at := player.global_position
		if at.x < minf(from_x, mouth_x) or at.x > maxf(from_x, mouth_x):
			return
		if at.y < floor_y - 240.0:
			return
		var gap := mouth_x - at.x
		player.move_and_collide(Vector2(signf(gap) * minf(300.0 * delta, absf(gap)), 0.0))
