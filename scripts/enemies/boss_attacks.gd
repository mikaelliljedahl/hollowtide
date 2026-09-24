extends RefCounted
## Attack planning and emission for CombatBoss (docs/features/boss-rework.md). `plan` runs when
## a telegraph starts and locks every aim, lane and floor target, so the telegraph shows exactly
## where damage will go. `emissions` turns the locked plan into timed shots for the active step.
## Charges carry their lane end in the plan and move the boss body instead of firing.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const BODY_RADIUS := 92.0
const ARENA_FALLBACK_HALF_WIDTH := 700.0
const FLOOR_FALLBACK_DEPTH := 400.0
const FLOOR_PROBE := 1400.0
const LANE_MARGIN := 40.0
## Heights above the floor: the low lane is jumped, the high lane passes over a crouch or ball.
const LOW_LANE_HEIGHT := 30.0
const HIGH_LANE_HEIGHT := 140.0
const SHOCKWAVE_HEIGHT := 26.0
const ROCK_DROP_HEIGHT := 560.0
const HEAT_RING_COUNT := 14
const HEAT_RING_GAP_STEPS := 3
const MAELSTROM_STEPS := 12
const MAELSTROM_INTERVAL := 0.1
const MAELSTROM_TURN := 0.42
const CHARGE_SPEEDS := {&"shoulder_charge": 640.0, &"scuttle_rush": 580.0}
## Floor every charge leaves clear before the first wall (a low roof or an arena step counts) or
## the lane end, so a player backed against the wall is outside the body's reach when it stops.
const CHARGE_WALL_POCKET := 128.0
const STYLES := {
	&"stone_guardian": &"rock",
	&"furnace_mother": &"fire",
	&"tidal_heart": &"water",
}


static func plan(boss: Node2D, attack: StringName) -> Dictionary:
	var stage: int = boss.get("stage")
	var core: Vector2 = boss.call("_core_world_position")
	var target := _target_point(boss)
	var aim := (target + Vector2(0.0, -80.0) - core).normalized()
	if aim.is_zero_approx():
		aim = Vector2.DOWN
	var floor_y := _floor_y(boss)
	var lane := _lane(boss)
	var desperate := stage >= Patterns.DESPERATION_STAGE
	var directions: Array[Vector2] = []
	var marks: Array[Dictionary] = []
	var result := {
		"attack": attack,
		"core": core,
		"aim": aim,
		"floor_y": floor_y,
		"lane": lane,
		"directions": directions,
		"marks": marks,
	}
	match attack:
		&"boulder_volley":
			var count := 1 if stage < Patterns.ARMORED_STAGE else (5 if desperate else 3)
			directions.append_array(_fan_below(aim, count, 0.2 if desperate else 0.22))
		&"ember_fan":
			directions.append_array(_spread(aim, 3 if stage < Patterns.ARMORED_STAGE else 5, 0.28))
		&"surge_lance":
			directions.append(aim)
		&"tide_ring":
			var count := 8 if stage < Patterns.ARMORED_STAGE else 10
			for index in count:
				directions.append(Vector2.RIGHT.rotated(TAU * float(index) / float(count)))
		&"fault_slam":
			var feet := Vector2(boss.global_position.x, floor_y - SHOCKWAVE_HEIGHT)
			marks.append(_lane_mark(feet, Vector2(lane.x, feet.y)))
			marks.append(_lane_mark(feet, Vector2(lane.y, feet.y)))
		&"rockfall", &"vent_burst":
			var spacing := 220.0 if attack == &"rockfall" else 300.0
			var offsets: Array[float] = [0.0, -1.0, 1.0]
			if desperate:
				spacing *= 0.7 if attack == &"vent_burst" else 1.0
				offsets.append_array([-2.0, 2.0])
			var columns: Array[float] = []
			for offset in offsets:
				var x := clampf(target.x + offset * spacing, lane.x, lane.y)
				if not columns.has(x):
					columns.append(x)
					marks.append({"kind": &"floor", "at": Vector2(x, floor_y), "width": 120.0})
			result["columns"] = columns
		&"heat_ring":
			var ring := {
				"kind": &"ring",
				"center": core,
				"gap": aim.angle(),
				"gap_width": TAU / float(HEAT_RING_COUNT) * float(HEAT_RING_GAP_STEPS),
				"count": HEAT_RING_COUNT,
			}
			marks.append(ring)
		&"crosscurrent":
			var from_right := target.x < (lane.x + lane.y) * 0.5
			var start_x := lane.y if from_right else lane.x
			var end_x := lane.x if from_right else lane.y
			var heights: Array[float] = [LOW_LANE_HEIGHT]
			if desperate:
				heights.append(HIGH_LANE_HEIGHT)
			for height in heights:
				var y := floor_y - height
				marks.append(_lane_mark(Vector2(start_x, y), Vector2(end_x, y)))
			result["start_x"] = start_x
			result["direction"] = Vector2.LEFT if from_right else Vector2.RIGHT
		&"maelstrom":
			marks.append({"kind": &"spiral", "center": core, "arms": 3 if desperate else 2})
			result["start_angle"] = aim.angle() + PI * 0.5
		&"shoulder_charge", &"scuttle_rush":
			var direction := signf(target.x - boss.global_position.x)
			if is_zero_approx(direction):
				direction = float(boss.get("_facing"))
			var end_x := boss.global_position.x
			var bounds: Rect2 = boss.get("arena_bounds")
			# Without an arena there is no lane to charge along (test benches only).
			if bounds.size != Vector2.ZERO:
				var limit := _first_wall_x(boss, direction, lane.y if direction > 0.0 else lane.x)
				end_x = limit - direction * (BODY_RADIUS + CHARGE_WALL_POCKET)
			result["charge_direction"] = direction
			result["charge_end_x"] = end_x
			var y := floor_y - 20.0
			marks.append(_lane_mark(Vector2(boss.global_position.x, y), Vector2(end_x, y)))
	return result


static func emissions(boss: Node2D, attack: StringName, locked: Dictionary) -> Array[Dictionary]:
	var stage: int = boss.get("stage")
	var desperate := stage >= Patterns.DESPERATION_STAGE
	var core: Vector2 = locked["core"]
	var floor_y: float = locked["floor_y"]
	var lane: Vector2 = locked["lane"]
	var shots: Array[Dictionary] = []
	match attack:
		&"boulder_volley", &"tide_ring":
			for direction: Vector2 in locked["directions"]:
				shots.append(_shot(0.0, core + direction * 60.0, direction, 360.0))
			if desperate and attack == &"tide_ring":
				var count: int = (locked["directions"] as Array).size()
				for index in count:
					var angle := TAU * (float(index) + 0.5) / float(count)
					var direction := Vector2.RIGHT.rotated(angle)
					shots.append(_shot(0.35, core + direction * 60.0, direction, 360.0))
		&"ember_fan":
			var repeats := 2 if desperate else 1
			for repeat in repeats:
				for direction: Vector2 in locked["directions"]:
					shots.append(
						_shot(0.3 * float(repeat), core + direction * 60.0, direction, 380.0)
					)
		&"surge_lance":
			var aim: Vector2 = locked["aim"]
			for index in 5 if desperate else 3:
				shots.append(_shot(0.12 * float(index), core + aim * 60.0, aim, 620.0, 1.3))
		&"fault_slam":
			var pairs := 2 if desperate else 1
			var lifetime := (lane.y - lane.x) / 430.0 + 0.3
			for pair in pairs:
				for side in [-1.0, 1.0]:
					var origin := Vector2(
						boss.global_position.x + side * 70.0, floor_y - SHOCKWAVE_HEIGHT
					)
					var shot := _shot(0.85 * float(pair), origin, Vector2(side, 0.0), 430.0, 2.2)
					shot["lifetime"] = lifetime
					shots.append(shot)
		&"rockfall":
			var bounds: Rect2 = boss.get("arena_bounds")
			var top := floor_y - ROCK_DROP_HEIGHT
			if bounds.size != Vector2.ZERO:
				top = maxf(top, bounds.position.y + 24.0)
			var index := 0
			for x: float in locked["columns"]:
				var shot := _shot(0.08 * float(index), Vector2(x, top), Vector2.DOWN, 640.0, 2.0)
				shot["lifetime"] = 1.6
				shots.append(shot)
				index += 1
		&"vent_burst":
			for x: float in locked["columns"]:
				for burst in 3:
					var shot := _shot(
						0.08 * float(burst), Vector2(x, floor_y - 16.0), Vector2.UP, 700.0, 1.8
					)
					shot["lifetime"] = 0.8
					shots.append(shot)
		&"heat_ring":
			var mark: Dictionary = locked["marks"][0]
			var gap: float = mark["gap"]
			var step := TAU / float(HEAT_RING_COUNT)
			var rings := 2 if desperate else 1
			for ring in rings:
				# Shots run from half the gap width past its centre round to half the gap before it;
				# the desperation ring is offset by half a step and so leaves a slightly wider gap.
				var first := float(HEAT_RING_GAP_STEPS) * 0.5 + 0.5 * float(ring)
				for index in HEAT_RING_COUNT - HEAT_RING_GAP_STEPS + 1 - ring:
					var direction := Vector2.RIGHT.rotated(gap + step * (first + float(index)))
					shots.append(
						_shot(0.4 * float(ring), core + direction * 60.0, direction, 330.0)
					)
		&"crosscurrent":
			var direction: Vector2 = locked["direction"]
			var start_x: float = locked["start_x"]
			var lifetime := (lane.y - lane.x) / 520.0 + 0.2
			var marks: Array = locked["marks"]
			for lane_index in marks.size():
				var y: float = (marks[lane_index] as Dictionary)["from"].y
				for bead in 3:
					var at := 1.0 * float(lane_index) + 0.07 * float(bead)
					var shot := _shot(at, Vector2(start_x, y), direction, 520.0, 2.0)
					shot["lifetime"] = lifetime
					shots.append(shot)
		&"maelstrom":
			var mark: Dictionary = locked["marks"][0]
			var arms: int = mark["arms"]
			var start: float = locked["start_angle"]
			for step in MAELSTROM_STEPS:
				for arm in arms:
					var angle := (
						start + MAELSTROM_TURN * float(step) + TAU * float(arm) / float(arms)
					)
					var direction := Vector2.RIGHT.rotated(angle)
					shots.append(
						_shot(
							MAELSTROM_INTERVAL * float(step),
							core + direction * 60.0,
							direction,
							300.0
						)
					)
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
	return shots


static func fire(boss: Node2D, shot: Dictionary) -> void:
	var projectile := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	if projectile == null:
		return
	var tree := boss.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(projectile)
	projectile.global_position = shot["origin"]
	projectile.style = STYLES.get(boss.get("enemy_id"), &"orb")
	projectile.size_scale = shot["scale"]
	projectile.speed = shot["speed"]
	projectile.lifetime = shot["lifetime"]
	projectile.launch(shot["direction"], int(boss.call("_contact_damage")))
	projectile.configure_arena(boss.get("arena_bounds"))


static func charge_speed(attack: StringName) -> float:
	return float(CHARGE_SPEEDS.get(attack, 600.0))


static func _shot(
	at: float, origin: Vector2, direction: Vector2, speed: float, scale := 1.6
) -> Dictionary:
	return {
		"at": at,
		"origin": origin,
		"direction": direction,
		"speed": speed,
		"scale": scale,
		"lifetime": 3.0,
	}


static func _lane_mark(from: Vector2, to: Vector2) -> Dictionary:
	return {"kind": &"lane", "from": from, "to": to}


## The volley's first rock flies on the locked aim line and the rest fan out below it, toward the
## floor, so jumping over the aim line clears every rock at any range.
static func _fan_below(aim: Vector2, count: int, step: float) -> Array[Vector2]:
	var side := 1.0 if aim.x >= 0.0 else -1.0
	var result: Array[Vector2] = []
	for index in count:
		result.append(aim.rotated(side * step * float(index)))
	return result


static func _spread(aim: Vector2, count: int, step: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in count:
		result.append(aim.rotated(step * (float(index) - float(count - 1) * 0.5)))
	return result


static func _target_point(boss: Node2D) -> Vector2:
	var player := boss.get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null and bool(boss.call("_in_arena", player.global_position)):
		return player.global_position
	return boss.global_position + Vector2(float(boss.get("_facing")) * 300.0, 0.0)


static func _floor_y(boss: Node2D) -> float:
	if boss.get("enemy_id") != &"tidal_heart":
		return boss.global_position.y + BODY_RADIUS
	var bounds: Rect2 = boss.get("arena_bounds")
	var fallback := boss.global_position.y + FLOOR_FALLBACK_DEPTH
	if bounds.size != Vector2.ZERO:
		fallback = bounds.end.y
	if not boss.is_inside_tree():
		return fallback
	var from := boss.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, FLOOR_PROBE), 1)
	var hit := boss.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return minf((hit["position"] as Vector2).y, fallback)


## The nearer of `lane_edge` and the first world wall the body would meet in `direction`: probed
## near the top of the body, at its centre and just above the floor, so a low roof or a step counts.
static func _first_wall_x(boss: Node2D, direction: float, lane_edge: float) -> float:
	if not boss.is_inside_tree():
		return lane_edge
	var limit := lane_edge
	var space := boss.get_world_2d().direct_space_state
	for height: float in [-BODY_RADIUS * 0.7, 0.0, BODY_RADIUS * 0.8]:
		var from := boss.global_position + Vector2(0.0, height)
		var query := PhysicsRayQueryParameters2D.create(
			from, Vector2(lane_edge, from.y), 1, [boss.call(&"get_rid")]
		)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (Vector2(hit["position"]).x - limit) * direction < 0.0:
			limit = Vector2(hit["position"]).x
	return limit


## Horizontal extent attacks may use: x = left edge, y = right edge.
static func _lane(boss: Node2D) -> Vector2:
	var bounds: Rect2 = boss.get("arena_bounds")
	if bounds.size == Vector2.ZERO:
		var x := boss.global_position.x
		return Vector2(x - ARENA_FALLBACK_HALF_WIDTH, x + ARENA_FALLBACK_HALF_WIDTH)
	return Vector2(bounds.position.x + LANE_MARGIN, bounds.end.x - LANE_MARGIN)
