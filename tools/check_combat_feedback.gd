extends Node2D

const CombatFeedbackScript = preload("res://scripts/effects/combat_feedback.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const BOMB_SCENE: PackedScene = preload("res://scenes/combat/bomb.tscn")
const HOPPER_TEXTURE = preload("res://assets/sprites/devmode/hopper.png")
const FROST_TEXTURE = preload("res://assets/sprites/devmode/frost_floater.png")
const BOSS_TEXTURE = preload("res://assets/sprites/devmode/stone_guardian.png")
const SWITCH_AUDIO = "res://assets/audio/sfx/weapon_switch.wav"

var failures: Array[String] = []
var _visual_demo := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_visual_demo = name == "CombatFeedbackSmoke"
	if _visual_demo:
		queue_redraw()
		call_deferred("_show_demo")
	else:
		call_deferred("_run_tests")


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), Color("#0b0e14"))
	if not _visual_demo:
		return
	draw_circle(Vector2(320.0, 420.0), 210.0, Color(0.05, 0.12, 0.16, 0.45))
	draw_circle(Vector2(960.0, 420.0), 210.0, Color(0.05, 0.12, 0.18, 0.45))
	draw_circle(Vector2(1600.0, 420.0), 330.0, Color(0.12, 0.07, 0.05, 0.45))


func _show_demo() -> void:
	_add_label("NORMAL", Vector2(270.0, 720.0), Color("#a9c2b8"))
	_add_label("FROZEN", Vector2(900.0, 720.0), Color("#8edfe7"))
	_add_label("BOSS", Vector2(1540.0, 800.0), Color("#d18b66"))
	_spawn_source(HOPPER_TEXTURE, Vector2(320.0, 420.0), false, false, 1.0)
	_spawn_source(FROST_TEXTURE, Vector2(960.0, 420.0), false, true, 1.0)
	_spawn_source(BOSS_TEXTURE, Vector2(1600.0, 420.0), true, false, 0.48)


func _spawn_source(
	texture: Texture2D, position: Vector2, boss: bool, frozen: bool, scale_value: float
) -> void:
	var source := Node2D.new()
	source.position = position
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * scale_value
	source.add_child(sprite)
	add_child(source)
	CombatFeedbackScript.spawn_death(source, boss, frozen)
	source.queue_free()


func _add_label(text: String, position: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 28)
	add_child(label)


func _run_tests() -> void:
	_check(FileAccess.file_exists(SWITCH_AUDIO), "weapon switch cue generated")
	await _test_normal_and_pause()
	await _test_frozen_and_boss()
	await _test_bomb_explosion()
	await _test_switch_audio()
	await _test_blocked_hit()
	if failures.is_empty():
		print("PASS: combat feedback art snapshots, pause, bounded cleanup, and switch semantics")
	else:
		for failure in failures:
			push_error(failure)
		await TestShutdown.finish(get_tree(), 1)
		return
	await TestShutdown.finish(get_tree())


func _test_normal_and_pause() -> void:
	var source := _make_source(HOPPER_TEXTURE, Vector2(240.0, 260.0), 1.0)
	var effect = CombatFeedbackScript.spawn_death(source)
	source.queue_free()
	await get_tree().physics_frame
	_check(effect != null, "normal death returns effect")
	_check(
		get_tree().get_nodes_in_group(&"transient").size() >= 10,
		"normal burst has transient layers"
	)
	var elapsed_before: float = effect.get("_elapsed")
	get_tree().paused = true
	await get_tree().physics_frame
	var elapsed_paused: float = effect.get("_elapsed")
	get_tree().paused = false
	_check(is_equal_approx(elapsed_before, elapsed_paused), "pause freezes effect visual")
	await _frames(40)
	_check(get_tree().get_nodes_in_group(&"transient").is_empty(), "normal burst self-cleans")


func _test_frozen_and_boss() -> void:
	var frozen_source := _make_source(FROST_TEXTURE, Vector2(420.0, 260.0), 1.0)
	var frozen = CombatFeedbackScript.spawn_death(frozen_source, false, true)
	frozen_source.queue_free()
	var boss_source := _make_source(BOSS_TEXTURE, Vector2(700.0, 260.0), 0.48)
	var boss = CombatFeedbackScript.spawn_death(boss_source, true, false)
	boss_source.queue_free()
	var animated_source := Node2D.new()
	animated_source.position = Vector2(980.0, 260.0)
	var animated := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.add_frame(&"default", HOPPER_TEXTURE)
	animated.sprite_frames = frames
	animated.animation = &"default"
	animated.frame = 0
	animated_source.add_child(animated)
	add_child(animated_source)
	var animated_effect = CombatFeedbackScript.spawn_death(animated_source)
	animated_source.queue_free()
	await get_tree().physics_frame
	_check(
		frozen != null and boss != null and animated_effect != null,
		"frozen, boss, and animated snapshots return effects"
	)
	_check(
		get_tree().get_nodes_in_group(&"transient").size() >= 24,
		"boss burst stays within layered budget"
	)
	await _frames(70)
	_check(get_tree().get_nodes_in_group(&"transient").is_empty(), "boss burst self-cleans")
	var reset_source := _make_source(HOPPER_TEXTURE, Vector2(1200.0, 260.0), 1.0)
	CombatFeedbackScript.spawn_death(reset_source)
	reset_source.queue_free()
	await get_tree().physics_frame
	get_node("/root/Weapons").reset_runtime()
	await get_tree().physics_frame
	_check(get_tree().get_nodes_in_group(&"transient").is_empty(), "runtime reset cleans feedback")


func _test_bomb_explosion() -> void:
	var bomb := BOMB_SCENE.instantiate() as Node2D
	add_child(bomb)
	bomb.global_position = Vector2(520.0, 260.0)
	bomb.call("_explode")
	await get_tree().physics_frame
	_check(not is_instance_valid(bomb), "bomb removes source at detonation")
	# D19 Resonance Pulse: the burst is an expanding resonance ring (ArsenalFx).
	var pulse: ArsenalFx = null
	for transient in get_tree().get_nodes_in_group(&"transient"):
		if transient is ArsenalFx and transient.kind == &"ring":
			pulse = transient
			break
	_check(pulse != null, "pulse detonation creates a resonance ring")
	if pulse != null:
		_check(pulse.lifetime <= 0.40, "pulse ring stays compact")
		_check(pulse.end_radius <= Catalog.BOMB_RADIUS, "pulse ring stays within catalog radius")
	await _frames(30)
	var leftover := false
	for transient in get_tree().get_nodes_in_group(&"transient"):
		leftover = leftover or transient is ArsenalFx
	_check(not leftover, "pulse feedback self-cleans")


func _test_blocked_hit() -> void:
	var effect = CombatFeedbackScript.spawn_blocked_hit(self, Vector2(760.0, 260.0))
	await get_tree().physics_frame
	_check(effect != null and effect.get("_effect_kind") == &"blocked", "blocked hit is distinct")
	_check(effect.get("_flash") == null, "blocked hit has no damaging flash")
	_check(effect.get("_ring") != null, "blocked hit has outward ricochet ring")
	await _frames(12)
	_check(not _has_effect_kind(&"blocked"), "blocked hit feedback self-cleans")


func _has_effect_kind(kind: StringName) -> bool:
	for transient in get_tree().get_nodes_in_group(&"transient"):
		if transient is CombatFeedbackScript and transient.get("_effect_kind") == kind:
			return true
	return false


func _test_switch_audio() -> void:
	var game_state := get_node("/root/GameState")
	game_state.reset_progress()
	await get_tree().physics_frame
	_check(not _switch_is_playing(), "startup/reset does not play switch cue")
	game_state.acquire_beam()
	await get_tree().physics_frame
	_check(not _switch_is_playing(), "beam acquisition does not play switch cue")
	game_state.unlock_ability(&"ice_beam")
	# The cue is 68 ms long: a slow frame on a loaded machine can end it before the next physics
	# frame, so sample right away as well.
	var cue_started := _switch_is_playing()
	await get_tree().physics_frame
	_check(cue_started or _switch_is_playing(), "successful auto-equip plays switch cue")
	await _frames(8)
	_check(game_state.set_active_beam(&"ice"), "unchanged active beam remains valid")
	await get_tree().physics_frame
	_check(not _switch_is_playing(), "unchanged active beam does not replay cue")
	_check(not game_state.set_active_beam(&"wave"), "failed beam selection rejected")
	await get_tree().physics_frame
	_check(not _switch_is_playing(), "failed beam selection does not play cue")
	game_state.reset_progress()


func _make_source(texture: Texture2D, position: Vector2, scale_value: float) -> Node2D:
	var source := Node2D.new()
	source.position = position
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * scale_value
	source.add_child(sprite)
	add_child(source)
	return source


func _switch_is_playing() -> bool:
	var stream := load(SWITCH_AUDIO) as AudioStream
	for player in get_node("/root/Audio").get_children():
		if player is AudioStreamPlayer and player.stream == stream and player.playing:
			return true
	return false


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % label)
