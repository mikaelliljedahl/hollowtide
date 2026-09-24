shader_type canvas_item;
// Elite rim (docs/features/revisit-remix.md section 5). Drawn behind the enemy sprite with the same
// texture: every texel within `width` texels of the silhouette lights up in `rim_color`, pulsing
// slowly so the variant reads at a glance without a flash.

uniform vec4 rim_color : source_color = vec4(0.95, 0.3, 0.62, 1.0);
uniform float width = 6.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.3;

varying vec4 modulate_color;

void vertex() {
	modulate_color = COLOR;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float cover = texture(TEXTURE, UV).a;
	for (int step = 0; step < 8; step++) {
		float angle = float(step) * 0.785398;
		vec2 dir = vec2(cos(angle), sin(angle));
		cover = max(cover, texture(TEXTURE, UV + dir * px).a);
		cover = max(cover, texture(TEXTURE, UV + dir * px * 0.5).a);
	}
	float beat = 1.0 - pulse + pulse * (0.5 + 0.5 * sin(TIME * 3.2));
	COLOR = vec4(rim_color.rgb, rim_color.a * cover * beat * modulate_color.a);
}
