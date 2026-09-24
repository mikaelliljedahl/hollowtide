extends Control

## Settings overlay shared by the start menu and the pause menu.

signal closed

const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")

const LABEL_WIDTH := 330
const SLOT_WIDTH := 210

var _first_focus: Control
var _back_button: Button
var _status: Label
var _scroll: ScrollContainer
var _slot_buttons: Dictionary = {}
var _capture_action: StringName = &""
var _capture_slot := -1
var _capture_frame := 0
var _return_focus: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Style.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()


func open() -> void:
	_cancel_capture()
	_refresh_bindings()
	show()
	_scroll.scroll_vertical = 0
	if _first_focus != null:
		_first_focus.grab_focus.call_deferred()


func close() -> void:
	_cancel_capture()
	hide()
	closed.emit()


## Returns true when the back request was consumed (e.g. cancelled a key capture).
func handle_back() -> bool:
	if not visible:
		return false
	if is_capturing():
		_cancel_capture()
		return true
	close()
	return true


func is_capturing() -> bool:
	return _capture_action != &""


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -470
	panel.offset_bottom = 470
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title := Style.label(column, "SETTINGS", Style.SIZE_H1, Style.TEXT, 10)
	Style.glow(title, Style.ACCENT, 0.2, 6)
	Style.rule(column)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_left", 4)
	_scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)

	_section(body, "Audio")
	_first_focus = _volume_row(body, "Master volume", "master")
	_volume_row(body, "Music", "music")
	_volume_row(body, "Effects", "sfx")
	_volume_row(body, "Ambience", "ambience")

	_section(body, "Display")
	var fullscreen := _toggle_row(body, "Fullscreen", Settings.fullscreen())
	fullscreen.toggled.connect(func(on: bool): Settings.set_setting("display", "fullscreen", on))

	_section(body, "Accessibility")
	_slider_row(
		body,
		"Screen shake",
		Settings.screen_shake(),
		func(v: float): Settings.set_setting("accessibility", "screen_shake", v)
	)
	var flashes := _toggle_row(body, "Reduce flashes", Settings.reduce_flashes())
	flashes.toggled.connect(
		func(on: bool): Settings.set_setting("accessibility", "reduce_flashes", on)
	)

	_section(body, "Controls")
	var hint := Style.label(
		body,
		"Select a slot, then press a key.  Esc cancels  ·  Backspace clears a slot.",
		Style.SIZE_SMALL,
		Style.TEXT_MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for entry in Settings.REBINDABLE_ACTIONS:
		_binding_row(body, entry[0], entry[1])
	var reset := Button.new()
	reset.name = "ResetControlsButton"
	reset.text = "Reset controls to defaults"
	reset.add_theme_font_size_override("font_size", Style.SIZE_BODY)
	reset.alignment = HORIZONTAL_ALIGNMENT_LEFT
	reset.pressed.connect(_reset_bindings)
	body.add_child(reset)
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size.y = 12
	body.add_child(bottom_pad)

	Style.rule(column)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	column.add_child(footer)
	_back_button = Button.new()
	_back_button.name = "SettingsBackButton"
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(220, 56)
	_back_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back_button.pressed.connect(close)
	footer.add_child(_back_button)
	_status = Style.label(footer, "", Style.SIZE_SMALL, Style.WARN)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _section(parent: Node, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 14
	parent.add_child(spacer)
	Style.caption(parent, title)


func _row(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.custom_minimum_size.y = 52
	parent.add_child(row)
	var name_label := Style.label(row, title, Style.SIZE_BODY, Style.TEXT)
	name_label.custom_minimum_size.x = LABEL_WIDTH
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


func _volume_row(parent: Node, title: String, key: String) -> HSlider:
	return _slider_row(
		parent, title, Settings.volume(key), func(v: float): Settings.set_setting("audio", key, v)
	)


func _slider_row(parent: Node, title: String, value: float, on_change: Callable) -> HSlider:
	var row := _row(parent, title)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = roundf(value * 100.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 30
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	var readout := Style.label(row, "%d%%" % int(slider.value), Style.SIZE_BODY, Style.TEXT_MUTED)
	readout.custom_minimum_size.x = 84
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slider.value_changed.connect(
		func(v: float):
			readout.text = "%d%%" % int(v)
			on_change.call(v / 100.0)
	)
	return slider


func _toggle_row(parent: Node, title: String, value: bool) -> CheckButton:
	var row := _row(parent, title)
	var toggle := CheckButton.new()
	toggle.button_pressed = value
	toggle.text = "On" if value else "Off"
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.custom_minimum_size.x = 170
	toggle.toggled.connect(func(on: bool): toggle.text = "On" if on else "Off")
	row.add_child(toggle)
	return toggle


func _binding_row(parent: Node, action: StringName, title: String) -> void:
	var row := _row(parent, title)
	row.custom_minimum_size.y = 50
	var slots: Array[Button] = []
	for slot in 2:
		var button := Button.new()
		button.name = "Bind_%s_%d" % [action, slot]
		button.custom_minimum_size = Vector2(SLOT_WIDTH, 46)
		button.add_theme_font_size_override("font_size", Style.SIZE_BODY)
		button.add_theme_stylebox_override("normal", _slot_box(false))
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(_begin_capture.bind(action, slot, button))
		row.add_child(button)
		slots.append(button)
	_slot_buttons[action] = slots


func _slot_box(active: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.5, 0.95, 0.88, 0.16) if active else Color(1, 1, 1, 0.035)
	box.border_color = Style.ACCENT if active else Color(1, 1, 1, 0.08)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	return box


func _refresh_bindings() -> void:
	for action in _slot_buttons:
		var keys := Settings.keys_for(action)
		var slots: Array = _slot_buttons[action]
		for slot in slots.size():
			var button: Button = slots[slot]
			button.add_theme_stylebox_override("normal", _slot_box(false))
			if slot < keys.size():
				button.text = Settings.key_name(keys[slot])
				button.add_theme_color_override("font_color", Style.TEXT)
			else:
				button.text = "—"
				button.add_theme_color_override("font_color", Style.TEXT_FAINT)


func _begin_capture(action: StringName, slot: int, button: Button) -> void:
	_refresh_bindings()
	_capture_action = action
	_capture_slot = slot
	_capture_frame = Engine.get_process_frames()
	_return_focus = button
	button.text = "Press a key…"
	button.add_theme_color_override("font_color", Style.ACCENT)
	button.add_theme_stylebox_override("normal", _slot_box(true))
	_status.text = ""


func _cancel_capture() -> void:
	if _capture_action == &"":
		return
	_capture_action = &""
	_capture_slot = -1
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if not visible or not is_capturing():
		return
	if not event is InputEventKey:
		if event is InputEventMouseButton or event is InputEventJoypadButton:
			if event.pressed:
				_cancel_capture()
				get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo or Engine.get_process_frames() == _capture_frame:
		return
	var code := int(event.physical_keycode)
	if code == 0:
		code = int(event.keycode)
	var action := _capture_action
	var slot := _capture_slot
	_capture_action = &""
	_capture_slot = -1
	if code == KEY_ESCAPE:
		_refresh_bindings()
	elif code == KEY_BACKSPACE or code == KEY_DELETE:
		if not Settings.clear_slot(action, slot):
			_status.text = "Each action needs at least one key."
		_refresh_bindings()
	elif Settings.RESERVED_KEYS.has(code):
		_status.text = "%s is reserved." % Settings.key_name(code)
		_refresh_bindings()
	else:
		var taken := Settings.rebind(action, slot, code)
		_refresh_bindings()
		if not taken.is_empty():
			_status.text = (
				"%s moved from %s." % [Settings.key_name(code), ", ".join(PackedStringArray(taken))]
			)
		_warn_unbound()
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()


func _warn_unbound() -> void:
	for entry in Settings.REBINDABLE_ACTIONS:
		if Settings.keys_for(entry[0]).is_empty():
			_status.text += ("  " if _status.text != "" else "") + "%s has no key." % entry[1]


func _reset_bindings() -> void:
	Settings.reset_bindings()
	_refresh_bindings()
	_status.text = "Controls reset to defaults."
