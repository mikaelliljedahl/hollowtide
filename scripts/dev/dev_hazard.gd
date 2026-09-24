extends Area2D
class_name DevHazard

const VFX_PATHS: Dictionary[StringName, String] = {
	&"fire_small": "res://assets/environment/vfx/industrial_fire.png",
	&"fire_vent": "res://assets/environment/vfx/industrial_fire.png",
	&"lava_surface": "res://assets/environment/vfx/lava_surface.png",
	&"steam_embers": "res://assets/environment/vfx/industrial_steam.png",
	&"steam_vent": "res://assets/environment/vfx/industrial_steam.png",
}
const VFX_PROFILE: Dictionary[StringName, Dictionary] = {
	&"fire_small": {"frames": 4, "width": 256.0, "anchor_y": 250.0},
	&"fire_vent": {"frames": 4, "width": 256.0, "anchor_y": 250.0},
	&"lava_surface": {"frames": 4, "width": 512.0, "anchor_y": 183.0},
	&"steam_embers": {"frames": 4, "width": 256.0, "anchor_y": 250.0},
	&"steam_vent": {"frames": 4, "width": 256.0, "anchor_y": 250.0},
}
const VENT_FIXTURE_HEIGHT := 96.0 * 0.6
const LOOP_AUDIO: Dictionary[StringName, StringName] = {
	&"fire_small": &"fire_loop",
	&"fire_vent": &"fire_loop",
	&"lava_surface": &"lava_loop",
	&"steam_embers": &"cold_ambience",
}

@export var damage := 12
@export var cooldown := 0.6
var hazard_size := Vector2(256, 64)
var kind: StringName = &"steam_embers"
var contact_enabled := true
var safe_floor_bypass := true
var ambient_override: StringName = &""
var _remaining := 0.0
var _steam_timer := 2.5
var _visual: AnimatedSprite2D
var _fixture: Node2D
var _audio: AudioStreamPlayer2D
var _configured_audio_id: StringName = &""


func configure(size: Vector2, amount: int, profile: StringName = &"steam_embers") -> void:
	configure_profile(profile, size, amount, true)


func configure_profile(
	profile: StringName,
	size: Vector2,
	amount: int,
	contacts := true,
	safe_bypass := true,
	ambient := &""
) -> void:
	kind = profile
	hazard_size = size
	damage = amount
	contact_enabled = contacts
	safe_floor_bypass = safe_bypass
	ambient_override = ambient
	if is_inside_tree():
		_build_visual()
		_configure_audio()


func audio_id_for_test() -> StringName:
	return _configured_audio_id


func visual_scale_for_test() -> Vector2:
	return _visual.scale if _visual != null else Vector2.ZERO


func contact_rect_for_test() -> Rect2:
	return Rect2(-hazard_size * 0.5, hazard_size)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 if contact_enabled else 0
	monitoring = contact_enabled
	monitorable = false
	var shape := CollisionShape2D.new()
	shape.name = "HazardCollision"
	var rectangle := RectangleShape2D.new()
	rectangle.size = hazard_size
	shape.shape = rectangle
	add_child(shape)
	if contact_enabled:
		body_entered.connect(_on_body_entered)
	_build_visual()
	_configure_audio()
	add_to_group("dev_owned")
	add_to_group("dev_hazard")
	if kind == &"lava_surface":
		add_to_group(&"visual_fluid")


## World rect of a fluid body; CaveVisuals grounds stepping stones that stand in it.
func fluid_rect() -> Rect2:
	return Rect2(global_position - hazard_size * 0.5, hazard_size)


func _build_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
	_visual = null
	_build_fixture()
	if kind == &"lava_surface":
		return
	_visual = AnimatedSprite2D.new()
	_visual.name = "AuthoredVfx_" + String(kind)
	_visual.centered = true
	_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"default")
	frames.set_animation_speed(&"default", 5.0)
	frames.set_animation_loop(&"default", true)
	var profile: Dictionary = VFX_PROFILE.get(kind, VFX_PROFILE[&"steam_embers"])
	var frame_width := float(profile["width"])
	var count: int = profile["frames"]
	var texture := load(VFX_PATHS.get(kind, "")) as Texture2D
	if texture != null:
		for index in count:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(index * frame_width, 0, frame_width, 256)
			frames.add_frame(&"default", atlas)
	_visual.sprite_frames = frames
	_visual.animation = &"default"
	# Uniform scale keeps fire/steam visual width inside damage width.
	var uniform_scale := minf(1.0, hazard_size.x / frame_width)
	_visual.scale = Vector2.ONE * uniform_scale
	var anchor_y := float(profile["anchor_y"]) * uniform_scale
	# Flame/steam emit from the crater of a rock vent whose base sits on the floor contact line.
	var crater := VENT_FIXTURE_HEIGHT
	if _fixture is VentMound:
		crater = (_fixture as VentMound).crater_height()
	var source_anchor := hazard_size.y * 0.5 - crater
	_visual.position.y = source_anchor - (-128.0 * uniform_scale + anchor_y)
	_visual.play()
	_visual.z_index = 1
	add_child(_visual)


func _build_fixture() -> void:
	if kind == &"lava_surface":
		var pool := LavaPool.new()
		pool.name = "LavaPool"
		pool.pool_rect = Rect2(-hazard_size * 0.5, hazard_size)
		pool.z_index = 1
		pool.area_id = _area_id()
		_fixture = pool
		add_child(pool)
		return
	var vent := VentMound.new()
	vent.name = "VentMound"
	vent.hot = kind in [&"fire_small", &"fire_vent"]
	vent.base_y = hazard_size.y * 0.5
	vent.mound_width = clampf(hazard_size.x * 0.6, 96.0, 180.0)
	vent.mound_height = VENT_FIXTURE_HEIGHT / 0.9
	vent.area_id = _area_id()
	vent.steam = kind in [&"steam_vent", &"steam_embers"]
	_fixture = vent
	add_child(vent)


func _area_id() -> StringName:
	var visuals := get_tree().get_first_node_in_group(&"cave_visuals") if is_inside_tree() else null
	if visuals != null and visuals.has_method("area_for_world_x"):
		return visuals.call("area_for_world_x", global_position.x)
	return &"kiln"


## Natural rock vent (fumarole) drawn with the area's rock material; flame/steam leave its crater.
class VentMound:
	extends Node2D
	var hot := true
	var base_y := 0.0
	var mound_width := 160.0
	var mound_height := 64.0
	var area_id: StringName = &"kiln"
	var steam := false
	var _fill: Texture2D
	var _sprite: Texture2D
	var _sprite_scale := 1.0

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		z_index = 0
		var kit := EnvironmentKit.load_for(area_id)
		_fill = kit.texture(&"fill")
		_sprite = kit.prop_of_kind(&"vent_steam" if steam else &"vent_fire")
		if _sprite != null:
			_sprite_scale = mound_width / float(_sprite.get_width())
		else:
			modulate = Color(kit.tint.r, kit.tint.g, kit.tint.b)

	## Height above the floor where flame/steam leaves the vent.
	func crater_height() -> float:
		if _sprite != null:
			return float(_sprite.get_height()) * _sprite_scale * 0.82
		return mound_height * 0.9

	func _draw() -> void:
		if _sprite != null:
			var size := Vector2(_sprite.get_size()) * _sprite_scale
			# Sink the flat base 4 px into the floor so the vent reads as rooted, not placed.
			draw_texture_rect(
				_sprite, Rect2(-size.x * 0.5, base_y - size.y + 4.0, size.x, size.y), false
			)
			return
		var w := mound_width * 0.5
		var h := mound_height
		var profile := [
			Vector2(-1.0, 0.0),
			Vector2(-0.92, -0.12),
			Vector2(-0.8, -0.2),
			Vector2(-0.66, -0.38),
			Vector2(-0.52, -0.46),
			Vector2(-0.38, -0.7),
			Vector2(-0.24, -0.86),
			Vector2(-0.14, -1.0),
			Vector2(-0.07, -0.9),
			Vector2(0.07, -0.9),
			Vector2(0.15, -0.97),
			Vector2(0.3, -0.8),
			Vector2(0.44, -0.62),
			Vector2(0.58, -0.5),
			Vector2(0.72, -0.3),
			Vector2(0.86, -0.16),
			Vector2(1.0, 0.0),
		]
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for p: Vector2 in profile:
			var point := Vector2(p.x * w, base_y + p.y * h)
			points.append(point)
			uvs.append((global_position + point) / 512.0)
		if _fill != null:
			draw_colored_polygon(points, Color.WHITE, uvs, _fill)
		else:
			draw_colored_polygon(points, Color(0.2, 0.16, 0.14))
		# Lit rim on the upper-left slope, darker base where it meets the floor.
		draw_polyline(points.slice(0, 8), Color(1, 1, 1, 0.22), 3.0, true)
		var base_shade := PackedVector2Array(
			[
				Vector2(-w, base_y),
				Vector2(-w * 0.8, base_y - h * 0.25),
				Vector2(w * 0.8, base_y - h * 0.25),
				Vector2(w, base_y)
			]
		)
		draw_polygon(
			base_shade,
			PackedColorArray(
				[Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)]
			)
		)
		var crater := Vector2(0.0, base_y - h * 0.93)
		var glow := Color(1.0, 0.45, 0.1, 0.9) if hot else Color(0.8, 0.85, 0.9, 0.35)
		_draw_ellipse(crater, Vector2(w * 0.22, h * 0.09), Color(0.05, 0.02, 0.02, 0.95))
		_draw_ellipse(crater + Vector2(0, 1), Vector2(w * 0.16, h * 0.05), glow)

	func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for index in 20:
			var angle := TAU * float(index) / 20.0
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_colored_polygon(points, color)


## Molten pool that fills its basin: surface slightly below the rim, body down past the basin floor.
class LavaPool:
	extends Node2D
	const SURFACE_DROP := 12.0
	const BODY_EXTRA := 18.0
	var pool_rect := Rect2()
	var area_id: StringName = &"kiln"
	var _time := 0.0
	var _texture: Texture2D
	var _texture_surface := 0.0

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var kit := EnvironmentKit.load_for(&"kiln")
		_texture = kit.texture(&"fluid")
		_texture_surface = kit.fluid_surface_y

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var surface := pool_rect.position.y + SURFACE_DROP
		var bottom := pool_rect.end.y + BODY_EXTRA
		if _texture != null:
			_draw_textured(surface, bottom)
			return
		var left := pool_rect.position.x
		var right := pool_rect.end.x
		var wave := PackedVector2Array()
		var x := left
		while x <= right + 0.1:
			var y := (
				surface + sin(x * 0.045 + _time * 1.7) * 2.2 + sin(x * 0.11 - _time * 2.3) * 1.2
			)
			wave.append(Vector2(x, y))
			x += 8.0
		# Heat glow above the surface.
		for index in wave.size() - 1:
			var a := wave[index]
			var b := wave[index + 1]
			draw_polygon(
				PackedVector2Array([a + Vector2(0, -52), b + Vector2(0, -52), b, a]),
				PackedColorArray(
					[
						Color(1, 0.4, 0.08, 0),
						Color(1, 0.4, 0.08, 0),
						Color(1, 0.45, 0.1, 0.32),
						Color(1, 0.45, 0.1, 0.32)
					]
				)
			)
		# Body: hot at the surface, dark red with depth.
		for index in wave.size() - 1:
			var a := wave[index]
			var b := wave[index + 1]
			var mid := surface + 14.0
			draw_polygon(
				PackedVector2Array([a, b, Vector2(b.x, mid), Vector2(a.x, mid)]),
				PackedColorArray(
					[
						Color(1, 0.72, 0.25),
						Color(1, 0.72, 0.25),
						Color(0.95, 0.3, 0.06),
						Color(0.95, 0.3, 0.06)
					]
				)
			)
			draw_polygon(
				PackedVector2Array(
					[
						Vector2(a.x, mid),
						Vector2(b.x, mid),
						Vector2(b.x, bottom),
						Vector2(a.x, bottom)
					]
				),
				PackedColorArray(
					[
						Color(0.95, 0.3, 0.06),
						Color(0.95, 0.3, 0.06),
						Color(0.3, 0.05, 0.02),
						Color(0.3, 0.05, 0.02)
					]
				)
			)
		# Drifting dark crust plates and a bright surface line.
		for index in 7:
			var phase := float(index) * 1.37
			var cx := (
				left
				+ fposmod(
					float(index) * 53.0 + _time * (6.0 + float(index % 3) * 3.0), right - left
				)
			)
			var cy := surface + 8.0 + sin(_time * 0.8 + phase) * 1.5
			draw_set_transform(Vector2(cx, cy), 0.0, Vector2(1.0, 0.32))
			draw_circle(Vector2.ZERO, 7.0 + float(index % 3) * 4.0, Color(0.35, 0.08, 0.03, 0.55))
			draw_set_transform(Vector2.ZERO)
		draw_polyline(wave, Color(1, 0.92, 0.55, 0.95), 2.5, true)

	func _draw_textured(surface: float, bottom: float) -> void:
		var top := surface - _texture_surface
		var height := minf(bottom - top, float(_texture.get_height()))
		var scroll := _time * 14.0
		var bob := sin(_time * 1.3) * 1.5
		var dest := Rect2(pool_rect.position.x, top + bob, pool_rect.size.x, height)
		draw_texture_rect_region(
			_texture, dest, Rect2(pool_rect.position.x + scroll, 0, pool_rect.size.x, height)
		)
		# Second layer drifting the other way gives the molten surface slow internal motion.
		draw_texture_rect_region(
			_texture,
			dest,
			Rect2(pool_rect.position.x - scroll * 0.6 + 200.0, 0, pool_rect.size.x, height),
			Color(1, 1, 1, 0.35)
		)
		if bottom > top + height:
			draw_rect(
				Rect2(
					pool_rect.position.x,
					top + height - 1.0,
					pool_rect.size.x,
					bottom - top - height + 1.0
				),
				Color(0.35, 0.06, 0.02)
			)
		# Cooler, darker lava toward the basin floor so the pool reads as depth, not a slab.
		var fade_top := surface + (bottom - surface) * 0.35
		var left := pool_rect.position.x
		var right := pool_rect.end.x
		draw_polygon(
			PackedVector2Array(
				[
					Vector2(left, fade_top),
					Vector2(right, fade_top),
					Vector2(right, bottom),
					Vector2(left, bottom)
				]
			),
			PackedColorArray(
				[
					Color(0.1, 0.02, 0.01, 0.0),
					Color(0.1, 0.02, 0.01, 0.0),
					Color(0.1, 0.02, 0.01, 0.92),
					Color(0.1, 0.02, 0.01, 0.92)
				]
			)
		)


func _configure_audio() -> void:
	if _audio != null and is_instance_valid(_audio):
		var old_audio := get_node_or_null("/root/Audio")
		if old_audio != null and old_audio.has_method("clear_positional_player"):
			old_audio.call("clear_positional_player", _audio)
		_audio.queue_free()
		_audio = null
	var audio_id: StringName = (
		ambient_override if ambient_override != &"" else LOOP_AUDIO.get(kind, &"")
	)
	if kind == &"steam_vent":
		audio_id = &"steam_vent"
	_configured_audio_id = audio_id
	if audio_id == &"":
		return
	_audio = AudioStreamPlayer2D.new()
	_audio.name = "HazardAudio"
	add_child(_audio)
	var audio := get_node_or_null("/root/Audio")
	if audio == null:
		return
	var configured := false
	if kind == &"steam_vent" and audio.has_method("configure_positional_one_shot"):
		configured = audio.call("configure_positional_one_shot", _audio, audio_id)
	elif audio.has_method("configure_positional_loop"):
		configured = audio.call("configure_positional_loop", _audio, audio_id)
	if configured and kind != &"steam_vent":
		_audio.play()


func _physics_process(delta: float) -> void:
	_remaining = maxf(_remaining - delta, 0.0)
	if kind == &"steam_vent" and _audio != null:
		_steam_timer -= delta
		if _steam_timer <= 0.0:
			_steam_timer = 3.5
			_audio.play()


func _on_body_entered(body: Node2D) -> void:
	if _remaining > 0.0 or not contact_enabled or not body.is_in_group("player"):
		return
	if damage > 0 and body.has_method("take_damage"):
		body.call("take_damage", damage, global_position)
	_remaining = cooldown


func _exit_tree() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null and _audio != null and audio.has_method("clear_positional_player"):
		audio.call("clear_positional_player", _audio)
