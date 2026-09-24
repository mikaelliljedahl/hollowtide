extends CanvasLayer

## Small always-on minimap in the top-right HUD corner, centred on the player. Same painter and
## markers as the full map (unexplored exits, gates, items, stations) at a smaller icon scale.
## Hidden while the full map is open. Turn it off in code with `enabled = false`.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Painter = preload("res://scripts/campaign/campaign_map_painter.gd")
const Style = preload("res://scripts/ui/ui_style.gd")

const PLATE_SIZE := Vector2(252, 156)
const MARGIN := Vector2(32, 26)
const TILE_SCALE := 3.4
const INSET := 5.0

var enabled := true:
	set(value):
		enabled = value
		_apply_visibility()

var _plate: Panel
var _canvas: Control
var _time := 0.0


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_plate = Panel.new()
	_plate.name = "MinimapPlate"
	_plate.size = PLATE_SIZE
	_plate.position = Vector2(1920.0 - MARGIN.x - PLATE_SIZE.x, MARGIN.y)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.035, 0.055, 0.74)
	style.border_color = Color(Style.ACCENT, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 6
	_plate.add_theme_stylebox_override("panel", style)
	add_child(_plate)
	_canvas = Control.new()
	_canvas.name = "MinimapCanvas"
	_canvas.position = Vector2(INSET, INSET)
	_canvas.size = PLATE_SIZE - Vector2(INSET, INSET) * 2.0
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_minimap)
	_plate.add_child(_canvas)
	_apply_visibility()


func _process(delta: float) -> void:
	_time += delta
	_apply_visibility()
	if _plate.visible:
		_canvas.queue_redraw()


func _apply_visibility() -> void:
	if _plate == null:
		return
	var map := _map()
	var show := enabled and not (map != null and map.visible)
	var root := get_parent()
	if root != null and root.get("current_room") == null:
		show = false
	_plate.visible = show


func _map() -> CanvasLayer:
	var root := get_parent()
	return root.get("map") as CanvasLayer if root != null else null


func _draw_minimap() -> void:
	var root := get_parent()
	if root == null:
		return
	var room_id := String(root.get("current_room_id"))
	var player := root.get("player") as Node2D
	var room := root.get("current_room") as Node2D
	if not Rooms.ROOMS.has(room_id) or player == null or room == null:
		return
	var local := (player.global_position - room.global_position) / Painter.TILE_PX
	var tile := Vector2(Rooms.ROOMS[room_id]["origin"]) + local - Vector2(0, 0.7)
	var view := Painter.View.new()
	view.scale = TILE_SCALE
	view.origin = _canvas.size * 0.5 - tile * TILE_SCALE
	view.icon_scale = 0.55
	view.time = _time
	view.reduce_motion = bool(ProjectSettings.get_setting("accessibility/reduce_flashes", false))
	Painter.paint(_canvas, view, room_id, tile)
