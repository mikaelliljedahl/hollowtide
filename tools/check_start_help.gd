extends SceneTree

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TestShutdown = preload("res://tools/test_shutdown.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_scene := load("res://scenes/ui/start_menu.tscn") as PackedScene
	_check(menu_scene != null, "start scene loads")
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		root.add_child(menu)
		await process_frame
		_check(menu.get_node_or_null("MenuPanel") != null, "menu builds panel")
		_check(menu.get_node_or_null("HelpPanel") != null, "menu builds help panel")
		_check(menu.get_node_or_null("Settings") != null, "menu builds settings")
		var column := menu.get_node("MenuPanel/MenuColumn")
		var menu_buttons := column.get_children()
		_check(_contains_button_text(menu_buttons, "New Game"), "new game button is present")
		_check(_contains_button_text(menu_buttons, "Settings"), "settings button is present")
		var help_button := _find_button(menu_buttons, "Controls")
		_check(help_button != null, "controls button is present")
		_check(_contains_button_text(menu_buttons, "Quit"), "quit button is present")
		var dev_mode := OS.get_cmdline_user_args().has("--dev-mode")
		_check(
			_contains_button_text(menu_buttons, "Dev Track") == dev_mode,
			"dev entry only in dev mode"
		)
		if help_button != null:
			help_button.emit_signal("pressed")
		await process_frame
		_check(menu.get_node("HelpPanel").visible, "menu help selection opens help")
		var help_text := _tree_text(menu.get_node("HelpPanel"))
		for control in [
			"ARROWS", "DOWN", "A", "SHIFT", "Z", "SPACE", "X", "C", "V", "Q", "F", "ESC"
		]:
			_check(help_text.contains(control), "menu help includes " + control)
		_check(help_text.contains("Z             Slipstream"), "menu help assigns Slipstream to Z")
		_check(help_text.contains("A / SPACE     Jump"), "menu help assigns jump to A and Space")
		_check_echo_help(help_text, "menu help")
		_check(not help_text.contains("A             Slipstream"), "no stale A Slipstream")
		menu.call("_hide_help")
		menu.queue_free()
		await process_frame

	var settings := load("res://scripts/ui/game_settings.gd")
	var jump_keys: Array = settings.keys_for(&"jump")
	settings.rebind(&"cycle_beam", 0, KEY_A)
	_check(_action_has_key("cycle_beam", KEY_A), "rebinding assigns the key")
	_check(not _action_has_key("jump", KEY_A), "rebinding removes the key from other actions")
	settings.reset_bindings()
	_check(settings.keys_for(&"jump") == jump_keys, "reset restores default bindings")
	_check(_action_has_key("cycle_beam", KEY_V), "reset restores V")

	var state := root.get_node_or_null("/root/GameState")
	_check(state != null, "GameState autoload exists")
	if state != null:
		state.reset_progress()
		_check(
			bool(state.call("validate_snapshot", state.call("snapshot"))),
			"clean snapshot validates without beam"
		)
		_check(bool(state.call("unlock_ability", &"beam")), "beam unlocks")
		_check(bool(state.call("collect_pickup", "check-ice", &"ice_beam")), "ice pickup applies")
		_check(state.get("active_beam") == &"ice", "ice pickup auto-equips")
		_check(
			bool(state.call("collect_pickup", "check-wave", &"wave_beam")), "wave pickup applies"
		)
		_check(state.get("active_beam") == &"wave", "wave pickup auto-equips")
		var invalid: Dictionary = state.call("snapshot").duplicate(true)
		invalid["active_beam"] = "ice"
		invalid["abilities"].erase("ice_beam")
		_check(not bool(state.call("validate_snapshot", invalid)), "unowned ice rejected")

	_check(InputMap.has_action("cycle_beam"), "V cycle action is registered")
	_check(_action_has_key("jump", KEY_A), "A is mapped to jump")
	_check(_action_has_key("slipstream", KEY_Z), "Z is mapped to Slipstream")
	_check(_action_has_key("jump", KEY_SPACE), "Space is mapped to jump")
	_check(_action_has_key("cycle_flux", KEY_Q), "Q is mapped to Flux select")
	_check(_action_has_key("activate_flux", KEY_F), "F is mapped to Flux activate")
	_check(not _action_has_key("slipstream", KEY_A), "A is removed from Slipstream")
	_check(not _action_has_key("jump", KEY_Z), "Z is removed from jump")
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	_check(hud_scene != null, "HUD scene loads")
	if hud_scene != null and state != null:
		var hud := hud_scene.instantiate()
		root.add_child(hud)
		await process_frame
		_check(
			not _tree_text(hud).contains("V cycle beam   ·   ESC help"),
			"HUD has no always-visible control instruction",
		)
		var pause := hud.get_node_or_null("PauseMenu")
		_check(pause != null, "HUD provides a pause menu")
		if pause != null:
			var esc := InputEventKey.new()
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			root.push_input(esc)
			await process_frame
			_check(paused and bool(pause.call("is_open")), "Esc opens the pause menu and pauses")
			root.push_input(esc)
			await process_frame
			_check(not paused and not bool(pause.call("is_open")), "Esc again resumes")
		hud.queue_free()

	if _failures.is_empty():
		print("check_start_help: PASS")
	else:
		for failure in _failures:
			push_error(failure)
		await TestShutdown.finish(self, 1)
		return
	await TestShutdown.finish(self)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_echo_help(help_text: String, surface: String) -> void:
	_check(help_text.contains("Echo Scan is one-shot"), surface + " identifies Echo as one-shot")
	_check(
		help_text.contains("F toggles Shield/Burst"),
		surface + " identifies Shield/Burst as toggles"
	)
	_check(
		help_text.contains("%d Flux" % Catalog.ECHO_SCAN_COST),
		surface + " derives the Echo Flux cost"
	)
	_check(
		help_text.contains("nearby enemies, bosses, pickups, gates, and stations"),
		surface + " describes Echo targets"
	)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _contains_button_text(nodes: Array[Node], fragment: String) -> bool:
	return _find_button(nodes, fragment) != null


func _find_button(nodes: Array[Node], fragment: String) -> Button:
	for node in nodes:
		if node is Button and node.text.contains(fragment):
			return node
	return null


func _tree_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += node.text
	elif node is Button:
		text += node.text
	for child in node.get_children():
		text += "\n" + _tree_text(child)
	return text
