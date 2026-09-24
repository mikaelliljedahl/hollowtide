class_name EnvironmentKit
extends RefCounted
## Per-area art kit loaded from assets/environment/areas/<area>/area.json
## (built by tools/build_area_art.py).

const AREA_ROOT := "res://assets/environment/areas/"

var area_id: StringName
var far_parallax := 0.15
var mid_parallax := 0.35
var tint := Color(0.6, 0.66, 0.72)
var fog := Color(0.4, 0.5, 0.6)
var glow := Color(0, 0, 0, 0)
var far_modulate := Color(0.65, 0.65, 0.7)
var mid_modulate := Color(0.45, 0.45, 0.5)
var particles: StringName = &""
var textures: Dictionary[StringName, Texture2D] = {}
var background_edges: Dictionary[StringName, Array] = {}
var strip: Dictionary = {}
var props: Array[Dictionary] = []
var fluid_surface_y := 0.0
var manifest: Dictionary = {}


static func load_for(id: StringName) -> EnvironmentKit:
	var kit := EnvironmentKit.new()
	kit.area_id = id
	var path := AREA_ROOT + String(id) + "/area.json"
	if not FileAccess.file_exists(path):
		return kit
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return kit
	kit.manifest = parsed
	kit.far_parallax = float(parsed.get("far_parallax", kit.far_parallax))
	kit.mid_parallax = float(parsed.get("mid_parallax", kit.mid_parallax))
	kit.tint = _color(parsed.get("tint"), kit.tint)
	kit.fog = _color(parsed.get("fog"), kit.fog)
	kit.glow = _color(parsed.get("glow"), kit.glow)
	kit.far_modulate = _color(parsed.get("far_modulate"), kit.far_modulate)
	kit.mid_modulate = _color(parsed.get("mid_modulate"), kit.mid_modulate)
	kit.particles = StringName(parsed.get("particles", ""))
	kit.strip = parsed.get("strip", {})
	var material: Dictionary = parsed.get("material", {})
	for role in material:
		kit._load_texture(StringName(role), String(material[role]))
	var background: Dictionary = parsed.get("background", {})
	for layer in background:
		var entry: Dictionary = background[layer]
		kit._load_texture(StringName(layer), String(entry.get("path", "")))
		kit.background_edges[StringName(layer)] = [
			_color(entry.get("top_color"), Color.BLACK),
			_color(entry.get("bottom_color"), Color.BLACK),
		]
	var fluid = parsed.get("fluid")
	if fluid is Dictionary:
		kit._load_texture(&"fluid", String(fluid.get("path", "")))
		kit.fluid_surface_y = float(fluid.get("surface_y", 0.0))
	for prop in parsed.get("props", []):
		if prop is Dictionary and ResourceLoader.exists(String(prop.get("path", ""))):
			var texture := load(String(prop["path"])) as Texture2D
			if texture != null:
				kit.props.append(
					{"texture": texture, "kind": StringName(prop.get("kind", "stand"))}
				)
	return kit


func texture(role: StringName) -> Texture2D:
	return textures.get(role)


func prop_of_kind(kind: StringName) -> Texture2D:
	for prop in props:
		if prop["kind"] == kind:
			return prop["texture"]
	return null


func strip_value(key: String, fallback: float) -> float:
	return float(strip.get(key, fallback))


func background_edge(layer: StringName, bottom: bool) -> Color:
	var edges: Array = background_edges.get(layer, [])
	if edges.size() < 2:
		return Color.BLACK
	return edges[1] if bottom else edges[0]


func _load_texture(role: StringName, path: String) -> void:
	if path != "" and ResourceLoader.exists(path):
		var loaded := load(path) as Texture2D
		if loaded != null:
			textures[role] = loaded


static func _color(value, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]))
	return fallback
