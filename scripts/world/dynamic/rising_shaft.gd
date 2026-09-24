class_name RisingShaft
extends Node2D
## Entering this vertical shaft starts a lava or water flood that rises at a steady, readable pace
## (slower than climbing). Touching it hurts and throws the player up toward open air - never an
## instant kill. It stops at a safe line below the top, and drains back and re-arms when the player
## leaves the shaft or dies. Position is the top-left of the shaft's air column.

signal started
signal reset_done

enum State { ARMED, WARNING, RISING, STOPPED, DRAINING }

const WARNING_SECONDS := 0.9
const DRAIN_SPEED := 700.0
const BOOST_SPEED := 1500.0
const SUBMERGE_MARGIN := 10.0
const SIDE_BLEED := 0.0
const SURFACE_BAND := 36.0

@export var shaft_size := Vector2(512, 1536)
## Height of the resting pool at the bottom of the shaft.
@export var rest_depth := 64.0
## Distance below the shaft top where the flood stops.
@export var safe_line := 320.0
@export var speed := 110.0
@export var damage := 20
@export var kind: StringName = &"lava"
@export var area_override: StringName = &""

var state := State.ARMED
var surface_y := 0.0
var _timer := 0.0
var _area: StringName = &"fringe"
var _front: Node2D
var _particles: CPUParticles2D
var _loop: AudioStreamPlayer2D
var _time := 0.0


func _ready() -> void:
	add_to_group(&"worldfx_rising_shaft")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = -7
	_area = WorldFx.area_for(self, area_override)
	WorldFx.warm("", _area)
	WorldFx.warm("", &"kiln" if kind == &"lava" else &"depths")
	surface_y = rest_y()
	_front = Node2D.new()
	_front.z_index = 3
	_front.z_as_relative = false
	_front.draw.connect(_draw_front)
	add_child(_front)
	_particles = CPUParticles2D.new()
	_particles.z_index = 4
	_particles.z_as_relative = false
	_particles.amount = int(clampf(shaft_size.x / 10.0, 16, 80))
	_particles.lifetime = 1.4
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(shaft_size.x * 0.5, 6)
	_particles.direction = Vector2.UP
	_particles.spread = 20.0
	_particles.initial_velocity_min = 30.0
	_particles.initial_velocity_max = 120.0
	_particles.scale_amount_min = 2.0
	_particles.scale_amount_max = 5.0
	if kind == &"lava":
		_particles.gravity = Vector2(0, -40)
		_particles.color = Color(1.0, 0.55, 0.18, 0.85)
	else:
		_particles.gravity = Vector2(0, -20)
		_particles.texture = WorldFx.puff_texture(16, true)
		_particles.color = Color(0.8, 0.95, 1.0, 0.6)
		_particles.scale_amount_min = 0.4
		_particles.scale_amount_max = 1.1
	add_child(_particles)
	_loop = AudioStreamPlayer2D.new()
	_loop.bus = &"SFX"
	_loop.volume_db = -10.0
	_loop.max_distance = shaft_size.y + 1200.0
	var loop_path := WorldFx.SFX_DIR + ("lava_loop" if kind == &"lava" else "water_loop") + ".wav"
	if ResourceLoader.exists(loop_path):
		_loop.stream = load(loop_path) as AudioStream
	_loop.tree_exiting.connect(_loop.stop)
	add_child(_loop)
	if not GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.connect(_on_player_died)
	_sync_visuals()


func _exit_tree() -> void:
	if GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.disconnect(_on_player_died)


func rest_y() -> float:
	return shaft_size.y - rest_depth


func stop_y() -> float:
	return safe_line


func surface_global_y() -> float:
	return global_position.y + surface_y


func shaft_rect_global() -> Rect2:
	return Rect2(global_position, shaft_size)


func _physics_process(delta: float) -> void:
	_time += delta
	var player := WorldFx.player_of(self)
	var inside := player != null and _player_inside(player)
	match state:
		State.ARMED:
			if (
				inside
				and GameState.health > 0
				and player.global_position.y < surface_global_y() - 8.0
			):
				state = State.WARNING
				_timer = WARNING_SECONDS
				WorldFx.play(
					self,
					&"world_rumble",
					global_position + Vector2(shaft_size.x * 0.5, surface_y),
					0.0,
					0.8
				)
				WorldFx.shake(self, 4.0, 0.5)
				started.emit()
		State.WARNING:
			_timer -= delta
			if not inside:
				_drain()
			elif _timer <= 0.0:
				state = State.RISING
				if _loop.stream != null:
					_loop.play()
		State.RISING, State.STOPPED:
			if not inside:
				_drain()
			else:
				surface_y = maxf(surface_y - speed * delta, stop_y())
				if surface_y <= stop_y():
					state = State.STOPPED
		State.DRAINING:
			surface_y = minf(surface_y + DRAIN_SPEED * delta, rest_y())
			if surface_y >= rest_y():
				state = State.ARMED
				_loop.stop()
				reset_done.emit()
	if player != null and GameState.health > 0:
		_touch(player)
	_sync_visuals()


func _player_inside(player: Node2D) -> bool:
	return shaft_rect_global().grow(8.0).has_point(player.global_position + Vector2(0, -40))


func _touch(player: Node2D) -> void:
	var feet := player.global_position
	var liquid := Rect2(
		Vector2(global_position.x - SIDE_BLEED, surface_global_y() + SUBMERGE_MARGIN),
		Vector2(shaft_size.x + SIDE_BLEED * 2.0, shaft_size.y)
	)
	if not liquid.has_point(feet):
		return
	if kind != &"lava" and state == State.ARMED:
		return  # A calm resting pool of water is harmless; only the surge hurts.
	if player.has_method("take_damage"):
		player.call("take_damage", damage, Vector2(feet.x, feet.y + 200.0))
	var depth := feet.y - surface_global_y()
	var gravity := PlayerConfig.GRAVITY_RISING
	var headroom := _headroom(player, depth + BOOST_SPEED * BOOST_SPEED / (2.0 * gravity))
	# Rock between her and the surface would pin her against it until she dies: no throw until
	# she moves out from under it. Otherwise the throw carries her no higher than the rock above.
	if headroom < depth:
		return
	var velocity: Vector2 = player.get("velocity")
	velocity.y = -minf(BOOST_SPEED, sqrt(2.0 * gravity * headroom))
	player.set("velocity", velocity)


## How far the player's body can rise before terrain stops it, at most `reach`.
func _headroom(player: Node2D, reach: float) -> float:
	# Inset so walls beside her and the floor under her feet do not count as contact.
	var body := WorldFx.player_rect(player).grow_individual(-4.0, 0.0, -4.0, -8.0)
	var shape := RectangleShape2D.new()
	shape.size = body.size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, body.get_center())
	query.motion = Vector2(0.0, -reach)
	query.collision_mask = player.get("collision_mask")
	query.exclude = [(player as CollisionObject2D).get_rid()]
	var fractions := get_world_2d().direct_space_state.cast_motion(query)
	return reach * fractions[0]


func _drain() -> void:
	if state == State.DRAINING or state == State.ARMED:
		return
	state = State.DRAINING


func _on_player_died() -> void:
	if state != State.ARMED:
		state = State.DRAINING
		surface_y = rest_y()


func _sync_visuals() -> void:
	_particles.position = Vector2(shaft_size.x * 0.5, surface_y - 4.0)
	_particles.emitting = state != State.ARMED or kind == &"lava"
	_loop.position = Vector2(shaft_size.x * 0.5, surface_y)
	queue_redraw()
	_front.queue_redraw()


func _liquid_colors() -> Array[Color]:
	# [just below the surface strip, deep, surface highlight]
	if kind == &"lava":
		return [Color(0.33, 0.02, 0.0), Color(0.14, 0.01, 0.0), Color(1.0, 0.8, 0.35)]
	var accent: Color = WorldFx.palette(_area)["accent"]
	var deep := Color(0.01, 0.02, 0.06).lerp(accent.darkened(0.9), 0.2)
	return [Color(0.0, 0.02, 0.1).lerp(accent.darkened(0.7), 0.1), deep, Color(0.75, 0.95, 1.0)]


func _draw() -> void:
	var colors := _liquid_colors()
	var left := -SIDE_BLEED
	var width := shaft_size.x + SIDE_BLEED * 2.0
	var top := surface_y
	var bottom := shaft_size.y + 32.0
	var body_top := minf(top + 110.0, bottom - 1.0)
	if bottom <= top:
		return
	# Body: vertical gradient from the lit surface colour to the deep colour.
	var body := PackedVector2Array(
		[
			Vector2(left, body_top),
			Vector2(left + width, body_top),
			Vector2(left + width, bottom),
			Vector2(left, bottom)
		]
	)
	var surface: Color = colors[0]
	var deep: Color = colors[1]
	var fade := clampf((bottom - top) / 500.0, 0.0, 1.0)
	var lower := surface.lerp(deep, fade)
	draw_polygon(body, PackedColorArray([surface, surface, lower, lower]))
	if kind == &"lava":
		# Slow glowing veins drifting in the molten body.
		for index in 5:
			var vx := left + width * (0.15 + 0.18 * index)
			var vy := top + 60.0 + fmod(_time * 12.0 + index * 97.0, maxf(bottom - top - 60.0, 1.0))
			draw_circle(
				Vector2(vx, vy), 10.0 + 4.0 * sin(_time + index), Color(1.0, 0.45, 0.1, 0.18)
			)
	# Surface texture strip from the area kit's fluid art, scrolled sideways.
	var texture := WorldFx.kit(&"kiln" if kind == &"lava" else &"depths").texture(&"fluid")
	if texture != null:
		var strip_height := float(texture.get_height())
		var scroll := fmod(_time * (40.0 if kind == &"lava" else 24.0), float(texture.get_width()))
		var modulate_color := Color.WHITE
		draw_texture_rect_region(
			texture,
			Rect2(Vector2(left, top - 36.0), Vector2(width, strip_height)),
			Rect2(Vector2(scroll, 0.0), Vector2(width, strip_height)),
			modulate_color
		)


func _draw_front() -> void:
	# Translucent band in front of actors so a touching player reads as submerged.
	var colors := _liquid_colors()
	var left := 0.0
	var width := shaft_size.x
	var band: Color = colors[0]
	band.a = 0.55
	var edge: Color = colors[2]
	var wave := PackedVector2Array()
	var steps := int(width / 32.0) + 1
	for index in steps + 1:
		var x := left + width * float(index) / float(steps)
		var y := surface_y + 6.0 + sin(_time * 2.4 + x * 0.03) * 4.0
		wave.append(Vector2(x, y))
	var polygon := wave.duplicate()
	polygon.append(Vector2(left + width, surface_y + SURFACE_BAND + 40.0))
	polygon.append(Vector2(left, surface_y + SURFACE_BAND + 40.0))
	var colors_array := PackedColorArray()
	for _point in wave:
		colors_array.append(band)
	var clear := band
	clear.a = 0.0
	colors_array.append(clear)
	colors_array.append(clear)
	_front.draw_polygon(polygon, colors_array)
	edge.a = 0.8
	_front.draw_polyline(wave, edge, 3.0)
