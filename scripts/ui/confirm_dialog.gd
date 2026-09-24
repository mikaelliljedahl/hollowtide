extends Control

## Modal yes/no confirmation. Default focus is the safe (cancel) choice.

signal confirmed
signal cancelled

const Style = preload("res://scripts/ui/ui_style.gd")

var _title: Label
var _body: Label
var _confirm: Button
var _cancel: Button
var _return_focus: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Style.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.02, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "ConfirmPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -170
	panel.offset_bottom = 170
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	_title = Style.label(column, "", 34, Style.TEXT, 4)
	_body = Style.label(column, "", Style.SIZE_BODY, Style.TEXT_MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	_cancel = _button(buttons, "Cancel")
	_cancel.name = "CancelButton"
	_cancel.pressed.connect(_on_cancel)
	_confirm = _button(buttons, "Confirm")
	_confirm.name = "ConfirmButton"
	_confirm.add_theme_color_override("font_focus_color", Style.WARN)
	_confirm.add_theme_color_override("font_hover_color", Style.WARN)
	_confirm.pressed.connect(_on_confirm)
	hide()


func ask(title: String, body: String, confirm_text: String) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	_title.text = title
	_body.text = body
	_confirm.text = confirm_text
	show()
	_cancel.grab_focus.call_deferred()


func handle_back() -> bool:
	if not visible:
		return false
	_on_cancel()
	return true


func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 58)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func _on_confirm() -> void:
	hide()
	confirmed.emit()


func _on_cancel() -> void:
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	cancelled.emit()
