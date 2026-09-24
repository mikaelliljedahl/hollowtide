class_name PushCurrent
extends Area2D
## A zone of flowing water, wind or rising steam that pushes the player (and optionally
## projectiles). Horizontal push displaces the body directly so it works with the player's own
## acceleration; vertical push adjusts velocity so updrafts can carry her upward.
## Visible streaks always show direction and strength. Position is the zone centre.

const KINDS := [&"water", &"wind", &"steam"]
const UPDRAFT_ACCEL := 5200.0

@export var zone_size := Vector2(512, 256)
## Unit direction of the flow.
@export var direction := Vector2.RIGHT
## Push speed in px/s (horizontal drift) or peak updraft speed (vertical).
@export var strength := 260.0
@export var kind: StringName = &"water"
@export var affect_projectiles := true
@export var area_override: StringName = &""

var _player: Node2D
var _area: StringName = &"fringe"
var _streaks: CPUParticles2D
var _audio: AudioStreamPlayer2D


func _ready() -> void:
	add_to_group(&"worldfx_current")
	collision_layer = 0
	collision_mask = WorldFx.PLAYER_LAYER | 16
	monitoring = true
	monitorable = false
	direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	_area = WorldFx.area_for(self, area_override)
	WorldFx.warm("", _area)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = zone_size
	shape.shape = rectangle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_particles()
	_build_audio()


## Velocity-equivalent push applied to a body inside the zone this frame.
func push_vector() -> Vector2:
	return direction * strength


func player_inside() -> bool:
	return is_instance_valid(_player)


func _physics_process(delta: float) -> void:
	if is_instance_valid(_player) and GameState.health > 0:
		_push_player(delta)
	if affect_projectiles:
		for area in get_overlapping_areas():
			if area is ProjectileBase:
				area.global_position += direction * strength * 0.45 * delta


func _push_player(delta: float) -> void:
	var body := _player as CharacterBody2D
	if body == null:
		return
	var horizontal := Vector2(direction.x * strength * delta, 0.0)
	if not is_zero_approx(horizontal.x):
		body.move_and_collide(horizontal)
	if direction.y < -0.1:
		# Updraft: accelerate toward the rise speed, strongest near the bottom of the zone.
		var depth := clampf(
			(body.global_position.y - (global_position.y - zone_size.y * 0.5)) / zone_size.y,
			0.0,
			1.0
		)
		var target := direction.y * strength * lerpf(0.55, 1.0, depth)
		if body.velocity.y > target:
			body.velocity.y = maxf(
				body.velocity.y - UPDRAFT_ACCEL * delta * absf(direction.y), target
			)
	elif direction.y > 0.1:
		body.velocity.y += direction.y * strength * 2.0 * delta


func _on_body_entered(body: Node) -> void:
	if WorldFx.is_player(body):
		_player = body as Node2D


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null


func _build_particles() -> void:
	var colors := WorldFx.palette(_area)
	_streaks = CPUParticles2D.new()
	_streaks.name = "Streaks"
	_streaks.z_index = 3
	var travel_time := clampf(zone_size.dot(direction.abs()) / maxf(strength * 1.6, 1.0), 0.6, 3.5)
	_streaks.lifetime = travel_time
	_streaks.amount = int(clampf(zone_size.x * zone_size.y / 5200.0, 16, 140))
	_streaks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_streaks.emission_rect_extents = zone_size * 0.5
	_streaks.direction = direction
	_streaks.spread = 4.0
	_streaks.gravity = Vector2.ZERO
	_streaks.initial_velocity_min = strength * 1.3
	_streaks.initial_velocity_max = strength * 1.9
	_streaks.particle_flag_align_y = false
	_streaks.local_coords = false
	var tint: Color
	match kind:
		&"wind":
			_streaks.texture = WorldFx.streak_texture(72, 4)
			tint = Color(0.86, 0.9, 0.95, 0.35)
			_streaks.scale_amount_min = 0.8
			_streaks.scale_amount_max = 1.6
		&"steam":
			_streaks.texture = WorldFx.puff_texture(48)
			tint = Color(0.95, 0.92, 0.88, 0.3)
			_streaks.amount = int(clampf(zone_size.x * zone_size.y / 2600.0, 24, 160))
			_streaks.emission_rect_extents = Vector2(zone_size.x * 0.35, zone_size.y * 0.5)
			_streaks.scale_amount_min = 1.4
			_streaks.scale_amount_max = 3.6
			_streaks.spread = 8.0
			_streaks.angular_velocity_min = -30.0
			_streaks.angular_velocity_max = 30.0
		_:
			_streaks.texture = WorldFx.streak_texture(56, 5)
			var accent: Color = colors["accent"]
			tint = Color(accent.r, accent.g, accent.b, 0.42).lerp(Color(0.8, 0.95, 1.0, 0.42), 0.4)
			_streaks.scale_amount_min = 0.7
			_streaks.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(tint, 0.0), tint, tint, Color(tint, 0.0)])
	_streaks.color_ramp = fade
	# Rotate the whole emitter so streak textures lie along the flow.
	_streaks.rotation = 0.0
	_streaks.angle_min = rad_to_deg(direction.angle())
	_streaks.angle_max = rad_to_deg(direction.angle())
	add_child(_streaks)
	_streaks.preprocess = travel_time
	_streaks.emitting = true
	if kind == &"water":
		var bubbles := CPUParticles2D.new()
		bubbles.name = "Bubbles"
		bubbles.z_index = 3
		bubbles.texture = WorldFx.puff_texture(16, true)
		bubbles.amount = int(clampf(zone_size.x * zone_size.y / 20000.0, 6, 40))
		bubbles.lifetime = travel_time
		bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		bubbles.emission_rect_extents = zone_size * 0.5
		bubbles.direction = (direction + Vector2(0, -0.35)).normalized()
		bubbles.spread = 10.0
		bubbles.gravity = Vector2(0, -60)
		bubbles.initial_velocity_min = strength * 0.9
		bubbles.initial_velocity_max = strength * 1.3
		bubbles.scale_amount_min = 0.4
		bubbles.scale_amount_max = 1.0
		bubbles.color = Color(0.85, 0.95, 1.0, 0.55)
		bubbles.preprocess = travel_time
		add_child(bubbles)
	queue_redraw()


func _build_audio() -> void:
	var id := (
		{&"water": &"water_loop", &"steam": &"world_steam", &"wind": &"world_wind"}.get(
			kind, &"water_loop"
		)
		as StringName
	)
	var path := WorldFx.SFX_DIR + String(id) + ".wav"
	if not ResourceLoader.exists(path):
		return
	_audio = AudioStreamPlayer2D.new()
	_audio.stream = load(path) as AudioStream
	_audio.bus = &"SFX"
	_audio.volume_db = -14.0
	_audio.max_distance = maxf(zone_size.x, zone_size.y) + 900.0
	_audio.autoplay = true
	_audio.tree_exiting.connect(_audio.stop)
	add_child(_audio)


func _draw() -> void:
	# No box: the streaks alone show the flow. Steam gets a soft vertical haze that fades out
	# toward the column's edges so it reads as a plume, not a rectangle.
	if kind != &"steam":
		return
	var half := zone_size * 0.5
	var strips := 6
	for index in strips:
		var t := (float(index) + 0.5) / strips
		var alpha := 0.07 * (1.0 - absf(t * 2.0 - 1.0))
		var x := -half.x + zone_size.x * float(index) / strips
		draw_rect(
			Rect2(x, -half.y, zone_size.x / strips, zone_size.y), Color(1.0, 0.95, 0.9, alpha)
		)
