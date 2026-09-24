extends Control

## Ending credits: slow scroll over the surface light, then back to the title. Any key after a
## short delay skips. The campaign save is kept.

const TITLE_SCENE := "res://scenes/ui/start_menu.tscn"
const SCROLL_SPEED := 70.0
const LINES := [
	["HOLLOWTIDE", 72],
	["", 40],
	["The tide is still.", 34],
	["", 120],
	["A small metroidvania", 28],
	["made in Godot 4", 28],
	["", 90],
	["Design, code and world", 24],
	["the Hollowtide team", 32],
	["", 60],
	["Art, sound and music", 24],
	["authored and generated in-project", 32],
	["", 60],
	["Built with", 24],
	["Godot Engine", 32],
	["", 160],
	["Thank you for playing.", 40],
]

const SURFACE_ART := "res://assets/environment/areas/fringe/fringe_far.png"

var _column: VBoxContainer
var _backdrop: TextureRect
var _elapsed := 0.0
var _leaving := false


func _ready() -> void:
	get_tree().paused = false
	var background := ColorRect.new()
	background.color = Color(0.02, 0.03, 0.05)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	# The surface cave she climbed into, dimmed behind the text.
	var far := load(SURFACE_ART) as Texture2D
	if far != null:
		_backdrop = TextureRect.new()
		_backdrop.texture = far
		_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_backdrop.size = Vector2(2112, 1188)
		_backdrop.position = Vector2(-96, -54)
		_backdrop.modulate = Color(0.34, 0.4, 0.46)
		add_child(_backdrop)
	# Soft shaft of daylight from above: horizontal falloff, fading toward the floor.
	var beam := TextureRect.new()
	var across := Gradient.new()
	across.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	across.colors = PackedColorArray(
		[Color(0.75, 0.9, 1.0, 0.0), Color(0.75, 0.9, 1.0, 0.22), Color(0.75, 0.9, 1.0, 0.0)]
	)
	var beam_texture := GradientTexture2D.new()
	beam_texture.gradient = across
	beam_texture.width = 256
	beam_texture.height = 4
	beam.texture = beam_texture
	beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	beam.stretch_mode = TextureRect.STRETCH_SCALE
	beam.position = Vector2(620, 0)
	beam.size = Vector2(680, 1080)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam.material = additive
	add_child(beam)
	# Vignette: darker top and bottom keep the scrolling text readable.
	var shade := TextureRect.new()
	var down := Gradient.new()
	down.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	down.colors = PackedColorArray(
		[Color(0, 0, 0, 0.85), Color(0, 0, 0, 0.2), Color(0, 0, 0, 0.2), Color(0, 0, 0, 0.9)]
	)
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = down
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(0, 1)
	shade_texture.width = 4
	shade_texture.height = 256
	shade.texture = shade_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_column = VBoxContainer.new()
	_column.position = Vector2(0, 1100)
	_column.size = Vector2(1920, 10)
	_column.add_theme_constant_override("separation", 10)
	add_child(_column)
	for line in LINES:
		var label := Label.new()
		label.text = line[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(1920, line[1] + 8)
		label.add_theme_font_size_override("font_size", line[1])
		label.add_theme_color_override("font_color", Color("d8ecef"))
		_column.add_child(label)
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_music"):
		audio.call("play_music", &"ending")


func _process(delta: float) -> void:
	_elapsed += delta
	_column.position.y -= SCROLL_SPEED * delta
	if _backdrop != null:
		# Very slow upward drift, as if still rising toward the light.
		_backdrop.position.y = -54.0 + sin(_elapsed * 0.05) * 40.0
	if _column.position.y + _column.size.y < 300.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _elapsed > 2.0 and event.is_pressed() and not event.is_echo():
		_finish()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(TITLE_SCENE)
