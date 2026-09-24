extends RefCounted

## Player settings persisted in user://settings.cfg (format owned by the ui lane).
##
## [audio]          master, music, sfx, ambience : float 0..1 (linear)
## [display]        fullscreen : bool
## [accessibility]  screen_shake : float 0..1, reduce_flashes : bool
## [assist]         game_speed : float 0.5..1, damage_taken : float 0..1, skip_ambushes : bool
## [input]          <action> : Array[int] of physical keycodes (only present after rebinding)
##
## Accessibility values are mirrored at runtime to ProjectSettings
## "accessibility/screen_shake" and "accessibility/reduce_flashes" so other systems can read
## them without depending on this script. Assist values are mirrored to "assist/<key>" the same
## way and read through scripts/progression/assist.gd.

const Assist = preload("res://scripts/progression/assist.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")

const PATH := "user://settings.cfg"
const VOLUME_BUSES := {
	"master": &"Master",
	"music": &"Music",
	"sfx": &"SFX",
	"ambience": &"Ambience",
}
const REBINDABLE_ACTIONS := [
	[&"move_left", "Move left"],
	[&"move_right", "Move right"],
	[&"move_up", "Aim up"],
	[&"move_down", "Crouch / aim down"],
	[&"jump", "Jump"],
	[&"run", "Run (hold)"],
	[&"dash", "Undertow Dash"],
	[&"slipstream", "Slipstream"],
	[&"fire_beam", "Beam / pulse"],
	[&"fire_missile", "Harpoon"],
	[&"cycle_beam", "Cycle beam"],
	[&"cycle_flux", "Cycle Flux module"],
	[&"activate_flux", "Activate Flux"],
]
const RESERVED_KEYS := [KEY_ESCAPE, KEY_F1]
const PAUSE_MUSIC_DUCK_DB := -9.0

static var _config: ConfigFile
static var _applied := false
static var _music_ducked := false


static func config() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(PATH)
	return _config


static func get_setting(section: String, key: String, default: Variant) -> Variant:
	return config().get_value(section, key, default)


static func set_setting(section: String, key: String, value: Variant) -> void:
	config().set_value(section, key, value)
	save()
	match section:
		"audio":
			apply_volume(key)
		"display":
			apply_display()
		"accessibility":
			apply_accessibility()
		"assist":
			apply_assist()


static func save() -> void:
	config().save(PATH)


## Applies everything once per process; safe to call from every menu/HUD entry point.
static func apply_all(force: bool = false) -> void:
	if _applied and not force:
		return
	_applied = true
	for key in VOLUME_BUSES:
		apply_volume(key)
	apply_display()
	apply_accessibility()
	apply_assist()
	apply_bindings()


# --- Audio -------------------------------------------------------------------


static func volume(key: String) -> float:
	return clampf(float(get_setting("audio", key, 1.0)), 0.0, 1.0)


static func bus_exists(key: String) -> bool:
	return AudioServer.get_bus_index(VOLUME_BUSES.get(key, &"")) >= 0


static func apply_volume(key: String) -> void:
	var index := AudioServer.get_bus_index(VOLUME_BUSES.get(key, &""))
	if index < 0:
		return
	var linear := volume(key)
	var db := linear_to_db(maxf(linear, 0.0001))
	if key == "music" and _music_ducked:
		db += PAUSE_MUSIC_DUCK_DB
	AudioServer.set_bus_volume_db(index, db)
	AudioServer.set_bus_mute(index, linear <= 0.001)


## Pause menu lowers music while open.
static func duck_music(ducked: bool) -> void:
	_music_ducked = ducked
	apply_volume("music")


# --- Display / accessibility ------------------------------------------------


static func fullscreen() -> bool:
	return bool(get_setting("display", "fullscreen", false))


static func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or is_test_run():
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	if fullscreen() and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen() and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


static func screen_shake() -> float:
	return clampf(float(get_setting("accessibility", "screen_shake", 1.0)), 0.0, 1.0)


static func reduce_flashes() -> bool:
	return bool(get_setting("accessibility", "reduce_flashes", false))


static func apply_accessibility() -> void:
	ProjectSettings.set_setting("accessibility/screen_shake", screen_shake())
	ProjectSettings.set_setting("accessibility/reduce_flashes", reduce_flashes())


static func assist_value(key: String) -> Variant:
	var full := "assist/" + key
	return get_setting("assist", key, Assist.DEFAULTS[full])


static func apply_assist() -> void:
	for full in Assist.DEFAULTS:
		ProjectSettings.set_setting(full, assist_value(String(full).trim_prefix("assist/")))
	if not is_test_run():
		Assist.apply_game_speed()


static func is_test_run() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return args.has("--test-mode") or args.has("--benchmark-cave")


# --- Input -------------------------------------------------------------------


static func action_label(action: StringName) -> String:
	for entry in REBINDABLE_ACTIONS:
		if entry[0] == action:
			return entry[1]
	return String(action)


static func keys_for(action: StringName) -> Array[int]:
	var keys: Array[int] = []
	if not InputMap.has_action(action):
		return keys
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code := int(event.physical_keycode)
			if code == 0:
				code = int(event.keycode)
			if code != 0 and not keys.has(code):
				keys.append(code)
	return keys


static func apply_bindings() -> void:
	var cfg := config()
	if not cfg.has_section("input"):
		return
	for entry in REBINDABLE_ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action) or not cfg.has_section_key("input", String(action)):
			continue
		var stored: Variant = cfg.get_value("input", String(action), [])
		if not stored is Array:
			continue
		var codes: Array[int] = []
		for value in stored:
			if (value is int or value is float) and int(value) > 0:
				codes.append(int(value))
		_set_keys(action, codes)


## Binds [param code] into [param slot] of [param action]. Removes the key from any other
## rebindable action and returns the labels of the actions it was taken from.
static func rebind(action: StringName, slot: int, code: int) -> Array[String]:
	var taken_from: Array[String] = []
	if RESERVED_KEYS.has(code) or not InputMap.has_action(action):
		return taken_from
	for entry in REBINDABLE_ACTIONS:
		var other: StringName = entry[0]
		if other == action:
			continue
		var other_keys := keys_for(other)
		if other_keys.has(code):
			other_keys.erase(code)
			_set_keys(other, other_keys)
			taken_from.append(entry[1])
	var keys := keys_for(action)
	keys.erase(code)
	if slot < keys.size():
		keys[slot] = code
	else:
		keys.append(code)
	_set_keys(action, keys)
	_store_bindings()
	return taken_from


## Clears one slot; refuses to leave the action without any key.
static func clear_slot(action: StringName, slot: int) -> bool:
	var keys := keys_for(action)
	if slot >= keys.size() or keys.size() <= 1:
		return false
	keys.remove_at(slot)
	_set_keys(action, keys)
	_store_bindings()
	return true


static func reset_bindings() -> void:
	InputMap.load_from_project_settings()
	var cfg := config()
	if cfg.has_section("input"):
		cfg.erase_section("input")
	save()


static func _set_keys(action: StringName, codes: Array[int]) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	for code in codes:
		var event := InputEventKey.new()
		event.physical_keycode = code as Key
		InputMap.action_add_event(action, event)


static func _store_bindings() -> void:
	var cfg := config()
	for entry in REBINDABLE_ACTIONS:
		cfg.set_value("input", String(entry[0]), keys_for(entry[0]))
	save()


static func key_name(code: int) -> String:
	match code:
		KEY_SHIFT:
			return "SHIFT"
		KEY_CTRL:
			return "CTRL"
		KEY_ALT:
			return "ALT"
		KEY_ESCAPE:
			return "ESC"
		KEY_ENTER:
			return "ENTER"
		KEY_BACKSPACE:
			return "BACKSPACE"
	var name := OS.get_keycode_string(code as Key)
	return name.to_upper() if name != "" else "KEY %d" % code


static func keys_text(action: StringName, separator: String = " / ") -> String:
	# Short names (letters) first, stable otherwise: "A / SPACE", "X / J".
	var names: PackedStringArray = []
	for code in keys_for(action):
		var name := key_name(code)
		var index := names.size()
		while index > 0 and names[index - 1].length() > name.length():
			index -= 1
		names.insert(index, name)
	return separator.join(names) if not names.is_empty() else "—"


# --- Controls help (pause + start menu) ---------------------------------------


static func controls_help_text(dev_mode: bool) -> String:
	var rows: Array = []
	rows.append([_movement_keys(), "Move / aim"])
	rows.append([_first_key(&"move_down"), "Crouch"])
	rows.append([keys_text(&"slipstream"), "Slipstream"])
	rows.append([keys_text(&"run"), "Run (hold)"])
	rows.append(["", ""])
	rows.append([keys_text(&"jump"), "Jump"])
	rows.append([keys_text(&"fire_beam"), "Beam / pulse / low shot"])
	rows.append([keys_text(&"fire_missile"), "Harpoon"])
	rows.append([keys_text(&"dash"), "Undertow Dash"])
	rows.append([keys_text(&"cycle_beam"), "Cycle beam"])
	rows.append([keys_text(&"cycle_flux"), "Cycle Flux module"])
	rows.append([keys_text(&"activate_flux"), "Activate / toggle Flux"])
	rows.append(["", ""])
	rows.append(["ESC", "Pause"])
	if dev_mode:
		rows.append(["F1", "Dev panel"])
	var lines: PackedStringArray = []
	for row in rows:
		var key: String = row[0]
		if key == "" and row[1] == "":
			lines.append("")
			continue
		lines.append(key.rpad(maxi(14, key.length() + 2)) + String(row[1]))
	return "\n".join(lines)


static func controls_detail_text() -> String:
	var flux_key := _first_key(&"activate_flux")
	return (
		(
			"%s cycles owned bolts: Seed Bolt, Bubble Snare, and Echo Shot. Focus Lens is passive.\n"
			+ "%s toggles Shield/Burst. Echo Scan is one-shot: %s spends %d Flux to mark nearby "
			+ "enemies, bosses, pickups, gates, and stations.\n"
			+ "%s on a save shrine opens its menu: Travel between used shrines, and Tide Sockets "
			+ "once a glyph is found."
		)
		% [
			_first_key(&"cycle_beam"),
			flux_key,
			flux_key,
			Catalog.ECHO_SCAN_COST,
			_first_key(&"move_up"),
		]
	)


static func _first_key(action: StringName) -> String:
	var keys := keys_for(action)
	return key_name(keys[0]) if not keys.is_empty() else "—"


static func _movement_keys() -> String:
	var firsts: Array[int] = []
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		var keys := keys_for(action)
		firsts.append(keys[0] if not keys.is_empty() else 0)
	if firsts == [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		return "ARROWS"
	var names: PackedStringArray = []
	for code in firsts:
		names.append(key_name(code) if code != 0 else "—")
	return " ".join(names)
