extends CanvasLayer

signal room_changed(room_id: String)

const ROOM_IDS := ["S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10"]
const ROOM_POSITIONS := [
	Vector2(54, 92),
	Vector2(122, 92),
	Vector2(190, 92),
	Vector2(258, 92),
	Vector2(326, 92),
	Vector2(394, 92),
	Vector2(462, 92),
	Vector2(530, 92),
	Vector2(598, 92),
	Vector2(666, 92),
	Vector2(734, 92),
]
const DEFAULT_NAMES := [
	"S0 Original Cave",
	"S1 Movement",
	"S2 Shooting Range",
	"S3 Ball / Pulse",
	"S4 Energy / Protection",
	"S5 Bubble Snare",
	"S6 Undertow Dash",
	"S7 Bestiary",
	"S8 Boss Arena",
	"S9 World Test",
	"S10 Graphics Test",
]

var rooms: Array = []
var room_names: Array = []
var current_room := ""
var current_subcell := ""
var connections: Array = []
var markers: Dictionary = {}
var _view: Control


func _ready() -> void:
	layer = 24
	_view = MapView.new()
	_view.name = "Miniature"
	_view.position = Vector2(1082, 24)
	_view.custom_minimum_size = Vector2(790, 230)
	_view.tooltip_text = "Developer map. Node colors show current, discovered, and undiscovered rooms."
	add_child(_view)
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
	set_rooms(ROOM_IDS)


func set_rooms(names: Array) -> void:
	rooms = names.duplicate()
	if room_names.size() != rooms.size():
		room_names.clear()
		for index in rooms.size():
			room_names.append(
				DEFAULT_NAMES[index] if index < DEFAULT_NAMES.size() else rooms[index]
			)
	if connections.is_empty():
		for index in range(maxi(rooms.size() - 1, 0)):
			connections.append(Vector2i(index, index + 1))
	_refresh_view()


func set_room_names(names: Array) -> void:
	room_names = names.duplicate()
	_refresh_view()


func set_connections(edges: Array) -> void:
	connections = edges.duplicate()
	_refresh_view()


func set_markers(values: Dictionary) -> void:
	markers = values.duplicate(true)
	_refresh_view()


func set_current(room_id: String) -> void:
	if not rooms.has(room_id):
		return
	if current_room != room_id:
		current_room = room_id
		room_changed.emit(room_id)
	if not GameState.discovered_rooms.has(room_id):
		GameState.discover_room(room_id)
	_refresh_view()


func set_current_subcell(subcell_id: String) -> void:
	current_subcell = subcell_id
	if not subcell_id.is_empty() and not GameState.discovered_rooms.has(subcell_id):
		GameState.discover_room(subcell_id)
	_refresh_view()


func _on_state_changed() -> void:
	_refresh_view()


func _refresh_view() -> void:
	if _view == null:
		return
	_view.set_data(rooms, room_names, current_room, current_subcell, connections, markers)
	_view.queue_redraw()


class MapView:
	extends Control
	var _rooms: Array = []
	var _names: Array = []
	var _current := ""
	var _subcell := ""
	var _connections: Array = []
	var _markers: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_data(
		rooms_value: Array,
		names_value: Array,
		current_value: String,
		subcell_value: String,
		connections_value: Array,
		markers_value: Dictionary
	) -> void:
		_rooms = rooms_value.duplicate()
		_names = names_value.duplicate()
		_current = current_value
		_subcell = subcell_value
		_connections = connections_value.duplicate()
		_markers = markers_value.duplicate(true)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var panel_rect := Rect2(0, 0, 790, 230)
		draw_style_box(_panel_style(), panel_rect)
		draw_string(
			font,
			Vector2(20, 28),
			"DEV WORLD MAP  /  S0-S10",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			21,
			Color("e4f1ef")
		)
		draw_string(
			font,
			Vector2(20, 53),
			"Connected route · state from GameState snapshot",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			Color("8da9a7")
		)
		for edge in _connections:
			if (
				edge.x < 0
				or edge.y < 0
				or edge.x >= ROOM_POSITIONS.size()
				or edge.y >= ROOM_POSITIONS.size()
			):
				continue
			draw_line(ROOM_POSITIONS[edge.x], ROOM_POSITIONS[edge.y], Color("647d80"), 4.0)
		for index in _rooms.size():
			if index >= ROOM_POSITIONS.size():
				continue
			var room_id: String = String(_rooms[index])
			var discovered := GameState.discovered_rooms.has(room_id)
			var color := Color("25383d")
			if discovered:
				color = Color("4e9e99")
			if room_id == _current:
				color = Color("e2c36a")
			draw_circle(ROOM_POSITIONS[index], 18.0, color)
			draw_arc(ROOM_POSITIONS[index], 18.0, 0.0, TAU, 20, Color("d8ece8"), 2.0)
			draw_string(
				font,
				ROOM_POSITIONS[index] - Vector2(9, -6),
				room_id,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				12,
				Color("102126") if discovered else Color("769096")
			)
			var short_name: String = (
				String(_names[index]).trim_prefix(room_id).strip_edges()
				if index < _names.size()
				else ""
			)
			draw_string(
				font,
				ROOM_POSITIONS[index] - Vector2(28, -42),
				short_name,
				HORIZONTAL_ALIGNMENT_LEFT,
				58,
				11,
				Color("c3d5d2")
			)
			_draw_markers(room_id, ROOM_POSITIONS[index], font)
		var subcell_text := (
			"S9 subcell: " + _subcell
			if not _subcell.is_empty()
			else "S9 route: three connected cells"
		)
		draw_string(
			font, Vector2(20, 150), subcell_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("9cb9b5")
		)
		draw_circle(Vector2(28, 181), 8.0, Color("e2c36a"))
		draw_string(
			font, Vector2(43, 186), "Current", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d5e6e3")
		)
		draw_circle(Vector2(126, 181), 8.0, Color("4e9e99"))
		draw_string(
			font,
			Vector2(141, 186),
			"Discovered",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color("d5e6e3")
		)
		draw_circle(Vector2(254, 181), 8.0, Color("25383d"))
		draw_string(
			font, Vector2(269, 186), "Unseen", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d5e6e3")
		)
		draw_string(
			font,
			Vector2(390, 186),
			"◇ checkpoint   + refill   □ gate",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color("d5e6e3")
		)
		draw_string(
			font,
			Vector2(20, 216),
			"Map markers are technical dev UI; no world tutorial text.",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color("708b8c")
		)

	func _draw_markers(room_id: String, center: Vector2, font: Font) -> void:
		var room_markers: Array = _markers.get(room_id, [])
		var offset := 0
		for marker in room_markers:
			var kind := String(marker.get("kind", ""))
			var color := Color("d5e6e3")
			var marker_position := center + Vector2(-12 + offset * 12, 25)
			if kind == "checkpoint":
				draw_diamond(marker_position, 5.0, Color("e2c36a"))
			elif kind == "refill":
				draw_string(
					font,
					marker_position + Vector2(-5, 5),
					"+",
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14,
					Color("80d8b0")
				)
			elif kind == "gate":
				draw_rect(
					Rect2(marker_position - Vector2(5, 5), Vector2(10, 10)), color, false, 2.0
				)
			offset += 1

	func _panel_style() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.06, 0.07, 0.94)
		style.border_color = Color("568d94")
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		return style

	func draw_diamond(center: Vector2, radius: float, color: Color) -> void:
		var points := PackedVector2Array(
			[
				center + Vector2(0, -radius),
				center + Vector2(radius, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius, 0),
			]
		)
		draw_colored_polygon(points, color)
