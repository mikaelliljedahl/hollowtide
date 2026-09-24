class_name CombatFeedback
extends Node2D

const Catalog = preload("res://scripts/progression/content_catalog.gd")

const NORMAL_DURATION := 0.52
const BOSS_DURATION := 1.05
const BOMB_DURATION := 0.30
const HIT_DURATION := 0.16
const BLOCKED_DURATION := 0.18
const PHASE_DURATION := 0.48
const PLAYER_DEATH_DURATION := 0.45
const NORMAL_FRAGMENTS := 12
const BOSS_FRAGMENTS := 24
const BOMB_FRAGMENTS := 6
const NORMAL_MOTES := 6
const BOSS_MOTES := 8
const BOMB_MOTES := 4
const HIT_MOTES := 4
const PHASE_MOTES := 8
const UNDERTOW_AURA_COLOR := Color(0.28, 0.88, 1.0, 1.0)

var _elapsed := 0.0
var _duration := NORMAL_DURATION
var _effect_kind: StringName = &"death"
var _ring: PressureRing
var _flash: FlashBurst
var _aura_radius := 82.0


class Fragment:
	extends Node2D

	var velocity := Vector2.ZERO
	var gravity := 0.0
	var angular_velocity := 0.0
	var lifetime := 0.5
	var age := 0.0
	var base_color := Color.WHITE
	var _texture: Texture2D
	var _region := Rect2()
	var _shape_size := Vector2(14.0, 14.0)
	var _shape_angle := 0.0
	var _sprite: Sprite2D

	func configure(
		texture: Texture2D,
		region: Rect2,
		color: Color,
		fragment_velocity: Vector2,
		fragment_gravity: float,
		spin: float,
		fragment_lifetime: float,
		shape_size: Vector2,
		shape_angle: float
	) -> void:
		_texture = texture
		_region = region
		base_color = color
		velocity = fragment_velocity
		gravity = fragment_gravity
		angular_velocity = spin
		lifetime = fragment_lifetime
		_shape_size = shape_size
		_shape_angle = shape_angle
		if _texture != null:
			_sprite = Sprite2D.new()
			var atlas_texture := AtlasTexture.new()
			atlas_texture.atlas = _texture
			atlas_texture.region = _region
			_sprite.texture = atlas_texture
			_sprite.centered = true
			_sprite.modulate = base_color
			_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			add_child(_sprite)
		else:
			modulate = base_color
			queue_redraw()

	func _ready() -> void:
		add_to_group(&"transient")

	func _process(delta: float) -> void:
		age += delta
		global_position += velocity * delta
		velocity.y += gravity * delta
		rotation += angular_velocity * delta
		var fade := clampf(1.0 - age / lifetime, 0.0, 1.0)
		if _sprite != null:
			_sprite.modulate.a = base_color.a * fade
		else:
			modulate.a = base_color.a * fade
			queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		if _texture != null:
			return
		var points := PackedVector2Array()
		var half := _shape_size * 0.5
		var raw_points := PackedVector2Array(
			[
				Vector2(0.0, -half.y),
				Vector2(half.x * 0.7, -half.y * 0.35),
				Vector2(half.x, half.y * 0.42),
				Vector2(-half.x * 0.35, half.y),
				Vector2(-half.x, -half.y * 0.18),
			]
		)
		for point in raw_points:
			points.append(point.rotated(_shape_angle))
		draw_colored_polygon(points, modulate)
		draw_polyline(points, Color(0.9, 0.97, 0.9, modulate.a * 0.55), 1.5, true)


class PressureRing:
	extends Node2D

	var age := 0.0
	var lifetime := 0.28
	var max_radius := 72.0
	var tint := Color(0.35, 0.82, 0.73, 0.8)
	var boss := false

	func configure(is_boss: bool, frozen: bool) -> void:
		boss = is_boss
		lifetime = 0.38 if boss else 0.25
		max_radius = 124.0 if boss else 72.0
		tint = (Color(0.48, 0.9, 1.0, 0.86) if frozen else Color(0.4, 0.84, 0.7, 0.82))

	func _ready() -> void:
		add_to_group(&"transient")
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		var progress := clampf(age / lifetime, 0.0, 1.0)
		var radius := lerpf(18.0, max_radius, ease(progress, 0.72))
		var alpha := (1.0 - progress) * tint.a
		var color := Color(tint, alpha)
		# Soft shockwave: faint filled disc, a wide dim band and a thin bright edge.
		draw_circle(Vector2.ZERO, radius, Color(tint, alpha * 0.1))
		var band := (14.0 if boss else 9.0) * (1.0 - progress * 0.6)
		draw_arc(Vector2.ZERO, radius - band * 0.5, 0.0, TAU, 32, Color(tint, alpha * 0.28), band)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, color, 2.5 if boss else 2.0, true)


class FlashBurst:
	extends Node2D

	var age := 0.0
	var lifetime := 0.11
	var boss := false
	var frozen := false
	var compact := false

	func configure(is_boss: bool, is_frozen: bool, is_compact: bool = false) -> void:
		boss = is_boss
		frozen = is_frozen
		compact = is_compact
		lifetime = 0.08 if compact else (0.14 if boss else 0.1)

	func _ready() -> void:
		add_to_group(&"transient")
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		var progress := clampf(age / lifetime, 0.0, 1.0)
		var end_radius := 34.0 if compact else (92.0 if boss else 54.0)
		var radius := lerpf(12.0 if compact else 22.0, end_radius, progress)
		var alpha := (1.0 - progress) * (0.46 if compact else 0.55)
		var tint := Color(0.72, 0.96, 1.0, alpha) if frozen else Color(1.0, 0.83, 0.57, alpha)
		draw_circle(Vector2.ZERO, radius, Color(tint, alpha * 0.12))
		draw_arc(
			Vector2.ZERO,
			radius,
			0.0,
			TAU,
			16 if compact else 20,
			tint,
			3.0 if compact else (7.0 if boss else 5.0),
			true
		)
		var ray_count := 4 if compact else (8 if boss else 6)
		for index in ray_count:
			var angle := TAU * float(index) / float(ray_count)
			var direction := Vector2.RIGHT.rotated(angle)
			draw_line(direction * radius * 0.55, direction * radius, tint, 3.0, true)


class Mote:
	extends Node2D

	var age := 0.0
	var lifetime := 0.45
	var velocity := Vector2.ZERO
	var gravity := 0.0
	var size := 6.0
	var tint := Color.WHITE

	func configure(
		mote_velocity: Vector2,
		mote_gravity: float,
		mote_size: float,
		mote_lifetime: float,
		color: Color
	) -> void:
		velocity = mote_velocity
		gravity = mote_gravity
		size = mote_size
		lifetime = mote_lifetime
		tint = color

	func _ready() -> void:
		add_to_group(&"transient")
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		global_position += velocity * delta
		velocity.y += gravity * delta
		rotation += delta * 2.0
		queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		var fade := clampf(1.0 - age / lifetime, 0.0, 1.0)
		var color := Color(tint, tint.a * fade)
		var direction := velocity.normalized() if not velocity.is_zero_approx() else Vector2.UP
		draw_line(-direction * size * 2.2, Vector2.ZERO, color, maxf(size * 0.65, 2.0), true)
		draw_circle(Vector2.ZERO, size, Color(color, color.a * 0.8))


static func spawn_undertow_aura(parent: Node2D, center: Vector2, radius: float = 82.0):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFeedback.new()
	parent.add_child(effect)
	effect.position = center
	effect.show_behind_parent = true
	effect._setup_undertow_aura(radius)
	return effect


static func spawn_bomb_explosion(source: Node2D, radius: float):
	if not is_instance_valid(source):
		return null
	var effect := CombatFeedback.new()
	var parent := source.get_parent()
	if parent == null:
		parent = source.get_tree().current_scene
	if parent == null:
		parent = source.get_tree().root
	parent.add_child(effect)
	effect.global_position = source.global_position
	effect._setup_bomb(radius)
	return effect


static func spawn_death(source: Node2D, boss: bool = false, frozen: bool = false):
	if not is_instance_valid(source):
		return null
	var effect := CombatFeedback.new()
	var parent := source.get_parent()
	if parent == null:
		parent = source.get_tree().current_scene
	if parent == null:
		parent = source.get_tree().root
	parent.add_child(effect)
	effect._setup_death(source, boss, frozen)
	return effect


static func spawn_player_death(source: Node2D):
	if not is_instance_valid(source):
		return null
	var effect := CombatFeedback.new()
	var parent := source.get_parent()
	if parent == null:
		parent = source.get_tree().current_scene
	if parent == null:
		parent = source.get_tree().root
	parent.add_child(effect)
	effect.process_mode = Node.PROCESS_MODE_ALWAYS
	effect._setup_death(source, false, false)
	effect._effect_kind = &"player_death"
	effect._duration = PLAYER_DEATH_DURATION
	return effect


## `direction` is the travel direction of the attack (sparks fly along it);
## `heavy` adds a larger flash and smoke for missiles, bombs and kills.
static func spawn_hit(
	parent: Node,
	position: Vector2,
	frozen: bool = false,
	direction := Vector2.ZERO,
	heavy := false,
	tint := Color(1.0, 0.74, 0.34, 0.95)
):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFeedback.new()
	parent.add_child(effect)
	effect.global_position = position
	effect._setup_hit(frozen, direction, heavy, tint)
	return effect


static func spawn_blocked_hit(parent: Node, position: Vector2, direction := Vector2.ZERO):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFeedback.new()
	parent.add_child(effect)
	effect.global_position = position
	effect._setup_blocked_hit(direction)
	return effect


static func spawn_phase_burst(source: Node2D, tint: Color, local_offset := Vector2.ZERO):
	if not is_instance_valid(source):
		return null
	var effect := CombatFeedback.new()
	var parent := source.get_parent()
	if parent == null:
		parent = source.get_tree().current_scene
	if parent == null:
		parent = source.get_tree().root
	parent.add_child(effect)
	effect.global_position = source.global_position + local_offset
	effect._setup_phase_burst(tint)
	return effect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"transient")


func _process(delta: float) -> void:
	_elapsed += delta
	if _effect_kind == &"undertow_aura":
		queue_redraw()
		return
	if _elapsed >= _duration:
		queue_free()


func _draw() -> void:
	if _effect_kind != &"undertow_aura":
		return
	var pulse := 0.5 + 0.5 * sin(_elapsed * 16.0)
	var glow := Color(UNDERTOW_AURA_COLOR, 0.035 + pulse * 0.025)
	draw_circle(Vector2.ZERO, _aura_radius * 0.72, glow)
	for ring_index in 2:
		var ring_radius := _aura_radius * (0.74 + float(ring_index) * 0.12)
		var ring_alpha := 0.18 - float(ring_index) * 0.045 + pulse * 0.025
		draw_arc(
			Vector2.ZERO,
			ring_radius,
			_elapsed * (1.7 - ring_index * 0.35) + ring_index * 2.2,
			_elapsed * (1.7 - ring_index * 0.35) + ring_index * 2.2 + 1.55,
			18,
			Color(UNDERTOW_AURA_COLOR, ring_alpha),
			3.0,
			true
		)
	for arc_index in 4:
		var phase := _elapsed * (3.2 + arc_index * 0.27) + arc_index * TAU / 4.0
		var start_angle := phase
		var end_angle := phase + 0.48 + 0.08 * sin(_elapsed * 9.0 + arc_index)
		var points := PackedVector2Array()
		for point_index in 6:
			var progress := float(point_index) / 5.0
			var angle := lerpf(start_angle, end_angle, progress)
			var wave := sin(progress * PI * 3.0 + _elapsed * 18.0 + arc_index) * 4.0
			var point_radius := _aura_radius * 0.68 + wave + progress * _aura_radius * 0.18
			points.append(Vector2.RIGHT.rotated(angle) * point_radius)
		draw_polyline(points, Color(UNDERTOW_AURA_COLOR, 0.42), 3.0, true)
	for streak_index in 3:
		var streak_phase := -_elapsed * (2.3 + streak_index * 0.3) + streak_index * 2.0
		var streak := PackedVector2Array()
		for point_index in 5:
			var progress := float(point_index) / 4.0
			var angle := streak_phase + progress * 0.58
			var point_radius := _aura_radius * (0.35 + progress * 0.57)
			streak.append(Vector2.RIGHT.rotated(angle) * point_radius)
		draw_polyline(streak, Color(0.64, 0.98, 1.0, 0.34), 2.0, true)


func _setup_undertow_aura(radius: float) -> void:
	_effect_kind = &"undertow_aura"
	_duration = INF
	_aura_radius = minf(maxf(radius, 1.0), float(Catalog.WEAPON_DATA[&"undertow"]["radius"]))
	_elapsed = 0.0
	queue_redraw()


func _setup_bomb(radius: float) -> void:
	_effect_kind = &"bomb"
	_duration = BOMB_DURATION
	var physical_radius := minf(maxf(radius, 1.0), float(Catalog.BOMB_RADIUS))
	_ring = PressureRing.new()
	_ring.max_radius = physical_radius
	_ring.lifetime = 0.24
	_ring.tint = Color(1.0, 0.52, 0.18, 0.72)
	_ring.z_index = 1
	add_child(_ring)
	_flash = FlashBurst.new()
	_flash.z_index = 2
	_flash.configure(false, false)
	add_child(_flash)
	var palette: Array[Color] = [
		Color(1.0, 0.68, 0.24, 0.9),
		Color(1.0, 0.34, 0.12, 0.82),
		Color(0.98, 0.87, 0.48, 0.86),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(global_position, false, false) ^ 0xB0B
	for index in BOMB_FRAGMENTS:
		_add_shaped_fragment(global_position, index, BOMB_FRAGMENTS, false, palette, rng)
		var fragment := get_child(get_child_count() - 1) as Fragment
		if fragment != null:
			fragment.velocity *= 0.55
			fragment.gravity = rng.randf_range(280.0, 520.0)
			fragment.lifetime = rng.randf_range(0.18, 0.32)
			fragment._shape_size *= 0.58
	for index in BOMB_MOTES:
		var mote := Mote.new()
		mote.global_position = global_position
		mote.z_index = 3
		var direction := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		mote.configure(
			direction * rng.randf_range(110.0, 220.0),
			rng.randf_range(180.0, 340.0),
			rng.randf_range(2.0, 3.5),
			rng.randf_range(0.18, 0.30),
			palette[index % palette.size()]
		)
		add_child(mote)


func _setup_hit(
	frozen: bool, direction := Vector2.ZERO, heavy := false, tint := Color(1.0, 0.74, 0.34, 0.95)
) -> void:
	_effect_kind = &"hit"
	_duration = HIT_DURATION * (1.8 if heavy else 1.25)
	_flash = FlashBurst.new()
	_flash.configure(heavy, frozen, not heavy)
	_flash.z_index = 84
	add_child(_flash)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(global_position, heavy, frozen) ^ 0x417
	if frozen:
		tint = Color(0.62, 0.92, 1.0, 0.95)
	var forward := direction.normalized() if not direction.is_zero_approx() else Vector2.ZERO
	var spark_count := 9 if heavy else 6
	for index in spark_count:
		var spark := CombatFx.Spark.new()
		spark.z_index = 85
		var angle := TAU * float(index) / float(spark_count) + rng.randf_range(-0.3, 0.3)
		var spark_direction := Vector2.RIGHT.rotated(angle)
		if forward != Vector2.ZERO:
			# Spray mostly back out of the wound, like splinters off the struck surface.
			spark_direction = (-forward).rotated(rng.randf_range(-1.15, 1.15))
		var speed := rng.randf_range(260.0, 520.0) * (1.35 if heavy else 1.0)
		spark.configure(
			spark_direction * speed,
			rng.randf_range(0.1, 0.2) * (1.3 if heavy else 1.0),
			rng.randf_range(10.0, 20.0) * (1.4 if heavy else 1.0),
			2.6 if heavy else 2.0,
			tint,
			420.0
		)
		add_child(spark)
	for index in HIT_MOTES:
		var mote := Mote.new()
		mote.z_index = 83
		var mote_direction := Vector2.RIGHT.rotated(
			TAU * float(index) / float(HIT_MOTES) + rng.randf_range(-0.18, 0.18)
		)
		mote.configure(
			mote_direction * rng.randf_range(80.0, 150.0),
			rng.randf_range(180.0, 280.0),
			rng.randf_range(1.5, 2.8),
			rng.randf_range(0.1, HIT_DURATION),
			tint
		)
		add_child(mote)
	if heavy:
		for index in 3:
			var puff := CombatFx.Puff.new()
			puff.z_index = 82
			puff.configure(
				Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(30.0, 70.0),
				rng.randf_range(0.3, 0.45),
				10.0,
				rng.randf_range(24.0, 34.0),
				Color(0.42, 0.4, 0.4, 0.55)
			)
			add_child(puff)
		_duration = maxf(_duration, 0.46)


func _setup_blocked_hit(direction := Vector2.ZERO) -> void:
	_effect_kind = &"blocked"
	_duration = BLOCKED_DURATION
	var glint := CombatFx.Glint.new()
	glint.z_index = 86
	glint.lifetime = BLOCKED_DURATION
	add_child(glint)
	_ring = PressureRing.new()
	_ring.lifetime = BLOCKED_DURATION
	_ring.max_radius = 30.0
	_ring.tint = Color(0.8, 0.86, 0.95, 0.6)
	_ring.z_index = 84
	add_child(_ring)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(global_position, false, false) ^ 0xB10C
	var back := -direction.normalized() if not direction.is_zero_approx() else Vector2.UP
	for index in 5:
		# Ricochet: sparks glance off in a tight fan back toward the shooter.
		var spark := CombatFx.Spark.new()
		spark.z_index = 85
		spark.configure(
			back.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(380.0, 620.0),
			rng.randf_range(0.08, 0.15),
			rng.randf_range(12.0, 22.0),
			1.8,
			Color(0.9, 0.95, 1.0, 0.95),
			600.0
		)
		add_child(spark)


func _setup_phase_burst(tint: Color) -> void:
	_effect_kind = &"phase"
	_duration = PHASE_DURATION
	_ring = PressureRing.new()
	_ring.lifetime = 0.42
	_ring.max_radius = 156.0
	_ring.tint = Color(tint, 0.7)
	_ring.z_index = 78
	add_child(_ring)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(global_position, true, false) ^ 0xFACE
	for index in PHASE_MOTES:
		var mote := Mote.new()
		mote.z_index = 80
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / float(PHASE_MOTES))
		mote.configure(
			direction * rng.randf_range(105.0, 185.0),
			rng.randf_range(40.0, 110.0),
			rng.randf_range(2.0, 4.0),
			rng.randf_range(0.28, 0.46),
			Color(tint, 0.84)
		)
		add_child(mote)


func _setup_death_from_visuals(visuals: Array[Dictionary], origin: Vector2) -> void:
	_setup_death_common(visuals, origin, true, false)


func _setup_death(source: Node2D, boss: bool, frozen: bool) -> void:
	var visuals: Array[Dictionary] = _capture_visuals(source) if source != null else []
	var origin := source.global_position if source != null else global_position
	_setup_death_common(visuals, origin, boss, frozen)


func _setup_death_common(
	visuals: Array[Dictionary], origin: Vector2, boss: bool, frozen: bool
) -> void:
	_effect_kind = &"death"
	_duration = BOSS_DURATION if boss else NORMAL_DURATION
	global_position = Vector2.ZERO
	_ring = PressureRing.new()
	_ring.global_position = origin
	_ring.z_index = 80
	_ring.configure(boss, frozen)
	add_child(_ring)
	_flash = FlashBurst.new()
	_flash.global_position = origin
	_flash.z_index = 82
	_flash.configure(boss, frozen)
	add_child(_flash)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_for(origin, boss, frozen)
	var palette: Array[Color] = []
	if frozen:
		palette = [
			Color(0.58, 0.86, 0.92, 0.9),
			Color(0.7, 0.96, 0.94, 0.86),
			Color(0.42, 0.7, 0.86, 0.86),
		]
	else:
		palette = [
			Color(0.82, 0.57, 0.42, 0.88),
			Color(0.38, 0.75, 0.68, 0.88),
			Color(0.65, 0.78, 0.7, 0.84),
		]
	var fragment_count := BOSS_FRAGMENTS if boss else NORMAL_FRAGMENTS
	if visuals.is_empty():
		for index in fragment_count:
			_add_shaped_fragment(origin, index, fragment_count, boss, palette, rng)
	else:
		for index in mini(fragment_count, visuals.size() * 12):
			var visual: Dictionary = visuals[index % visuals.size()]
			_add_textured_fragment(
				origin, visual, index, fragment_count, boss, frozen, palette, rng
			)
	var mote_count := BOSS_MOTES if boss else NORMAL_MOTES
	for index in mote_count:
		var mote := Mote.new()
		mote.global_position = origin
		mote.z_index = 84
		var direction := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		mote.configure(
			direction * rng.randf_range(90.0, 250.0 if boss else 190.0),
			rng.randf_range(80.0, 260.0),
			rng.randf_range(2.0, 5.0),
			rng.randf_range(0.24, 0.62 if boss else 0.48),
			palette[index % palette.size()]
		)
		add_child(mote)
	for index in 5 if boss else 3:
		var puff := CombatFx.Puff.new()
		puff.global_position = origin + Vector2(rng.randf_range(-20.0, 20.0), -10.0)
		puff.z_index = 81
		puff.configure(
			Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-60.0, -10.0)),
			rng.randf_range(0.4, 0.6),
			10.0,
			rng.randf_range(30.0, 46.0) * (1.6 if boss else 1.0),
			Color(0.8, 0.9, 1.0, 0.4) if frozen else Color(0.45, 0.43, 0.42, 0.5),
			2.5
		)
		add_child(puff)


func _add_textured_fragment(
	_origin: Vector2,
	visual: Dictionary,
	index: int,
	_count: int,
	boss: bool,
	frozen: bool,
	palette: Array[Color],
	rng: RandomNumberGenerator
) -> void:
	if frozen and index % 3 == 0:
		_add_shaped_fragment(_origin, index, _count, boss, palette, rng)
		return
	var region: Rect2 = visual["region"]
	var columns := 4 if not boss else 5
	var rows := 3 if not boss else 4
	var column := index % columns
	var row := floori(float(index) / float(columns)) % rows
	var piece := Vector2(region.size.x / columns, region.size.y / rows)
	var piece_region := Rect2(region.position + Vector2(column * piece.x, row * piece.y), piece)
	var local_center := Vector2(
		(column + 0.5) / columns * region.size.x - region.size.x * 0.5,
		(row + 0.5) / rows * region.size.y - region.size.y * 0.5
	)
	if not visual["centered"]:
		local_center += region.size * 0.5
	local_center += visual["offset"]
	if visual["flip_h"]:
		local_center.x = -local_center.x
	var fragment := Fragment.new()
	fragment.configure(
		visual["texture"],
		piece_region,
		Color(palette[index % palette.size()], 0.92),
		Vector2(rng.randf_range(-250.0, 250.0), rng.randf_range(-330.0, -90.0)),
		rng.randf_range(420.0, 760.0) if boss else rng.randf_range(340.0, 620.0),
		rng.randf_range(-9.0, 9.0),
		rng.randf_range(0.34, 0.8 if boss else 0.55),
		piece * 0.4,
		rng.randf_range(-0.35, 0.35)
	)
	add_child(fragment)
	fragment.z_index = int(visual["z_index"]) + 2
	fragment.global_transform = visual["transform"]
	fragment.global_position = visual["transform"] * local_center
	if fragment._sprite != null:
		fragment._sprite.flip_h = visual["flip_h"]
		fragment._sprite.flip_v = visual["flip_v"]


func _add_shaped_fragment(
	origin: Vector2,
	index: int,
	_count: int,
	boss: bool,
	palette: Array[Color],
	rng: RandomNumberGenerator
) -> void:
	var fragment := Fragment.new()
	fragment.configure(
		null,
		Rect2(),
		palette[index % palette.size()],
		Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-350.0, -100.0)),
		rng.randf_range(400.0, 760.0) if boss else rng.randf_range(320.0, 600.0),
		rng.randf_range(-10.0, 10.0),
		rng.randf_range(0.34, 0.82 if boss else 0.56),
		Vector2(rng.randf_range(10.0, 26.0), rng.randf_range(8.0, 22.0)) * (1.3 if boss else 1.0),
		rng.randf_range(-0.8, 0.8)
	)
	add_child(fragment)
	fragment.z_index = 82
	fragment.global_position = origin


func _capture_visuals(source: Node2D) -> Array[Dictionary]:
	var visuals: Array[Dictionary] = []
	_capture_children(source, visuals)
	return visuals


func _capture_children(node: Node, visuals: Array[Dictionary]) -> void:
	if node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.visible and sprite.texture != null:
			var texture: Texture2D = sprite.texture
			var texture_size := texture.get_size()
			var frames_x := maxi(sprite.hframes, 1)
			var frames_y := maxi(sprite.vframes, 1)
			var frame_size := Vector2(texture_size.x / frames_x, texture_size.y / frames_y)
			var frame := maxi(sprite.frame, 0)
			var frame_row := floori(float(frame) / float(frames_x))
			var frame_rect := Rect2(
				Vector2((frame % frames_x) * frame_size.x, frame_row * frame_size.y), frame_size
			)
			if sprite.region_enabled:
				frame_rect = sprite.region_rect
			var flattened := _flatten_atlas(texture, frame_rect)
			var visual := {
				"texture": flattened["texture"],
				"region": flattened["region"],
				"transform": sprite.global_transform,
				"offset": sprite.offset,
				"centered": sprite.centered,
				"flip_h": sprite.flip_h,
				"flip_v": sprite.flip_v,
				"z_index": sprite.z_index,
			}
			visuals.append(visual)
	elif node is AnimatedSprite2D:
		var animated := node as AnimatedSprite2D
		var frames := animated.sprite_frames
		if animated.visible and frames != null:
			var texture := frames.get_frame_texture(animated.animation, animated.frame)
			if texture != null:
				var flattened := _flatten_atlas(texture, Rect2(Vector2.ZERO, texture.get_size()))
				var visual := {
					"texture": flattened["texture"],
					"region": flattened["region"],
					"transform": animated.global_transform,
					"offset": Vector2.ZERO,
					"centered": animated.centered,
					"flip_h": animated.flip_h,
					"flip_v": animated.flip_v,
					"z_index": animated.z_index,
				}
				visuals.append(visual)
	for child in node.get_children():
		_capture_children(child, visuals)


func _flatten_atlas(texture: Texture2D, region: Rect2) -> Dictionary:
	var source := texture
	var source_region := region
	while source is AtlasTexture:
		var atlas := source as AtlasTexture
		source_region.position += atlas.region.position
		source = atlas.atlas
	return {"texture": source, "region": source_region}


func _seed_for(origin: Vector2, boss: bool, frozen: bool) -> int:
	var seed_value := 0x484F4C4C
	seed_value ^= int(absf(origin.x) * 17.0) ^ int(absf(origin.y) * 31.0)
	if boss:
		seed_value ^= 0xB055
	if frozen:
		seed_value ^= 0x1CE
	return seed_value
