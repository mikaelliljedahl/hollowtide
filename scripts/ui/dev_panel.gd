class_name DevPanel
extends CanvasLayer

const Catalog = preload("res://scripts/progression/content_catalog.gd")

signal action_requested(action: StringName, data: Dictionary)

const ABILITY_LABELS := {
	&"beam": "Base Beam",
	&"slipstream": "Slipstream",
	&"missiles": "Harpoon",
	&"long_beam": "Focus Lens",
	&"ice_beam": "Bubble Snare",
	&"wave_beam": "Echo Shot",
	&"bombs": "Resonance Pulse / lift",
	&"high_jump": "Updraft Cloak",
	&"pressure_seal": "Pressure Seal",
	&"undertow_dash": "Undertow Dash",
	&"flux_shield": "Flux Shield",
	&"burst_beam": "Burst Beam",
	&"echo_scan": "Echo Scan",
}
const ENEMY_IDS: Array[StringName] = Catalog.ENEMY_IDS
const ENEMY_LABELS := {
	&"crawler": "Crawler",
	&"ceiling_diver": "Ceiling Diver",
	&"vent_flyer": "Vent Flyer",
	&"hopper": "Hopper",
	&"spitter": "Spitter",
	&"armored_guard": "Armored Guard",
	&"frost_floater": "Frost Floater",
	&"energy_parasite": "Leech Wisp",
	&"shard_turret": "Shard Turret",
	&"burrower": "Burrower",
	&"grasshopper": "Grasshopper",
	&"shooting_gargoyle": "Shooting Gargoyle",
	&"lava_monster": "Lava Monster",
}
const BOSS_IDS := [&"stone_guardian", &"furnace_mother", &"tidal_heart"]

var _panel: PanelContainer
var _status: Label
var _station: OptionButton
var _abilities: Dictionary = {}
var _energy_tanks: SpinBox
var _missile_tanks: SpinBox
var _health: SpinBox
var _ammo: SpinBox
var _flux_tanks: SpinBox
var _flux_current: SpinBox
var _beam: OptionButton
var _flux_module: OptionButton
var _flux_toggle: CheckButton
var _god: CheckButton
var _infinite_ammo: CheckButton
var _previous_pause := false
var _indicator: Label


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("dev_panel")
	layer = 30
	var theme := Theme.new()
	theme.default_font_size = 22
	_panel = PanelContainer.new()
	_panel.theme = theme
	_panel.position = Vector2(350, 54)
	_panel.size = Vector2(1220, 972)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.045, 0.065, 0.98)
	background.border_color = Color("568d94")
	background.set_border_width_all(2)
	background.set_corner_radius_all(12)
	background.content_margin_left = 28
	background.content_margin_right = 28
	background.content_margin_top = 22
	background.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", background)
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	_panel.add_child(rows)
	_label(rows, "HOLLOWTIDE  /  DEV TRACK", 30)
	_label(rows, "F1 closes panel. Changes use real game systems. Campaign saves are isolated.", 18)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	rows.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 540
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 540
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	_build_loadout(left)
	_build_stations(right)
	_status = _label(rows, "Ready. Choose a station or continue in the original cave.", 18)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 44
	_button(rows, "Return to Game  ·  F1", func(): set_open(false))
	_indicator = Label.new()
	_indicator.position = Vector2(36, 1036)
	_indicator.add_theme_font_size_override("font_size", 16)
	_indicator.modulate = Color(0.5, 0.71, 0.71, 0.75)
	_indicator.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_indicator.add_theme_constant_override("shadow_outline_size", 6)
	add_child(_indicator)
	_panel.hide()
	GameState.state_changed.connect(refresh)
	refresh()


func _build_loadout(parent: VBoxContainer):
	_label(parent, "LOADOUT", 22)
	var presets := HBoxContainer.new()
	parent.add_child(presets)
	_button(presets, "Start Preset", func(): _request(&"preset", {"id": &"start"}))
	_button(presets, "All Abilities", func(): _request(&"preset", {"id": &"all"}))
	var grid := GridContainer.new()
	grid.columns = 2
	parent.add_child(grid)
	for id in ABILITY_LABELS:
		var checkbox := CheckButton.new()
		checkbox.text = ABILITY_LABELS[id]
		checkbox.custom_minimum_size = Vector2(260, 38)
		checkbox.toggled.connect(
			func(enabled): _request(&"ability", {"id": id, "enabled": enabled})
		)
		grid.add_child(checkbox)
		_abilities[id] = checkbox
	_label(parent, "Capacity / Current Resource", 20)
	var tanks := HBoxContainer.new()
	parent.add_child(tanks)
	_energy_tanks = _number(tanks, "Heart Pearls", 6)
	_missile_tanks = _number(tanks, "Bolt Quivers", 12)
	_flux_tanks = _number(tanks, "Flux Tanks", Catalog.MAX_FLUX_TANKS)
	_button(
		parent,
		"Apply Capacity",
		func():
			_request(
				&"capacity",
				{
					"energy": int(_energy_tanks.value),
					"missiles": int(_missile_tanks.value),
					"flux_tanks": int(_flux_tanks.value),
				}
			)
	)
	var resources := HBoxContainer.new()
	parent.add_child(resources)
	_health = _number(resources, "Health", 700)
	_ammo = _number(resources, "Bolts", 60)
	_flux_current = _number(resources, "Flux", Catalog.MAX_FLUX)
	_button(
		parent,
		"Apply Resources",
		func():
			_request(
				&"resources",
				{
					"health": int(_health.value),
					"ammo": int(_ammo.value),
					"flux": int(_flux_current.value),
				}
			)
	)
	_button(parent, "Refill Health and Ammo", func(): _request(&"refill"))
	var beam_row := HBoxContainer.new()
	parent.add_child(beam_row)
	_label(beam_row, "Active Bolt", 20)
	_beam = OptionButton.new()
	for title in ["Seed Bolt", "Bubble Snare", "Echo Shot"]:
		_beam.add_item(title)
	_beam.item_selected.connect(
		func(index): _request(&"beam", {"id": [&"base", &"ice", &"wave"][index]})
	)
	beam_row.add_child(_beam)
	_label(parent, "Focus Lens is passive. Bubble Snare and Echo Shot cannot be combined.", 17)
	var flux_row := HBoxContainer.new()
	parent.add_child(flux_row)
	_label(flux_row, "Active Flux", 20)
	_flux_module = OptionButton.new()
	for id in Catalog.FLUX_ABILITY_IDS:
		_flux_module.add_item(String(id).replace("_", " ").to_upper())
	_flux_module.item_selected.connect(
		func(index): _request(&"flux_module", {"id": Catalog.FLUX_ABILITY_IDS[index]})
	)
	flux_row.add_child(_flux_module)
	_flux_toggle = CheckButton.new()
	_flux_toggle.text = "Flux ON"
	_flux_toggle.toggled.connect(func(enabled): _request(&"flux_toggle", {"enabled": enabled}))
	flux_row.add_child(_flux_toggle)


func _build_stations(parent: VBoxContainer):
	_label(parent, "STATIONS / BESTIARY", 22)
	_station = OptionButton.new()
	_station.custom_minimum_size.x = 520
	parent.add_child(_station)
	_button(
		parent,
		"Go to Station",
		func():
			_request(&"station", {"index": _station.selected})
			set_open(false)
	)
	var enemy := OptionButton.new()
	for id in ENEMY_IDS:
		enemy.add_item(ENEMY_LABELS.get(id, String(id)))
	parent.add_child(enemy)
	_button(
		parent,
		"Reset Arena + Spawn Enemy",
		func():
			_request(&"enemy", {"id": ENEMY_IDS[enemy.selected]})
			set_open(false)
	)
	var surprise := OptionButton.new()
	for id in SurpriseCatalog.IDS:
		surprise.add_item(SurpriseCatalog.label(id))
	parent.add_child(surprise)
	_button(
		parent,
		"Reset Arena + Spawn Surprise Enemy",
		func():
			_request(&"enemy", {"id": SurpriseCatalog.IDS[surprise.selected]})
			set_open(false)
	)
	var boss := OptionButton.new()
	for title in ["Stone Guardian", "Cinder Warden", "Tidal Heart"]:
		boss.add_item(title)
	parent.add_child(boss)
	var phase_choice := OptionButton.new()
	for title in ["Full Fight from Start", "Phase 1", "Phase 2"]:
		phase_choice.add_item(title)
	parent.add_child(phase_choice)
	_button(
		parent,
		"Reset Arena + Spawn Boss",
		func():
			_request(&"boss", {"id": BOSS_IDS[boss.selected], "phase": phase_choice.selected})
			set_open(false)
	)
	var reset_row := HBoxContainer.new()
	parent.add_child(reset_row)
	_button(reset_row, "Reset Station", func(): _request(&"reset", {"all": false}))
	_button(reset_row, "Reset Everything", func(): _request(&"reset", {"all": true}))
	var save_row := HBoxContainer.new()
	parent.add_child(save_row)
	_button(save_row, "Save Dev Profile", func(): _request(&"save"))
	_button(save_row, "Load Dev Profile", func(): _request(&"load"))
	_god = CheckButton.new()
	_god.text = "Invulnerable (off for acceptance tests)"
	_god.toggled.connect(func(_value): _send_cheats())
	parent.add_child(_god)
	_infinite_ammo = CheckButton.new()
	_infinite_ammo.text = "Infinite Ammo"
	_infinite_ammo.toggled.connect(func(_value): _send_cheats())
	parent.add_child(_infinite_ammo)
	var overlay := CheckButton.new()
	overlay.text = "Show Physics / Test Status"
	overlay.toggled.connect(func(enabled): _request(&"overlay", {"enabled": enabled}))
	parent.add_child(overlay)
	_label(
		parent,
		(
			(
				"Arrows · move / aim · Down crouch · Z Slipstream · Left Shift run · B dash\n"
				+ "A/Space jump · X shoot or pulse in ball / low shot while crouched\n"
				+ "C harpoon · V cycle bolt · Q cycle Flux · F activate Flux\n"
				+ "F toggles Shield/Burst. Echo Scan is one-shot: F spends %d Flux to mark nearby "
				+ "enemies, bosses, pickups, gates, and stations.\n"
				+ "Esc pause/help · F1 close panel\n"
				+ "Up at checkpoint saves position · J alternate bolt · K alternate harpoon · L alternate dash"
			)
			% Catalog.ECHO_SCAN_COST
		),
		17
	)


func _send_cheats():
	_request(&"cheats", {"god": _god.button_pressed, "ammo": _infinite_ammo.button_pressed})


func set_stations(names: Array[String]):
	_station.clear()
	for title in names:
		_station.add_item(title)


func set_status(message: String):
	_status.text = message


func refresh():
	if not is_instance_valid(_panel):
		return
	for id in _abilities:
		_abilities[id].set_pressed_no_signal(GameState.has_ability(id))
	_energy_tanks.set_value_no_signal((GameState.max_health - 100) / 100)
	_missile_tanks.set_value_no_signal(GameState.max_missiles / 5)
	_flux_tanks.set_value_no_signal(GameState.flux_tanks)
	_health.max_value = GameState.max_health
	_health.set_value_no_signal(GameState.health)
	_ammo.max_value = GameState.max_missiles
	_ammo.set_value_no_signal(GameState.missile_count)
	_flux_current.max_value = GameState.flux_max
	_flux_current.set_value_no_signal(GameState.flux_current)
	_beam.select([&"base", &"ice", &"wave"].find(GameState.active_beam))
	_flux_module.select(Catalog.FLUX_ABILITY_IDS.find(GameState.active_flux_module))
	_flux_toggle.set_pressed_no_signal(GameState.flux_enabled)
	_indicator.text = "DEV  ·  F1 tools"
	if _god.button_pressed or _infinite_ammo.button_pressed:
		_indicator.text += "  ·  CHEATS ACTIVE"


func is_open() -> bool:
	return is_instance_valid(_panel) and _panel.visible


func set_open(open: bool):
	if open == _panel.visible:
		return
	if open:
		_previous_pause = get_tree().paused
		get_tree().paused = true
		refresh()
	else:
		get_tree().paused = _previous_pause
	_panel.visible = open


func _unhandled_key_input(event: InputEvent):
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_F1
	):
		set_open(not _panel.visible)
		get_viewport().set_input_as_handled()


func _request(action: StringName, data: Dictionary = {}):
	action_requested.emit(action, data)
	refresh()


func _label(parent: Node, text: String, size: int):
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable):
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _number(parent: Node, title: String, maximum: int):
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 255
	parent.add_child(column)
	_label(column, title, 18)
	var spin := SpinBox.new()
	spin.max_value = maximum
	spin.step = 1
	column.add_child(spin)
	return spin
