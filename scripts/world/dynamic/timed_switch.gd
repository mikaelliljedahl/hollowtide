class_name TimedSwitch
extends StaticBody2D
## A wall-mounted crystal eye. Any shot opens its linked TimedDoor for a few seconds.
## It sits on the enemy/projectile layer so shots hit it but the player walks past it.

signal triggered

const HitResult = preload("res://scripts/combat/hit_result.gd")
const RADIUS := 22.0

var active := false
var latched := false
var area_id: StringName = &"fringe"
var _flash := 0.0
var _age := 0.0


func _ready() -> void:
	add_to_group(&"worldfx_switch")
	WorldFx.warm("switches", area_id)
	collision_layer = 8
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS + 6.0
	shape.shape = circle
	add_child(shape)


func receive_hit(_amount: int, _kind: StringName, _context := {}) -> HitResult.Reaction:
	_flash = 0.35
	triggered.emit()
	return HitResult.Reaction.TRIGGERED


func take_damage(amount: int, kind: StringName) -> void:
	receive_hit(amount, kind)


func is_vulnerable_to(_kind: StringName) -> bool:
	return not latched


func allows_projectile(_kind: StringName) -> bool:
	return false


func _process(delta: float) -> void:
	_age += delta
	_flash = maxf(_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var accent: Color = WorldFx.palette(area_id)["accent"]
	var art := WorldFx.sheet_region("switches", area_id)
	if not art.is_empty() and art["texture"] != null:
		var pulse_art := 0.5 + 0.5 * sin(_age * 3.2)
		var halo := accent
		halo.a = (0.5 if active or latched else 0.12 + 0.12 * pulse_art) + _flash
		draw_circle(Vector2.ZERO, RADIUS + 18.0, halo * Color(1, 1, 1, 0.6))
		var size := Vector2(RADIUS, RADIUS) * 3.4
		var tint := Color(1.35, 1.35, 1.35) if active or _flash > 0.0 else Color.WHITE
		if latched:
			tint = Color(0.75, 0.75, 0.75)
		draw_texture_rect_region(art["texture"], Rect2(-size * 0.5, size), art["region"], tint)
		return
	# Stone socket.
	draw_circle(Vector2.ZERO, RADIUS + 12.0, Color(0.07, 0.07, 0.08))
	draw_arc(Vector2.ZERO, RADIUS + 12.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 3.0)
	for index in 4:
		var angle := TAU * index / 4.0 + PI * 0.25
		draw_circle(Vector2.from_angle(angle) * (RADIUS + 9.0), 3.5, Color(0.2, 0.2, 0.22))
	var glow := accent
	var pulse := 0.5 + 0.5 * sin(_age * 3.2)
	var strength := 0.45 + 0.25 * pulse
	if active or latched:
		strength = 1.0
	strength = minf(strength + _flash * 2.0, 1.4)
	glow.a = 0.35 * strength
	draw_circle(Vector2.ZERO, RADIUS + 8.0, glow)
	var core := accent.darkened(0.55).lerp(accent.lightened(0.3), clampf(strength, 0.0, 1.0))
	draw_circle(Vector2.ZERO, RADIUS, core)
	# Iris: a vertical slit that opens while the door is held.
	var slit := 5.0 if not active else 12.0
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0, -RADIUS * 0.8),
				Vector2(slit, 0),
				Vector2(0, RADIUS * 0.8),
				Vector2(-slit, 0)
			]
		),
		Color(0.02, 0.02, 0.03, 0.9)
	)
	draw_circle(Vector2(-7, -8), 4.0, Color(1, 1, 1, 0.55))
