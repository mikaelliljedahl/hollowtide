class_name CaveBackgroundRenderer
extends Node2D
## Screen-covering parallax backdrop: far panorama, mid silhouettes, per-area atmosphere
## (fog gradient, light shafts, glow) and ambient particles. Drawn behind all terrain.

const BOUNDARIES: Array[float] = [5888.0, 9984.0, 14080.0, 18176.0]
const KIT_IDS: Array[StringName] = [&"fringe", &"nexus", &"vaults", &"kiln", &"depths"]
const TRANSITION_HALF_WIDTH := 384.0

var _camera_rect := Rect2()
var _kits: Dictionary[StringName, EnvironmentKit] = {}
var _fixed_area: StringName = &""
var _room := Rect2()
var _particles: CPUParticles2D
var _particle_area: StringName = &""


func configure() -> void:
	z_as_relative = false
	z_index = -15
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func sync(camera_rect: Rect2, kits: Dictionary, fixed_area: StringName, room: Rect2) -> void:
	_camera_rect = camera_rect
	_fixed_area = fixed_area
	_room = room
	_kits.clear()
	for id in kits:
		var kit := kits[id] as EnvironmentKit
		if kit != null:
			_kits[StringName(id)] = kit
	_sync_particles()
	queue_redraw()


func current_area() -> StringName:
	return _background_blend(_camera_rect.get_center().x)["base"]


func _draw() -> void:
	if _camera_rect.size.is_zero_approx():
		return
	var blend := _background_blend(_camera_rect.get_center().x)
	var base := _kits.get(blend["base"]) as EnvironmentKit
	if base == null:
		return
	var overlay := _kits.get(blend["overlay"]) as EnvironmentKit
	var weight: float = blend["weight"]
	if overlay == base:
		overlay = null
		weight = 0.0
	var base_alpha := 1.0 - weight
	_draw_layer(base, &"far", base.far_parallax, 1.0, true)
	if overlay != null and weight > 0.0:
		_draw_layer(overlay, &"far", overlay.far_parallax, weight, true)
	_draw_atmosphere(base, base_alpha, true)
	if overlay != null:
		_draw_atmosphere(overlay, weight, true)
	_draw_layer(base, &"mid", base.mid_parallax, base_alpha, false)
	if overlay != null:
		_draw_layer(overlay, &"mid", overlay.mid_parallax, weight, false)
	_draw_atmosphere(base, base_alpha, false)
	if overlay != null:
		_draw_atmosphere(overlay, weight, false)


func _anchor_y() -> float:
	if _room.size.y > 0.0:
		return _room.get_center().y
	return 640.0


func _draw_layer(
	kit: EnvironmentKit, layer: StringName, parallax: float, alpha: float, opaque: bool
) -> void:
	if alpha <= 0.0:
		return
	var texture := kit.texture(layer)
	var view := _camera_rect
	if texture == null:
		if opaque:
			draw_rect(view, Color(kit.fog.darkened(0.85), alpha))
		return
	var size := Vector2(texture.get_size())
	var camera := view.get_center()
	# Zoomed-out views (map/overview captures) scale the panorama up so it still fills the screen.
	var fit := maxf(1.0, view.size.y / size.y)
	var height := size.y * fit
	# Vertical parallax: the texture centre sits on the screen centre when the camera is at the
	# room's vertical centre and drifts by `parallax` as the camera moves. In tall rooms the drift
	# is reduced so the panorama always covers the full view at every camera position.
	var slack := maxf(0.0, (height - view.size.y) * 0.5)
	var vertical := parallax
	var reach := maxf(0.0, (_room.size.y - view.size.y) * 0.5)
	if reach * vertical > slack:
		vertical = slack / reach
	var top := camera.y - (camera.y - _anchor_y()) * vertical - height * 0.5
	top = clampf(top, view.end.y - height, view.position.y)
	var bottom := top + height
	var band_top := maxf(top, view.position.y)
	var band_bottom := minf(bottom, view.end.y)
	if band_bottom > band_top:
		# The horizontal source wraps (textures are seamless).
		var source_width := view.size.x / fit
		var source_x := camera.x * parallax / fit - source_width * 0.5 + size.x * 0.5
		draw_texture_rect_region(
			texture,
			Rect2(view.position.x, band_top, view.size.x, band_bottom - band_top),
			Rect2(source_x, (band_top - top) / fit, source_width, (band_bottom - band_top) / fit),
			Color(kit.far_modulate if opaque else kit.mid_modulate, alpha)
		)


func _draw_atmosphere(kit: EnvironmentKit, alpha: float, behind_mid: bool) -> void:
	if alpha <= 0.0:
		return
	var view := _camera_rect
	if behind_mid:
		# Distance haze over the far panorama pushes it back and unifies the palette per area.
		draw_rect(view, Color(kit.fog.darkened(0.55), 0.28 * alpha))
		match kit.area_id:
			&"fringe":
				_draw_light_shafts(view, Color(0.78, 0.88, 0.95), 0.07 * alpha)
			&"nexus":
				_draw_light_shafts(view, Color(0.45, 0.95, 0.9), 0.045 * alpha)
		return
	# Low mist / heat glow rising from the bottom of the screen, darker vignette at the top.
	var mist_height := view.size.y * 0.45
	var bottom_color := kit.fog
	var bottom_alpha := 0.2
	match kit.area_id:
		&"kiln":
			bottom_color = Color(1.0, 0.38, 0.1)
			bottom_alpha = 0.3
		&"depths":
			bottom_color = Color(0.1, 0.12, 0.3)
			bottom_alpha = 0.4
		&"vaults":
			bottom_color = Color(0.85, 0.93, 1.0)
			bottom_alpha = 0.16
	_draw_vertical_gradient(
		Rect2(view.position.x, view.end.y - mist_height, view.size.x, mist_height),
		Color(bottom_color, 0.0),
		Color(bottom_color, bottom_alpha * alpha)
	)
	_draw_vertical_gradient(
		Rect2(view.position.x, view.position.y, view.size.x, view.size.y * 0.35),
		Color(0.0, 0.0, 0.02, 0.45 * alpha),
		Color(0.0, 0.0, 0.02, 0.0)
	)


func _draw_vertical_gradient(rect: Rect2, top: Color, bottom: Color) -> void:
	# Vertex-colour quads: no texture sampling, so no wrap/filter seams at the gradient edges.
	var points := PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y)
		]
	)
	draw_polygon(points, PackedColorArray([top, top, bottom, bottom]))


func _draw_light_shafts(view: Rect2, color: Color, alpha: float) -> void:
	# Soft slanted shafts in 0.3 parallax space so they drift gently with the camera.
	var spacing := 900.0
	var offset := view.get_center().x * 0.7
	var first := int(floorf((view.position.x - offset) / spacing)) - 1
	for index in range(first, first + int(view.size.x / spacing) + 4):
		var hash_value := absi(index * 73856093) % 1000
		if hash_value % 3 == 0:
			continue
		var x := offset + float(index) * spacing + float(hash_value % 300)
		var width := 90.0 + float(hash_value % 140)
		var slant := 260.0
		var points := PackedVector2Array(
			[
				Vector2(x, view.position.y),
				Vector2(x + width, view.position.y),
				Vector2(x + width + slant, view.end.y),
				Vector2(x + slant * 0.6, view.end.y),
			]
		)
		var strength := alpha * (0.6 + float(hash_value % 5) * 0.1)
		var colors := PackedColorArray(
			[Color(color, strength), Color(color, strength), Color(color, 0.0), Color(color, 0.0)]
		)
		draw_polygon(points, colors)


func _background_blend(camera_x: float) -> Dictionary:
	if _fixed_area != &"":
		return {"base": _fixed_area, "overlay": _fixed_area, "weight": 0.0}
	for index in BOUNDARIES.size():
		var distance := camera_x - BOUNDARIES[index]
		if absf(distance) <= TRANSITION_HALF_WIDTH:
			var linear := clampf(
				(distance + TRANSITION_HALF_WIDTH) / (TRANSITION_HALF_WIDTH * 2.0), 0.0, 1.0
			)
			var weight := linear * linear * (3.0 - 2.0 * linear)
			return {"base": KIT_IDS[index], "overlay": KIT_IDS[index + 1], "weight": weight}
	var current: StringName = KIT_IDS.back()
	for index in BOUNDARIES.size():
		if camera_x < BOUNDARIES[index]:
			current = KIT_IDS[index]
			break
	return {"base": current, "overlay": current, "weight": 0.0}


# ------------------------------------------------------------------ particles


func _sync_particles() -> void:
	var area := current_area()
	var kit := _kits.get(area) as EnvironmentKit
	if kit == null:
		return
	if _particles == null or not is_instance_valid(_particles):
		_particles = CPUParticles2D.new()
		_particles.name = "AmbientParticles"
		_particles.local_coords = false
		_particles.z_as_relative = false
		_particles.z_index = -14
		add_child(_particles)
	_particles.global_position = _camera_rect.get_center()
	if _particle_area == area:
		return
	_particle_area = area
	_configure_particles(kit)


func _configure_particles(kit: EnvironmentKit) -> void:
	var p := _particles
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1100, 640)
	p.preprocess = 6.0
	p.direction = Vector2(0, 1)
	p.spread = 10.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = Color(1, 1, 1, 0.3)
	match kit.particles:
		&"drip":
			p.amount = 40
			p.lifetime = 3.0
			p.gravity = Vector2(0, 260)
			p.initial_velocity_min = 20
			p.initial_velocity_max = 60
			p.color = Color(0.7, 0.82, 0.9, 0.35)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
		&"mist":
			p.amount = 50
			p.lifetime = 7.0
			p.direction = Vector2(0.3, -1)
			p.spread = 40.0
			p.initial_velocity_min = 6
			p.initial_velocity_max = 18
			p.color = Color(0.5, 1.0, 0.95, 0.35)
		&"snow":
			p.amount = 90
			p.lifetime = 9.0
			p.direction = Vector2(0.25, 1)
			p.spread = 25.0
			p.initial_velocity_min = 18
			p.initial_velocity_max = 40
			p.color = Color(0.92, 0.97, 1.0, 0.55)
			p.scale_amount_min = 1.5
			p.scale_amount_max = 4.0
		&"embers":
			p.amount = 70
			p.lifetime = 5.0
			p.direction = Vector2(0.15, -1)
			p.spread = 30.0
			p.initial_velocity_min = 30
			p.initial_velocity_max = 80
			p.color = Color(1.0, 0.55, 0.18, 0.8)
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.0
		&"motes":
			p.amount = 60
			p.lifetime = 8.0
			p.direction = Vector2(0, -1)
			p.spread = 180.0
			p.initial_velocity_min = 4
			p.initial_velocity_max = 14
			p.color = Color(0.55, 0.45, 1.0, 0.6)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.5
		_:
			p.amount = 1
			p.color = Color(1, 1, 1, 0)
	p.restart()
	p.emitting = true
