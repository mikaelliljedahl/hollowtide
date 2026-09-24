extends CanvasLayer

## Pause menu usable from the dev level and campaign rooms.
## Instance res://scenes/ui/pause_menu.tscn once per room (the HUD adds one automatically when
## none exists). Esc / gamepad Start opens it; losing window focus opens it too.

signal opened
signal closed

const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const ControlsPanel = preload("res://scripts/ui/controls_panel.gd")
const ConfirmDialog = preload("res://scripts/ui/confirm_dialog.gd")
const TITLE_SCENE := "res://scenes/ui/start_menu.tscn"
const TITLE_META := &"hollowtide_returned_to_title"
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 2.6;
uniform vec4 tint : source_color = vec4(0.012, 0.03, 0.05, 0.64);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	float v = 1.0 - smoothstep(0.35, 1.05, length(SCREEN_UV - vec2(0.5)) * 1.3);
	COLOR = vec4(mix(c, tint.rgb, tint.a) * mix(0.6, 1.0, v), 1.0);
}
"""

var _root: Control
var _menu: Control
var _resume: Button
var _settings: Control
var _controls: Control
var _confirm: Control
var _was_paused := false
var _open := false


func _enter_tree() -> void:
	add_to_group("pause_menu")


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.apply_all()
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
	Settings.duck_music(true)
	_root.show()
	_menu.show()
	_resume.grab_focus.call_deferred()
	opened.emit()


func resume() -> void:
	if not _open:
		return
	if _settings.visible:
		_settings.call("close")
	_controls.hide()
	_confirm.hide()
	_root.hide()
	_open = false
	get_tree().paused = _was_paused
	Settings.duck_music(false)
	closed.emit()


func _build() -> void:
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.theme = Style.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	backdrop.material = material
	_root.add_child(backdrop)

	_menu = Control.new()
	_menu.name = "PauseMenuPanel"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu)
	var column := VBoxContainer.new()
	column.position = Vector2(170, 330)
	column.custom_minimum_size.x = 460
	column.add_theme_constant_override("separation", 10)
	_menu.add_child(column)
	var title := Style.label(column, "PAUSED", 72, Style.TEXT, 18)
	Style.glow(title, Style.ACCENT, 0.2, 6)
	var rule := Style.rule(column, 360)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	column.add_child(gap)
	_resume = _button(column, "Resume", resume)
	_resume.name = "ResumeButton"
	_button(column, "Settings", _show_settings).name = "SettingsButton"
	_button(column, "Controls", _show_controls).name = "ControlsButton"
	_button(column, "Quit to Title", _ask_quit).name = "QuitToTitleButton"

	_settings = SettingsMenu.new()
	_settings.name = "Settings"
	_root.add_child(_settings)
	_settings.closed.connect(_show_menu.bind("SettingsButton"))
	_controls = ControlsPanel.new()
	_controls.name = "Controls"
	_controls.dev_mode = _dev_mode()
	_root.add_child(_controls)
	_controls.closed.connect(_show_menu.bind("ControlsButton"))
	_confirm = ConfirmDialog.new()
	_confirm.name = "ConfirmQuit"
	_root.add_child(_confirm)
	_confirm.confirmed.connect(_quit_to_title)


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(420, 60)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _show_menu(focus_name: String) -> void:
	_menu.show()
	var target := _menu.find_child(focus_name, true, false) as Control
	if target != null:
		target.grab_focus.call_deferred()


func _show_settings() -> void:
	_menu.hide()
	_settings.call("open")


func _show_controls() -> void:
	_menu.hide()
	_controls.call("open")


func _ask_quit() -> void:
	(
		_confirm
		. call(
			"ask",
			"Quit to title?",
			"Progress since your last save will be lost.",
			"Quit to Title",
		)
	)


func _quit_to_title() -> void:
	_open = false
	get_tree().paused = false
	Settings.duck_music(false)
	Engine.set_meta(TITLE_META, true)
	get_tree().change_scene_to_file(TITLE_SCENE)


func _back() -> void:
	if bool(_confirm.call("handle_back")):
		return
	if bool(_settings.call("handle_back")):
		return
	if bool(_controls.call("handle_back")):
		return
	resume()


func _unhandled_input(event: InputEvent) -> void:
	var toggle := _is_pause_toggle(event)
	if _open:
		if toggle or event.is_action_pressed(&"ui_cancel"):
			_back()
			get_viewport().set_input_as_handled()
		return
	if toggle and _can_open():
		open()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not _open and _can_open() and not Settings.is_test_run():
			open()


func _is_pause_toggle(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_START
	return false


func _can_open() -> bool:
	if not is_inside_tree() or get_tree().paused:
		return false
	for panel in get_tree().get_nodes_in_group("dev_panel"):
		if panel.has_method("is_open") and panel.is_open():
			return false
	return true


func _dev_mode() -> bool:
	return OS.get_cmdline_args().has("--dev-mode") or OS.get_cmdline_user_args().has("--dev-mode")
