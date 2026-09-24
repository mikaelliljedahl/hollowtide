shader_type canvas_item;
// Per-sprite combat feedback: solid hit flash, frozen/ice look and a soft inner glow.
// Used by enemies, bosses and the player; each sprite owns its own ShaderMaterial.

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float glow_amount : hint_range(0.0, 2.0) = 0.0;
uniform float darken_amount : hint_range(0.0, 1.0) = 0.0;

// In Godot 4 the fragment COLOR already includes the texture; keep modulate separately.
varying vec4 modulate_color;

void vertex() {
	modulate_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = tex.rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	if (darken_amount > 0.0) {
		vec3 stone = vec3(lum) * vec3(0.78, 0.82, 0.9);
		c = mix(c, stone * 0.72, darken_amount);
	}
	if (glow_amount > 0.0) {
		// Brighten the already-bright parts (cores, seams) so they read as hot/alive.
		float hot = smoothstep(0.28, 0.75, lum);
		c += glow_color.rgb * hot * glow_amount;
	}
	if (frost_amount > 0.0) {
		vec3 ice = mix(vec3(0.32, 0.58, 0.82), vec3(0.9, 0.97, 1.0), smoothstep(0.06, 0.6, lum));
		vec2 px = TEXTURE_PIXEL_SIZE * 3.0;
		float inner = texture(TEXTURE, UV + vec2(px.x, 0.0)).a
			* texture(TEXTURE, UV - vec2(px.x, 0.0)).a
			* texture(TEXTURE, UV + vec2(0.0, px.y)).a
			* texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		float rim = clamp(1.0 - inner, 0.0, 1.0);
		// Diagonal frost streaks catch light like an ice coating.
		float streak = smoothstep(0.82, 1.0, sin((UV.x + UV.y) / (TEXTURE_PIXEL_SIZE.x * 23.0)));
		ice = mix(ice, vec3(1.0), clamp(rim * 0.95 + streak * 0.22, 0.0, 1.0));
		c = mix(c, ice, frost_amount);
	}
	c = mix(c, flash_color.rgb, flash_amount);
	COLOR = vec4(c, tex.a) * modulate_color;
}
