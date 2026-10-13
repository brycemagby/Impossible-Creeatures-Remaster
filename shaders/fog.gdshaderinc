// Fog of war for ground-level surfaces: black where unexplored, dim where
// explored but out of sight, full colour where currently visible.

// R channel: 0 = unexplored, ~0.5 = explored, 1 = visible.
uniform sampler2D fog : filter_linear, repeat_disable;
// Map area covered by the fog texture: (x, z, width, depth).
uniform vec4 map_rect = vec4(-50.0, -50.0, 100.0, 100.0);
uniform bool fog_enabled = true;
uniform float unexplored_light = 0.08;
uniform float explored_light = 0.45;

float fog_light(vec2 world_xz) {
	if (!fog_enabled) {
		return 1.0;
	}
	vec2 uv = (world_xz - map_rect.xy) / map_rect.zw;
	// Soften the 1 m grid with a small blur so fog edges look round.
	vec2 texel = 1.5 / vec2(textureSize(fog, 0));
	float state = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			state += texture(fog, uv + vec2(float(x), float(y)) * texel).r;
		}
	}
	state /= 9.0;
	return state < 0.5
			? mix(unexplored_light, explored_light, state * 2.0)
			: mix(explored_light, 1.0, (state - 0.5) * 2.0);
}

// Smooth value noise and a few octaves of it, for ground patterns.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.4);
		amplitude *= 0.5;
	}
	return total;
}
