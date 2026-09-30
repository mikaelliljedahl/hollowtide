extends RefCounted
## Lanternjaw's code-drawn body (docs/features/mini-bosses.md 3.5): a long tapered deepwater
## predator with a hinged jaw and one violet lure, the brightest thing in the room. Faces
## `_facing`; the jaw gapes during Bite Lunge and Undertow Pull, the lure swells during Lure Pulse
## and Dark Lance. Pure presentation; no text, and every tone stays mid-range (no dark zones).

const Telegraphs = preload("res://scripts/enemies/effects/boss_telegraphs.gd")
const SKIN := Color(0.3, 0.42, 0.6)
const SKIN_LIGHT := Color(0.46, 0.6, 0.78)
const BELLY := Color(0.55, 0.66, 0.78)
const FIN := Color(0.38, 0.32, 0.6)
const TOOTH := Color(0.92, 0.94, 0.88)
const MOUTH := Color(0.4, 0.22, 0.5)


static func draw_body(boss: Node2D, canvas: CanvasItem) -> void:
	var age: float = boss.get("_age")
	var facing: float = boss.get("_facing")
	var accent: Color = boss.call("_boss_accent_color")
	var telegraphing: bool = float(boss.get("_telegraph_remaining")) > 0.0
	var p := Telegraphs.progress(boss) if telegraphing else 0.0
	var attack: StringName = boss.get("_attack_id")
	var active: bool = boss.get("_attack_state") == &"active"
	var exposed: bool = boss.call("weak_point_exposed")
	var armored: bool = int(boss.get("phase")) == 2 and not exposed
	var flash := clampf(float(boss.get("_hit_flash_remaining")) / 0.14, 0.0, 1.0)
	var skin := SKIN.darkened(0.12) if armored else SKIN
	skin = skin.lerp(Color.WHITE, flash * 0.7)
	var jaw_attack := attack == &"bite_lunge" or attack == &"undertow_pull"
	var gape := 0.1 + 0.04 * sin(age * 2.0)
	if telegraphing and jaw_attack:
		gape = 0.1 + 0.5 * p
	elif active and jaw_attack:
		gape = 0.6
	var swell := 1.0 + 0.05 * sin(age * 3.0)
	if telegraphing and (attack == &"lure_pulse" or attack == &"dark_lance"):
		swell = 1.0 + 0.9 * p
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))
	# Tail and fins sway behind.
	var sway := sin(age * 2.4) * 14.0
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-70, -6),
				Vector2(-150, -44 + sway),
				Vector2(-176, -62 + sway),
				Vector2(-168, -2 + sway),
				Vector2(-176, 58 + sway),
				Vector2(-150, 40 + sway),
				Vector2(-70, 12)
			]
		),
		FIN
	)
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(-30, -52), Vector2(-66, -96), Vector2(10, -56)]), FIN
	)
	canvas.draw_colored_polygon(
		PackedVector2Array([Vector2(-20, 50), Vector2(-50, 88), Vector2(20, 52)]), FIN
	)
	# Long tapered body with a pale belly.
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-90, -8),
				Vector2(-40, -58),
				Vector2(30, -66),
				Vector2(86, -40),
				Vector2(92, 6),
				Vector2(80, 44),
				Vector2(20, 62),
				Vector2(-50, 40)
			]
		),
		skin
	)
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-70, 8),
				Vector2(0, 26),
				Vector2(60, 30),
				Vector2(70, 46),
				Vector2(10, 58),
				Vector2(-46, 38)
			]
		),
		BELLY.lerp(skin, 0.3)
	)
	for index in 5:
		var x := -50.0 + 28.0 * float(index)
		canvas.draw_arc(Vector2(x, -4.0), 22.0, PI * 1.15, PI * 1.85, 8, SKIN_LIGHT, 3.0, true)
	if armored:
		for index in 3:
			var x := -50.0 + 40.0 * float(index)
			canvas.draw_line(Vector2(x, -58), Vector2(x + 10, 0), SKIN_LIGHT, 7.0)
	# Hinged jaw: the mouth cavity is fixed, the lower jaw swings open around the hinge.
	var hinge := Vector2(40.0, 14.0)
	canvas.draw_colored_polygon(
		PackedVector2Array(
			[
				hinge + Vector2(0, -8),
				hinge + Vector2(80, -2),
				hinge + Vector2(84, 22),
				hinge + Vector2(0, 24)
			]
		),
		MOUTH.lerp(accent, 0.15 + 0.4 * p)
	)
	var lower := PackedVector2Array()
	for point in [Vector2(0, 0), Vector2(84, 0), Vector2(92, 18), Vector2(70, 34), Vector2(0, 30)]:
		lower.append(hinge + (point as Vector2).rotated(gape))
	canvas.draw_colored_polygon(lower, skin.lightened(0.05))
	for index in 4:
		var t := 14.0 + 16.0 * float(index)
		var top := hinge + Vector2(t, -2.0)
		canvas.draw_colored_polygon(
			PackedVector2Array([top + Vector2(-5, 0), top + Vector2(0, 14), top + Vector2(5, 0)]),
			TOOTH
		)
		var bottom := hinge + Vector2(t, 4.0).rotated(gape)
		canvas.draw_colored_polygon(
			PackedVector2Array(
				[bottom + Vector2(-5, 0), bottom + Vector2(0, -14), bottom + Vector2(5, 0)]
			),
			TOOTH
		)
	# Blind, milky eye.
	canvas.draw_circle(Vector2(30.0, -24.0), 8.0, Color(0.85, 0.88, 0.92, 0.85))
	canvas.draw_circle(Vector2(30.0, -24.0), 3.0, Color(0.5, 0.56, 0.66))
	# The lure: a stalk arching over the jaw, the brightest thing drawn.
	var tip := Vector2(120.0, -96.0 + sin(age * 2.6) * 6.0)
	var stalk := PackedVector2Array()
	for step in 9:
		var t := float(step) / 8.0
		stalk.append(
			Vector2(lerpf(30.0, tip.x, t), lerpf(-58.0, tip.y, t) - 40.0 * sin(t * PI))
		)
	canvas.draw_polyline(stalk, SKIN_LIGHT, 5.0, true)
	var radius := 16.0 * swell
	canvas.draw_circle(tip, radius * 2.4, Color(accent, 0.12 + 0.12 * p))
	canvas.draw_circle(tip, radius * 1.5, Color(accent, 0.3 + 0.2 * p))
	canvas.draw_circle(tip, radius, accent.lightened(0.35 + 0.3 * p))
	canvas.draw_circle(tip, radius * 0.45, Color(1.0, 0.96, 1.0))
	canvas.draw_set_transform(Vector2.ZERO)
