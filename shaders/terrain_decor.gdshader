// Scattered ground clutter (grass tufts, pebbles, flowers) drawn as
// MultiMeshes with a colour per instance. Grass sways in the wind; all of
// it darkens with fog of war like the ground.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/fog.gdshaderinc"

uniform float sway = 0.0;
// Light flat cut-outs (grass, flowers) like the ground under them, from both sides.
uniform bool ground_lit = false;

void vertex() {
	if (sway > 0.0) {
		vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float gust = sin(TIME * 1.8 + base.x * 0.35 + base.z * 0.2);
		VERTEX.x += gust * sway * VERTEX.y;
		VERTEX.z += gust * sway * 0.5 * VERTEX.y;
	}
}

void fragment() {
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ALBEDO = COLOR.rgb * fog_light(world_position.xz);
	if (ground_lit) {
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
	ROUGHNESS = 0.95;
}
