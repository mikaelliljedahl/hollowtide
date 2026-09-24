extends CanvasLayer

## Save-shrine menu: one small panel listing what this shrine offers right now, "Travel" (fast
## travel, docs/features/fast-travel.md) and "Tide Sockets" (docs/features/tide-modules.md).
## Opened by CampaignRoot.open_shrine only when both are available; with a single option the root
## opens that screen directly. Pauses the tree while open; a choice closes the panel first and
## then emits `chosen`, so the next screen starts from the unpaused state.

signal chosen(option: StringName)

const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")
const TRAVEL := &"travel"
const TIDE := &"tide"
const LABELS: Dictionary[StringName, String] = {TRAVEL: "Travel", TIDE: "Tide Sockets"}
const PANEL_SIZE := Vector2(560, 0)

var _root: Control
var _panel: PanelContainer
var _buttons: VBoxContainer
var _hint: Label
var _options: Array[StringName] = []
var _open := false
var _was_paused := false


func _ready() -> void:
	layer = 42
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_open() -> bool:
	return _open


## The options shown, in display order (empty while closed).
func options() -> Array[StringName]:
	return _options.duplicate() if _open else []


func open(offered: Array[StringName]) -> void:
	if _open or offered.is_empty():
		return
	_open = true
	_options = offered.duplicate()
	_was_paused = get_tree().paused
	get_tree().paused = true
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for option in _options:
		var button := Button.new()
		button.name = "Option_%s" % option
		button.text = LABELS.get(option, String(option))
		button.custom_minimum_size = Vector2(0, 62)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(choose.bind(option))
		_buttons.add_child(button)
	_hint.text = (
		"%s %s  move        %s  choose        Esc  leave"
		% [_first_key(&"move_up"), _first_key(&"move_down"), _first_key(&"jump")]
	)
	_root.show()
	(_buttons.get_child(0) as Button).grab_focus.call_deferred()


## Closes the panel and emits `chosen`; false when `option` is not offered.
func choose(option: StringName) -> bool:
	if not _open or not _options.has(option):
		return false
	close()
	chosen.emit(option)
	return true


func close() -> void:
	if not _open:
		return
	_open = false
	_options.clear()
	_root.hide()
	get_tree().paused = _was_paused


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
		if focused != null and _buttons.is_ancestor_of(focused):
			focused.pressed.emit()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.name = "ShrineMenuRoot"
	_root.theme = Style.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(Style.BG_DEEP, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "ShrinePanel"
	_panel.add_theme_stylebox_override("panel", Style.panel_box())
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	Style.caption(column, "Save shrine")
	var line := Style.rule(column, 220)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_buttons = VBoxContainer.new()
	_buttons.name = "Options"
	_buttons.add_theme_constant_override("separation", 6)
	column.add_child(_buttons)
	_hint = Style.label(column, "", Style.SIZE_SMALL, Style.TEXT_FAINT, 2)
	_hint.name = "KeyHint"


func _step_focus(step: int) -> void:
	var count := _buttons.get_child_count()
	if count == 0:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var index := focused.get_index() if focused != null and focused.get_parent() == _buttons else -1
	var next := 0 if index < 0 else posmod(index + step, count)
	(_buttons.get_child(next) as Button).grab_focus()


func _first_key(action: StringName) -> String:
	var keys := Settings.keys_for(action)
	return Settings.key_name(keys[0]) if not keys.is_empty() else "-"
