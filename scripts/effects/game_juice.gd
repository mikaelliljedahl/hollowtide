class_name GameJuice
extends RefCounted
## Shared combat "juice": camera shake, hit-stop and flash intensity.
##
## Accessibility: every shake amplitude is multiplied by the float setting
## `accessibility/screen_shake` (0..1, default 1.0) and `accessibility/reduce_flashes`
## (bool) shortens/tones down sprite flashes. The UI lane mirrors both from
## `user://settings.cfg` (section `accessibility`) into ProjectSettings at runtime; when
## ProjectSettings has no value yet the cfg file is read once as a fallback.
## Hit-stop is skipped in headless runs and `--test-mode` so automated checks stay
## deterministic.

const SETTINGS_PATH := "user://settings.cfg"
const SHAKE_SETTING := "accessibility/screen_shake"
const REDUCE_FLASHES_SETTING := "accessibility/reduce_flashes"
const SHAKER_NAME := "JuiceShaker"
const MAX_SHAKE := 18.0
const HIT_STOP_SCALE := 0.25
const MAX_HIT_STOP := 0.06
## Minimum real time between two hit-stops so rapid fights never feel like slow motion.
const HIT_STOP_COOLDOWN_MSEC := 400

## Global kill switch for all camera shake (e.g. for capture tools).
static var shake_enabled := true
static var _file_settings_loaded := false
static var _file_shake := 1.0
static var _file_reduce_flashes := false
static var _hit_stop_until_msec := 0
static var _hit_stop_active := false


static func screen_shake_scale() -> float:
	if ProjectSettings.has_setting(SHAKE_SETTING):
		return clampf(float(ProjectSettings.get_setting(SHAKE_SETTING, 1.0)), 0.0, 1.0)
	_load_file_settings()
	return _file_shake


static func reduce_flashes() -> bool:
	if ProjectSettings.has_setting(REDUCE_FLASHES_SETTING):
		return bool(ProjectSettings.get_setting(REDUCE_FLASHES_SETTING, false))
	_load_file_settings()
	return _file_reduce_flashes


## Multiplier for sprite flash strength (1.0 normally, lower with reduce_flashes).
static func flash_strength() -> float:
	return 0.55 if reduce_flashes() else 1.0


## Re-read the settings file (call after the settings screen saves).
static func reload_settings() -> void:
	_file_settings_loaded = false
	_load_file_settings()


## Shake the active 2D camera. `strength` is the peak offset in pixels.
static func shake(source: Node, strength: float, duration := 0.22) -> void:
	if not shake_enabled or source == null or not source.is_inside_tree():
		return
	var amount := minf(strength, MAX_SHAKE) * screen_shake_scale()
	if amount <= 0.05 or duration <= 0.0:
		return
	var camera := source.get_viewport().get_camera_2d()
	if camera == null:
		return
	var shaker := camera.get_node_or_null(SHAKER_NAME) as CameraShaker
	if shaker == null:
		shaker = CameraShaker.new()
		shaker.name = SHAKER_NAME
		camera.add_child(shaker)
	shaker.add_trauma(amount, duration)


## Freeze gameplay for a few frames to sell an impact. Very short by design.
static func hit_stop(source: Node, seconds: float) -> void:
	if source == null or not source.is_inside_tree() or seconds <= 0.0:
		return
	if DisplayServer.get_name() == "headless":
		return
	if OS.get_cmdline_user_args().has("--test-mode") or OS.get_cmdline_args().has("--test-mode"):
		return
	var tree := source.get_tree()
	if tree == null or tree.paused:
		return
	var now := Time.get_ticks_msec()
	if now < _hit_stop_until_msec + HIT_STOP_COOLDOWN_MSEC:
		return
	var until := now + int(minf(seconds, MAX_HIT_STOP) * 1000.0)
	_hit_stop_until_msec = until
	if not _hit_stop_active:
		_hit_stop_active = true
		Engine.time_scale = HIT_STOP_SCALE
	var timer := tree.create_timer(minf(seconds, MAX_HIT_STOP), true, false, true)
	timer.timeout.connect(_release_hit_stop, CONNECT_ONE_SHOT)


static func _release_hit_stop() -> void:
	# A SceneTreeTimer can fire up to a frame early relative to the tick clock. Never leave the
	# game slowed: if the stop was extended (or the timer fired early), re-arm for the remainder.
	var remaining_msec := _hit_stop_until_msec - Time.get_ticks_msec()
	var tree := Engine.get_main_loop() as SceneTree
	if remaining_msec > 1 and tree != null:
		var timer := tree.create_timer(remaining_msec / 1000.0, true, false, true)
		timer.timeout.connect(_release_hit_stop, CONNECT_ONE_SHOT)
		return
	_hit_stop_active = false
	Engine.time_scale = 1.0


## Safety net: restore normal speed if a hit-stop outlived its window (e.g. across a scene change).
static func ensure_time_restored() -> void:
	if _hit_stop_active and Time.get_ticks_msec() > _hit_stop_until_msec + 50:
		_hit_stop_active = false
		Engine.time_scale = 1.0


static func _load_file_settings() -> void:
	if _file_settings_loaded:
		return
	_file_settings_loaded = true
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	_file_shake = clampf(float(config.get_value("accessibility", "screen_shake", 1.0)), 0.0, 1.0)
	_file_reduce_flashes = bool(config.get_value("accessibility", "reduce_flashes", false))


class CameraShaker:
	extends Node
	## Adds a decaying, noise-like offset to its parent Camera2D.

	var _amount := 0.0
	var _duration := 0.2
	var _remaining := 0.0
	var _seed := 0.0
	var _applied := Vector2.ZERO

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE

	func add_trauma(amount: float, duration: float) -> void:
		# Stack gently: a bigger hit replaces a smaller one, small hits never cancel big ones.
		var current := _amount * (_remaining / maxf(_duration, 0.001))
		if amount >= current:
			_amount = amount
			_duration = duration
			_remaining = duration
		_seed = randf() * 100.0

	func _process(delta: float) -> void:
		var camera := get_parent() as Camera2D
		if camera == null:
			return
		camera.offset -= _applied
		_applied = Vector2.ZERO
		if _remaining <= 0.0:
			return
		# Use real time so hit-stop does not freeze the shake.
		var real_delta := delta / maxf(Engine.time_scale, 0.001)
		_remaining = maxf(_remaining - real_delta, 0.0)
		var fade := _remaining / maxf(_duration, 0.001)
		var t := Time.get_ticks_msec() * 0.001 * 38.0 + _seed
		var amount := _amount * fade * fade
		_applied = (
			(
				Vector2(sin(t * 1.13) + sin(t * 2.71) * 0.5, cos(t * 1.37) + sin(t * 3.07) * 0.5)
				* amount
				* 0.66
			)
			. round()
		)
		camera.offset += _applied

	func _exit_tree() -> void:
		var camera := get_parent() as Camera2D
		if camera != null:
			camera.offset -= _applied
		_applied = Vector2.ZERO


## Play the first SFX id the audio lane provides; silently skip unknown ids.
static func play_sfx(primary: StringName, fallback: StringName = &"") -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := tree.root.get_node_or_null("Audio") if tree != null else null
	if audio == null or not audio.has_method(&"play_sfx"):
		return
	var script := audio.get_script() as Script
	var known: Dictionary = script.get_script_constant_map().get("SFX_PATHS", {}) if script else {}
	if known.has(primary):
		audio.call(&"play_sfx", primary)
	elif fallback != &"" and known.has(fallback):
		audio.call(&"play_sfx", fallback)
