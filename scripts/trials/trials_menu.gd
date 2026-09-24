extends Control
## Start-menu overlay listing the two Trials with their best times. Emits `chosen` with the mode;
## the start menu fades out and calls TrialsEntry.start. Menu text outside the game world.

signal closed
signal chosen(mode: StringName)

const Style = preload("res://scripts/ui/ui_style.gd")

var _buttons: Dictionary = {}
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
	panel.name = "TrialsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -480
	panel.offset_right = 480
	panel.offset_top = -200
	panel.offset_bottom = 200
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title := Style.label(column, "TRIALS", Style.SIZE_H1, Style.TEXT, 10)
	Style.glow(title, Style.ACCENT, 0.2, 6)
	var about := Style.label(
		column,
		"Full kit. Clear time and hits taken are recorded.",
		Style.SIZE_SMALL,
		Style.TEXT_MUTED
	)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Style.rule(column)
	for mode in TrialCatalog.MODES:
		var button := Button.new()
		button.name = "%sButton" % TrialCatalog.title(mode).replace(" ", "")
		button.custom_minimum_size = Vector2(760, 62)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void: chosen.emit(mode))
		column.add_child(button)
		_buttons[mode] = button
	Style.rule(column)
	_back = Button.new()
	_back.name = "TrialsBackButton"
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(220, 56)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back.pressed.connect(close)
	column.add_child(_back)
	hide()


func open(records: Dictionary) -> void:
	for mode in _buttons:
		var best := TrialRecords.best(records, mode)
		var shown := "-:--.--" if best.is_empty() else TrialRecords.format_time(best["time_ms"])
		(_buttons[mode] as Button).text = "%s  ·  best %s" % [TrialCatalog.title(mode), shown]
	show()
	(_buttons[TrialCatalog.GAUNTLET] as Button).grab_focus.call_deferred()


func close() -> void:
	hide()
	closed.emit()


func handle_back() -> bool:
	if not visible:
		return false
	close()
	return true
