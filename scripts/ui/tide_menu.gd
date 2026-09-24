extends CanvasLayer

## Save-shrine screen for socketing Tide Glyphs (docs/features/tide-modules.md). Opened by
## scripts/campaign/tide_hook.gd; pauses the tree and opens a GameState.tide station session so
## the loadout can change only here. Layout: title and capacity gauge on top, one full-width row
## per owned glyph with its gain and cost lines inline, no side pane.

signal closed(changed: bool)

const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TideCatalog = preload("res://scripts/progression/tide_catalog.gd")
const TideModules = preload("res://scripts/progression/tide_modules.gd")
const LEFT := 170.0
const ROW_WIDTH := 1180.0
const ROW_HEIGHT := 104.0
const FLASH_SECONDS := 0.45


## Capacity as slanted tide-mark segments: filled = used, outlined = free, faint = not found yet.
class Gauge:
	extends Control
	const SEGMENT := Vector2(58, 22)
	const STEP := 66.0
	const SLANT := 9.0
	var total := TideCatalog.MAX_CAPACITY
	var capacity := TideCatalog.BASE_CAPACITY
	var used := 0
	var flash := 0.0
	var unit := 1.0

	func _draw() -> void:
		var segment := SEGMENT * unit
		var slant := SLANT * unit
		for i in total:
			var x := i * STEP * unit
			var points := PackedVector2Array(
				[
					Vector2(x + slant, 0),
					Vector2(x + segment.x + slant, 0),
					Vector2(x + segment.x, segment.y),
					Vector2(x, segment.y),
				]
			)
			var outline := points.duplicate()
			outline.append(points[0])
			if i < used:
				var fill := Style.ACCENT.lerp(Style.DANGER, flash)
				draw_colored_polygon(points, fill)
				draw_line(points[0], points[1], Color(1, 1, 1, 0.5), 2.0)
			elif i < capacity:
				draw_colored_polygon(points, Color(Style.ACCENT, 0.08 + 0.3 * flash))
				draw_polyline(outline, Color(Style.ACCENT.lerp(Style.DANGER, flash), 0.8), 2.0)
			else:
				draw_polyline(outline, Color(Style.TEXT_FAINT, 0.35), 1.0)

	func _get_minimum_size() -> Vector2:
		return Vector2(total * STEP + SLANT, SEGMENT.y) * unit


var _root: Control
var _rows: VBoxContainer
var _gauge: Gauge
var _gauge_label: Label
var _empty_label: Label
var _hint: Label
var _buttons: Dictionary = {}
var _open := false
var _was_paused := false
var _initial: Array[StringName] = []
var _flash_tween: Tween


func _ready() -> void:
	layer = 42
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_tide().open_station()
	_initial = _tide().equipped.duplicate()
	_rebuild_rows()
	_hint.text = (
		"%s %s  move        %s  socket / release        Esc  leave"
		% [_first_key(&"move_up"), _first_key(&"move_down"), _first_key(&"jump")]
	)
	_root.show()
	var first := _rows.get_child(0) as Control if _rows.get_child_count() > 0 else null
	if first != null and first is Button:
		first.grab_focus.call_deferred()


func close() -> void:
	if not _open:
		return
	_open = false
	_tide().close_station()
	_root.hide()
	get_tree().paused = _was_paused
	closed.emit(_tide().equipped != _initial)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var key := event as InputEventKey
	var escape := key != null and key.pressed and key.physical_keycode == KEY_ESCAPE
	if escape or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_up") or event.is_action_pressed(&"move_down"):
		_step_focus(-1 if event.is_action_pressed(&"move_up") else 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"jump"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and _rows.is_ancestor_of(focused):
			focused.pressed.emit()
		get_viewport().set_input_as_handled()


func _step_focus(step: int) -> void:
	var count := _rows.get_child_count()
	if count == 0:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var index := focused.get_index() if focused != null and focused.get_parent() == _rows else -1
	var next := 0 if index < 0 else posmod(index + step, count)
	(_rows.get_child(next) as Button).grab_focus()


func _first_key(action: StringName) -> String:
	var keys := Settings.keys_for(action)
	return Settings.key_name(keys[0]) if not keys.is_empty() else "-"


## Toggles `id` as a menu press would; refused changes flash the gauge. Returns the result.
func press(id: StringName) -> bool:
	var ok := _tide().toggle(id)
	if not ok:
		_flash()
		var audio := get_node_or_null("/root/Audio")
		if audio != null:
			audio.call("play_sfx", &"flux_empty")
	_refresh()
	return ok


func _tide() -> TideModules:
	return GameState.tide


func _build() -> void:
	_root = Control.new()
	_root.name = "TideMenuRoot"
	_root.theme = Style.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(Style.BG_DEEP, 0.985)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var column := VBoxContainer.new()
	column.position = Vector2(LEFT, 120)
	column.custom_minimum_size.x = ROW_WIDTH
	column.add_theme_constant_override("separation", 12)
	_root.add_child(column)
	Style.caption(column, "Save shrine")
	var title := Style.label(column, "TIDE SOCKETS", 64, Style.TEXT, 14)
	Style.glow(title, Style.ACCENT, 0.2, 6)
	var line := Style.rule(column, 420)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var gauge_row := HBoxContainer.new()
	gauge_row.add_theme_constant_override("separation", 28)
	column.add_child(gauge_row)
	_gauge = Gauge.new()
	_gauge.name = "CapacityGauge"
	_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gauge_row.add_child(_gauge)
	_gauge_label = Style.label(gauge_row, "", Style.SIZE_BODY, Style.TEXT_MUTED, 3)
	_gauge_label.name = "CapacityLabel"

	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	column.add_child(gap)
	_rows = VBoxContainer.new()
	_rows.name = "GlyphRows"
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	_empty_label = Style.label(column, "No glyphs found yet.", Style.SIZE_BODY, Style.TEXT_FAINT)

	_hint = Style.label(_root, "", Style.SIZE_SMALL, Style.TEXT_FAINT, 2)
	_hint.name = "KeyHint"
	_hint.position = Vector2(LEFT, 1080 - 96)


func _rebuild_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for id: StringName in TideCatalog.GLYPHS:
		if _tide().owns(id):
			_rows.add_child(_row(id))
	_empty_label.visible = _buttons.is_empty()
	_refresh()


func _row(id: StringName) -> Button:
	var data: Dictionary = TideCatalog.GLYPHS[id]
	var button := Button.new()
	button.name = "Glyph_%s" % id
	button.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	button.pressed.connect(press.bind(id))
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 22
	body.offset_right = -28
	body.add_theme_constant_override("separation", 22)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(body)
	var icon := TextureRect.new()
	icon.texture = Catalog.pickup_texture(TideCatalog.pickup_kind(id))
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(text)
	var name_label := Style.label(text, String(data["name"]).to_upper(), 26, Style.TEXT, 3)
	name_label.name = "Name"
	Style.label(text, "+  " + String(data["upside"]), Style.SIZE_SMALL, Style.ACCENT)
	Style.label(text, "−  " + String(data["downside"]), Style.SIZE_SMALL, Style.WARN)
	var state := Style.label(body, "", Style.SIZE_SMALL, Style.ACCENT, 4)
	state.name = "State"
	state.custom_minimum_size.x = 150
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cost := Gauge.new()
	cost.name = "Cost"
	cost.total = int(data["cost"])
	cost.capacity = cost.total
	cost.unit = 0.55
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Fixed width for the largest cost keeps the cost column aligned across rows.
	cost.custom_minimum_size.x = 3 * Gauge.STEP * cost.unit
	body.add_child(cost)
	for child in body.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons[id] = button
	return button


func _refresh() -> void:
	var tide := _tide()
	_gauge.capacity = tide.capacity()
	_gauge.used = tide.used()
	_gauge.queue_redraw()
	_gauge_label.text = "%d / %d  CAPACITY" % [tide.used(), tide.capacity()]
	for id: StringName in _buttons:
		var button: Button = _buttons[id]
		var equipped := tide.is_equipped(id)
		var fits := equipped or tide.used() + TideCatalog.cost(id) <= tide.capacity()
		var state := button.find_child("State", true, false) as Label
		state.text = "SOCKETED" if equipped else ("" if fits else "NO ROOM")
		state.add_theme_color_override("font_color", Style.ACCENT if equipped else Style.TEXT_FAINT)
		var cost := button.find_child("Cost", true, false) as Gauge
		cost.used = cost.total if equipped else 0
		cost.queue_redraw()
		var name_label := button.find_child("Name", true, false) as Label
		name_label.add_theme_color_override("font_color", Style.TEXT if fits else Style.TEXT_FAINT)
		if equipped:
			var box := Style.panel_box(0.0)
			box.bg_color = Color(Style.ACCENT, 0.1)
			box.border_color = Style.ACCENT
			box.set_border_width_all(0)
			box.border_width_left = 4
			box.set_corner_radius_all(0)
			box.shadow_size = 0
			button.add_theme_stylebox_override("normal", box)
		else:
			button.remove_theme_stylebox_override("normal")


func _flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	_gauge.flash = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, FLASH_SECONDS)


func _set_flash(value: float) -> void:
	_gauge.flash = value
	_gauge.queue_redraw()
