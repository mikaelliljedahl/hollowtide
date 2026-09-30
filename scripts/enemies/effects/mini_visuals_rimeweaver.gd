extends RefCounted
## Rimeweaver body (docs/features/mini-bosses.md 3.3): a thin cross of icicle-tipped limestone legs
## around a small cold body. Legs fold before a skitter, the crown of needles lifts before a needle
## line, the legs spread before a drop and the body swells before a ring. Pure visuals, no text.

const Telegraphs = preload("res://scripts/enemies/effects/boss_telegraphs.gd")
const STONE := Color(0.78, 0.82, 0.86)
const ICE := Color(0.74, 0.93, 1.0)


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
	var stone := STONE.darkened(0.25) if armored else STONE
	stone = stone.lerp(Color.WHITE, flash * 0.7)
	var dark := stone.darkened(0.32)
	var fold := 0.0
	var spread := 0.0
	var swell := 1.0
	var crown := 0.0
	if telegraphing:
		match attack:
			&"wall_skitter":
				fold = p
			&"icicle_drop":
				spread = p
			&"frost_ring":
				swell = 1.0 + 0.16 * p
			_:
				crown = p
	var running: bool = state == &"active" and attack == &"wall_skitter"
	var sway := sin(age * (16.0 if running else 2.4))
	canvas.draw_set_transform(Vector2(0.0, 6.0), 0.0, Vector2(facing, 1.0))
	# Eight jointed legs, four each side, reaching out and down to icicle tips.
	for side in [-1.0, 1.0]:
		for index in 4:
			var t := float(index) / 3.0
			var reach := 120.0 - 48.0 * fold + 18.0 * spread
			var wobble := 6.0 * sway * (1.0 if index % 2 == 0 else -1.0)
			var hip := Vector2(side * 14.0, -6.0 + 10.0 * t)
			var knee := hip + Vector2(side * reach * 0.55, -70.0 + 34.0 * t - 22.0 * spread)
			var foot := Vector2(hip.x + side * reach, minf(40.0 + 50.0 * t + wobble, 82.0))
			var line := PackedVector2Array([hip, knee, foot])
			canvas.draw_polyline(line, dark, 9.0, true)
			canvas.draw_polyline(line, stone, 4.0, true)
			var along := (foot - knee).normalized()
			canvas.draw_colored_polygon(
				PackedVector2Array(
					[foot + along.orthogonal() * 6.0, foot + along * 26.0, foot - along.orthogonal() * 6.0]
				),
				ICE
			)
	# Small cold body with a pale abdomen and a crown of needles.
	canvas.draw_colored_polygon(oval(Vector2(-10.0, 4.0), Vector2(30.0, 34.0) * swell), dark)
	canvas.draw_colored_polygon(oval(Vector2(0.0, -8.0), Vector2(26.0, 28.0) * swell), stone)
	for index in 5:
		var angle := -PI * 0.5 + (float(index) - 2.0) * 0.32
		var direction := Vector2(cos(angle), sin(angle))
		var base := Vector2(0.0, -28.0) + direction * 6.0
		canvas.draw_line(base, base + direction * (30.0 + 18.0 * crown + 8.0 * p), ICE, 4.0, true)
	# Eyes: cold points, bright while a window or a wind-up shows.
	var glow := Color(accent, 0.3 + 0.6 * p) if exposed or telegraphing else Color(accent, 0.15)
	for index in 3:
		canvas.draw_circle(
			Vector2(8.0 + 8.0 * float(index), -12.0 - 3.0 * float(index % 2)), 4.0, glow
		)
	canvas.draw_set_transform(Vector2.ZERO)


static func oval(center: Vector2, radii: Vector2, steps := 20) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in steps:
		var angle := TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
