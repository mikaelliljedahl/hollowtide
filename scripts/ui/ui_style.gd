extends RefCounted

## Shared look for Hollowtide menus: dark, cool, subtle teal glow.

const BG_DEEP := Color("060b12")
const PANEL := Color(0.027, 0.055, 0.082, 0.94)
const PANEL_SOFT := Color(0.02, 0.045, 0.07, 0.62)
const BORDER := Color(0.36, 0.62, 0.64, 0.32)
const ACCENT := Color("7fe3d6")
const ACCENT_DIM := Color("3f8f89")
const TEXT := Color("dcefe9")
const TEXT_MUTED := Color("86a6a3")
const TEXT_FAINT := Color("56716f")
const WARN := Color("e6a064")
const DANGER := Color("ec6a5e")
const FLUX := Color("b29cff")

const SIZE_TITLE := 104
const SIZE_H1 := 46
const SIZE_H2 := 20
const SIZE_BUTTON := 28
const SIZE_BODY := 23
const SIZE_SMALL := 18

const MONO_FONTS := [
	"JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "monospace"
]

static var _theme: Theme
static var _mono: Font
static var _spaced: Dictionary = {}


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = SIZE_BODY
	t.set_color("font_color", "Label", TEXT)

	var normal := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	var hover := _box(Color(0.5, 0.9, 0.85, 0.06), Color(0, 0, 0, 0), 0)
	var focus := _box(Color(0.5, 0.95, 0.88, 0.12), ACCENT, 0)
	focus.border_width_left = 4
	focus.shadow_color = Color(ACCENT, 0.18)
	focus.shadow_size = 14
	var pressed := _box(Color(0.5, 0.95, 0.88, 0.2), ACCENT, 0)
	pressed.border_width_left = 4
	for box in [normal, hover, focus, pressed]:
		box.content_margin_left = 26
		box.content_margin_right = 22
		box.content_margin_top = 8
		box.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", normal)
	t.set_color("font_color", "Button", Color(TEXT, 0.82))
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)
	t.set_font_size("font_size", "Button", SIZE_BUTTON)

	# Toggle switches.
	for kind in ["CheckButton"]:
		t.set_stylebox("normal", kind, normal)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("focus", kind, focus)
		t.set_stylebox("pressed", kind, normal)
		t.set_stylebox("hover_pressed", kind, hover)
		t.set_color("font_color", kind, Color(TEXT, 0.82))
		t.set_color("font_hover_color", kind, TEXT)
		t.set_color("font_focus_color", kind, Color.WHITE)
		t.set_color("font_pressed_color", kind, TEXT)
		t.set_color("font_hover_pressed_color", kind, Color.WHITE)
		t.set_font_size("font_size", kind, SIZE_BODY)
		t.set_icon("checked", kind, _toggle_texture(true))
		t.set_icon("unchecked", kind, _toggle_texture(false))

	# Sliders.
	var track := _box(Color(0.12, 0.2, 0.24, 1.0), Color(0, 0, 0, 0), 4)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var track_fill := _box(ACCENT_DIM, Color(0, 0, 0, 0), 4)
	track_fill.content_margin_top = 3
	track_fill.content_margin_bottom = 3
	var track_fill_focus := _box(ACCENT, Color(0, 0, 0, 0), 4)
	track_fill_focus.content_margin_top = 3
	track_fill_focus.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_fill_focus)
	var slider_focus := _box(Color(0, 0, 0, 0), Color(ACCENT, 0.55), 6)
	slider_focus.set_border_width_all(1)
	slider_focus.expand_margin_left = 10
	slider_focus.expand_margin_right = 10
	slider_focus.expand_margin_top = 10
	slider_focus.expand_margin_bottom = 10
	t.set_stylebox("focus", "HSlider", slider_focus)
	t.set_icon("grabber", "HSlider", _dot_texture(22, TEXT, ACCENT_DIM))
	t.set_icon("grabber_highlight", "HSlider", _dot_texture(24, Color.WHITE, ACCENT))
	t.set_icon("grabber_disabled", "HSlider", _dot_texture(22, TEXT_FAINT, TEXT_FAINT))

	# Scrollbars: slim and quiet.
	var bar := _box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 3)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	var grab := _box(Color(ACCENT, 0.3), Color(0, 0, 0, 0), 3)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := _box(Color(ACCENT, 0.55), Color(0, 0, 0, 0), 3)
	grab_hi.content_margin_left = 3
	grab_hi.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", bar)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	t.set_stylebox("panel", "PanelContainer", panel_box())
	_theme = t
	return t


static func panel_box(alpha: float = 0.94) -> StyleBoxFlat:
	var style := _box(Color(PANEL, alpha), BORDER, 14)
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 32
	style.content_margin_left = 56
	style.content_margin_right = 56
	style.content_margin_top = 44
	style.content_margin_bottom = 40
	return style


static func mono_font() -> Font:
	if _mono == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(MONO_FONTS)
		_mono = font
	return _mono


## Default font with extra letter spacing, for titles and small caps captions.
static func spaced_font(spacing: int, weight: float = 0.0) -> Font:
	var key := "%d/%.2f" % [spacing, weight]
	if _spaced.has(key):
		return _spaced[key]
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = spacing
	if weight != 0.0:
		font.variation_embolden = weight
	_spaced[key] = font
	return font


static func label(
	parent: Node, text: String, size: int, color: Color = TEXT, spacing: int = 0
) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if spacing != 0:
		node.add_theme_font_override("font", spaced_font(spacing))
	if parent != null:
		parent.add_child(node)
	return node


static func caption(parent: Node, text: String) -> Label:
	return label(parent, text.to_upper(), SIZE_H2, ACCENT_DIM.lightened(0.25), 4)


static func glow(
	node: Label, color: Color = ACCENT, strength: float = 0.35, size: int = 16
) -> void:
	node.add_theme_color_override("font_shadow_color", Color(color, strength))
	node.add_theme_constant_override("shadow_outline_size", size)
	node.add_theme_constant_override("shadow_offset_x", 0)
	node.add_theme_constant_override("shadow_offset_y", 0)


static func rule(parent: Node, width: float = 0.0) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.28)
	line.custom_minimum_size = Vector2(width, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(line)
	return line


static func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


static func _dot_texture(diameter: int, fill: Color, ring: Color) -> Texture2D:
	var image := Image.create_empty(diameter, diameter, false, Image.FORMAT_RGBA8)
	var center := Vector2(diameter, diameter) * 0.5
	var radius := diameter * 0.5 - 1.0
	for y in diameter:
		for x in diameter:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var edge := clampf(radius - distance + 0.5, 0.0, 1.0)
			if edge <= 0.0:
				continue
			var color := fill if distance < radius - 3.0 else ring
			image.set_pixel(x, y, Color(color, color.a * edge))
	return ImageTexture.create_from_image(image)


static func _toggle_texture(on: bool) -> Texture2D:
	var width := 60
	var height := 30
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var track := ACCENT_DIM if on else Color(0.16, 0.24, 0.28, 1.0)
	var knob := Color.WHITE if on else Color(0.6, 0.7, 0.7, 1.0)
	var radius := height * 0.5
	var knob_center := Vector2(width - radius, radius) if on else Vector2(radius, radius)
	for y in height:
		for x in width:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, radius, width - radius)
			var d := p.distance_to(Vector2(cx, radius))
			var a := clampf(radius - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var color := track
			var kd := p.distance_to(knob_center)
			var ka := clampf(radius - 4.0 - kd + 0.5, 0.0, 1.0)
			color = color.lerp(knob, ka)
			image.set_pixel(x, y, Color(color, a))
	return ImageTexture.create_from_image(image)
