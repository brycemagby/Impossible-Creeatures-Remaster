// Minimap background: ground colour darkened by the fog-of-war texture.
shader_type canvas_item;

uniform vec4 ground_color : source_color = vec4(0.3, 0.42, 0.2, 1.0);
uniform bool fog_enabled = true;

void fragment() {
	float state = fog_enabled ? texture(TEXTURE, UV).r : 1.0;
	float light = state < 0.5 ? mix(0.08, 0.45, state * 2.0) : mix(0.45, 1.0, (state - 0.5) * 2.0);
	COLOR = vec4(ground_color.rgb * light, 1.0);
}
