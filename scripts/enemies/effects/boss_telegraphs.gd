extends RefCounted
## Attack telegraphs for CombatBoss (docs/features/boss-rework.md): the wind-up pose of each attack
## family, the release flash, and the markers that show where the locked attack will land (aim
## lines, floor lanes, floor circles, the heat ring gap, the maelstrom arms). Pure visuals.

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const RISE_ATTACKS: Array[StringName] = [&"fault_slam", &"rockfall", &"vent_burst"]
const LUNGE_ATTACKS: Array[StringName] = [&"shoulder_charge", &"scuttle_rush"]
const SWELL_ATTACKS: Array[StringName] = [&"tide_ring", &"heat_ring", &"maelstrom", &"crosscurrent"]
## The body flashes during the last part of every telegraph: "now".
const RELEASE_FLASH_SECONDS := 0.12
const DASH := 26.0
const DASH_GAP := 16.0


static func progress(boss: Node) -> float:
	var length := maxf(float(boss.get("_telegraph_length")), 0.01)
	return clampf(1.0 - float(boss.get("_telegraph_remaining")) / length, 0.0, 1.0)


## Sprite pose while telegraphing: {"scale", "offset", "rotation", "flash"}.
static func pose(boss: Node) -> Dictionary:
	var result := {"scale": Vector2.ONE, "offset": Vector2.ZERO, "rotation": 0.0, "flash": 0.0}
	var remaining := float(boss.get("_telegraph_remaining"))
	if remaining <= 0.0:
		return result
	var attack: StringName = boss.get("_attack_id")
	var age := float(boss.get("_age"))
	var facing := float(boss.get("_facing"))
	var p := progress(boss)
	if RISE_ATTACKS.has(attack):
		result["scale"] = Vector2(1.0 - 0.07 * p, 1.0 + 0.11 * p)
		result["offset"] = Vector2(0.0, -22.0 * p)
	elif LUNGE_ATTACKS.has(attack):
		result["scale"] = Vector2(1.0 + 0.07 * p, 1.0 - 0.09 * p)
		result["offset"] = Vector2(-facing * 26.0 * p, 10.0 * p)
		result["rotation"] = -facing * 0.07 * p
	elif SWELL_ATTACKS.has(attack):
		var shiver := sin(age * 60.0) * 0.012 * p
		result["scale"] = Vector2.ONE * (1.0 + 0.1 * p + shiver)
	else:
		var pulse := 0.5 + 0.5 * sin(age * 26.0)
		result["scale"] = Vector2(1.035 + pulse * 0.035, 0.98 - pulse * 0.015)
	if remaining <= RELEASE_FLASH_SECONDS:
		result["flash"] = 0.55
	return result


static func draw(boss: Node, canvas: CanvasItem, core: Vector2, accent: Color) -> void:
	var state: StringName = boss.get("_attack_state")
	if int(boss.get("stage")) >= Patterns.DESPERATION_STAGE:
		_draw_desperation(boss, canvas, accent)
	var telegraphing := float(boss.get("_telegraph_remaining")) > 0.0
	if not telegraphing and state != &"active":
		return
	var p := progress(boss) if telegraphing else 1.0
	var strength := 1.0 if telegraphing else 0.35
	if telegraphing:
		for direction: Vector2 in boss.get("_pending_directions"):
			var start := core + direction * 60.0
			var finish := core + direction * (90.0 + 200.0 * p)
			canvas.draw_line(start, finish, Color(accent, 0.25), 14.0, true)
			canvas.draw_line(start, finish, Color(accent.lightened(0.4), 0.8), 4.0, true)
	var node := boss as Node2D
	var age := float(boss.get("_age"))
	for mark: Dictionary in boss.get("_telegraph_marks"):
		match mark["kind"]:
			&"lane":
				_draw_lane(
					canvas,
					node.to_local(mark["from"]),
					node.to_local(mark["to"]),
					accent,
					p,
					strength
				)
			&"floor":
				_draw_floor(
					canvas,
					node.to_local(mark["at"]),
					float(mark["width"]),
					accent,
					p,
					age,
					strength
				)
			&"ring":
				_draw_ring(canvas, node.to_local(mark["center"]), mark, accent, p, strength)
			&"spiral":
				_draw_spiral(
					canvas,
					node.to_local(mark["center"]),
					int(mark["arms"]),
					accent,
					p,
					age,
					strength
				)


static func _draw_lane(
	canvas: CanvasItem, from: Vector2, to: Vector2, accent: Color, p: float, strength: float
) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var along := (to - from) / length
	var lit := length * p
	var distance := 0.0
	while distance < length:
		var start := from + along * distance
		var finish := from + along * minf(distance + DASH, length)
		var alpha := (0.85 if distance <= lit else 0.22) * strength
		canvas.draw_line(start, finish, Color(accent, alpha * 0.35), 16.0, true)
		canvas.draw_line(start, finish, Color(accent.lightened(0.35), alpha), 5.0, true)
		distance += DASH + DASH_GAP
	var normal := along.orthogonal() * 14.0
	var tip := to - along * 4.0
	canvas.draw_polyline(
		PackedVector2Array([tip - along * 22.0 + normal, tip, tip - along * 22.0 - normal]),
		Color(accent.lightened(0.35), 0.9 * strength),
		5.0,
		true
	)


static func _draw_floor(
	canvas: CanvasItem,
	at: Vector2,
	width: float,
	accent: Color,
	p: float,
	age: float,
	strength: float
) -> void:
	var pulse := 0.5 + 0.5 * sin(age * 22.0)
	var column := Rect2(at + Vector2(-width * 0.3, -420.0), Vector2(width * 0.6, 420.0))
	canvas.draw_rect(column, Color(accent, (0.05 + 0.1 * p) * strength), true)
	canvas.draw_set_transform(at, 0.0, Vector2(1.0, 0.28))
	var radius := width * 0.5 * (0.55 + 0.45 * p)
	canvas.draw_circle(Vector2.ZERO, radius, Color(accent, (0.2 + 0.25 * pulse) * strength))
	canvas.draw_arc(
		Vector2.ZERO,
		width * 0.5,
		0.0,
		TAU,
		32,
		Color(accent.lightened(0.4), 0.9 * strength),
		5.0,
		true
	)
	canvas.draw_set_transform(Vector2.ZERO)


static func _draw_ring(
	canvas: CanvasItem, center: Vector2, mark: Dictionary, accent: Color, p: float, strength: float
) -> void:
	var count: int = mark["count"]
	var gap: float = mark["gap"]
	var half_gap := float(mark["gap_width"]) * 0.5
	var radius := 110.0 + 70.0 * p
	for index in count:
		var angle := gap + TAU * (float(index) + 0.5) / float(count)
		if absf(wrapf(angle - gap, -PI, PI)) < half_gap:
			continue
		var dot := center + Vector2.RIGHT.rotated(angle) * radius
		canvas.draw_circle(dot, 9.0 + 5.0 * p, Color(accent, 0.75 * strength))
	# The safe gap is framed by two bright spokes.
	for side in [-1.0, 1.0]:
		var edge := Vector2.RIGHT.rotated(gap + side * half_gap)
		canvas.draw_line(
			center + edge * 70.0,
			center + edge * (radius + 40.0),
			Color(accent.lightened(0.5), 0.9 * strength),
			4.0,
			true
		)


static func _draw_spiral(
	canvas: CanvasItem,
	center: Vector2,
	arms: int,
	accent: Color,
	p: float,
	age: float,
	strength: float
) -> void:
	for arm in arms:
		var points := PackedVector2Array()
		var base := age * 3.0 + TAU * float(arm) / float(arms)
		for step in 17:
			var t := float(step) / 16.0
			points.append(center + Vector2.RIGHT.rotated(base + t * 2.4) * (50.0 + 170.0 * p * t))
		canvas.draw_polyline(points, Color(accent.lightened(0.3), 0.8 * strength), 5.0, true)


static func _draw_desperation(boss: Node, canvas: CanvasItem, accent: Color) -> void:
	var center: Vector2 = boss.get("_visual_base_position")
	var age := float(boss.get("_age"))
	var beat := 0.5 + 0.5 * sin(age * 9.0)
	canvas.draw_arc(
		center, 200.0 + 10.0 * beat, 0.0, TAU, 48, Color(accent, 0.12 + 0.14 * beat), 8.0, true
	)
