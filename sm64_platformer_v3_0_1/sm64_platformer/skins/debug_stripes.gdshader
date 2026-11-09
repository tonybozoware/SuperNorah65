shader_type spatial;
// Test skin only: glowing stripes that scroll up each body part, locked to the body.
// Safe to delete along with debug_stripes.tres and debug_sparks.tscn.

uniform vec4 color_a : source_color = vec4(0.08, 0.02, 0.25, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.25, 0.8, 1.0);
uniform float stripe_scale = 8.0;
uniform float speed = 1.0;
uniform float glow = 1.5;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;   // object space: the pattern sticks to the body part
}

void fragment() {
	float s = 0.5 + 0.5 * sin((obj_pos.y * stripe_scale + TIME * speed) * TAU);
	vec3 c = mix(color_a.rgb, color_b.rgb, s);
	ALBEDO = c;
	EMISSION = color_b.rgb * pow(s, 4.0) * glow;
	ROUGHNESS = 0.6;
}
