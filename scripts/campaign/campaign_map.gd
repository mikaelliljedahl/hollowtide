extends CanvasLayer

## Campaign map screen (M / Tab). Discovered rooms are drawn at their true shape, coloured by area.
## Doors into rooms not yet entered pulse as unexplored exits; the room behind them is only a
## dashed frame. Closed gates, save shrines, refills, uncollected items in visited rooms, bosses
## and the final seal have icons. Arrows / drag pan, wheel or +/- zooms, R recentres.
## The frame centre is a cursor that snaps to cells: fire_beam places or cycles a map pin there,
## fire_missile removes it (docs/features/map-pins.md).
## Opened from a save shrine it runs in travel mode instead: movement steps between activated
## shrines, jump travels, pins are read-only (docs/features/fast-travel.md).
## Menu UI only: labels here are map legend text, never instructions in the world.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Model = preload("res://scripts/campaign/campaign_map_model.gd")
const Painter = preload("res://scripts/campaign/campaign_map_painter.gd")
const Style = preload("res://scripts/ui/ui_style.gd")
const Pins = preload("res://scripts/campaign/campaign_map_pins.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")
const Travel = preload("res://scripts/campaign/campaign_map_travel.gd")

const AREA_NAMES := {
	&"fringe": "FRINGE CAVERN",
	&"nexus": "RESONANCE HUB",
	&"vaults": "DROP VAULTS",
	&"kiln": "GLOW PASSAGES",
	&"depths": "DEEP CHAMBER",
}
const GATE_NAMES := {
	&"missile": "HARPOON",
	&"bomb": "PULSE",
	&"wave": "ECHO",
	&"undertow": "DASH",
	&"flag": "SEALED",
}
const FRAME := Rect2(60, 172, 1800, 790)
const FIT_MARGIN := 70.0
const MAX_FIT_SCALE := 13.0
const MIN_ZOOM := 0.6
const MAX_ZOOM := 4.0
const PAN_SPEED := 900.0
const NO_TILE := Vector2(-9999, -9999)
const PIN_NAMES := {"return": "COME BACK", "danger": "DANGER", "item": "ITEM MARK"}
const TRAVEL_FOCUS_SPEED := 9.0

var current_room := ""
var _canvas: Control
var _legend: Control
var _title: Label
var _subtitle: Label
var _progress: HBoxContainer
var _hint: Label
var _legend_labels: Array[Label] = []
var _was_paused := false
var _time := 0.0
var _fit_scale := 6.0
var _zoom := 1.0
var _center := Vector2.ZERO
var _dragging := false
## Non-null while the map runs in travel mode.
var _travel: Travel


func _ready() -> void:
	layer = 70
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.008, 0.016, 0.026, 0.93)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var frame := Panel.new()
	frame.position = FRAME.position - Vector2(2, 2)
	frame.size = FRAME.size + Vector2(4, 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.035, 0.055, 0.74)
	style.border_color = Color(Style.ACCENT, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	_canvas = Control.new()
	_canvas.position = FRAME.position
	_canvas.size = FRAME.size
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	_title = _centered_label(Style.SIZE_H1, Style.TEXT, 34.0, 8)
	Style.glow(_title, Style.ACCENT, 0.22, 14)
	_subtitle = _centered_label(Style.SIZE_BODY, Style.TEXT_MUTED, 92.0, 2)
	_progress = HBoxContainer.new()
	_progress.add_theme_constant_override("separation", 40)
	_progress.position = Vector2(0, 134)
	_progress.size = Vector2(1920, 26)
	_progress.alignment = BoxContainer.ALIGNMENT_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress)
	_legend = Control.new()
	_legend.position = Vector2(FRAME.position.x, FRAME.end.y + 16)
	_legend.size = Vector2(FRAME.size.x, 40)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.draw.connect(_draw_legend)
	add_child(_legend)
	_hint = Style.label(self, "", 15, Style.TEXT_FAINT, 2)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.position = Vector2(FRAME.position.x, 1036)
	_hint.size = Vector2(FRAME.size.x, 24)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	_reset_view()
	_refresh_labels()
	_refresh_hint()
	_canvas.queue_redraw()
	_legend.queue_redraw()


func close() -> void:
	visible = false
	_dragging = false
	_travel = null
	get_tree().paused = _was_paused


## Opens the map to choose a fast-travel destination (called by the campaign root). `targets`
## come from FastTravel.targets; the root repeats every check when travel_to is called.
func open_travel(from_id: String, targets: Array[Dictionary]) -> void:
	open()
	_travel = Travel.new(from_id, targets)
	_zoom = 1.0
	_center = _travel.focus_tile()
	_clamp_center()
	_refresh_labels()
	_refresh_hint()


func is_travel_mode() -> bool:
	return visible and _travel != null


## Selected travel destination id, or "" outside travel mode (tools and checks).
func travel_selection() -> String:
	return String(_travel.selected().get("id", "")) if _travel != null else ""


func _step_travel(amount: int) -> void:
	_travel.step(amount)
	_refresh_labels()


func _confirm_travel() -> void:
	var from := _travel.from_id
	var to := travel_selection()
	close()
	var root := get_parent()
	if root != null and root.has_method("travel_to") and not to.is_empty():
		root.call("travel_to", from, to)


func _travel_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"move_up"):
		_step_travel(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"move_down"):
		_step_travel(1)
	elif event.is_action_pressed(&"jump") or event.is_action_pressed(&"ui_accept"):
		_confirm_travel()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode not in [KEY_ESCAPE, KEY_M, KEY_TAB]:
			return
		close()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 1.12, MIN_ZOOM, MAX_ZOOM)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom / 1.12, MIN_ZOOM, MAX_ZOOM)
	else:
		return
	get_viewport().set_input_as_handled()


func set_current(room_id: String) -> void:
	current_room = room_id
	if visible:
		_refresh_labels()
		_canvas.queue_redraw()


## Current map scale in pixels per tile (tools and checks).
func map_scale() -> float:
	return _fit_scale * _zoom


## Pans and zooms the open map (tools): centre in world tiles, zoom 1 = fit the known map.
func focus(center_tile: Vector2, zoom: float) -> void:
	_zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	_center = center_tile
	_clamp_center()


## The discovered room cell under the cursor (room, cell, size), or {} over unexplored space.
func cursor_target() -> Dictionary:
	return Model.cell_at(GameState.discovered_rooms, _center)


## Places a pin on the cursor cell, or advances the kind of the pin already there.
func pin_at_cursor() -> bool:
	var target := cursor_target()
	if target.is_empty():
		return false
	var room: String = target["room"]
	return _apply_pins(
		Pins.activated(
			GameState.map_pins, GameState.discovered_rooms, room, target["size"], target["cell"]
		)
	)


func unpin_at_cursor() -> bool:
	var target := cursor_target()
	if target.is_empty():
		return false
	return _apply_pins(Pins.removed(GameState.map_pins, target["room"], target["cell"]))


func _apply_pins(pins: Array[Dictionary]) -> bool:
	if pins == GameState.map_pins or not GameState.set_map_pins(pins):
		return false
	_refresh_legend()
	_refresh_hint()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _travel != null:
		_travel_input(event)
		return
	if event.is_action_pressed(&"fire_beam") or event.is_action_pressed(&"fire_missile"):
		if event.is_action_pressed(&"fire_beam"):
			pin_at_cursor()
		else:
			unpin_at_cursor()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE, KEY_M, KEY_TAB:
				close()
			KEY_R, KEY_HOME:
				var player := _player_tile()
				if player != NO_TILE:
					_center = player
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				_set_zoom(_zoom * 1.25, FRAME.get_center())
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				_set_zoom(_zoom / 1.25, FRAME.get_center())
			KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
				pass
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 1.12, mouse.position)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 1.12, mouse.position)
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_center -= (event as InputEventMouseMotion).relative / map_scale()
		_clamp_center()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _travel != null:
		# Glide to the selected shrine instead of free panning.
		_center = _center.lerp(_travel.focus_tile(), minf(1.0, TRAVEL_FOCUS_SPEED * delta))
		_clamp_center()
		_canvas.queue_redraw()
		_legend.queue_redraw()
		return
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		_center += pan.normalized() * PAN_SPEED * delta / map_scale()
		_clamp_center()
	_canvas.queue_redraw()
	_legend.queue_redraw()


func _reset_view() -> void:
	var known: Array = GameState.discovered_rooms.duplicate()
	known.append_array(Model.ghost_rooms(GameState.discovered_rooms))
	if not current_room.is_empty() and not known.has(current_room):
		known.append(current_room)
	var bounds := Model.bounds_of(known)
	if bounds.size == Vector2.ZERO:
		bounds = Model.bounds_of(Rooms.ROOMS.keys())
	var usable := FRAME.size - Vector2(FIT_MARGIN, FIT_MARGIN) * 2.0
	_fit_scale = minf(minf(usable.x / bounds.size.x, usable.y / bounds.size.y), MAX_FIT_SCALE)
	_zoom = 1.0
	_center = bounds.get_center()


func _set_zoom(value: float, anchor_screen: Vector2) -> void:
	var anchor := _screen_to_tile(anchor_screen)
	_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	# Keep the tile under the cursor fixed.
	var local := anchor_screen - FRAME.position
	_center = anchor - (local - FRAME.size * 0.5) / map_scale()
	_clamp_center()


func _screen_to_tile(screen: Vector2) -> Vector2:
	return _center + (screen - FRAME.position - FRAME.size * 0.5) / map_scale()


func _clamp_center() -> void:
	var all := Model.bounds_of(Rooms.ROOMS.keys())
	_center = _center.clamp(all.position, all.end)


func _view() -> Painter.View:
	var view := Painter.View.new()
	view.scale = map_scale()
	view.origin = FRAME.size * 0.5 - _center * view.scale
	view.icon_scale = clampf(0.75 + 0.03 * view.scale, 0.85, 1.2)
	view.time = _time
	view.reduce_motion = _reduce_motion()
	return view


func _reduce_motion() -> bool:
	return bool(ProjectSettings.get_setting("accessibility/reduce_flashes", false))


func _draw_map() -> void:
	var view := _view()
	Painter.paint(_canvas, view, current_room, _player_tile())
	if _travel != null:
		_travel.draw(_canvas, view)
	else:
		_draw_cursor(view)


func _draw_cursor(view: Painter.View) -> void:
	var center := FRAME.size * 0.5
	var target := cursor_target()
	var color := Color(Painter.PLAYER_COLOR, 0.45)
	if not target.is_empty():
		var origin := Vector2(Rooms.ROOMS[target["room"]]["origin"])
		var cell := view.rect(Rect2(origin + Vector2(target["cell"]), Vector2.ONE))
		cell = cell.grow(maxf(2.0, cell.size.x * 0.15))
		_canvas.draw_rect(cell.grow(1.5), Painter.INK, false, 3.0)
		_canvas.draw_rect(cell, Color(Painter.PLAYER_COLOR, 0.95), false, 1.5)
		color = Color(Painter.PLAYER_COLOR, 0.8)
	# Short crosshair ticks outside the cell so the cursor reads over empty space too.
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var start: Vector2 = center + direction * maxf(10.0, view.scale * 0.9)
		_canvas.draw_line(start, start + direction * 10.0, color, 2.0)


func _player_tile() -> Vector2:
	var root := get_parent()
	if root == null or not Rooms.ROOMS.has(current_room):
		return NO_TILE
	var player := root.get("player") as Node2D
	var room := root.get("current_room") as Node2D
	if player == null or room == null:
		return NO_TILE
	var local := (player.global_position - room.global_position) / Painter.TILE_PX
	return Vector2(Rooms.ROOMS[current_room]["origin"]) + local - Vector2(0, 0.7)


func _centered_label(font_size: int, color: Color, y: float, spacing: int) -> Label:
	var label := Style.label(self, "", font_size, color, spacing)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, y)
	label.size = Vector2(1920, font_size + 16)
	return label


func _refresh_labels() -> void:
	var target := _travel.selected() if _travel != null else {}
	if not target.is_empty():
		var room: Dictionary = Rooms.ROOMS[target["room"]]
		_title.text = "TRAVEL"
		_subtitle.text = "%s  ·  %s" % [AREA_NAMES.get(room["area"], ""), room["name"]]
	elif not Rooms.ROOMS.has(current_room):
		_title.text = "MAP"
		_subtitle.text = ""
	else:
		var data: Dictionary = Rooms.ROOMS[current_room]
		_title.text = AREA_NAMES.get(data["area"], "MAP")
		_subtitle.text = String(data["name"])
	for child in _progress.get_children():
		_progress.remove_child(child)
		child.queue_free()
	var progress := Model.area_progress(GameState.discovered_rooms)
	for area in Model.AREAS:
		var value: Vector2i = progress[area]
		var seen := value.x > 0
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 10)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = Painter.area_color(area) if seen else Color(Style.TEXT_FAINT, 0.4)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(swatch)
		var name_text: String = AREA_NAMES[area] if seen else "UNCHARTED"
		var color := Style.TEXT_FAINT
		if seen:
			color = Style.ACCENT if value.x == value.y else Style.TEXT_MUTED
		Style.label(chip, "%s  %d/%d" % [name_text, value.x, value.y], Style.SIZE_SMALL, color, 2)
		_progress.add_child(chip)
	_refresh_legend()


func _refresh_legend() -> void:
	for label in _legend_labels:
		label.queue_free()
	_legend_labels.clear()
	var kinds: Array[StringName] = []
	var has_boss := false
	var has_seal := false
	for gate in Model.gate_markers(GameState.discovered_rooms):
		if gate["kind"] == &"boss":
			has_boss = true
		elif gate["final"]:
			has_seal = true
		elif not kinds.has(gate["kind"]):
			kinds.append(gate["kind"])
	var entries: Array = [["you", "YOU"], ["save", "SAVE"], ["refill", "REFILL"]]
	entries.append(["item", "ITEM"])
	entries.append(["exit", "UNEXPLORED"])
	for kind in GATE_NAMES:
		if kinds.has(kind):
			entries.append([String(kind), GATE_NAMES[kind]])
	if has_seal:
		entries.append(["seal", "FINAL SEAL"])
	if has_boss:
		entries.append(["boss", "BOSS"])
	for kind in Pins.KINDS:
		if GameState.map_pins.any(func(pin: Dictionary) -> bool: return pin["kind"] == kind):
			entries.append(["pin:" + kind, PIN_NAMES[kind]])
	var x := 12.0
	for entry in entries:
		var label := Style.label(_legend, entry[1], Style.SIZE_SMALL, Style.TEXT_MUTED, 2)
		label.position = Vector2(x + 30.0, 5.0)
		label.set_meta(&"glyph", entry[0])
		label.set_meta(&"x", x)
		_legend_labels.append(label)
		x += 30.0 + label.get_minimum_size().x + 36.0


func _draw_legend() -> void:
	var view := Painter.View.new()
	view.icon_scale = 0.9
	view.time = _time
	view.reduce_motion = _reduce_motion()
	for label in _legend_labels:
		if not is_instance_valid(label):
			continue
		var at := Vector2(float(label.get_meta(&"x")) + 12.0, 18.0)
		match String(label.get_meta(&"glyph")):
			"you":
				var still := Painter.View.new()
				still.reduce_motion = true
				Painter.draw_player(_legend, at, still)
			"save":
				Painter.draw_save(_legend, at, 0.9)
			"refill":
				Painter.draw_refill(_legend, at, 0.9)
			"item":
				Painter.draw_item(_legend, at, view)
			"exit":
				_legend.draw_line(
					at + Vector2(-8, -9), at + Vector2(-8, 9), Painter.EXIT_COLOR, 4.0
				)
				_legend.draw_colored_polygon(
					PackedVector2Array(
						[at + Vector2(10, 0), at + Vector2(-2, -8), at + Vector2(-2, 8)]
					),
					Painter.EXIT_COLOR
				)
			"seal":
				Painter.draw_final_seal(_legend, at, 0.8, Vector2i(0, 2))
			"boss":
				Painter.draw_boss(_legend, at, 0.85, false)
			var glyph when String(glyph).begins_with("pin:"):
				Painter.draw_pin(
					_legend, at + Vector2(0, 8), String(glyph).trim_prefix("pin:"), 0.85
				)
			var kind:
				Painter.draw_gate_badge(_legend, at, StringName(kind), 0.85)


func _refresh_hint() -> void:
	if _travel != null:
		_hint.text = (
			"%s %s  SELECT     %s  TRAVEL     M  CANCEL"
			% [_first_key(&"move_left"), _first_key(&"move_right"), _first_key(&"jump")]
		)
		return
	var pins := (
		"%s  PIN %d/%d     %s  UNPIN"
		% [
			_first_key(&"fire_beam"),
			GameState.map_pins.size(),
			Pins.MAX_PINS,
			_first_key(&"fire_missile")
		]
	)
	_hint.text = "ARROWS  PAN     WHEEL  ZOOM     %s     R  CENTRE     M  CLOSE" % pins


func _first_key(action: StringName) -> String:
	var keys := Settings.keys_for(action)
	return Settings.key_name(keys[0]) if not keys.is_empty() else "-"
