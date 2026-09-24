extends Control

## Controls reference built from the live InputMap (reflects rebinding). Menu-only text.

signal closed

const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")

var dev_mode := false
var _keys: Label
var _details: Label
var _back: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Style.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "HelpPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -400
	panel.offset_bottom = 400
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title := Style.label(column, "CONTROLS", Style.SIZE_H1, Style.TEXT, 10)
	Style.glow(title, Style.ACCENT, 0.2, 6)
	Style.rule(column)
	_keys = Style.label(column, "", Style.SIZE_BODY, Style.TEXT)
	_keys.name = "ControlsList"
	_keys.add_theme_font_override("font", Style.mono_font())
	_keys.add_theme_constant_override("line_spacing", 5)
	_details = Style.label(column, "", Style.SIZE_SMALL, Style.TEXT_MUTED)
	_details.name = "ControlsDetails"
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Style.rule(column)
	_back = Button.new()
	_back.name = "HelpBackButton"
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(220, 56)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back.pressed.connect(close)
	column.add_child(_back)
	refresh()
	hide()


func refresh() -> void:
	_keys.text = Settings.controls_help_text(dev_mode)
	_details.text = Settings.controls_detail_text()


func open() -> void:
	refresh()
	show()
	_back.grab_focus.call_deferred()


func close() -> void:
	hide()
	closed.emit()


func handle_back() -> bool:
	if not visible:
		return false
	close()
	return true
