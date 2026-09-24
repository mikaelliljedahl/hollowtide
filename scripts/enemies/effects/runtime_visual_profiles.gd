class_name RuntimeVisualProfiles
extends RefCounted

const MANIFEST_PATH := "res://assets/sprites/devmode/devmode_art_manifest.json"
const ENEMY_FRAME_HEIGHT := 256.0
const BOSS_FRAME_HEIGHT := 512.0
const GROUND_BODY_HALF_HEIGHT := 25.0
const BOSS_BODY_RADIUS := 92.0
const ART_OVERRIDE_DIR := "res://assets/sprites/combat/"

static var _profiles: Dictionary = {}
static var _override_bounds: Dictionary = {}


static func profile(runtime_id: StringName) -> Dictionary:
	_load_once()
	var data: Dictionary = _profiles.get(String(runtime_id), {}).duplicate(true)
	var bounds := _override_visible_bounds(runtime_id)
	if not bounds.is_empty():
		data["nominal_visible_bounds_px"] = bounds
	return data


## Restyled art in assets/sprites/combat/ replaces the dev-mode sprite; its measured
## alpha bounds replace the manifest bounds so ground contact stays exact.
static func override_texture_path(runtime_id: StringName) -> String:
	var path := ART_OVERRIDE_DIR + "%s.png" % String(runtime_id)
	if runtime_id == &"shooting_gargoyle":
		path = ART_OVERRIDE_DIR + "shooting_gargoyle_folded.png"
	return path if ResourceLoader.exists(path) else ""


static func _override_visible_bounds(runtime_id: StringName) -> Array:
	var key := String(runtime_id)
	if _override_bounds.has(key):
		return _override_bounds[key]
	var result: Array = []
	var path := override_texture_path(runtime_id)
	if not path.is_empty():
		var texture := load(path) as Texture2D
		var image := texture.get_image() if texture != null else null
		if image != null and not image.is_empty():
			var used := image.get_used_rect()
			result = [used.position.x, used.position.y, used.end.x, used.end.y]
	_override_bounds[key] = result
	return result


static func visual_offset(runtime_id: StringName) -> Vector2:
	var data := profile(runtime_id)
	var values: Array = data.get("local_visual_offset_px", [])
	if values.size() != 2:
		return Vector2.ZERO
	var offset := Vector2(float(values[0]), float(values[1]))
	var bounds: Array = data.get("nominal_visible_bounds_px", [])
	if not bool(data.get("grounded", false)) or runtime_id == &"crawler" or bounds.size() != 4:
		return offset
	var is_boss := runtime_id in [&"stone_guardian", &"furnace_mother"]
	var frame_height := BOSS_FRAME_HEIGHT if is_boss else ENEMY_FRAME_HEIGHT
	if float(bounds[3]) > frame_height:
		return offset
	var visible_bottom := (float(bounds[3]) - frame_height * 0.5) * visual_scale(runtime_id)
	var physical_support := BOSS_BODY_RADIUS if is_boss else GROUND_BODY_HALF_HEIGHT
	offset.y = physical_support - visible_bottom
	return offset


static func visual_scale(runtime_id: StringName) -> float:
	return float(profile(runtime_id).get("desired_texture_scale", 1.0))


static func _load_once() -> void:
	if not _profiles.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary:
		_profiles = parsed.get("runtime_visual_profiles", {})
