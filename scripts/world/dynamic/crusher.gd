class_name Crusher
extends Node2D
## A stone piston that slams down on a fixed, readable rhythm: rest, telegraph (rattle, dust,
## rumble and brightening seams), slam, hold, slow rise. Being under it deals heavy damage and the
## player is ejected sideways to free space, never left inside rock. The top is standable.
## Position is the top-centre of the block at rest; the block drops until it meets the floor.

enum Phase { REST, TELEGRAPH, SLAM, HOLD, RISE }

const DURATIONS := {
	Phase.REST: 1.3,
	Phase.TELEGRAPH: 0.6,
	Phase.SLAM: 0.16,
	Phase.HOLD: 0.45,
	Phase.RISE: 1.1,
}
const PLAYER_SIZE := Vector2(56, 176)
const ENEMY_DAMAGE := 999
## Share of the crusher art taken by the piston collar above the block (assets/worldfx/crushers.png).
const ART_SHAFT_FRACTION := 0.375

@export var width := 192.0
@export var block_height := 128.0
## Pixels the block travels; 0 detects the floor below automatically.
@export var travel := 0.0
@export var damage := 35
## Seconds into the cycle at start, to stagger neighbouring crushers.
@export var phase_offset := 0.0
@export var area_override: StringName = &""

var phase := Phase.REST
var _timer := 0.0
var _offset := 0.0
var _area: StringName = &"fringe"
var _body: AnimatableBody2D
var _shake := Vector2.ZERO
var _glow := 0.0
var _rod_top := -256.0


func _ready() -> void:
	add_to_group(&"worldfx_crusher")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_area = WorldFx.area_for(self, area_override)
	# Tiled fill needs repeat; the delivered (non power-of-two) art sheet must not repeat.
	WorldFx.warm("crushers", _area)
	texture_repeat = WorldFx.repeat_mode("crushers", _area)
	_body = AnimatableBody2D.new()
	_body.sync_to_physics = false
	_body.collision_layer = WorldFx.TERRAIN_LAYER
	_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width, block_height)
	shape.shape = rectangle
	_body.add_child(shape)
	_body.position = Vector2(0, block_height * 0.5)
	add_child(_body)
	_timer = DURATIONS[Phase.REST]
	call_deferred("_measure_and_offset")


func _measure_and_offset() -> void:
	# Tile collision in generated rooms is only queryable after the physics server has stepped.
	for _i in 2:
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	if travel <= 0.0:
		travel = _detect_travel()
	_rod_top = _detect_ceiling()
	var remaining := fposmod(phase_offset, cycle_seconds())
	while remaining > 0.0:
		var step := minf(remaining, _timer)
		_advance(step, false)
		remaining -= step


func cycle_seconds() -> float:
	var total := 0.0
	for value in DURATIONS.values():
		total += float(value)
	return total


func block_rect_global() -> Rect2:
	return Rect2(global_position + Vector2(-width * 0.5, _offset), Vector2(width, block_height))


func _detect_travel() -> float:
	var space := get_world_2d().direct_space_state
	var best := 1600.0
	for x in [-width * 0.5 + 6.0, 0.0, width * 0.5 - 6.0]:
		var from := global_position + Vector2(x, block_height + 2.0)
		var query := PhysicsRayQueryParameters2D.create(
			from, from + Vector2(0, 1600), WorldFx.TERRAIN_LAYER, [_body.get_rid()]
		)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			best = minf(best, Vector2(hit["position"]).y - (global_position.y + block_height))
	return maxf(best, 0.0)


## Local y of the rock above the rest position (where the piston rod disappears into the ceiling).
func _detect_ceiling() -> float:
	var from := global_position + Vector2(0, -2)
	var query := PhysicsRayQueryParameters2D.create(
		from, from + Vector2(0, -1200), WorldFx.TERRAIN_LAYER, [_body.get_rid()]
	)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1200.0
	return Vector2(hit["position"]).y - global_position.y - 12.0


func _physics_process(delta: float) -> void:
	_advance(delta, true)


func _advance(delta: float, live: bool) -> void:
	_timer -= delta
	var previous := _offset
	match phase:
		Phase.REST:
			_offset = 0.0
		Phase.TELEGRAPH:
			var t := 1.0 - _timer / DURATIONS[Phase.TELEGRAPH]
			_offset = 0.0
			_glow = t
			_shake = Vector2(randf_range(-1, 1), randf_range(-1, 0.5)) * (1.0 + 2.5 * t)
		Phase.SLAM:
			var t := clampf(1.0 - _timer / DURATIONS[Phase.SLAM], 0.0, 1.0)
			_offset = travel * t * t
			_shake = Vector2.ZERO
		Phase.HOLD:
			_offset = travel
			_glow = maxf(_glow - delta * 2.0, 0.0)
		Phase.RISE:
			var t := clampf(1.0 - _timer / DURATIONS[Phase.RISE], 0.0, 1.0)
			_offset = travel * (1.0 - t)
			_glow = 0.0
	if live and _offset > previous:
		_crush_check()
	_body.position = Vector2(0, _offset + block_height * 0.5)
	if _timer <= 0.0:
		_next_phase(live)
	if live:
		queue_redraw()


func _next_phase(live: bool) -> void:
	phase = ((phase + 1) % DURATIONS.size()) as Phase
	_timer += DURATIONS[phase]
	if not live:
		return
	match phase:
		Phase.TELEGRAPH:
			WorldFx.play(self, &"world_rumble", global_position + Vector2(0, block_height), -6.0)
			var colors := WorldFx.palette(_area)
			WorldFx.dust(
				get_parent(),
				global_position + Vector2(0, 4),
				Vector2(width * 0.4, 4),
				colors["dust"],
				12,
				10.0
			)
		Phase.HOLD:
			var floor_y := global_position.y + travel + block_height
			var colors := WorldFx.palette(_area)
			WorldFx.dust(
				get_parent(),
				Vector2(global_position.x - width * 0.5 - 10, floor_y - 8),
				Vector2(14, 6),
				colors["dust"],
				14,
				220.0
			)
			WorldFx.dust(
				get_parent(),
				Vector2(global_position.x + width * 0.5 + 10, floor_y - 8),
				Vector2(14, 6),
				colors["dust"],
				14,
				220.0
			)
			WorldFx.play(
				self,
				&"world_slam",
				Vector2(global_position.x, floor_y),
				-2.0,
				randf_range(0.95, 1.05)
			)
			_shake_if_near(floor_y)
		Phase.REST:
			_offset = 0.0


func _shake_if_near(floor_y: float) -> void:
	var player := WorldFx.player_of(self)
	if player == null:
		return
	var distance := player.global_position.distance_to(Vector2(global_position.x, floor_y))
	if distance < 1400.0:
		WorldFx.shake(self, lerpf(6.0, 1.5, distance / 1400.0), 0.22)


func _crush_check() -> void:
	var rect := block_rect_global()
	var player := WorldFx.player_of(self)
	if player != null and float(GameState.health) > 0.0:
		var body := WorldFx.player_rect(player)
		# Riders stand on the top face; only bodies below the top are crushed.
		var riding := player.global_position.y <= rect.position.y + 6.0
		if not riding and body.intersects(rect.grow(-2.0)):
			_crush_player(player, rect)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if (
			enemy is Node2D
			and enemy.has_method("take_damage")
			and rect.has_point(enemy.global_position)
		):
			enemy.call("take_damage", ENEMY_DAMAGE, &"missile")


func _crush_player(player: Node2D, rect: Rect2) -> void:
	var side := signf(player.global_position.x - rect.get_center().x)
	if side == 0.0:
		side = 1.0
	var target := _free_spot(player, rect, side)
	if target == Vector2.INF:
		target = _free_spot(player, rect, -side)
		side = -side
	if target != Vector2.INF:
		player.global_position = target
	if player.has_method("take_damage"):
		player.call("take_damage", damage, Vector2(rect.get_center().x, player.global_position.y))
	player.set("velocity", Vector2(side * 620.0, -380.0))
	WorldFx.play(self, &"world_slam", player.global_position, -4.0, 1.3)


## Feet position beside the block on `side` where a standing body fits, or Vector2.INF.
func _free_spot(player: Node2D, rect: Rect2, side: float) -> Vector2:
	var x := rect.get_center().x + side * (rect.size.x * 0.5 + PLAYER_SIZE.x * 0.5 + 6.0)
	var space := get_world_2d().direct_space_state
	var probe := RectangleShape2D.new()
	probe.size = PLAYER_SIZE - Vector2(4, 4)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.collision_mask = WorldFx.TERRAIN_LAYER
	query.exclude = [_body.get_rid(), (player as CollisionObject2D).get_rid()]
	for lift in [0.0, -32.0, -64.0, -128.0, -192.0]:
		var feet := Vector2(x, player.global_position.y + lift)
		query.transform = Transform2D(0.0, feet + Vector2(0, -PLAYER_SIZE.y * 0.5))
		if space.intersect_shape(query, 1).is_empty():
			return feet
	return Vector2.INF


func _draw() -> void:
	var colors := WorldFx.palette(_area)
	var accent: Color = colors["accent"]
	var top := _offset
	# Piston rod from the ceiling slot down to the block.
	var rod_top := minf(_rod_top, top - 8.0)
	var art := WorldFx.sheet_region("crushers", _area)
	var art_height := block_height / (1.0 - ART_SHAFT_FRACTION)
	var art_top := top + block_height - art_height
	if not art.is_empty() and art["texture"] != null:
		_draw_art_rod(art, rod_top, art_top)
	else:
		_draw_plain_rod(rod_top, top)
	var block := Rect2(Vector2(-width * 0.5, top) + _shake, Vector2(width, block_height - 16.0))
	var art_rect := Rect2(Vector2(block.position.x, art_top + _shake.y), Vector2(width, art_height))
	# The telegraph heats the whole head toward the area's glow colour.
	var heat := Color.WHITE.lerp(
		Color(accent.r * 1.6, accent.g * 1.6, accent.b * 1.6), 0.45 * _glow
	)
	if WorldFx.draw_sheet(self, "crushers", _area, art_rect, heat):
		return
	WorldFx.draw_rock(self, block, _area, false)
	# Heavy teeth along the bottom edge.
	var teeth := 4
	var tooth_width := width / teeth
	for index in teeth:
		var left := block.position.x + index * tooth_width
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(left + 2, block.end.y - 2),
					Vector2(left + tooth_width - 2, block.end.y - 2),
					Vector2(left + tooth_width * 0.5, block.end.y + 16),
				]
			),
			Color(0.09, 0.09, 0.1)
		)
	# Seams brighten through the telegraph so the slam is readable ahead of time.
	var seam := accent
	seam.a = 0.18 + 0.75 * _glow
	for row in [0.33, 0.66]:
		var sy: float = block.position.y + block.size.y * float(row)
		draw_line(
			Vector2(block.position.x + 10, sy),
			Vector2(block.end.x - 10, sy),
			seam,
			3.0 + 3.0 * _glow
		)


## Tiles the art's own collar section up to the ceiling so the rod matches the head.
func _draw_art_rod(art: Dictionary, rod_top: float, art_top: float) -> void:
	var region: Rect2 = art["region"]
	var scale := width / region.size.x
	var stub_width := region.size.x * 0.32
	var band := Rect2(
		region.position.x + (region.size.x - stub_width) * 0.5,
		region.position.y + region.size.y * 0.12,
		stub_width,
		region.size.y * 0.16
	)
	var piece := Vector2(band.size.x, band.size.y) * scale
	var y := art_top + region.size.y * 0.1 * scale - piece.y
	while y + piece.y > rod_top:
		var dest := Rect2(Vector2(-piece.x * 0.5, y), piece)
		var visible_rect := dest.intersection(Rect2(-piece.x, rod_top, piece.x * 2.0, 99999.0))
		if visible_rect.size.y > 0.5:
			var cut := (visible_rect.position.y - dest.position.y) / scale
			draw_texture_rect_region(
				art["texture"],
				visible_rect,
				Rect2(
					band.position + Vector2(0, cut),
					Vector2(band.size.x, visible_rect.size.y / scale)
				)
			)
		y -= piece.y


func _draw_plain_rod(rod_top: float, top: float) -> void:
	var rod_width := width * 0.34
	draw_rect(
		Rect2(Vector2(-rod_width * 0.5, rod_top), Vector2(rod_width, top - rod_top)),
		Color(0.05, 0.05, 0.06),
		true
	)
	var y := top - 40.0
	while y > rod_top:
		draw_rect(
			Rect2(Vector2(-rod_width * 0.5 - 6, y), Vector2(rod_width + 12, 14)),
			Color(0.14, 0.14, 0.16),
			true
		)
		y -= 72.0
