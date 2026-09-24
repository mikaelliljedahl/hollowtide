extends Node2D

## Soft column of light used as an environmental landmark. With `required_flag` set, the shaft
## stays dark until the flag exists (the ending light opens when the Tidal Heart falls).

@export var required_flag := ""
@export var shaft_size := Vector2(256, 1024)
@export var tint := Color(0.75, 0.92, 1.0)

var _light: PointLight2D
var _strength := 0.0
var _time := 0.0


func _ready() -> void:
	z_index = -4
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	_light = PointLight2D.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_light.texture = texture
	_light.texture_scale = 4.0
	_light.color = tint
	add_child(_light)
	_strength = 1.0 if _active() else 0.0
	_apply()
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.disconnect(_on_state_changed)


func _active() -> bool:
	return required_flag.is_empty() or GameState.has_world_flag(required_flag)


func _on_state_changed() -> void:
	if _active() and _strength < 1.0:
		var tween := create_tween()
		tween.tween_method(_set_strength, _strength, 1.0, 2.5)


func _set_strength(value: float) -> void:
	_strength = value
	_apply()


func _apply() -> void:
	_light.energy = 1.1 * _strength
	queue_redraw()


func _process(delta: float) -> void:
	if _strength > 0.0:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if _strength <= 0.0:
		return
	# Additive layered beam: a wide soft halo, the main shaft and a bright core, each with
	# transparent edges so the column reads as light falling through dust, not a flat wedge.
	var shimmer := 0.9 + 0.1 * sin(_time * 0.7)
	_draw_beam(1.6, 0.07 * shimmer)
	_draw_beam(1.0, 0.16 * shimmer)
	_draw_beam(0.45, 0.2 * shimmer)
	# Pool of light where the shaft meets the floor.
	var pool := PackedVector2Array()
	var colors := PackedColorArray()
	pool.append(Vector2(0.0, -6.0))
	colors.append(Color(tint, 0.34 * _strength))
	for index in 25:
		var angle := TAU * float(index) / 24.0
		pool.append(Vector2(cos(angle) * shaft_size.x * 0.75, -6.0 + sin(angle) * 26.0))
		colors.append(Color(tint, 0.0))
	draw_polygon(pool, colors)


func _draw_beam(width_scale: float, alpha: float) -> void:
	var top := shaft_size.x * 0.3 * width_scale
	var bottom := shaft_size.x * width_scale
	var core := Color(tint, alpha * _strength)
	var faint := Color(tint, alpha * 0.25 * _strength)
	var clear := Color(tint, 0.0)
	var y_top := -shaft_size.y
	# Three strips across the beam: clear edge -> core -> clear edge.
	var xs_top := [-top * 0.5, -top * 0.15, top * 0.15, top * 0.5]
	var xs_bottom := [-bottom * 0.5, -bottom * 0.15, bottom * 0.15, bottom * 0.5]
	var top_colors := [clear, core, core, clear]
	var bottom_colors := [clear, faint, faint, clear]
	for index in 3:
		draw_polygon(
			PackedVector2Array(
				[
					Vector2(xs_top[index], y_top),
					Vector2(xs_top[index + 1], y_top),
					Vector2(xs_bottom[index + 1], 0.0),
					Vector2(xs_bottom[index], 0.0),
				]
			),
			PackedColorArray(
				[
					top_colors[index],
					top_colors[index + 1],
					bottom_colors[index + 1],
					bottom_colors[index],
				]
			)
		)
