extends CanvasLayer

## Compact in-game HUD (top-left): energy with Heart Pearl pips, harpoon bolts, selected beam, Flux.
## Player-visible names/icons follow the D19 mapping in ContentCatalog (internal ids unchanged).
## Every value has a shape/text signal in addition to colour.

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const Style = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/ui/game_settings.gd")
const PAUSE_MENU_PATH := "res://scenes/ui/pause_menu.tscn"
const ICON_DIR := "res://assets/sprites/devmode/"

const ORIGIN := Vector2(32, 26)
const GAP := 12.0
const PLATE_HEIGHT := 84.0
const ENERGY_WIDTH := 384.0
const SMALL_WIDTH := 156.0
const LOW_ENERGY := 30

const ENERGY_COLOR := Color("8fe6d8")
const BEAM_NAMES := {&"base": "POWER", &"ice": "BUBBLE", &"wave": "ECHO"}
const BEAM_ICONS := {&"base": "beam", &"ice": "ice_beam", &"wave": "wave_beam"}
const BEAM_COLORS := {&"base": Color("f2c46d"), &"ice": Color("8fd8ff"), &"wave": Color("b59bff")}


class Meter:
	extends Control
	var ratio := 1.0
	var ghost := 1.0
	var fill := Color.WHITE
	var ticks := 10

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.03, 0.07, 0.09, 0.9)
		back.border_color = Color(1, 1, 1, 0.1)
		back.set_border_width_all(1)
		back.set_corner_radius_all(3)
		draw_style_box(back, r)
		var inner := r.grow(-2)
		if ghost > ratio:
			draw_rect(
				Rect2(inner.position, Vector2(inner.size.x * ghost, inner.size.y)),
				Color(1.0, 0.62, 0.55, 0.5)
			)
		if ratio > 0.0:
			var bar := StyleBoxFlat.new()
			bar.bg_color = fill
			bar.set_corner_radius_all(2)
			draw_style_box(bar, Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)))
			draw_rect(
				Rect2(inner.position, Vector2(inner.size.x * ratio, 1.0)), Color(1, 1, 1, 0.35)
			)
		for i in range(1, ticks):
			var x := inner.position.x + inner.size.x * float(i) / ticks
			draw_line(
				Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.35), 1.0
			)


class Pips:
	extends Control
	const PIP := Vector2(15, 11)
	const STEP := 20.0
	var total := 0
	var filled := 0
	var color := Color.WHITE

	func _draw() -> void:
		for i in total:
			var rect := Rect2(Vector2(i * STEP, 0), PIP)
			var box := StyleBoxFlat.new()
			box.set_corner_radius_all(2)
			if i < filled:
				box.bg_color = color
				box.border_color = color.lightened(0.4)
			else:
				box.bg_color = Color(0, 0, 0, 0.35)
				box.border_color = Color(color, 0.45)
			box.set_border_width_all(1)
			draw_style_box(box, rect)

	func _get_minimum_size() -> Vector2:
		return Vector2(maxf(total * STEP - (STEP - PIP.x), 0.0), PIP.y)


var _energy_plate: Panel
var _low_tag: Label
var _pips: Pips
var _energy_value: Label
var _energy_bar: Meter
var _flux_icon: TextureRect
var _flux_bar: ProgressBar
var _flux_label: Label
var _missile_plate: Panel
var _missile_value: Label
var _missile_max: Label
var _beam_plate: Panel
var _beam_icon: TextureRect
var _beam_label: Label
var _feedback_label: Label
var _feedback_tween: Tween
var _ghost_tween: Tween
var _last_health := -1
var _plate_offsets: Dictionary = {}
var _low := false
var _pulse := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	for pair in _signal_pairs():
		if not pair[0].is_connected(pair[1]):
			pair[0].connect(pair[1])
	_refresh_loadout()
	_ensure_pause_menu()


func _exit_tree() -> void:
	for pair in _signal_pairs():
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _signal_pairs() -> Array:
	return [
		[GameState.health_changed, _on_value_changed],
		[GameState.state_changed, _refresh_loadout],
		[GameState.ammo_changed, _on_value_changed],
		[GameState.pickup_feedback, _on_pickup_feedback],
		[GameState.flux_changed, _on_value_changed],
	]


func _ensure_pause_menu() -> void:
	if not get_tree().get_nodes_in_group("pause_menu").is_empty():
		return
	var scene := load(PAUSE_MENU_PATH) as PackedScene
	if scene != null:
		var menu := scene.instantiate()
		menu.name = "PauseMenu"
		add_child(menu)


# --- Build --------------------------------------------------------------------


func _build() -> void:
	_energy_plate = _plate("HealthPanel", Vector2(ENERGY_WIDTH, PLATE_HEIGHT))
	_text(_energy_plate, "VITALITY", 15, Style.TEXT_MUTED, Vector2(18, 10), 4)
	_pips = Pips.new()
	_pips.name = "EnergyTanks"
	_pips.position = Vector2(112, 14)
	_pips.color = ENERGY_COLOR
	_energy_plate.add_child(_pips)
	_low_tag = _text(_energy_plate, "LOW", 15, Style.DANGER, Vector2(0, 10), 4)
	_low_tag.name = "LowEnergy"
	_low_tag.hide()
	# LoadoutLabel / FluxMeter / FluxStatus stay HUD-root children (stable node paths for
	# checks); _layout() keeps them positioned on the energy plate.
	_energy_value = _text(self, "100", 40, Style.TEXT, Vector2.ZERO)
	_energy_value.name = "LoadoutLabel"
	_plate_offsets[_energy_value] = Vector2(14, 26)
	_energy_value.size.x = 80
	_energy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_energy_bar = Meter.new()
	_energy_bar.name = "HealthMeter"
	_energy_bar.position = Vector2(110, 46)
	_energy_bar.size = Vector2(ENERGY_WIDTH - 128, 16)
	_energy_bar.fill = ENERGY_COLOR
	_energy_plate.add_child(_energy_bar)

	_flux_icon = TextureRect.new()
	_flux_icon.name = "FluxIcon"
	_flux_icon.position = Vector2(16, 82)
	_flux_icon.size = Vector2(28, 28)
	_flux_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flux_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flux_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_plate.add_child(_flux_icon)
	_flux_bar = ProgressBar.new()
	_flux_bar.name = "FluxMeter"
	_flux_bar.show_percentage = false
	_flux_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_offsets[_flux_bar] = Vector2(52, 92)
	_flux_bar.size = Vector2(150, 9)
	_flux_bar.add_theme_stylebox_override("background", _flat(Color(0.05, 0.06, 0.12, 0.9), 3))
	_flux_bar.add_theme_stylebox_override("fill", _flat(Style.FLUX, 3))
	add_child(_flux_bar)
	_flux_label = _text(self, "", 15, Style.FLUX.lightened(0.3), Vector2.ZERO, 1)
	_flux_label.name = "FluxStatus"
	_plate_offsets[_flux_label] = Vector2(214, 84)

	_missile_plate = _plate("MissilePanel", Vector2(SMALL_WIDTH, PLATE_HEIGHT))
	_icon(_missile_plate, "missiles", Vector2(8, 16), 52)
	_missile_value = _text(_missile_plate, "0", 32, Style.TEXT, Vector2(64, 12))
	_missile_value.name = "MissileLabel"
	_missile_max = _text(_missile_plate, "/ 0", 15, Style.TEXT_MUTED, Vector2(66, 52), 1)
	_missile_max.name = "MissileMax"

	_beam_plate = _plate("BeamPanel", Vector2(SMALL_WIDTH, PLATE_HEIGHT))
	_beam_icon = _icon(_beam_plate, "beam", Vector2(6, 14), 56)
	_text(_beam_plate, "BOLT", 13, Style.TEXT_MUTED, Vector2(68, 18), 3)
	_beam_label = _text(_beam_plate, "POWER", 20, Style.TEXT, Vector2(68, 38), 2)
	_beam_label.name = "BeamLabel"

	_feedback_label = _text(self, "", 20, Style.ACCENT, Vector2.ZERO, 1)
	_feedback_label.name = "PickupFeedback"
	_feedback_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_feedback_label.add_theme_constant_override("shadow_offset_x", 2)
	_feedback_label.add_theme_constant_override("shadow_offset_y", 2)
	_feedback_label.modulate.a = 0.0


func _plate(node_name: String, plate_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.size = plate_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _flat(Color(0.015, 0.035, 0.055, 0.74), 10)
	style.border_color = Color(Style.ACCENT, 0.16)
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _text(
	parent: Node, value: String, font_size: int, color: Color, at: Vector2, spacing: int = 0
) -> Label:
	var label := Style.label(parent, value, font_size, color, spacing)
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _icon(parent: Node, id: String, at: Vector2, edge: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.position = at
	rect.size = Vector2(edge, edge)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = _icon_texture(id)
	parent.add_child(rect)
	return rect


func _icon_texture(id: String) -> Texture2D:
	var path := Catalog.pickup_icon_path(StringName(id))
	if path.is_empty():
		path = ICON_DIR + id + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


# --- State --------------------------------------------------------------------


func _on_value_changed(_current: int, _maximum: int) -> void:
	_refresh_loadout()


func _has_flux_ability() -> bool:
	for id in Catalog.FLUX_ABILITY_IDS:
		if GameState.has_ability(id):
			return true
	return false


func _refresh_loadout() -> void:
	if not is_instance_valid(_energy_plate):
		return
	_refresh_energy()
	_refresh_flux()
	_refresh_missiles()
	_refresh_beam()
	_layout()


func _refresh_energy() -> void:
	var health: int = GameState.health
	var tanks: int = GameState.energy_tanks
	var full_reserve := 0
	if health > 0:
		full_reserve = clampi((health - 1) / Catalog.ENERGY_PER_TANK, 0, tanks)
	var segment := health - full_reserve * Catalog.ENERGY_PER_TANK
	var segment_max: int = (
		Catalog.DEFAULT_MAX_HEALTH if full_reserve == 0 else Catalog.ENERGY_PER_TANK
	)
	_energy_value.text = str(segment)
	_pips.total = tanks
	_pips.filled = full_reserve
	_pips.visible = tanks > 0
	_pips.size = _pips.get_minimum_size()
	_pips.queue_redraw()
	var ratio := clampf(float(segment) / float(maxi(segment_max, 1)), 0.0, 1.0)
	if _last_health >= 0 and health < _last_health:
		_energy_bar.ghost = maxf(_energy_bar.ghost, _energy_bar.ratio)
		if _ghost_tween != null:
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(0.25)
		_ghost_tween.tween_method(_set_ghost, _energy_bar.ghost, ratio, 0.45)
	elif _ghost_tween == null or not _ghost_tween.is_running():
		_energy_bar.ghost = ratio
	_last_health = health
	_energy_bar.ratio = ratio
	_low = full_reserve == 0 and segment <= LOW_ENERGY
	_energy_bar.fill = Style.DANGER if _low else ENERGY_COLOR
	_energy_bar.queue_redraw()
	_low_tag.visible = _low
	_low_tag.position.x = 112.0 + (_pips.size.x + 12.0 if _pips.visible else 0.0)
	_energy_value.add_theme_color_override("font_color", Style.DANGER if _low else Style.TEXT)
	if not _low:
		_energy_value.modulate.a = 1.0


func _set_ghost(value: float) -> void:
	_energy_bar.ghost = value
	_energy_bar.queue_redraw()


func _refresh_flux() -> void:
	var shown: bool = GameState.flux_max > 0 and _has_flux_ability()
	_flux_icon.visible = shown
	_flux_bar.visible = shown
	_flux_label.visible = shown
	_energy_plate.size.y = PLATE_HEIGHT + (36.0 if shown else 0.0)
	if not shown:
		return
	_flux_bar.max_value = GameState.flux_max
	_flux_bar.value = GameState.flux_current
	var module: StringName = GameState.active_flux_module
	_flux_icon.texture = _icon_texture(String(module)) if module != &"" else null
	var module_name := String(module).replace("_", " ").to_upper()
	var status := "ON" if GameState.flux_enabled else "OFF"
	if module == &"echo_scan":
		status = "READY" if GameState.flux_current >= Catalog.ECHO_SCAN_COST else "EMPTY"
	_flux_label.text = "%s %s" % [module_name, status]
	_flux_label.modulate.a = 1.0 if GameState.flux_enabled or module == &"echo_scan" else 0.6


func _refresh_missiles() -> void:
	_missile_plate.visible = GameState.max_missiles > 0
	_missile_value.text = str(GameState.missile_count)
	_missile_max.text = "/ %d" % GameState.max_missiles
	var empty: bool = GameState.missile_count <= 0
	_missile_value.add_theme_color_override("font_color", Style.TEXT_FAINT if empty else Style.TEXT)


func _refresh_beam() -> void:
	_beam_plate.visible = GameState.has_beam
	var beam: StringName = GameState.active_beam
	_beam_label.text = BEAM_NAMES.get(beam, "POWER")
	_beam_label.add_theme_color_override("font_color", BEAM_COLORS.get(beam, Style.TEXT))
	_beam_icon.texture = _icon_texture(BEAM_ICONS.get(beam, "beam"))


func _layout() -> void:
	_energy_plate.position = ORIGIN
	for node in _plate_offsets:
		node.position = ORIGIN + _plate_offsets[node]
	var x := ORIGIN.x + _energy_plate.size.x + GAP
	for plate in [_missile_plate, _beam_plate]:
		if plate.visible:
			plate.position = Vector2(x, ORIGIN.y)
			x += plate.size.x + GAP
	_feedback_label.position = Vector2(ORIGIN.x + 4, ORIGIN.y + _energy_plate.size.y + 14)


func _process(delta: float) -> void:
	if not _low:
		return
	if Settings.reduce_flashes():
		_energy_value.modulate.a = 1.0
		return
	_pulse += delta
	_energy_value.modulate.a = 0.65 + 0.35 * cos(_pulse * TAU * 0.9)


func _on_pickup_feedback(message: String) -> void:
	_feedback_label.text = message
	_feedback_label.modulate = Color.WHITE
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(3.5)
	_feedback_tween.tween_property(_feedback_label, "modulate:a", 0.0, 0.8)
