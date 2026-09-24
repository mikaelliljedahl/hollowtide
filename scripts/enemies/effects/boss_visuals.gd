extends RefCounted
## Presentation helpers for CombatBoss: weak-point glow, vulnerable-window timer ring,
## Tidal Heart shield bubble and grate tether, attack telegraphs (boss_telegraphs.gd), health bar,
## sprite state/pose and the small hit, release and heat effects.
## Pure visuals: nothing here changes damage rules or timings.

const GLOW_MATERIAL = preload("res://resources/combat/beam_glow_add.tres")
const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
const Telegraphs = preload("res://scripts/enemies/effects/boss_telegraphs.gd")
const ART_DIR := "res://assets/sprites/combat/"
const CORE_OFFSETS := {
	&"stone_guardian": Vector2(62.0, -22.0),
	&"furnace_mother": Vector2(34.0, -11.0),
	&"tidal_heart": Vector2(46.0, -30.0),
}
const CORE_RADIUS := {
	&"stone_guardian": 48.0,
	&"furnace_mother": 62.0,
	&"tidal_heart": 66.0,
}
const SHIELD_RADIUS := 222.0
const WAVE_TETHER_COLOR := Color(0.72, 0.5, 1.0, 1.0)


class BossOverlay:
	extends Node2D
	var boss: Node2D

	func _draw() -> void:
		if is_instance_valid(boss) and boss.visible:
			boss.call("_draw_overlay_on", self)


static func core_offset(enemy_id: StringName) -> Vector2:
	return CORE_OFFSETS.get(enemy_id, Vector2.ZERO)


static func optional_texture(file_name: String) -> Texture2D:
	var path := ART_DIR + file_name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func create_overlay(boss: Node2D) -> Node2D:
	var overlay := BossOverlay.new()
	overlay.name = "WeakPointOverlay"
	overlay.boss = boss
	overlay.material = GLOW_MATERIAL
	overlay.z_index = 1
	boss.add_child(overlay)
	return overlay


static func heartbeat(age: float) -> float:
	# Double "lub-dub" pulse every 1.1 s.
	var t := fmod(age, 1.1)
	return maxf(exp(-pow((t - 0.08) * 18.0, 2.0)), 0.7 * exp(-pow((t - 0.3) * 18.0, 2.0)))


static func state_look(boss: Node) -> Dictionary:
	var id: StringName = boss.enemy_id
	var age: float = boss._age
	var phase: int = boss.phase
	var exposed: bool = boss.weak_point_exposed()
	var fraction: float = boss.window_fraction_left()
	var accent: Color = boss._boss_accent_color()
	var look := {"glow": 0.0, "darken": 0.0, "frost": 0.0, "glow_color": accent}
	var closing := fraction >= 0.0 and fraction < 0.22
	var pulse := 0.5 + 0.5 * sin(age * 7.0)
	match id:
		&"tidal_heart":
			if exposed:
				look["glow"] = 0.3 + 0.35 * heartbeat(age * 1.6)
			else:
				look["darken"] = 0.0 if boss.has_state_art() else 0.3
		&"stone_guardian":
			# Pale granite washes out under glow; the core overlay carries the "open" read.
			if phase == 2 and exposed:
				look["glow"] = 0.08 + 0.06 * pulse
			elif phase == 2:
				look["darken"] = 0.5
		&"furnace_mother":
			if phase == 1:
				look["glow"] = 0.3 + 0.12 * pulse
			elif exposed:
				# Cooling window: the crust darkens, only the core stays hot.
				look["darken"] = 0.4
				look["glow"] = 0.15
			else:
				# Overheated: the whole carapace is white-hot and untouchable.
				look["glow"] = 0.85 + 0.25 * sin(age * 18.0)
				look["glow_color"] = Color(1.0, 0.88, 0.62, 1.0)
	if closing:
		look["glow"] = float(look["glow"]) * (0.4 + 0.6 * absf(sin(age * 26.0)))
	if int(boss.stage) >= Patterns.DESPERATION_STAGE:
		# Desperation: a fast, hot pulse over whatever state the body is in.
		look["glow"] = maxf(float(look["glow"]), 0.22 + 0.18 * absf(sin(age * 9.0)))
	return look


static func draw_overlay(boss: Node, canvas: CanvasItem) -> void:
	var id: StringName = boss.enemy_id
	var age: float = boss._age
	var accent: Color = boss._boss_accent_color()
	var core: Vector2 = boss._core_local()
	var radius: float = CORE_RADIUS.get(id, 56.0)
	var exposed: bool = boss.weak_point_exposed()
	var fraction: float = boss.window_fraction_left()
	var center: Vector2 = boss._sprite.position if boss._sprite != null else Vector2.ZERO
	if id == &"furnace_mother" and boss.phase == 2 and not exposed:
		# Overheated: the carapace radiates; shots will only splash off it.
		var heat := 0.5 + 0.5 * sin(age * 18.0)
		for layer in 3:
			var reach := 190.0 - float(layer) * 45.0
			canvas.draw_circle(
				center + Vector2(0.0, 30.0), reach, Color(1.0, 0.45, 0.12, 0.06 + 0.03 * heat)
			)
	if id == &"tidal_heart" and boss.phase == 2:
		_draw_tether(boss, canvas, core, age)
		if not exposed:
			_draw_shield(boss, canvas, center, age)
		elif float(boss._open_elapsed) < 0.35:
			var pop := float(boss._open_elapsed) / 0.35
			canvas.draw_arc(
				center,
				SHIELD_RADIUS * (1.0 + pop * 0.35),
				0.0,
				TAU,
				48,
				Color(0.5, 0.85, 1.0, 0.6 * (1.0 - pop)),
				6.0,
				true
			)
	if exposed:
		var beat := heartbeat(age * 1.6)
		var r := radius * (0.9 + 0.2 * beat)
		for layer in 4:
			var scale := 1.0 - float(layer) * 0.24
			canvas.draw_circle(core, r * scale, Color(accent, 0.07 + 0.08 * float(layer)))
		canvas.draw_circle(core, r * 0.2, Color(1.0, 1.0, 1.0, 0.35 + 0.35 * beat))
		if id == &"stone_guardian" and boss.phase == 2:
			_draw_cracks(canvas, core, accent, age)
	elif id == &"tidal_heart" and boss.phase == 1:
		# Protected but alive: a slow heartbeat leaks through the shell seam.
		var beat := heartbeat(age)
		canvas.draw_circle(core, radius * 0.45, Color(accent, 0.08 + 0.14 * beat))
		var ring := fmod(age, 1.1) / 1.1
		canvas.draw_arc(
			core, radius * (0.5 + ring * 1.4), 0.0, TAU, 32, Color(accent, 0.25 * (1.0 - ring)), 3.0
		)
	if fraction >= 0.0:
		var closing := fraction < 0.22
		var ring_alpha := 0.85
		if closing:
			ring_alpha *= absf(sin(age * 26.0))
		canvas.draw_arc(core, radius + 26.0, 0.0, TAU, 48, Color(accent, 0.14), 5.0, true)
		canvas.draw_arc(
			core,
			radius + 26.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * fraction,
			48,
			Color(accent, ring_alpha),
			5.0,
			true
		)
	for ripple in boss._shield_ripples:
		var local: Vector2 = ripple["position"]
		var progress := float(ripple["age"]) / 0.45
		var toward := (local - center).normalized()
		var at := center + toward * SHIELD_RADIUS
		canvas.draw_arc(
			at,
			18.0 + 46.0 * progress,
			toward.angle() + PI * 0.5,
			toward.angle() + PI * 1.5,
			16,
			Color(0.7, 0.92, 1.0, 0.8 * (1.0 - progress)),
			4.0,
			true
		)
	Telegraphs.draw(boss, canvas, core, accent)


static func _draw_cracks(canvas: CanvasItem, core: Vector2, accent: Color, age: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57011E
	for index in 7:
		var angle := TAU * float(index) / 7.0 + rng.randf_range(-0.3, 0.3)
		var points := PackedVector2Array([core])
		var point := core
		var length := rng.randf_range(60.0, 120.0)
		for step in 4:
			angle += rng.randf_range(-0.5, 0.5)
			point += Vector2.RIGHT.rotated(angle) * length * 0.25
			points.append(point)
		var flicker := 0.6 + 0.4 * sin(age * 9.0 + float(index))
		canvas.draw_polyline(points, Color(accent, 0.7 * flicker), 3.0, true)


static func _draw_shield(boss: Node, canvas: CanvasItem, center: Vector2, age: float) -> void:
	var points := PackedVector2Array()
	for index in 65:
		var angle := TAU * float(index) / 64.0
		var wobble := sin(angle * 6.0 + age * 2.6) * 6.0 + sin(angle * 11.0 - age * 3.4) * 3.0
		points.append(center + Vector2.RIGHT.rotated(angle) * (SHIELD_RADIUS + wobble))
	var fill := points.duplicate()
	fill.remove_at(fill.size() - 1)
	canvas.draw_colored_polygon(fill, Color(0.2, 0.55, 0.9, 0.1))
	var block := float(boss._block_flash_remaining) > 0.0
	canvas.draw_polyline(points, Color(0.55, 0.88, 1.0, 0.85 if block else 0.5), 4.0, true)
	var sweep := fmod(age * 0.8, TAU)
	canvas.draw_arc(
		center, SHIELD_RADIUS - 12.0, sweep, sweep + 0.9, 20, Color(0.85, 0.97, 1.0, 0.4), 3.0, true
	)
	canvas.draw_arc(
		center,
		SHIELD_RADIUS - 24.0,
		-sweep * 1.3,
		-sweep * 1.3 + 0.5,
		16,
		Color(0.85, 0.97, 1.0, 0.25),
		2.0,
		true
	)


static func _draw_tether(boss: Node, canvas: CanvasItem, core: Vector2, age: float) -> void:
	var grate := _nearest_grate(boss)
	if grate == null:
		return
	var start := (boss as Node2D).to_local(grate.global_position)
	var end := core
	var flash := float(boss._tether_flash) / 0.5
	var along := end - start
	var normal := along.normalized().orthogonal()
	var points := PackedVector2Array()
	for index in 33:
		var t := float(index) / 32.0
		var wave := sin(t * 18.0 - age * 9.0) * 7.0 * sin(t * PI)
		points.append(start + along * t + normal * wave)
	var alpha := 0.2 + 0.1 * sin(age * 4.0) + 0.7 * flash
	canvas.draw_polyline(points, Color(WAVE_TETHER_COLOR, alpha), 3.0 + 6.0 * flash, true)
	# Energy motes travel from the grate into the heart: "power flows from there".
	for index in 3:
		var t := fmod(age * 0.7 + float(index) / 3.0, 1.0)
		var wave := sin(t * 18.0 - age * 9.0) * 7.0 * sin(t * PI)
		canvas.draw_circle(
			start + along * t + normal * wave, 5.0 + 4.0 * flash, Color(WAVE_TETHER_COLOR, 0.6)
		)
	canvas.draw_circle(start, 16.0 + 10.0 * flash, Color(WAVE_TETHER_COLOR, 0.18 + 0.4 * flash))


static func _nearest_grate(boss: Node) -> Node2D:
	var best: Node2D
	var best_distance := INF
	for node in boss.get_tree().get_nodes_in_group(&"projectile_grate"):
		var grate := node as Node2D
		if grate == null or not is_instance_valid(grate):
			continue
		var relay = (
			grate.call("_relay_target_node") if grate.has_method("_relay_target_node") else null
		)
		if relay != null and relay != boss:
			continue
		var distance := grate.global_position.distance_to((boss as Node2D).global_position)
		if distance < best_distance and distance < 1400.0:
			best = grate
			best_distance = distance
	return best


static func draw_health_bar(boss: Node) -> void:
	var canvas := boss as CanvasItem
	var accent: Color = boss._boss_accent_color()
	var size := Vector2(300.0, 18.0)
	var top_left: Vector2 = boss._visual_base_position + Vector2(-size.x * 0.5, -236.0)
	var inner := Rect2(top_left + Vector2(3.0, 3.0), size - Vector2(6.0, 6.0))
	var max_health := float(maxi(int(boss.max_health), 1))
	canvas.draw_rect(Rect2(top_left, size), Color(0.02, 0.03, 0.04, 0.88), true)
	var trail := clampf(float(boss._health_trail) / max_health, 0.0, 1.0)
	var ratio := clampf(float(boss.health) / max_health, 0.0, 1.0)
	canvas.draw_rect(
		Rect2(inner.position, Vector2(inner.size.x * trail, inner.size.y)),
		Color(1.0, 0.96, 0.88, 0.85),
		true
	)
	var fill := accent if boss.weak_point_exposed() else accent.darkened(0.35)
	canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)), fill, true)
	canvas.draw_rect(
		Rect2(inner.position, Vector2(inner.size.x * ratio, 3.0)), Color(1.0, 1.0, 1.0, 0.25), true
	)
	# One notch per stage still ahead; the last one marks desperation.
	for threshold in Patterns.STAGE_THRESHOLDS:
		if ratio <= threshold:
			continue
		var notch_x := inner.position.x + inner.size.x * threshold
		canvas.draw_line(
			Vector2(notch_x, top_left.y - 2.0),
			Vector2(notch_x, top_left.y + size.y + 2.0),
			Color(1.0, 1.0, 1.0, 0.55),
			2.0
		)
	canvas.draw_rect(Rect2(top_left, size), Color(accent, 0.55), false, 2.0)


static func advance_timers(boss: Node2D, delta: float) -> void:
	boss._hit_flash_remaining = maxf(float(boss._hit_flash_remaining) - delta, 0.0)
	boss._block_flash_remaining = maxf(float(boss._block_flash_remaining) - delta, 0.0)
	boss._stagger_remaining = maxf(float(boss._stagger_remaining) - delta, 0.0)
	boss._tether_flash = maxf(float(boss._tether_flash) - delta, 0.0)
	boss._recoil *= exp(-14.0 * delta)
	boss._health_trail_delay = maxf(float(boss._health_trail_delay) - delta, 0.0)
	var health := float(boss.health)
	if boss._health_trail_delay == 0.0:
		var rate := float(boss.max_health) * delta * 0.6
		boss._health_trail = move_toward(float(boss._health_trail), health, rate)
	boss._health_trail = maxf(float(boss._health_trail), health)
	for ripple: Dictionary in boss._shield_ripples:
		ripple["age"] = float(ripple["age"]) + delta
	boss._shield_ripples = boss._shield_ripples.filter(func(r): return float(r["age"]) < 0.45)
	var exposed: bool = boss.weak_point_exposed()
	var window: bool = boss.phase == 2 or boss.enemy_id == &"tidal_heart"
	if exposed != boss._was_open and window:
		if exposed:
			GameJuice.play_sfx(&"boss_open")
			CombatFeedback.spawn_phase_burst(boss, boss._boss_accent_color(), boss._core_local())
		else:
			GameJuice.play_sfx(&"boss_close")
			spawn_close_puff(boss)
	boss._was_open = exposed
	boss._open_elapsed = float(boss._open_elapsed) + delta if exposed else 0.0
	if boss.enemy_id == &"furnace_mother" and boss.phase == 2:
		boss._steam_timer -= delta
		if boss._steam_timer <= 0.0:
			boss._steam_timer = 0.12 if boss._branch_open else 0.3
			spawn_heat_particle(boss)


static func apply_presentation(boss: Node) -> void:
	var sprite: Sprite2D = boss._sprite
	var age: float = boss._age
	var accent: Color = boss._boss_accent_color()
	var tidal: bool = boss.enemy_id == &"tidal_heart"
	var pose := Telegraphs.pose(boss)
	sprite.position = boss._visual_base_position + boss._recoil + pose["offset"]
	sprite.position.y += sin(age * 1.8) * (4.0 if tidal else 1.5)
	sprite.scale = boss._visual_base_scale * (pose["scale"] as Vector2)
	sprite.rotation = sin(age * 1.25) * (0.018 if tidal else 0.008) + float(pose["rotation"])
	sprite.modulate = Color.WHITE
	var look := state_look(boss)
	var glow: float = look["glow"]
	var glow_color: Color = look["glow_color"]
	var flash := 0.0
	var flash_color := Color.WHITE
	if float(boss._telegraph_remaining) > 0.0:
		var attack_pulse := 0.5 + 0.5 * sin(age * 26.0)
		glow = maxf(glow, 0.45 + attack_pulse * 0.35)
		glow_color = accent
		flash = float(pose["flash"])
		flash_color = accent.lightened(0.6)
	var stagger: float = boss._stagger_remaining
	if stagger > 0.0:
		var shake: float = stagger / float(boss.STAGGER_SECONDS)
		sprite.position += Vector2(sin(age * 80.0), cos(age * 67.0)) * 6.0 * shake
		flash = maxf(flash, 0.35 * shake)
		flash_color = accent
	var strength := GameJuice.flash_strength()
	if float(boss._hit_flash_remaining) > 0.0:
		flash = clampf(float(boss._hit_flash_remaining) / float(boss.HIT_FLASH_SECONDS), 0.0, 1.0)
		flash *= 0.85 * strength
		flash_color = Color(1.0, 0.97, 0.9)
		sprite.scale *= 1.02
	elif float(boss._block_flash_remaining) > 0.0:
		flash = 0.45 * strength
		flash_color = Color(0.6, 0.66, 0.76)
		sprite.position.x += sin(age * 95.0) * 2.5
	var fx: ShaderMaterial = boss._fx
	if fx != null:
		fx.set_shader_parameter(&"flash_amount", flash)
		fx.set_shader_parameter(&"flash_color", flash_color)
		fx.set_shader_parameter(&"glow_amount", glow)
		fx.set_shader_parameter(&"glow_color", glow_color)
		fx.set_shader_parameter(&"frost_amount", look["frost"])
		fx.set_shader_parameter(&"darken_amount", look["darken"])
	var overlay: Node2D = boss._overlay
	if overlay != null:
		overlay.queue_redraw()


static func apply_state_art(boss: Node) -> void:
	if not boss.has_state_art():
		return
	var sprite: Sprite2D = boss._sprite
	sprite.texture = boss._open_texture if boss.weak_point_exposed() else boss._closed_texture
	# D19 "Bubble -> Harpoon": Bubble Snare encases the exposed core; a harpoon pops it.
	var bubbled: bool = boss.phase == 1 and boss._branch_open and not boss._core_cracked
	var radius: float = boss.CORE_BUBBLE_RADIUS
	if bubbled and not is_instance_valid(boss._core_bubble):
		boss._core_bubble = BubbleVisual.attach(
			boss, Rect2(-radius, -radius, radius * 2.0, radius * 2.0), 4
		)
	var bubble: BubbleVisual = boss._core_bubble
	if is_instance_valid(bubble):
		bubble.visible = bubbled
		bubble.position = boss._core_local()
		var closing := float(boss._branch_timer) / float(boss.CLOSING_WARNING_SECONDS)
		bubble.warning = clampf(1.0 - closing, 0.0, 1.0) if bubbled else 0.0


static func release_feedback(boss: Node2D, attack: StringName) -> void:
	var parent: Node = boss._effect_parent()
	if parent == null:
		return
	var feet := boss.global_position + Vector2(0.0, 88.0)
	if Telegraphs.RISE_ATTACKS.has(attack):
		CombatFx.spawn_dust(parent, feet, &"land", 1.0, 2.5)
		GameJuice.shake(boss, 6.0, 0.25)
	elif Telegraphs.LUNGE_ATTACKS.has(attack):
		CombatFx.spawn_dust(parent, feet, &"skid", float(boss._facing), 2.0)
	else:
		CombatFx.spawn_muzzle_flash(
			parent, boss._core_world_position(), Vector2.UP, boss._boss_accent_color()
		)


static func charge_impact(boss: Node2D) -> void:
	var parent: Node = boss._effect_parent()
	if parent != null:
		var front := boss.global_position + Vector2(float(boss._facing) * 90.0, 40.0)
		CombatFx.spawn_dust(parent, front, &"wall", -float(boss._facing), 2.5)
	GameJuice.shake(boss, 7.0, 0.3)


static func spawn_compact_hit(
	boss: Node, impact_position: Vector2, direction := Vector2.ZERO, heavy := false
) -> void:
	var parent: Node = boss._effect_parent()
	if parent != null:
		var tint: Color = boss._boss_accent_color().lightened(0.25)
		CombatFeedback.spawn_hit(parent, impact_position, false, direction, heavy, tint)


static func spawn_blocked_hit(
	boss: Node2D, impact_position: Vector2, direction := Vector2.ZERO
) -> void:
	var parent: Node = boss._effect_parent()
	if parent != null:
		CombatFeedback.spawn_blocked_hit(parent, impact_position, direction)
	boss._block_flash_remaining = boss.BLOCK_FLASH_SECONDS
	if boss.enemy_id == &"tidal_heart" and boss.phase == 2:
		boss._shield_ripples.append({"position": boss.to_local(impact_position), "age": 0.0})
	if Audio.has_method(&"play_sfx"):
		GameJuice.play_sfx(&"armor_clink", &"beam_ricochet")


static func spawn_close_puff(boss: Node2D) -> void:
	var parent: Node = boss._effect_parent()
	if parent == null:
		return
	var tint := Color(0.5, 0.5, 0.52, 0.5)
	for index in 3:
		var puff := CombatFx.Puff.new()
		parent.add_child(puff)
		puff.global_position = boss._core_world_position()
		puff.z_index = 6
		var angle := TAU * float(index) / 3.0 + float(boss._age)
		puff.configure(Vector2.RIGHT.rotated(angle) * 70.0, 0.35, 10.0, 34.0, tint)


static func spawn_heat_particle(boss: Node2D) -> void:
	var parent: Node = boss._effect_parent()
	if parent == null or not boss.is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var puff := CombatFx.Puff.new()
	parent.add_child(puff)
	var spread := Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-170.0, -40.0))
	puff.global_position = boss.global_position + boss._visual_base_position + spread
	puff.z_index = 6
	if boss._branch_open:
		# Cooling window: pale steam vents off the cracked shell.
		var rise := Vector2(0.0, -rng.randf_range(80.0, 150.0))
		puff.configure(rise, 0.7, 8.0, 36.0, Color(0.85, 0.87, 0.9, 0.4), 1.5)
	else:
		# Overheated: embers rise off the white-hot carapace.
		var rise := Vector2(rng.randf_range(-20.0, 20.0), -rng.randf_range(120.0, 220.0))
		puff.configure(rise, 0.45, 3.0, 5.0, Color(1.0, 0.72, 0.3, 0.9), 0.5)
