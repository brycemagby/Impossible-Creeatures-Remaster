// Water: a gently rippling surface with lighter crests and a pale band along
// the shore, darkened by fog of war.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/fog.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.1, 0.26, 0.48, 1.0);
uniform vec4 crest : source_color = vec4(0.55, 0.75, 0.85, 1.0);
// Per-vertex distance to the shore is in COLOR.r: 0 on the edge, 1 inland.
uniform float shore_width = 1.0;

varying vec3 world_position;
varying float inland;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	inland = COLOR.r;
}

void fragment() {
	vec2 p = world_position.xz;
	float t = TIME;
	float ripple = value_noise(p * 0.7 + vec2(t * 0.35, t * 0.2)) * 0.6
			+ value_noise(p * 1.6 - vec2(t * 0.25, -t * 0.4)) * 0.4;
	vec3 colour = albedo.rgb * mix(0.75, 1.05, ripple);
	colour = mix(colour, crest.rgb, smoothstep(0.72, 0.9, ripple) * 0.25);
	// Foam where the water meets the land.
	float foam = 1.0 - smoothstep(0.0, 0.25 * shore_width, inland);
	foam *= 0.6 + 0.4 * sin(t * 1.5 + (p.x + p.y) * 0.8);
	colour = mix(colour, vec3(0.85, 0.9, 0.88), foam * 0.6);
	ALBEDO = colour * fog_light(p);
	ROUGHNESS = 0.3;
	SPECULAR = 0.4;
}
