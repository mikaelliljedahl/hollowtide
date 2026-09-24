class_name DashFx
extends Node2D
## Undertow Dash (D19) visuals: teal after-images of the player plus a curling current streak, and
## the ripple that turns a deflected shot.
## Self-cleaning and in group `transient`.

const TINT := Color(0.4, 1.0, 0.92, 0.6)
const CURRENT := Color(0.45, 0.95, 1.0, 0.8)

var lifetime := 0.2
var _age := 0.0
var _direction := 1
var _kind: StringName = &"ghost"
var _scale := 1.0


func _ready() -> void:
	add_to_group(&"transient")


func _process(delta: float) -> void:
	_age += delta
	var fade := clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _kind == &"ghost":
		modulate.a = fade
	queue_redraw()
	if _age >= lifetime:
		queue_free()


func _draw() -> void:
	if _kind == &"turn":
		_draw_turn()
		return
	if _kind != &"burst":
		return
	var progress := clampf(_age / lifetime, 0.0, 1.0)
	var alpha := 1.0 - progress
	var s := float(_direction)
	# Tapered current streaks trailing the launch point, like water pulled along the body.
	for index in 5:
		var y := -158.0 + float(index) * 34.0 + 6.0 * sin(float(index) * 1.9)
		var length := (
			lerpf(60.0, 230.0, ease(progress, 0.35)) * (1.0 - absf(float(index) - 2.0) * 0.14)
		)
		var thickness := 7.0 - absf(float(index) - 2.0) * 1.6
		var head := Vector2(-s * 8.0, y)
		var tail := Vector2(-s * length, y + 6.0)
		var normal := Vector2(0.0, thickness * 0.5)
		draw_colored_polygon(
			PackedVector2Array([head - normal, head + normal, tail]), Color(CURRENT, alpha * 0.55)
		)
		draw_line(head, tail.lerp(head, 0.35), Color(0.9, 1.0, 1.0, alpha * 0.7), 1.5, true)
	for index in 7:
		var droplet := Vector2(-s * (24.0 + progress * 140.0 + index * 16.0), -30.0 - index * 20.0)
		droplet.y += 110.0 * progress * progress
		draw_circle(droplet, 3.2 * alpha + 1.0, Color(0.85, 1.0, 1.0, alpha))


static func spawn_afterimage(player: Node2D, sprite: AnimatedSprite2D) -> void:
	if sprite == null or sprite.sprite_frames == null or player.get_parent() == null:
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return
	var ghost := DashFx.new()
	ghost._kind = &"ghost"
	ghost.lifetime = 0.18
	var image := Sprite2D.new()
	image.texture = texture
	image.flip_h = sprite.flip_h
	image.modulate = TINT
	ghost.add_child(image)
	ghost.z_index = -1
	player.get_parent().add_child(ghost)
	ghost.global_transform = sprite.global_transform


static func spawn_burst(player: Node2D, direction: int) -> void:
	if player.get_parent() == null:
		return
	var burst := DashFx.new()
	burst._kind = &"burst"
	burst._direction = direction
	burst.lifetime = 0.32
	burst.z_index = 1
	player.get_parent().add_child(burst)
	burst.global_position = player.global_position


## Deflect turn (DashDeflect): an undertow ripple ring squeezed along the new heading, a current
## curling back around the turn point, and spray thrown forward. Local +x is the new heading.
func _draw_turn() -> void:
	var progress := clampf(_age / lifetime, 0.0, 1.0)
	var alpha := 1.0 - progress
	var size := _scale
	for index in 2:
		var local := clampf(progress * 1.25 - float(index) * 0.22, 0.0, 1.0)
		if local <= 0.0:
			continue
		var radius := lerpf(12.0, 74.0, ease(local, 0.35)) * size
		var ring := PackedVector2Array()
		for step in 33:
			var angle := TAU * float(step) / 32.0
			ring.append(Vector2(cos(angle) * radius * 0.55, sin(angle) * radius))
		var fade := (1.0 - local) * (1.0 if index == 0 else 0.6)
		draw_polyline(ring, Color(CURRENT, fade * 0.35), 7.0 * size, true)
		draw_polyline(ring, Color(CURRENT, fade), 2.5 * size, true)
	var sweep := lerpf(0.4, PI, ease(progress * 1.6, 0.4))
	var curl_radius := 26.0 * size
	var curl_start := PI * 0.5
	draw_arc(
		Vector2.ZERO, curl_radius, curl_start, curl_start + sweep, 20, Color(TINT, alpha), 4.0, true
	)
	draw_arc(
		Vector2.ZERO,
		curl_radius * 0.7,
		curl_start,
		curl_start + sweep,
		20,
		Color(0.9, 1.0, 1.0, alpha * 0.8),
		1.5,
		true
	)
	for index in 6:
		var spread := (float(index) - 2.5) * 0.22
		var travel := (18.0 + progress * 120.0 + float(index % 3) * 10.0) * size
		var droplet := Vector2.RIGHT.rotated(spread) * travel
		draw_circle(droplet, (3.0 * alpha + 1.0) * size, Color(0.85, 1.0, 1.0, alpha))


static func spawn_turn(parent: Node, position: Vector2, heading: Vector2, size := 1.0) -> void:
	if not is_instance_valid(parent):
		return
	var turn := DashFx.new()
	turn._kind = &"turn"
	turn._scale = size
	turn.lifetime = 0.34
	turn.z_index = 3
	parent.add_child(turn)
	turn.global_position = position
	turn.rotation = heading.angle()
