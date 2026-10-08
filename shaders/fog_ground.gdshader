// Ground that darkens with fog of war: black where unexplored, dim where
// explored but out of sight, full colour where currently visible.
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.3, 0.42, 0.2, 1.0);
// R channel: 0 = unexplored, ~0.5 = explored, 1 = visible.
uniform sampler2D fog : filter_linear, repeat_disable;
// Map area covered by the fog texture: (x, z, width, depth).
uniform vec4 map_rect = vec4(-50.0, -50.0, 100.0, 100.0);
uniform bool fog_enabled = true;
uniform float unexplored_light = 0.08;
uniform float explored_light = 0.45;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float light = 1.0;
	if (fog_enabled) {
		vec2 uv = (world_position.xz - map_rect.xy) / map_rect.zw;
		// Soften the 1 m grid with a small blur so fog edges look round.
		vec2 texel = 1.5 / vec2(textureSize(fog, 0));
		float state = 0.0;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				state += texture(fog, uv + vec2(float(x), float(y)) * texel).r;
			}
		}
		state /= 9.0;
		light = state < 0.5
				? mix(unexplored_light, explored_light, state * 2.0)
				: mix(explored_light, 1.0, (state - 0.5) * 2.0);
	}
	ALBEDO = albedo.rgb * light;
	ROUGHNESS = 1.0;
}
