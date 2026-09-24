extends Control

## Title screen: Continue / New Game / Settings / Controls / Quit (+ Dev Track with --dev-mode).

const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const ControlsPanel = preload("res://scripts/ui/controls_panel.gd")
const ConfirmDialog = preload("res://scripts/ui/confirm_dialog.gd")
const LEVEL_PATH := "res://scenes/levels/level_01.tscn"
const SPLASH_PATH := "res://assets/ui/splash.png"
const CAMPAIGN_ENTRY_PATH := "res://scripts/campaign/campaign_entry.gd"
const TITLE_META := &"hollowtide_returned_to_title"

var _menu_panel: Control
var _settings: Control
var _controls: Control
var _confirm: Control
var _fader: ColorRect
var _status: Label
var _buttons: Dictionary = {}
var _entry: Script
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	Settings.apply_all()
	_build_background()
	var returned := Engine.has_meta(TITLE_META) and bool(Engine.get_meta(TITLE_META))
	Engine.set_meta(TITLE_META, false)
	if _has_argument("--skip-splash") and not returned:
		call_deferred("_load_level")
		return
	_entry = _load_campaign_entry()
	_build_menu()
	_build_overlays()
	_build_fader()
	_play_menu_music()


# --- Layout -------------------------------------------------------------------


func _build_background() -> void:
	var base := ColorRect.new()
	base.color = Style.BG_DEEP
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var cover := TextureRect.new()
	cover.name = "Splash"
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := load(SPLASH_PATH) as Texture2D
	if texture != null:
		cover.texture = texture
		cover.modulate = Color(0.62, 0.74, 0.78, 1.0)
	add_child(cover)

	# Left-to-right shade so the menu column reads cleanly over the art.
	var shade := TextureRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.texture = _gradient_texture(
		[0.0, 0.34, 0.62, 1.0],
		[
			Color(0.01, 0.02, 0.035, 0.94),
			Color(0.01, 0.025, 0.04, 0.78),
			Color(0.01, 0.03, 0.05, 0.2),
			Color(0.01, 0.03, 0.05, 0.0)
		],
		false
	)
	add_child(shade)

	var vignette := TextureRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.texture = _gradient_texture(
		[0.0, 0.6, 1.0],
		[Color(0, 0, 0, 0), Color(0.0, 0.01, 0.02, 0.25), Color(0.0, 0.01, 0.02, 0.8)],
		true
	)
	add_child(vignette)

	var motes := CPUParticles2D.new()
	motes.name = "Motes"
	motes.position = Vector2(960, 1120)
	motes.amount = 70
	motes.lifetime = 16.0
	motes.preprocess = 16.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(1100, 40)
	motes.direction = Vector2(0.15, -1)
	motes.spread = 20.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 22.0
	motes.initial_velocity_max = 70.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 3.2
	motes.texture = _soft_dot()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
	ramp.colors = PackedColorArray(
		[
			Color(Style.ACCENT, 0.0),
			Color(Style.ACCENT, 0.4),
			Color(Style.ACCENT, 0.22),
			Color(Style.ACCENT, 0.0)
		]
	)
	motes.color_ramp = ramp
	add_child(motes)


func _build_menu() -> void:
	_menu_panel = Control.new()
	_menu_panel.name = "MenuPanel"
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_panel)

	var column := VBoxContainer.new()
	column.name = "MenuColumn"
	column.position = Vector2(170, 230)
	column.custom_minimum_size.x = 620
	column.add_theme_constant_override("separation", 8)
	_menu_panel.add_child(column)

	var title := Style.label(column, "HOLLOWTIDE", Style.SIZE_TITLE, Style.TEXT, 22)
	title.name = "Title"
	Style.glow(title, Style.ACCENT, 0.2, 6)
	var tagline := Style.label(column, "BENEATH THE SILENT SHORE", 20, Style.ACCENT_DIM, 9)
	tagline.name = "Tagline"
	tagline.add_theme_color_override("font_color", Color(Style.ACCENT, 0.62))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	column.add_child(gap)
	var rule := Style.rule(column, 420)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 34
	column.add_child(gap2)

	var has_save := _campaign_has_save()
	if has_save:
		_add_button(column, "ContinueButton", "Continue", _continue_game)
	_add_button(column, "NewGameButton", "New Game", _new_game)
	if _is_dev_mode():
		var dev := _add_button(column, "StartDevButton", "Dev Track", _start_dev)
		dev.add_theme_color_override("font_color", Color(Style.FLUX, 0.85))
		dev.add_theme_color_override("font_focus_color", Style.FLUX.lightened(0.3))
	_add_button(column, "SettingsButton", "Settings", _show_settings)
	_add_button(column, "HelpButton", "Controls", _show_help)
	_add_button(column, "QuitButton", "Quit", _quit_game)

	_status = Style.label(column, "", Style.SIZE_SMALL, Style.WARN)
	_status.name = "Status"
	_status.custom_minimum_size = Vector2(560, 34)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var footer := Style.label(
		_menu_panel,
		"Arrows  select     Enter  confirm     Esc  back",
		Style.SIZE_SMALL,
		Style.TEXT_FAINT,
		2
	)
	footer.name = "Footer"
	footer.position = Vector2(176, 1000)
	if _is_dev_mode():
		var dev_note := Style.label(
			_menu_panel, "DEV MODE", Style.SIZE_SMALL, Color(Style.FLUX, 0.7), 5
		)
		dev_note.position = Vector2(1700, 1000)

	for key in ["StartDevButton", "ContinueButton", "NewGameButton"]:
		if _buttons.has(key):
			(_buttons[key] as Control).grab_focus.call_deferred()
			break


func _add_button(parent: Node, node_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(440, 62)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_override("font", Style.spaced_font(3))
	button.add_theme_font_size_override("font_size", 30)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons[node_name] = button
	return button


func _build_overlays() -> void:
	_settings = SettingsMenu.new()
	_settings.name = "Settings"
	add_child(_settings)
	_settings.closed.connect(_show_menu.bind("SettingsButton"))
	_controls = ControlsPanel.new()
	_controls.name = "HelpPanel"
	_controls.dev_mode = _is_dev_mode()
	add_child(_controls)
	_controls.closed.connect(_show_menu.bind("HelpButton"))
	_confirm = ConfirmDialog.new()
	_confirm.name = "ConfirmNewGame"
	add_child(_confirm)
	_confirm.confirmed.connect(_begin_new_game)


func _build_fader() -> void:
	_fader = ColorRect.new()
	_fader.name = "Fader"
	_fader.color = Color(0, 0, 0, 1)
	_fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fader)
	var tween := create_tween()
	tween.tween_property(_fader, "color:a", 0.0, 0.6)


func _show_menu(focus_name: String) -> void:
	_menu_panel.show()
	if _buttons.has(focus_name):
		(_buttons[focus_name] as Control).grab_focus.call_deferred()


func _show_settings() -> void:
	_menu_panel.hide()
	_settings.call("open")


func _show_help() -> void:
	_menu_panel.hide()
	_controls.call("open")


func _hide_help() -> void:
	_controls.call("close")


# --- Campaign entry -------------------------------------------------------------


func _load_campaign_entry() -> Script:
	if not ResourceLoader.exists(CAMPAIGN_ENTRY_PATH):
		return null
	var script := load(CAMPAIGN_ENTRY_PATH) as Script
	if script == null:
		return null
	var names: Array[String] = []
	for method in script.get_script_method_list():
		names.append(String(method.get("name", "")))
	for required in ["has_save", "new_game", "continue_game"]:
		if not names.has(required):
			return null
	return script


func _campaign_has_save() -> bool:
	return _entry != null and bool(_entry.call("has_save"))


func _new_game() -> void:
	if _busy:
		return
	if _campaign_has_save():
		(
			_confirm
			. call(
				"ask",
				"Start a new game?",
				"Your saved progress will be overwritten. This cannot be undone.",
				"Overwrite Save",
			)
		)
		return
	_begin_new_game()


func _begin_new_game() -> void:
	if _entry == null:
		_load_level()
		return
	_transition(func(): _entry.call("new_game"))


func _continue_game() -> void:
	if _entry == null:
		_load_level()
		return
	_transition(func(): _entry.call("continue_game"))


func _start_dev() -> void:
	_load_level()


func _load_level() -> void:
	if _fader == null:
		if _busy:
			return
		_busy = true
		get_tree().change_scene_to_file(LEVEL_PATH)
		return
	_transition(func(): get_tree().change_scene_to_file(LEVEL_PATH))


func _transition(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fader, "color:a", 1.0, 0.35)
	tween.tween_callback(action)


func _quit_game() -> void:
	if _busy:
		return
	_busy = true
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("shutdown"):
		await audio.shutdown()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	for overlay in [_confirm, _settings, _controls]:
		if overlay != null and bool(overlay.call("handle_back")):
			get_viewport().set_input_as_handled()
			return


func _play_menu_music() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_music"):
		audio.call("play_music", &"cave_theme")


func _is_dev_mode() -> bool:
	return _has_argument("--dev-mode")


func _has_argument(argument: String) -> bool:
	return OS.get_cmdline_args().has(argument) or OS.get_cmdline_user_args().has(argument)


# --- Art helpers --------------------------------------------------------------


func _gradient_texture(offsets: Array, colors: Array, radial: bool) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 288
	if radial:
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.15, 1.15)
	else:
		texture.fill_from = Vector2(0, 0.5)
		texture.fill_to = Vector2(1, 0.5)
	return texture


func _soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
