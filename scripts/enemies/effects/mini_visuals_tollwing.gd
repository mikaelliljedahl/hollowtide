extends RefCounted
## Tollwing body (docs/features/mini-bosses.md 3.2): a tall teardrop bell of resonant crystal with two
## glassy wings and a clapper that swings harder the closer a release gets. Code-drawn, no text;
## pure presentation. Origin = body centre (92 px body circle), the lip sits near the floor.

const Telegraphs = preload("res://scripts/enemies/effects/boss_telegraphs.gd")
const GLASS := Color(0.5, 0.68, 0.8, 0.92)
const GLASS_DEEP := Color(0.22, 0.34, 0.46, 0.95)
const GLASS_LIGHT := Color(0.8, 0.93, 1.0, 0.9)
const PROFILE_STEPS := 12


static func draw_body(boss: Node2D, canvas: CanvasItem) -> void:
	var age: float = boss.get("_age")
	var facing: float = boss.get("_facing")
	var accent: Color = boss.call("_boss_accent_color")
	var telegraphing: bool = float(boss.get("_telegraph_remaining")) > 0.0
	var state: StringName = boss.get("_attack_state")
	var attack: StringName = boss.get("_attack_id")
	var p := Telegraphs.progress(boss) if telegraphing else 0.0
	var exposed: bool = boss.call("weak_point_exposed")
	var armored: bool = int(boss.get("phase")) == 2 and not exposed
	var flash := clampf(float(boss.get("_hit_flash_remaining")) / 0.14, 0.0, 1.0)
	var glass := GLASS.darkened(0.3) if armored else GLASS
	glass = glass.lerp(Color.WHITE, flash * 0.7)
	var lift := -8.0 + 4.0 * sin(age * 2.0)
	var tilt := 0.0
	var swell := 1.0
	var diving := state == &"active" and attack == &"swoop"
	if telegraphing and attack == &"swoop":
		tilt = -facing * 0.35 * p
	elif diving:
		tilt = facing * 0.3
	elif telegraphing and attack == &"toll_ring":
		swell = 1.0 + 0.12 * p
	elif telegraphing and attack == &"shard_drop":
		lift -= 22.0 * p
	elif telegraphing and attack == &"peal_lane":
		swell = 1.0 + 0.06 * sin(age * 40.0) * p + 0.06 * p
	canvas.draw_set_transform(Vector2(0.0, lift), tilt, Vector2(swell, swell))
	_draw_wings(canvas, age, diving, glass)
	_draw_bell(canvas, glass, accent, p)
	_draw_clapper(canvas, age, accent, p, telegraphing)
	canvas.draw_set_transform(Vector2.ZERO)


static func _profile(half_width_scale: float) -> PackedVector2Array:
	var right := PackedVector2Array()
	for index in range(1, PROFILE_STEPS + 1):
		var t := float(index) / float(PROFILE_STEPS)
		right.append(Vector2((16.0 + 62.0 * pow(t, 2.0)) * half_width_scale, -96.0 + 150.0 * t))
	var points := PackedVector2Array()
	points.append(Vector2(0.0, -104.0))
	points.append_array(right)
	for index in range(right.size() - 1, -1, -1):
		points.append(Vector2(-right[index].x, right[index].y))
	return points


static func _draw_bell(canvas: CanvasItem, glass: Color, accent: Color, p: float) -> void:
	canvas.draw_colored_polygon(_profile(1.0), GLASS_DEEP.lerp(glass, 0.35))
	canvas.draw_colored_polygon(_profile(0.78), glass)
	canvas.draw_colored_polygon(_profile(0.4), Color(GLASS_LIGHT, 0.45))
	# Facet lines and the lip band.
	for x in [-0.55, -0.2, 0.2, 0.55]:
		canvas.draw_line(
			Vector2(x * 10.0, -84.0), Vector2(x * 70.0, 48.0), Color(GLASS_LIGHT, 0.4), 2.0, true
		)
	var lip := PackedVector2Array([Vector2(-80.0, 50.0), Vector2(80.0, 50.0)])
	canvas.draw_polyline(lip, accent.lerp(Color.WHITE, 0.2 + 0.5 * p), 7.0, true)
	canvas.draw_circle(Vector2(0.0, -104.0), 7.0, accent)


static func _draw_clapper(
	canvas: CanvasItem, age: float, accent: Color, p: float, telegraphing: bool
) -> void:
	var amplitude := 0.12 + (0.65 * p if telegraphing else 0.0)
	var swing := sin(age * (7.0 + 14.0 * p)) * amplitude
	var tip := Vector2(sin(swing) * 62.0, 6.0 + cos(swing) * 62.0)
	canvas.draw_line(Vector2(0.0, -10.0), tip, GLASS_LIGHT, 4.0, true)
	canvas.draw_circle(tip, 13.0, accent)
	canvas.draw_circle(tip, 7.0, accent.lightened(0.5))


static func _draw_wings(canvas: CanvasItem, age: float, diving: bool, glass: Color) -> void:
	var flap := 0.14 * sin(age * 5.0) + (0.35 if diving else 0.0)
	for side in [-1.0, 1.0]:
		var shoulder := Vector2(side * 46.0, -26.0)
		var outward := Vector2(side, -0.55 + flap).normalized()
		var length := 96.0 + (24.0 if diving else 0.0)
		var tip := shoulder + outward * length
		var lower := shoulder + Vector2(side * 30.0, 50.0 - 18.0 * flap)
		var wing := PackedVector2Array([shoulder, tip, tip.lerp(lower, 0.45), lower])
		# Order the points so the polygon stays valid whichever side it is mirrored to.
		if side < 0.0:
			wing.reverse()
		canvas.draw_colored_polygon(wing, Color(glass, 0.55))
		canvas.draw_polyline(
			PackedVector2Array([shoulder, tip, lower]), Color(GLASS_LIGHT, 0.85), 3.0, true
		)
		canvas.draw_line(shoulder, tip.lerp(lower, 0.5), Color(GLASS_LIGHT, 0.4), 2.0, true)
