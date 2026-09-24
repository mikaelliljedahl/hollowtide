class_name DevMap
extends CanvasLayer

var room_ids: Array[String] = []
var current_room := "prototype"
var _map: Control


func _ready():
	layer = 12
	_map = Control.new()
	_map.position = Vector2(1430, 28)
	_map.size = Vector2(456, 110)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	add_child(_map)
	GameState.state_changed.connect(_refresh)


func set_rooms(ids: Array[String]):
	room_ids = ids
	_refresh()


func set_current(room: String):
	current_room = room
	_refresh()


func _refresh():
	if is_instance_valid(_map):
		_map.queue_redraw()


func _draw_map():
	_map.draw_rect(Rect2(0, 0, 456, 110), Color(0.025, 0.04, 0.06, 0.82))
	for index in room_ids.size():
		if not GameState.discovered_rooms.has(room_ids[index]):
			continue
		var origin := Vector2(14 + (index % 11) * 39, 15 + (index / 11) * 42)
		var color := Color("679398") if room_ids[index] != current_room else Color("bdede0")
		_map.draw_rect(Rect2(origin, Vector2(31, 31)), color, false, 2)
		if room_ids[index] == current_room:
			_map.draw_circle(origin + Vector2(15, 15), 4, color)
		if index + 1 < room_ids.size() and GameState.discovered_rooms.has(room_ids[index + 1]):
			_map.draw_line(origin + Vector2(31, 15), origin + Vector2(39, 15), color, 2)
