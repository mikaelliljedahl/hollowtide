class_name CrumbleFloor
extends Node2D
## A row of brittle floor tiles. Each tile shakes when stood on, crumbles after `delay` seconds
## and reforms after `respawn_seconds` (never while the player overlaps it). `permanent` tiles stay
## gone; only place those where losing them cannot strand the player.
## Position is the top-left corner of the first tile, in the parent's space.

enum State { SOLID, SHAKING, GONE, REFORMING }

const TILE := 64.0
const REFORM_SECONDS := 0.45
const CRACK_SEED := 7

@export var cells := 3
@export var delay := 0.6
@export var respawn_seconds := 4.0
@export var permanent := false
@export var area_override: StringName = &""

var _bodies: Array[StaticBody2D] = []
var _state: Array[int] = []
var _timer: Array[float] = []
var _area: StringName = &"fringe"


func _ready() -> void:
	add_to_group(&"worldfx_crumble")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_area = WorldFx.area_for(self, area_override)
	WorldFx.warm("", _area)
	for index in cells:
		var body := StaticBody2D.new()
		body.collision_layer = WorldFx.TERRAIN_LAYER
		body.collision_mask = 0
		body.position = Vector2(index * TILE + TILE * 0.5, TILE * 0.5)
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(TILE, TILE)
		shape.shape = rectangle
		body.add_child(shape)
		add_child(body)
		_bodies.append(body)
		_state.append(State.SOLID)
		_timer.append(0.0)


func state_of(index: int) -> int:
	return _state[index]


func is_solid(index: int) -> bool:
	return _state[index] in [State.SOLID, State.SHAKING]


func _physics_process(delta: float) -> void:
	var player := WorldFx.player_of(self)
	var standing := 0
	if player != null and player.is_on_floor():
		standing = _standing_mask(player)
	var redraw := false
	for index in cells:
		match _state[index]:
			State.SOLID:
				if standing & (1 << index):
					_state[index] = State.SHAKING
					_timer[index] = delay
					WorldFx.play(self, &"world_crack", _center(index), -4.0, randf_range(0.9, 1.1))
			State.SHAKING:
				_timer[index] -= delta
				redraw = true
				if _timer[index] <= 0.0:
					_crumble(index)
			State.GONE:
				if permanent:
					continue
				_timer[index] -= delta
				if _timer[index] <= 0.0 and not _player_overlaps(player, index):
					_state[index] = State.REFORMING
					_timer[index] = REFORM_SECONDS
					_set_solid(index, true)
					redraw = true
			State.REFORMING:
				_timer[index] -= delta
				redraw = true
				if _timer[index] <= 0.0:
					_state[index] = State.SOLID
	if redraw:
		queue_redraw()


func _standing_mask(player: Node2D) -> int:
	var feet := player.global_position
	var top := global_position.y
	if feet.y < top - 6.0 or feet.y > top + 10.0:
		return 0
	var mask := 0
	var rect := WorldFx.player_rect(player)
	for index in cells:
		var left := global_position.x + index * TILE
		var overlap := minf(rect.end.x, left + TILE) - maxf(rect.position.x, left)
		if overlap > 6.0:
			mask |= 1 << index
	return mask


func _player_overlaps(player: Node2D, index: int) -> bool:
	if player == null:
		return false
	var cell := Rect2(global_position + Vector2(index * TILE, 0), Vector2(TILE, TILE))
	return WorldFx.player_rect(player).grow(4.0).intersects(cell)


func _crumble(index: int) -> void:
	_state[index] = State.GONE
	_timer[index] = respawn_seconds
	_set_solid(index, false)
	var colors := WorldFx.palette(_area)
	var center := _center(index)
	WorldFx.dust(get_parent(), center, Vector2(26, 20), colors["dust"], 26, 120.0)
	_spawn_chunks(center)
	WorldFx.play(self, &"world_crumble", center, -2.0, randf_range(0.92, 1.08))
	queue_redraw()


func _spawn_chunks(center: Vector2) -> void:
	var chunks := CPUParticles2D.new()
	chunks.one_shot = true
	chunks.explosiveness = 0.95
	chunks.amount = 9
	chunks.lifetime = 1.1
	chunks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	chunks.emission_rect_extents = Vector2(24, 18)
	chunks.direction = Vector2.DOWN
	chunks.spread = 35.0
	chunks.initial_velocity_min = 40.0
	chunks.initial_velocity_max = 160.0
	chunks.gravity = Vector2(0, 2200)
	chunks.angular_velocity_min = -360.0
	chunks.angular_velocity_max = 360.0
	chunks.scale_amount_min = 7.0
	chunks.scale_amount_max = 14.0
	var rock: Color = WorldFx.palette(_area)["spike"]
	chunks.color = rock.lightened(0.15)
	chunks.z_index = 5
	get_parent().add_child(chunks)
	chunks.global_position = center
	chunks.emitting = true
	chunks.finished.connect(chunks.queue_free)


func _set_solid(index: int, solid: bool) -> void:
	var body := _bodies[index]
	body.collision_layer = WorldFx.TERRAIN_LAYER if solid else 0
	var shape := body.get_child(0) as CollisionShape2D
	shape.set_deferred("disabled", not solid)


func _center(index: int) -> Vector2:
	return global_position + Vector2(index * TILE + TILE * 0.5, TILE * 0.5)


func _draw() -> void:
	var colors := WorldFx.palette(_area)
	var accent: Color = colors["accent"]
	for index in cells:
		var state := _state[index]
		if state == State.GONE:
			continue
		var offset := Vector2.ZERO
		var alpha := 1.0
		if state == State.SHAKING:
			var t := 1.0 - _timer[index] / maxf(delay, 0.01)
			offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (1.5 + 3.5 * t)
		elif state == State.REFORMING:
			alpha = 1.0 - _timer[index] / REFORM_SECONDS
		var rect := Rect2(Vector2(index * TILE, 0) + offset, Vector2(TILE, TILE))
		WorldFx.draw_rock(self, rect, _area, true, 0.0, true, true)
		_draw_cracks(rect, index, accent, state == State.SHAKING)
		if alpha < 1.0:
			draw_rect(rect, Color(0.02, 0.02, 0.03, 1.0 - alpha), true)
	# Hairline gaps between tiles make the brittle row readable before it is touched.
	for index in range(1, cells):
		if is_solid(index) or is_solid(index - 1):
			var x := index * TILE
			draw_line(Vector2(x, 8), Vector2(x, TILE - 6), Color(0, 0, 0, 0.35), 1.5)


func _draw_cracks(rect: Rect2, index: int, accent: Color, shaking: bool) -> void:
	# Fine hairline fractures mark the tile as brittle; they glow while it gives way.
	var noise := RandomNumberGenerator.new()
	noise.seed = CRACK_SEED + index * 131
	var crack := Color(0.02, 0.02, 0.03, 0.75 if shaking else 0.4)
	var glow := Color(accent.r, accent.g, accent.b, 0.7)
	for _branch in 2 if shaking else 1:
		var point := rect.position + Vector2(noise.randf_range(12, 52), 6)
		var points := PackedVector2Array([point])
		for _step in 4:
			point += Vector2(noise.randf_range(-10, 10), noise.randf_range(9, 14))
			points.append(point)
		if shaking:
			draw_polyline(points, glow, 3.5)
		draw_polyline(points, crack, 1.4)
