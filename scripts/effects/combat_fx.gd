class_name CombatFx
extends Node2D
## Extra combat/player VFX: sparks, dust, explosions, ice shatter, muzzle flashes and the
## staged boss death. Everything is procedural and self-cleaning (group `transient`).

const BOSS_DEATH_SEQUENCE := 2.2
const UNSHADED = preload("res://resources/combat/fx_unshaded.tres")
const BOSS_DEATH_BURST_AT := 1.25

var _elapsed := 0.0
var _duration := 0.5
var _effect_kind: StringName = &""
var _death_tint := Color.WHITE
var _death_source_visuals: Array[Dictionary] = []
var _death_origin := Vector2.ZERO
var _death_ghosts: Array[Sprite2D] = []
var _death_ghost_base: Array[Vector2] = []
var _death_next_blast := 0.0
var _death_blast_index := 0
var _death_finished := false
var _death_sfx: StringName = &""


class Spark:
	extends Node2D
	## Bright streak that flies out and slows down; used for impacts and clinks.

	var age := 0.0
	var lifetime := 0.16
	var velocity := Vector2.ZERO
	var drag := 6.0
	var gravity := 0.0
	var length := 14.0
	var width := 2.5
	var tint := Color.WHITE

	func configure(
		spark_velocity: Vector2,
		spark_lifetime: float,
		spark_length: float,
		spark_width: float,
		color: Color,
		spark_gravity := 0.0
	) -> void:
		velocity = spark_velocity
		lifetime = spark_lifetime
		length = spark_length
		width = spark_width
		tint = color
		gravity = spark_gravity

	func _ready() -> void:
		add_to_group(&"transient")
		# Effects are light sources in their own right; don't let area darkness dim them.
		material = UNSHADED
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		global_position += velocity * delta
		velocity *= maxf(1.0 - drag * delta, 0.0)
		velocity.y += gravity * delta
		queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		var fade := clampf(1.0 - age / lifetime, 0.0, 1.0)
		var direction := velocity.normalized() if not velocity.is_zero_approx() else Vector2.RIGHT
		var tail := -direction * length * (0.35 + 0.65 * fade)
		draw_line(tail, Vector2.ZERO, Color(tint, tint.a * fade), width, true)
		draw_line(tail * 0.4, Vector2.ZERO, Color(1.0, 1.0, 1.0, fade * 0.9), width * 0.5, true)


class Puff:
	extends Node2D
	## Soft round cloud (dust, smoke, steam) that grows, drifts and fades.

	const BLOBS := [
		Vector3(0.0, 0.0, 0.8),
		Vector3(-0.5, 0.15, 0.6),
		Vector3(0.5, 0.18, 0.62),
		Vector3(-0.18, -0.38, 0.58),
		Vector3(0.28, -0.32, 0.52),
	]

	var age := 0.0
	var lifetime := 0.4
	var velocity := Vector2.ZERO
	var drag := 4.0
	var start_radius := 6.0
	var end_radius := 18.0
	var tint := Color(0.7, 0.66, 0.6, 0.5)

	func configure(
		puff_velocity: Vector2,
		puff_lifetime: float,
		radius_from: float,
		radius_to: float,
		color: Color,
		puff_drag := 4.0
	) -> void:
		velocity = puff_velocity
		lifetime = puff_lifetime
		start_radius = radius_from
		end_radius = radius_to
		tint = color
		drag = puff_drag

	func _ready() -> void:
		add_to_group(&"transient")
		# Effects are light sources in their own right; don't let area darkness dim them.
		material = UNSHADED
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		global_position += velocity * delta
		velocity *= maxf(1.0 - drag * delta, 0.0)
		queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		var progress := clampf(age / lifetime, 0.0, 1.0)
		var radius := lerpf(start_radius, end_radius, ease(progress, 0.4))
		var alpha := tint.a * (1.0 - progress) * (1.0 - progress * 0.5)
		# A loose cluster of soft blobs reads as a cloud rather than a ball.
		for blob: Vector3 in BLOBS:
			var center := Vector2(blob.x, blob.y) * radius
			var blob_radius := radius * blob.z
			draw_circle(center, blob_radius, Color(tint, alpha * 0.22))
			draw_circle(center, blob_radius * 0.66, Color(tint, alpha * 0.22))


class Glint:
	extends Node2D
	## Four-point metallic star: the visual "clink" for an armored / immune hit.

	var age := 0.0
	var lifetime := 0.16
	var size := 30.0
	var tint := Color(0.86, 0.92, 1.0, 1.0)

	func _ready() -> void:
		add_to_group(&"transient")
		# Effects are light sources in their own right; don't let area darkness dim them.
		material = UNSHADED
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		rotation += delta * 5.0
		queue_redraw()
		if age >= lifetime:
			queue_free()

	func _draw() -> void:
		var progress := clampf(age / lifetime, 0.0, 1.0)
		var reach := size * (0.55 + 0.45 * sin(progress * PI))
		var alpha := 1.0 - progress * progress
		var color := Color(tint, alpha)
		for index in 4:
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 4.0)
			var side := direction.orthogonal() * reach * 0.12
			draw_colored_polygon(
				PackedVector2Array([direction * reach, side, -side * 0.2, -side]), color
			)
		draw_circle(Vector2.ZERO, reach * 0.18, Color(1.0, 1.0, 1.0, alpha))
		draw_arc(Vector2.ZERO, reach * 0.62, 0.0, TAU, 16, Color(tint, alpha * 0.5), 2.0, true)


## Soft ground dust. `kind`: land, run, jump, skid, wall.
static func spawn_dust(
	parent: Node, position: Vector2, kind: StringName, facing := 1.0, strength := 1.0
):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFx.new()
	parent.add_child(effect)
	effect.global_position = position
	effect._setup_dust(kind, facing, strength)
	return effect


static func spawn_explosion(parent: Node, position: Vector2, radius := 56.0, tint := Color()):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFx.new()
	parent.add_child(effect)
	effect.global_position = position
	effect._setup_explosion(radius, tint)
	return effect


static func spawn_ice_shatter(parent: Node, position: Vector2, radius := 48.0):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFx.new()
	parent.add_child(effect)
	effect.global_position = position
	effect._setup_ice_shatter(radius)
	return effect


static func spawn_muzzle_flash(parent: Node, position: Vector2, direction: Vector2, tint: Color):
	if not is_instance_valid(parent):
		return null
	var effect := CombatFx.new()
	parent.add_child(effect)
	effect.global_position = position
	effect._setup_muzzle(direction, tint)
	return effect


## Staged boss death: flashing silhouette, rolling explosions, then the final burst.
static func spawn_boss_death_sequence(source: Node2D, tint: Color, final_sfx := &""):
	if not is_instance_valid(source):
		return null
	var effect := CombatFx.new()
	var parent := source.get_parent()
	if parent == null:
		parent = source.get_tree().current_scene
	if parent == null:
		return null
	parent.add_child(effect)
	effect.global_position = source.global_position
	effect._death_sfx = final_sfx
	effect._setup_boss_death(source, tint)
	return effect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"transient")


func _process(delta: float) -> void:
	_elapsed += delta
	if _effect_kind == &"boss_death":
		_advance_boss_death()
	if _elapsed >= _duration:
		queue_free()


func _advance_boss_death() -> void:
	if _death_finished:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xDEAD ^ _death_blast_index
	var shake := 3.0 + 7.0 * clampf(_elapsed / BOSS_DEATH_BURST_AT, 0.0, 1.0)
	var blink := int(_elapsed * 18.0) % 2 == 0
	for index in _death_ghosts.size():
		var ghost := _death_ghosts[index]
		if not is_instance_valid(ghost):
			continue
		ghost.position = (
			_death_ghost_base[index]
			+ Vector2(rng.randf_range(-shake, shake), rng.randf_range(-shake, shake))
		)
		ghost.modulate = (
			Color(1.6, 1.5, 1.4, 1.0) if blink else Color(_death_tint, 1.0).lightened(0.3)
		)
	if _elapsed >= _death_next_blast and _elapsed < BOSS_DEATH_BURST_AT:
		_death_blast_index += 1
		_death_next_blast = _elapsed + 0.14
		var offset := Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-230.0, -40.0))
		var parent := get_parent()
		if parent != null:
			spawn_explosion(
				parent, _death_origin + offset, rng.randf_range(34.0, 58.0), _death_tint
			)
		if _death_blast_index % 2 == 1:
			GameJuice.play_sfx(&"boss_explosion", &"bomb_explode")
		GameJuice.shake(self, 5.0, 0.18)
	if _elapsed >= BOSS_DEATH_BURST_AT:
		_death_finished = true
		for ghost in _death_ghosts:
			if is_instance_valid(ghost):
				ghost.queue_free()
		_death_ghosts.clear()
		var parent := get_parent()
		if parent != null:
			spawn_explosion(parent, _death_origin + Vector2(0.0, -140.0), 150.0, _death_tint)
			var burst := CombatFeedback.new()
			parent.add_child(burst)
			burst.global_position = _death_origin
			burst._setup_death_from_visuals(_death_source_visuals, _death_origin)
		GameJuice.shake(self, 16.0, 0.6)
		GameJuice.hit_stop(self, 0.12)
		if _death_sfx != &"":
			GameJuice.play_sfx(_death_sfx)


func _setup_dust(kind: StringName, facing: float, strength: float) -> void:
	_effect_kind = &"dust"
	_duration = 0.6
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var color := Color(0.8, 0.77, 0.72, 0.85 * clampf(strength, 0.4, 1.2))
	var grow := 1.6
	match kind:
		&"land":
			for side in [-1.0, 1.0]:
				for index in 3:
					var puff := Puff.new()
					puff.z_index = 1
					puff.position = Vector2(side * (6.0 + index * 10.0), -6.0)
					puff.configure(
						Vector2(
							side * rng.randf_range(90.0, 190.0) * strength,
							-rng.randf_range(8.0, 30.0)
						),
						rng.randf_range(0.4, 0.55),
						5.0 * grow,
						rng.randf_range(12.0, 18.0) * grow * clampf(strength, 0.6, 1.3),
						color,
						6.0
					)
					add_child(puff)
		&"run", &"skid":
			for index in 3:
				var puff := Puff.new()
				puff.z_index = 1
				puff.position = Vector2(-facing * (4.0 + index * 8.0), -5.0)
				puff.configure(
					Vector2(-facing * rng.randf_range(40.0, 110.0), -rng.randf_range(12.0, 36.0)),
					rng.randf_range(0.36, 0.5),
					4.0 * grow,
					rng.randf_range(11.0, 17.0) * grow,
					color,
					5.0
				)
				add_child(puff)
		&"jump":
			for index in 4:
				var puff := Puff.new()
				puff.z_index = 1
				var side := -1.0 if index % 2 == 0 else 1.0
				puff.position = Vector2(side * 8.0, -4.0)
				puff.configure(
					Vector2(side * rng.randf_range(50.0, 110.0), rng.randf_range(-10.0, 6.0)),
					rng.randf_range(0.32, 0.45),
					4.0 * grow,
					rng.randf_range(9.0, 13.0) * grow,
					color,
					6.0
				)
				add_child(puff)
		&"wall":
			# `facing` is the direction away from the wall.
			for index in 4:
				var puff := Puff.new()
				puff.z_index = 1
				puff.position = Vector2(0.0, -float(index) * 14.0)
				puff.configure(
					Vector2(facing * rng.randf_range(60.0, 140.0), rng.randf_range(-40.0, 30.0)),
					rng.randf_range(0.36, 0.5),
					5.0 * grow,
					rng.randf_range(10.0, 15.0) * grow,
					color,
					6.0
				)
				add_child(puff)
		&"slide":
			var puff := Puff.new()
			puff.z_index = 1
			puff.configure(
				Vector2(facing * rng.randf_range(10.0, 40.0), -rng.randf_range(20.0, 50.0)),
				0.3,
				3.0,
				8.0,
				Color(color, color.a * 0.8),
				3.0
			)
			add_child(puff)


func _setup_explosion(radius: float, tint: Color) -> void:
	_effect_kind = &"explosion"
	_duration = 0.6
	var hot := tint if tint.a > 0.0 else Color(1.0, 0.62, 0.22, 0.95)
	var flash := CombatFeedback.FlashBurst.new()
	flash.configure(true, false)
	flash.z_index = 86
	add_child(flash)
	var ring := CombatFeedback.PressureRing.new()
	ring.lifetime = 0.26
	ring.max_radius = radius * 1.35
	ring.tint = Color(hot, 0.75)
	ring.z_index = 85
	add_child(ring)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for index in 5:
		var fire := Puff.new()
		fire.z_index = 84
		fire.configure(
			Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(40.0, 120.0),
			rng.randf_range(0.16, 0.26),
			radius * 0.2,
			radius * rng.randf_range(0.5, 0.75),
			Color(hot.lightened(0.25), 0.9),
			5.0
		)
		add_child(fire)
	for index in 4:
		var smoke := Puff.new()
		smoke.z_index = 83
		smoke.configure(
			Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-90.0, -30.0)),
			rng.randf_range(0.42, 0.58),
			radius * 0.2,
			radius * rng.randf_range(0.55, 0.8),
			Color(0.24, 0.23, 0.24, 0.6),
			2.5
		)
		add_child(smoke)
	for index in 10:
		var spark := Spark.new()
		spark.z_index = 87
		spark.configure(
			Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(300.0, 650.0),
			rng.randf_range(0.14, 0.28),
			rng.randf_range(10.0, 22.0),
			2.4,
			hot,
			700.0
		)
		add_child(spark)


func _setup_ice_shatter(radius: float) -> void:
	_effect_kind = &"ice_shatter"
	_duration = 0.6
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var palette: Array[Color] = [
		Color(0.78, 0.94, 1.0, 0.92),
		Color(0.55, 0.82, 0.98, 0.9),
		Color(0.95, 0.99, 1.0, 0.95),
	]
	for index in 10:
		var fragment := CombatFeedback.Fragment.new()
		var start := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius)
		fragment.configure(
			null,
			Rect2(),
			palette[index % palette.size()],
			start.normalized() * rng.randf_range(120.0, 260.0) + Vector2(0.0, -120.0),
			rng.randf_range(600.0, 900.0),
			rng.randf_range(-12.0, 12.0),
			rng.randf_range(0.3, 0.55),
			Vector2(rng.randf_range(6.0, 14.0), rng.randf_range(10.0, 20.0)),
			rng.randf_range(-0.8, 0.8)
		)
		add_child(fragment)
		fragment.z_index = 84
		fragment.global_position = global_position + start
	for index in 3:
		var mist := Puff.new()
		mist.z_index = 83
		mist.configure(
			Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 0.0)),
			0.45,
			radius * 0.3,
			radius * 0.8,
			Color(0.8, 0.93, 1.0, 0.35),
			3.0
		)
		add_child(mist)


func _setup_muzzle(direction: Vector2, tint: Color) -> void:
	_effect_kind = &"muzzle"
	_duration = 0.4
	rotation = direction.angle()
	var flash := CombatFeedback.FlashBurst.new()
	flash.configure(false, false, true)
	flash.z_index = 30
	add_child(flash)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for index in 4:
		var spark := Spark.new()
		spark.z_index = 31
		spark.configure(
			direction.rotated(rng.randf_range(-0.45, 0.45)) * rng.randf_range(260.0, 480.0),
			rng.randf_range(0.06, 0.12),
			rng.randf_range(10.0, 18.0),
			2.2,
			tint
		)
		add_child(spark)
	for index in 2:
		var smoke := Puff.new()
		smoke.z_index = 29
		smoke.configure(
			direction * rng.randf_range(40.0, 90.0) + Vector2(0.0, -20.0),
			rng.randf_range(0.28, 0.38),
			4.0,
			rng.randf_range(12.0, 16.0),
			Color(0.55, 0.55, 0.58, 0.45),
			4.0
		)
		add_child(smoke)


func _setup_boss_death(source: Node2D, tint: Color) -> void:
	_effect_kind = &"boss_death"
	_duration = BOSS_DEATH_SEQUENCE
	_death_tint = tint
	var probe := CombatFeedback.new()
	_death_source_visuals = probe._capture_visuals(source)
	probe.free()
	_death_origin = global_position
	# Ghost copy of the sprite that flickers and shakes before bursting.
	for visual in _death_source_visuals:
		var ghost := Sprite2D.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = visual["texture"]
		atlas.region = visual["region"]
		ghost.texture = atlas
		ghost.centered = visual["centered"]
		ghost.offset = visual["offset"]
		ghost.flip_h = visual["flip_h"]
		ghost.z_index = int(visual["z_index"]) + 1
		add_child(ghost)
		ghost.global_transform = visual["transform"]
		_death_ghosts.append(ghost)
		_death_ghost_base.append(ghost.position)
