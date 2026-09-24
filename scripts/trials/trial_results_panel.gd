extends Control
## Menu screen shown when a trial ends: clear time, hits taken and the stored best, with Retry and
## Title. Menu text outside the game world, styled like the other menus.

signal retry_pressed
signal title_pressed

const Style = preload("res://scripts/ui/ui_style.gd")

var _title: Label
var _time: Label
var _hits: Label
var _best: Label
var _note: Label
var _retry: Button
var _leave: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Style.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "ResultsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -460
	panel.offset_right = 460
	panel.offset_top = -210
	panel.offset_bottom = 210
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	_title = Style.label(column, "", Style.SIZE_H1, Style.TEXT, 10)
	_title.name = "ResultTitle"
	Style.glow(_title, Style.ACCENT, 0.2, 6)
	Style.rule(column)
	_time = _row(column, "ResultTime", "Clear time")
	_hits = _row(column, "ResultHits", "Hits taken")
	_best = _row(column, "ResultBest", "Best time")
	_note = Style.label(column, "", Style.SIZE_SMALL, Style.ACCENT)
	_note.name = "ResultNote"
	_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Style.rule(column)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	_retry = _button(buttons, "RetryButton", "Retry")
	_retry.pressed.connect(func() -> void: retry_pressed.emit())
	_leave = _button(buttons, "TitleButton", "Title")
	_leave.pressed.connect(func() -> void: title_pressed.emit())
	hide()


## `result`: mode, cleared, time_ms, hits, and for a clear previous (best before), new_best, saved.
func present(result: Dictionary) -> void:
	var mode := StringName(result.get("mode", &""))
	var cleared := bool(result.get("cleared", false))
	var time_ms := int(result.get("time_ms", 0))
	var hits := int(result.get("hits", 0))
	_title.text = (
		"%s %s" % [TrialCatalog.title(mode).to_upper(), "CLEARED" if cleared else "FAILED"]
	)
	_title.add_theme_color_override("font_color", Style.TEXT if cleared else Style.WARN)
	_time.text = TrialRecords.format_time(time_ms) if cleared else "--"
	_hits.text = str(hits)
	var previous: Dictionary = result.get("previous", {})
	var new_best := bool(result.get("new_best", false))
	var best := {"time_ms": time_ms, "hits": hits} if new_best else previous
	_best.text = (
		"--"
		if best.is_empty()
		else "%s  (%d hits)" % [TrialRecords.format_time(best["time_ms"]), best["hits"]]
	)
	_note.text = ""
	if new_best:
		_note.text = "New best time"
	elif cleared and int(result.get("saved", OK)) != OK:
		_note.text = "Best time could not be saved"
		_note.add_theme_color_override("font_color", Style.WARN)
	show()
	_retry.grab_focus.call_deferred()


## A stat row: muted name in a fixed-width column, then the value label (returned).
func _row(parent: Node, node_name: String, caption: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	parent.add_child(row)
	var name_label := Style.label(row, caption, Style.SIZE_BODY, Style.TEXT_MUTED)
	name_label.custom_minimum_size.x = 220
	var value := Style.label(row, "", Style.SIZE_BODY, Style.TEXT)
	value.name = node_name
	return value


func _button(parent: Node, node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(220, 56)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(button)
	return button
