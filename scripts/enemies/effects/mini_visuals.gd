extends RefCounted
## Code-drawn bodies for the mini-bosses (docs/features/mini-bosses.md; art batch later). Drawn on
## the CombatBoss node itself (origin = body centre, the 92 px body circle). Fernmaw lives here;
## every other boss draws through its own scripts/enemies/effects/mini_visuals_<id>.gd with a
## static `draw_body(boss, canvas)`, found by name so this file never needs editing for them.
## Pure presentation: nothing here changes damage rules or timings.

const Telegraphs = preload("res://scripts/enemies/effects/boss_telegraphs.gd")
const BODY_RADIUS := 92.0
const MOSS := Color(0.2, 0.34, 0.15)
const MOSS_DARK := Color(0.1, 0.18, 0.09)
const BARK := Color(0.3, 0.22, 0.14)
const FROND := Color(0.42, 0.74, 0.24)


static func draw_body(boss: Node2D, canvas: CanvasItem) -> void:
	var id: StringName = boss.get("enemy_id")
	var path := "res://scripts/enemies/effects/mini_visuals_%s.gd" % String(id)
	if id != &"fernmaw" and ResourceLoader.exists(path):
		var script := load(path) as GDScript
		script.draw_body(boss, canvas)
		return
	if id == &"fernmaw":
		_draw_fernmaw(boss, canvas)
	else:
		_draw_placeholder(boss, canvas)


## A plain accent-coloured disc for a boss whose own visuals are not written yet.
static func _draw_placeholder(boss: Node2D, canvas: CanvasItem) -> void:
	var accent: Color = boss.call("_boss_accent_color")
	canvas.draw_circle(Vector2.ZERO, BODY_RADIUS * 0.7, accent.darkened(0.5))
	canvas.draw_arc(Vector2.ZERO, BODY_RADIUS * 0.7, 0.0, TAU, 32, accent, 4.0, true)


static func oval(center: Vector2, radii: Vector2, steps := 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in steps:
		var angle := TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


static func _draw_fernmaw(boss: Node2D, canvas: CanvasItem) -> void:
	var age: float = boss.get("_age")
	var facing: float = boss.get("_facing")
	var accent: Color = boss.call("_boss_accent_color")
	var telegraphing: bool = float(boss.get("_telegraph_remaining")) > 0.0
	var p := Telegraphs.progress(boss) if telegraphing else 0.0
	var attack: StringName = boss.get("_attack_id")
	var exposed: bool = boss.call("weak_point_exposed")
	var armored: bool = int(boss.get("phase")) == 2 and not exposed
	var flash := clampf(float(boss.get("_hit_flash_remaining")) / 0.14, 0.0, 1.0)
	var moss := MOSS.darkened(0.25) if armored else MOSS
	moss = moss.lerp(Color.WHITE, flash * 0.7)
	# Crouch before a pounce, rise before a burst, otherwise breathe.
	var squash := 1.0 + 0.03 * sin(age * 2.2)
	var lift := 0.0
	if telegraphing and attack == &"pounce":
		squash = 1.0 - 0.22 * p
	elif telegraphing and attack == &"root_burst":
		lift = -26.0 * p
	canvas.draw_set_transform(Vector2(0.0, 40.0 + lift), 0.0, Vector2(facing, squash))
	# Hind legs: heavy thighs with a folded foot.
	for side in [-1.0, -0.45]:
		var hip := Vector2(side * 70.0, -4.0)
		canvas.draw_colored_polygon(oval(hip, Vector2(34.0, 40.0)), moss.darkened(0.3))
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[
					hip + Vector2(-30, 30),
					hip + Vector2(40, 34),
					hip + Vector2(46, 50),
					hip + Vector2(-34, 50)
				]
			),
			BARK
		)
	# Body: a wide low oval with a moss back ridge.
	canvas.draw_colored_polygon(oval(Vector2(0.0, -10.0), Vector2(104.0, 64.0)), moss)
	canvas.draw_colored_polygon(oval(Vector2(-6.0, 6.0), Vector2(90.0, 40.0)), moss.darkened(0.22))
	for index in 7:
		var x := -84.0 + 28.0 * float(index)
		var h := 22.0 + 10.0 * sin(float(index) * 2.3)
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[Vector2(x - 10, -56), Vector2(x + 2, -56 - h), Vector2(x + 12, -54)]
			),
			FROND.darkened(0.3)
		)
	if armored:
		# Stage 2 bark plates close over the back while the body is protected.
		for index in 3:
			var x := -50.0 + 50.0 * float(index)
			canvas.draw_line(Vector2(x, -66), Vector2(x + 14, -14), BARK.lightened(0.1), 7.0)
	# Mouth: a ring of fern fronds that lifts and flares before each attack.
	var mouth := Vector2(84.0, -6.0)
	canvas.draw_colored_polygon(oval(mouth, Vector2(26.0, 34.0)), MOSS_DARK)
	var glow := Color(accent, 0.25 + 0.5 * p) if exposed or telegraphing else Color(accent, 0.12)
	canvas.draw_colored_polygon(oval(mouth + Vector2(-3.0, 2.0), Vector2(15.0, 22.0)), glow)
	var flare := 0.35 + 1.0 * p
	for index in 9:
		var t := float(index) / 8.0
		var angle := lerpf(-PI * 0.42, PI * 0.42, t) - 0.12 * flare
		var length := 52.0 + 26.0 * flare + 6.0 * sin(age * 3.0 + float(index))
		var start := mouth + Vector2(cos(angle), sin(angle)) * 26.0
		var bend := Vector2(cos(angle - 0.35 * flare), sin(angle - 0.35 * flare)) * length * 0.6
		var tip := start + bend + Vector2(0.0, -14.0 * flare)
		canvas.draw_line(start, tip, FROND.lerp(Color.WHITE, flash * 0.5), 6.0, true)
		canvas.draw_line(start, tip, FROND.lightened(0.25), 2.0, true)
	# Eyes.
	canvas.draw_circle(Vector2(54.0, -36.0), 6.0, Color(1.0, 0.82, 0.3))
	canvas.draw_circle(Vector2(26.0, -42.0), 5.0, Color(1.0, 0.82, 0.3))
	canvas.draw_set_transform(Vector2.ZERO)
