extends RefCounted
## Assist options (D22): optional help set in the settings menu, never in the game world.
##
## The ui lane stores them in `user://settings.cfg` section `assist` and mirrors them to
## ProjectSettings `assist/game_speed` (0.5..1.0), `assist/damage_taken` (0..1) and
## `assist/skip_ambushes` (bool). Gameplay reads them here only. When ProjectSettings has no value
## yet (a direct campaign launch skips the menus) the cfg file is read once. Test runs always get
## the defaults so automated checks stay deterministic.

const SETTINGS_PATH := "user://settings.cfg"
const GAME_SPEED := "assist/game_speed"
const DAMAGE_TAKEN := "assist/damage_taken"
const SKIP_AMBUSHES := "assist/skip_ambushes"
const MIN_GAME_SPEED := 0.5
const DEFAULTS := {GAME_SPEED: 1.0, DAMAGE_TAKEN: 1.0, SKIP_AMBUSHES: false}

## Values set by automated checks; they win over test-mode defaults.
static var forced: Dictionary = {}
static var _file: ConfigFile


static func game_speed() -> float:
	return clampf(float(_value(GAME_SPEED)), MIN_GAME_SPEED, 1.0)


static func damage_taken() -> float:
	return clampf(float(_value(DAMAGE_TAKEN)), 0.0, 1.0)


static func skip_ambushes() -> bool:
	return bool(_value(SKIP_AMBUSHES))


## Damage after the assist multiplier: rounded up so any non-zero setting still hurts.
static func scale_damage(amount: int) -> int:
	var scale := damage_taken()
	if amount <= 0 or scale <= 0.0:
		return 0
	return maxi(1, ceili(float(amount) * scale))


## Sets the engine's base speed; the hit-stop scales relative to it.
static func apply_game_speed() -> void:
	Engine.time_scale = game_speed()


static func is_test_run() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return args.has("--test-mode") or args.has("--benchmark-cave")


static func _value(key: String) -> Variant:
	if forced.has(key):
		return forced[key]
	if is_test_run():
		return DEFAULTS[key]
	if ProjectSettings.has_setting(key):
		return ProjectSettings.get_setting(key, DEFAULTS[key])
	if _file == null:
		_file = ConfigFile.new()
		_file.load(SETTINGS_PATH)
	return _file.get_value("assist", key.trim_prefix("assist/"), DEFAULTS[key])
