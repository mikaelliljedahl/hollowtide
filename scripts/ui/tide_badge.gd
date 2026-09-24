extends CanvasLayer

## Minimal HUD indication for socketed Tide Glyphs: their icons in a quiet strip in the bottom-left
## corner, hidden while nothing is socketed. Kept out of hud.gd on purpose (isolated owner).

const Style = preload("res://scripts/ui/ui_style.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TideCatalog = preload("res://scripts/progression/tide_catalog.gd")
const ICON := 44.0
const MARGIN := Vector2(32, 28)

var _strip: PanelContainer
var _icons: HBoxContainer


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_strip = PanelContainer.new()
	_strip.name = "TideBadge"
	var box := Style.panel_box(0.55)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	box.shadow_size = 0
	box.set_corner_radius_all(6)
	_strip.add_theme_stylebox_override("panel", box)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_icons = HBoxContainer.new()
	_icons.add_theme_constant_override("separation", 6)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(_icons)
	GameState.tide.changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if GameState.tide.changed.is_connected(refresh):
		GameState.tide.changed.disconnect(refresh)


func icon_count() -> int:
	return _icons.get_child_count() if _strip.visible else 0


func refresh() -> void:
	for child in _icons.get_children():
		_icons.remove_child(child)
		child.queue_free()
	for id: StringName in GameState.tide.equipped:
		var icon := TextureRect.new()
		icon.texture = Catalog.pickup_texture(TideCatalog.pickup_kind(id))
		icon.custom_minimum_size = Vector2(ICON, ICON)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = TideCatalog.glyph_name(id)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icons.add_child(icon)
	_strip.visible = _icons.get_child_count() > 0
	_strip.reset_size()
	var viewport := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080)
	)
	_strip.position = Vector2(
		MARGIN.x, viewport.y - MARGIN.y - _strip.get_combined_minimum_size().y
	)
