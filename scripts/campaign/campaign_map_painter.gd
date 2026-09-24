extends RefCounted

## Draws the campaign map (rooms, unexplored exits, icons) onto any CanvasItem. Shared by the
## full map screen and the HUD minimap. `view` maps world tiles to canvas pixels:
## pixel = view.origin + tile * view.scale. `icon_scale` shrinks markers for the minimap.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Model = preload("res://scripts/campaign/campaign_map_model.gd")

const AREA_COLORS := {
	&"fringe": Color("7f9f72"),
	&"nexus": Color("4fb3a6"),
	&"vaults": Color("9cc4e4"),
	&"kiln": Color("d9834f"),
	&"depths": Color("7a70d6"),
}
const GATE_COLORS := {
	&"missile": Color("ec6a5e"),
	&"bomb": Color("e8c052"),
	&"wave": Color("b59bff"),
	&"undertow": Color("8ee35a"),
	&"flag": Color("7fe3d6"),
	&"boss": Color("ff4d6a"),
}
const GATE_ICONS := {
	&"missile": "res://assets/sprites/arsenal/harpoon.png",
	&"bomb": "res://assets/sprites/arsenal/resonance_pulse.png",
	&"wave": "res://assets/sprites/arsenal/echo_shot.png",
	&"undertow": "res://assets/sprites/arsenal/undertow_dash.png",
}
const EXIT_COLOR := Color("ffdd70")
const SAVE_COLOR := Color("7fe3ff")
const REFILL_COLOR := Color("9df29b")
const ITEM_COLOR := Color("ffcf5a")
const PLAYER_COLOR := Color("fff3c4")
const INK := Color(0.01, 0.02, 0.03, 0.92)
const TILE_PX := 64.0

static var _icons: Dictionary = {}


class View:
	var origin := Vector2.ZERO
	var scale := 6.0
	var icon_scale := 1.0
	var time := 0.0
	var reduce_motion := false

	func point(tile: Vector2) -> Vector2:
		return origin + tile * scale

	func rect(tile_rect: Rect2) -> Rect2:
		return Rect2(point(tile_rect.position), tile_rect.size * scale)


static func area_color(area: StringName) -> Color:
	return AREA_COLORS.get(area, Color("6b8a8f"))


static func paint(
	canvas: CanvasItem, view: View, current_room: String, player_tile: Vector2
) -> void:
	var discovered: Array = GameState.discovered_rooms
	for room_id in Model.ghost_rooms(discovered):
		_paint_ghost(canvas, view, room_id)
	for room_id in discovered:
		if Rooms.ROOMS.has(room_id):
			_paint_room(canvas, view, room_id, room_id == current_room)
	for room_id in discovered:
		if Rooms.ROOMS.has(room_id):
			_paint_room_frame(canvas, view, room_id, room_id == current_room)
	for exit in Model.unexplored_exits(discovered):
		_paint_exit(canvas, view, exit)
	for room_id in discovered:
		if Rooms.ROOMS.has(room_id):
			_paint_stations(canvas, view, room_id)
	for pickup in Model.seen_pickups(discovered, GameState.collected_pickup_ids):
		var origin := Vector2(Rooms.ROOMS[pickup["room"]]["origin"])
		draw_item(canvas, view.point(origin + Vector2(pickup["cell"]) + Vector2(0.5, 0.5)), view)
	for gate in Model.gate_markers(discovered):
		_paint_gate(canvas, view, gate)
	if player_tile.x > -9000.0:
		draw_player(canvas, view.point(player_tile), view)


static func _paint_ghost(canvas: CanvasItem, view: View, room_id: String) -> void:
	var data: Dictionary = Rooms.ROOMS[room_id]
	var color := area_color(data["area"])
	var rect := view.rect(Rect2(Vector2(data["origin"]), Vector2(data["size"])))
	canvas.draw_rect(rect.grow(-1.0), Color(color, 0.06), true)
	var dash := maxf(4.0, 7.0 * view.icon_scale)
	var line := Color(color.lightened(0.25), 0.42)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end]
	corners.append(Vector2(rect.position.x, rect.end.y))
	for index in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		canvas.draw_dashed_line(a, b, line, 1.5, dash)


static func _paint_room(canvas: CanvasItem, view: View, room_id: String, current: bool) -> void:
	var data: Dictionary = Rooms.ROOMS[room_id]
	var color := area_color(data["area"])
	var origin := Vector2(data["origin"])
	var rect := view.rect(Rect2(origin, Vector2(data["size"])))
	canvas.draw_rect(rect, color.darkened(0.86), true)
	var geometry := Model.geometry(room_id)
	var fill := color.darkened(0.5)
	if current:
		var pulse := 0.0 if view.reduce_motion else 0.06 * sin(view.time * 3.0)
		fill = color.darkened(0.28 + pulse)
	for air in geometry["air"]:
		canvas.draw_rect(view.rect(Rect2(origin + air.position, air.size)), fill, true)
	for lava in geometry["lava"]:
		canvas.draw_rect(
			view.rect(Rect2(origin + lava.position, lava.size)), Color("c8502a").darkened(0.1), true
		)
	var walls: PackedVector2Array = geometry["walls"]
	var width := clampf(view.scale * 0.32, 1.2, 3.0)
	var wall := color.lightened(0.18 if current else 0.02)
	for index in range(0, walls.size(), 2):
		canvas.draw_line(
			view.point(origin + walls[index]), view.point(origin + walls[index + 1]), wall, width
		)


static func _paint_room_frame(
	canvas: CanvasItem, view: View, room_id: String, current: bool
) -> void:
	var data: Dictionary = Rooms.ROOMS[room_id]
	var color := area_color(data["area"])
	var rect := view.rect(Rect2(Vector2(data["origin"]), Vector2(data["size"])))
	if current:
		canvas.draw_rect(rect, Color(color.lightened(0.55), 0.9), false, 2.0)
	else:
		canvas.draw_rect(rect, Color(color.lightened(0.1), 0.38), false, 1.0)


static func _paint_exit(canvas: CanvasItem, view: View, exit: Dictionary) -> void:
	var data: Dictionary = Rooms.ROOMS[exit["room"]]
	var origin := Vector2(data["origin"])
	var size := Vector2(data["size"])
	var from := Vector2(exit["from"])
	var to := Vector2(exit["to"]) + Vector2.ONE
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var outward := Vector2.ZERO
	match exit["edge"]:
		&"west":
			a = Vector2(0, from.y)
			b = Vector2(0, to.y)
			outward = Vector2.LEFT
		&"east":
			a = Vector2(size.x, from.y)
			b = Vector2(size.x, to.y)
			outward = Vector2.RIGHT
		&"north":
			a = Vector2(from.x, 0)
			b = Vector2(to.x, 0)
			outward = Vector2.UP
		_:
			a = Vector2(from.x, size.y)
			b = Vector2(to.x, size.y)
			outward = Vector2.DOWN
	var pa := view.point(origin + a)
	var pb := view.point(origin + b)
	var mid := (pa + pb) * 0.5
	var blocked: bool = exit["blocked"]
	var color: Color = GATE_COLORS.get(exit["gate"], EXIT_COLOR) if blocked else EXIT_COLOR
	var wave := 0.0 if view.reduce_motion else 0.5 + 0.5 * sin(view.time * 4.2)
	var glow := 1.0 if blocked else 0.75 + 0.25 * wave
	# Bright bar across the opening.
	canvas.draw_line(pa, pb, Color(color, 0.95 * glow), maxf(3.0, 5.0 * view.icon_scale))
	# Chevron pointing out of the room, bobbing outward.
	var size_px := 11.0 * maxf(view.icon_scale, 0.7)
	var push := (7.0 + (0.0 if blocked else 4.0 * wave)) * view.icon_scale
	var tip := mid + outward * (push + size_px * 1.6)
	var side := Vector2(-outward.y, outward.x)
	var base := tip - outward * size_px * 1.3
	var points := PackedVector2Array([tip, base + side * size_px, base - side * size_px])
	var outline := PackedVector2Array(
		[
			tip + outward * 2.0,
			base + side * (size_px + 2.5) - outward * 1.5,
			base - side * (size_px + 2.5) - outward * 1.5
		]
	)
	canvas.draw_colored_polygon(outline, INK)
	canvas.draw_colored_polygon(points, Color(color, glow))
	if blocked:
		var badge := tip + outward * (size_px + 10.0 * view.icon_scale)
		draw_gate_badge(canvas, badge, exit["gate"], view.icon_scale * 0.8)


static func _paint_stations(canvas: CanvasItem, view: View, room_id: String) -> void:
	var data: Dictionary = Rooms.ROOMS[room_id]
	var origin := Vector2(data["origin"])
	for save in data["saves"]:
		draw_save(canvas, view.point(origin + save / TILE_PX - Vector2(0, 0.9)), view.icon_scale)
	for refill in data["refills"]:
		draw_refill(
			canvas, view.point(origin + refill / TILE_PX - Vector2(0, 0.7)), view.icon_scale
		)


static func _paint_gate(canvas: CanvasItem, view: View, gate: Dictionary) -> void:
	var data: Dictionary = Rooms.ROOMS[gate["room"]]
	var center := Vector2(data["origin"]) + Vector2(gate["cell"]) + Vector2(gate["size"]) * 0.5
	var point := view.point(center)
	var kind: StringName = gate["kind"]
	if kind == &"boss":
		draw_boss(canvas, point, view.icon_scale, gate["defeated"])
		return
	# The closed gate itself: a bar in the gate colour across its cells.
	var cells := view.rect(Rect2(center - Vector2(gate["size"]) * 0.5, Vector2(gate["size"])))
	canvas.draw_rect(cells, Color(GATE_COLORS.get(kind, Color.WHITE), 0.85), true)
	if gate["final"]:
		draw_final_seal(canvas, point, view.icon_scale, Model.seal_progress(gate["flag"]))
	else:
		draw_gate_badge(canvas, point, kind, view.icon_scale)


static func draw_save(canvas: CanvasItem, center: Vector2, k: float) -> void:
	var r := 10.0 * k
	_diamond(canvas, center, r + 2.5, INK)
	_diamond(canvas, center, r, SAVE_COLOR)
	_diamond(canvas, center, r * 0.42, Color("0b2a33"))


static func draw_refill(canvas: CanvasItem, center: Vector2, k: float) -> void:
	var r := 8.0 * k
	canvas.draw_circle(center, r + 2.5, INK)
	canvas.draw_circle(center, r, REFILL_COLOR)
	var arm := r * 0.6
	var ink := Color("0f2a12")
	canvas.draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0), ink, maxf(1.5, 2.5 * k))
	canvas.draw_line(center - Vector2(0, arm), center + Vector2(0, arm), ink, maxf(1.5, 2.5 * k))


static func draw_item(canvas: CanvasItem, center: Vector2, view: View) -> void:
	var k := view.icon_scale
	var r := 6.0 * k
	var ring := 0.0 if view.reduce_motion else fmod(view.time * 0.9, 1.0)
	if k >= 0.9 and not view.reduce_motion:
		canvas.draw_arc(
			center, r + 3.0 + ring * 8.0, 0.0, TAU, 24, Color(ITEM_COLOR, 0.6 * (1.0 - ring)), 1.5
		)
	canvas.draw_circle(center, r + 2.0, INK)
	canvas.draw_circle(center, r, ITEM_COLOR)
	canvas.draw_circle(center - Vector2(r, r) * 0.25, r * 0.4, Color(1, 1, 0.9, 0.9))


static func draw_player(canvas: CanvasItem, center: Vector2, view: View) -> void:
	var k := maxf(view.icon_scale, 0.8)
	var beat := 1.0 if view.reduce_motion else absf(sin(view.time * 3.2))
	if not view.reduce_motion:
		var ring := fmod(view.time * 1.1, 1.0)
		canvas.draw_arc(
			center,
			(9.0 + ring * 14.0) * k,
			0.0,
			TAU,
			32,
			Color(PLAYER_COLOR, 0.7 * (1.0 - ring)),
			2.0
		)
	canvas.draw_circle(center, 10.0 * k, INK)
	canvas.draw_circle(center, 7.5 * k, Color(PLAYER_COLOR, 0.75 + 0.25 * beat))
	canvas.draw_circle(center, 3.5 * k, Color("ff9f5a").lerp(Color.WHITE, 0.3 * beat))


static func draw_gate_badge(
	canvas: CanvasItem, center: Vector2, kind: StringName, k: float
) -> void:
	var color: Color = GATE_COLORS.get(kind, Color.WHITE)
	var r := 13.0 * k
	canvas.draw_circle(center, r + 2.5, INK)
	canvas.draw_circle(center, r, color.darkened(0.62))
	canvas.draw_arc(center, r, 0.0, TAU, 32, color, maxf(1.5, 2.5 * k), true)
	var texture := _icon(kind)
	if texture != null and r >= 7.0:
		var edge := r * 1.55
		canvas.draw_texture_rect(
			texture, Rect2(center - Vector2(edge, edge) * 0.5, Vector2(edge, edge)), false
		)
	elif kind == &"flag":
		_lock(canvas, center, r * 0.62, color)
	else:
		canvas.draw_circle(center, r * 0.45, color)


static func draw_final_seal(canvas: CanvasItem, center: Vector2, k: float, seals: Vector2i) -> void:
	var color: Color = GATE_COLORS[&"flag"]
	var r := 16.0 * k
	canvas.draw_circle(center, r + 3.0, INK)
	canvas.draw_circle(center, r, Color("15343a"))
	canvas.draw_arc(center, r, 0.0, TAU, 40, color, maxf(1.5, 3.0 * k), true)
	canvas.draw_arc(center, r * 0.72, 0.0, TAU, 32, Color(color, 0.45), maxf(1.0, 1.5 * k), true)
	# One seal light per required boss: lit when that boss is down.
	for index in seals.y:
		var angle := -PI * 0.5 + TAU * float(index) / maxf(1.0, seals.y) + PI * 0.5
		var light := center + Vector2(cos(angle), sin(angle)) * r * 0.42
		var lit := index < seals.x
		canvas.draw_circle(light, r * 0.24 + 1.5, INK)
		canvas.draw_circle(light, r * 0.24, Color("fff3c4") if lit else Color(color, 0.25))


static func draw_boss(canvas: CanvasItem, center: Vector2, k: float, defeated: bool) -> void:
	var color: Color = Color("6b7378") if defeated else GATE_COLORS[&"boss"]
	var r := 14.0 * k
	canvas.draw_circle(center, r + 2.5, INK)
	canvas.draw_circle(center, r, color.darkened(0.55))
	canvas.draw_arc(center, r, 0.0, TAU, 32, color, maxf(1.5, 2.5 * k), true)
	# Horned skull glyph.
	var s := r * 0.62
	var bone := Color("f4e9e0") if not defeated else Color("9aa3a6")
	var horns_left := PackedVector2Array(
		[
			center + Vector2(-0.55, -0.35) * s,
			center + Vector2(-1.05, -1.15) * s,
			center + Vector2(-0.2, -0.65) * s
		]
	)
	var horns_right := PackedVector2Array(
		[
			center + Vector2(0.55, -0.35) * s,
			center + Vector2(1.05, -1.15) * s,
			center + Vector2(0.2, -0.65) * s
		]
	)
	canvas.draw_colored_polygon(horns_left, bone)
	canvas.draw_colored_polygon(horns_right, bone)
	canvas.draw_circle(center + Vector2(0, -0.1) * s, s * 0.72, bone)
	canvas.draw_rect(Rect2(center + Vector2(-0.4, 0.3) * s, Vector2(0.8, 0.55) * s), bone, true)
	var eye := color.darkened(0.7)
	canvas.draw_circle(center + Vector2(-0.3, -0.12) * s, s * 0.2, eye)
	canvas.draw_circle(center + Vector2(0.3, -0.12) * s, s * 0.2, eye)
	if defeated:
		canvas.draw_line(
			center + Vector2(-r, r) * 0.7, center + Vector2(r, -r) * 0.7, Color("c9d2d4"), 2.5 * k
		)


static func _lock(canvas: CanvasItem, center: Vector2, s: float, color: Color) -> void:
	canvas.draw_arc(
		center + Vector2(0, -0.35) * s, s * 0.5, PI, TAU, 12, color, maxf(1.5, s * 0.22), true
	)
	canvas.draw_rect(Rect2(center + Vector2(-0.75, -0.35) * s, Vector2(1.5, 1.2) * s), color, true)
	canvas.draw_circle(center + Vector2(0, 0.2) * s, s * 0.18, color.darkened(0.7))


static func _diamond(canvas: CanvasItem, center: Vector2, r: float, color: Color) -> void:
	(
		canvas
		. draw_colored_polygon(
			PackedVector2Array(
				[
					center + Vector2(0, -r),
					center + Vector2(r, 0),
					center + Vector2(0, r),
					center + Vector2(-r, 0),
				]
			),
			color
		)
	)


static func _icon(kind: StringName) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var texture: Texture2D = null
	if GATE_ICONS.has(kind) and ResourceLoader.exists(GATE_ICONS[kind]):
		texture = load(GATE_ICONS[kind]) as Texture2D
	_icons[kind] = texture
	return texture
