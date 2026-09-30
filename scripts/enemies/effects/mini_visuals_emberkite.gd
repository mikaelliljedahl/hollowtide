extends RefCounted
## Emberkite body (docs/features/mini-bosses.md 3.4): a sharp swept triangle with a hooked beak, a
## glowing keel and a streaming ember tail. Code-drawn on the CombatBoss node (origin = body centre).
## Pure presentation: nothing here changes damage rules or timings.

const Telegraphs = preload("res://scripts/enemies/effects/boss_telegraphs.gd")
const BASALT := Color(0.16, 0.12, 0.12)
const BASALT_LIGHT := Color(0.3, 0.2, 0.17)
const EMBER := Color(1.0, 0.5, 0.14)


static func draw_body(boss: Node2D, canvas: CanvasItem) -> void:
	var age: float = boss.get("_age")
	var facing: float = boss.get("_facing")
	var accent: Color = boss.call("_boss_accent_color")
	var telegraphing: bool = float(boss.get("_telegraph_remaining")) > 0.0
	var p := Telegraphs.progress(boss) if telegraphing else 0.0
	var attack: StringName = boss.get("_attack_id")
	var exposed: bool = boss.call("weak_point_exposed")
	var armored: bool = int(boss.get("phase")) == 2 and not exposed
	var flash := clampf(float(boss.get("_hit_flash_remaining")) / 0.14, 0.0, 1.0)
	var hull := BASALT.lightened(0.08) if armored else BASALT
	hull = hull.lerp(Color.WHITE, flash * 0.7)
	# Bank back before a dive, pulse before a fan, swell the keel before rain and vents.
	var bob := 6.0 * sin(age * 3.0)
	var tilt := 0.0
	if telegraphing and attack == &"flare_dive":
		tilt = -0.45 * p
	canvas.draw_set_transform(Vector2(0.0, bob), tilt * facing, Vector2(facing, 1.0))
	# Ember tail streaming behind: three flickering plumes.
	for index in 3:
		var y := -10.0 + 22.0 * float(index)
		var length := 90.0 + 26.0 * sin(age * 7.0 + float(index) * 1.7) + 30.0 * p
		var plume := PackedVector2Array(
			[Vector2(-50.0, y - 7.0), Vector2(-50.0 - length, y + 6.0), Vector2(-50.0, y + 9.0)]
		)
		canvas.draw_colored_polygon(plume, Color(EMBER, 0.55))
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[Vector2(-50.0, y - 3.0), Vector2(-50.0 - length * 0.55, y + 4.0), Vector2(-50.0, y + 5.0)]
			),
			Color(1.0, 0.86, 0.4, 0.8)
		)
	# Swept wings: two hard triangles, the far one darker.
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(10, -6), Vector2(-62, -96), Vector2(-40, -4)]),
		hull.darkened(0.3)
	)
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(20, 4), Vector2(-74, 92), Vector2(-46, 10)]), hull
	)
	# Body: a swept triangle pointing forward, hooked beak at the tip.
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(96, 4), Vector2(-50, -34), Vector2(-58, 26)]), hull
	)
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(86, 6), Vector2(-30, -8), Vector2(-40, 20)]),
		BASALT_LIGHT.lerp(Color.WHITE, flash * 0.5)
	)
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(96, 4), Vector2(118, 26), Vector2(78, 18)]), Color(0.75, 0.55, 0.3)
	)
	# Glowing keel along the belly: dim while armoured, hot while telegraphing or open.
	var heat := 0.3 + 0.7 * p if telegraphing else (0.85 if exposed else 0.25)
	canvas.draw_line(Vector2(70, 14), Vector2(-46, 22), Color(EMBER, heat), 8.0, true)
	canvas.draw_line(Vector2(60, 14), Vector2(-30, 21), Color(accent, heat), 3.0, true)
	if armored:
		for index in 3:
			var x := -30.0 + 34.0 * float(index)
			canvas.draw_line(Vector2(x, -22), Vector2(x - 10, 8), BASALT_LIGHT, 6.0)
	# Eye.
	canvas.draw_circle(Vector2(52.0, -6.0), 7.0, Color(1.0, 0.9, 0.4))
	canvas.draw_circle(Vector2(54.0, -6.0), 3.0, Color(0.1, 0.05, 0.05))
	canvas.draw_set_transform(Vector2.ZERO)
