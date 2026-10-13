// The map's ground: the map's base colour broken up into lighter and darker
// patches of grass, bare earth and speckles, darkened by fog of war.
//
// Real art: set ground_texture (tiled every texture_scale metres) and it
// replaces the painted pattern; the fog still applies.
shader_type spatial;

#include "res://shaders/fog.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.3, 0.42, 0.2, 1.0);
// Colour of the bare-earth patches.
uniform vec4 earth : source_color = vec4(0.42, 0.34, 0.22, 1.0);
// 0 = flat colour (as before), 1 = full painted pattern.
uniform float detail = 1.0;
uniform sampler2D ground_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float texture_scale = 8.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec3 colour = albedo.rgb;
	if (use_texture) {
		colour = texture(ground_texture, p / texture_scale).rgb;
	} else if (detail > 0.0) {
		// Broad light and dark patches, a warmer/cooler tint, bare earth in
		// the low spots, and fine speckle.
		float broad = fbm(p * 0.06);
		float mid = fbm(p * 0.22 + 31.0);
		float fine = value_noise(p * 1.7);
		vec3 painted = colour * mix(0.72, 1.22, broad);
		painted = mix(painted, painted * vec3(1.08, 1.04, 0.86), smoothstep(0.35, 0.7, mid));
		float bare = smoothstep(0.56, 0.68, fbm(p * 0.09 + 77.0) * 0.6 + mid * 0.4);
		painted = mix(painted, earth.rgb * mix(0.9, 1.1, fine), bare * 0.75);
		painted *= mix(0.96, 1.04, fine);
		colour = mix(colour, painted, detail);
	}
	ALBEDO = colour * fog_light(p);
	ROUGHNESS = 1.0;
}
