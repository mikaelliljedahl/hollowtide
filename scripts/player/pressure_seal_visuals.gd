class_name PressureSealVisuals
extends Node2D

## Pressure Seal (internal id `pressure_seal`): the sealed layer she wears once found. Mirrors the player
## sprite every frame and paints a cool-blue sealed accent over it — a thin rim, a collar/gorget
## band, a waist seam and shin cuffs — so it follows every pose without per-pose art. Inside a
## heat zone the seal flares and sheds tiny cool-blue motes: the heat is being held off.

const ABILITY := &"pressure_seal"
const SEAL_COLOR := Color(0.5, 0.85, 1.0)
const SHADER_CODE := """
shader_type canvas_item;
uniform vec4 seal_color : source_color = vec4(0.5, 0.85, 1.0, 1.0);
uniform vec2 frame_size = vec2(256.0, 256.0);
uniform float intensity = 0.55;
uniform float time_offset = 0.0;
uniform vec2 body_span = vec2(0.0, 1.0);
uniform float seam_strength = 1.0;
varying vec2 local_uv;

void vertex() {
	local_uv = VERTEX / frame_size + vec2(0.5);
}

float band(float y, float center, float half_width) {
	return 1.0 - smoothstep(half_width * 0.5, half_width, abs(y - center));
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	float n = min(
		min(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
		min(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a)
	);
	float rim = clamp(a - n, 0.0, 1.0);
	float body = smoothstep(0.85, 1.0, n);
	vec3 base = texture(TEXTURE, UV).rgb;
	float dark = 1.0 - smoothstep(0.35, 0.8, dot(base, vec3(0.3, 0.5, 0.2)));
	float y = (local_uv.y - body_span.x) / max(body_span.y - body_span.x, 0.01);
	float seams = band(y, 0.195, 0.016) + band(y, 0.45, 0.009) * 0.6 + band(y, 0.86, 0.013) * 0.8;
	float pulse = 0.8 + 0.2 * sin(TIME * 2.2 + time_offset);
	float glow = (rim * 0.8 + seams * seam_strength * body * dark * 0.9) * intensity * pulse;
	COLOR = vec4(seal_color.rgb, clamp(glow, 0.0, 1.0) * a);
}
"""

var _source: AnimatedSprite2D
var _overlay: AnimatedSprite2D
var _material: ShaderMaterial
var _motes: CPUParticles2D
var _heat_flare := 0.0
var _spans := {}


func _ready() -> void:
	if _source == null and get_parent().has_node(^"AnimatedSprite2D"):
		setup(get_parent().get_node(^"AnimatedSprite2D") as AnimatedSprite2D)


func setup(source: AnimatedSprite2D) -> void:
	_source = source
	_overlay = AnimatedSprite2D.new()
	_overlay.name = &"SealOverlay"
	_overlay.sprite_frames = source.sprite_frames
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter(&"seal_color", SEAL_COLOR)
	_overlay.material = _material
	_overlay.z_index = 1
	add_child(_overlay)
	_motes = CPUParticles2D.new()
	_motes.emitting = false
	_motes.amount = 26
	_motes.lifetime = 0.9
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(26, 70)
	_motes.position = Vector2(0, -96)
	_motes.direction = Vector2.UP
	_motes.spread = 30.0
	_motes.gravity = Vector2(0, -40)
	_motes.initial_velocity_min = 10.0
	_motes.initial_velocity_max = 35.0
	_motes.scale_amount_min = 2.0
	_motes.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.95, 1.0, 0.9))
	ramp.set_color(1, Color(0.45, 0.8, 1.0, 0.0))
	_motes.color_ramp = ramp
	_motes.z_index = 2
	add_child(_motes)


func is_sealed() -> bool:
	return GameState.has_ability(ABILITY)


func in_heat() -> bool:
	for zone in get_tree().get_nodes_in_group(&"campaign_heat"):
		if zone.has_method(&"player_inside") and zone.player_inside():
			return true
	return false


func _process(delta: float) -> void:
	if _source == null:
		return
	var sealed := is_sealed()
	_overlay.visible = sealed and _source.visible
	var heated := sealed and in_heat()
	_motes.emitting = heated
	_heat_flare = move_toward(_heat_flare, 1.0 if heated else 0.0, delta * 3.0)
	if not _overlay.visible:
		return
	if _overlay.animation != _source.animation:
		_overlay.animation = _source.animation
	_overlay.frame = _source.frame
	_overlay.position = _source.position
	_overlay.scale = _source.scale
	_overlay.rotation = _source.rotation
	_overlay.flip_h = _source.flip_h
	_overlay.offset = _source.offset
	_overlay.centered = _source.centered
	_overlay.modulate.a = _source.modulate.a
	var texture := _source.sprite_frames.get_frame_texture(_source.animation, _source.frame)
	if texture != null:
		_material.set_shader_parameter(&"frame_size", texture.get_size())
		_material.set_shader_parameter(&"body_span", _body_span(texture))
	# Seams only make sense on an upright body; the ball and spin keep the rim alone.
	var upright := not (
		String(_source.animation).begins_with("ball")
		or String(_source.animation).begins_with("spin")
		or String(_source.animation).begins_with("wall_slide")
	)
	_material.set_shader_parameter(&"seam_strength", 1.0 if upright else 0.0)
	_material.set_shader_parameter(&"intensity", 0.55 + 0.45 * _heat_flare)


## Vertical extent of opaque pixels in a frame (0..1), so seams sit on the body whatever the padding.
func _body_span(texture: Texture2D) -> Vector2:
	if _spans.has(texture):
		return _spans[texture]
	var span := Vector2(0.0, 1.0)
	var image := texture.get_image()
	if image != null:
		var used := image.get_used_rect()
		if used.size.y > 0:
			var height := float(image.get_height())
			span = Vector2(used.position.y / height, used.end.y / height)
	_spans[texture] = span
	return span
