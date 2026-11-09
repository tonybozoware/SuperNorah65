/*
	Flame particles for the fire skin.
	Based on "Fire Shader" by Yui Kinomoto (@arlez80), MIT License
	https://godotshaders.com/shader/fire-shader/
	Ported to Godot 4, made into a camera-facing (Y-up) particle with a fade
	over each particle's life (particle colour alpha), a soft flame-shaped outline,
	additive blending and an intensity boost for glow.
*/
shader_type spatial;
render_mode blend_add, depth_draw_never, unshaded, shadows_disabled, cull_disabled;

uniform sampler2D noise_tex : hint_default_white, repeat_enable;
uniform vec4 root_color : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 0.03, 0.001, 1.0);
uniform float fire_alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec2 fire_speed = vec2(0.0, 1.0);
uniform float fire_aperture : hint_range(0.0, 3.0) = 0.22;
uniform float intensity = 2.0;

varying float seed;

void vertex() {
	// Face the camera but stay upright, keeping the particle's scale.
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)) * s, 0.0),
		vec4(0.0, s, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))) * s, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = fract(float(INSTANCE_ID) * 0.61803);   // stable per particle
}

void fragment() {
	vec2 uv = UV;   // UV.y = 1 at the bottom of the quad: the flame's root
	vec2 shifted_uv = UV + TIME * fire_speed + seed;
	float fire_noise = texture(noise_tex, shifted_uv).r;
	float noise = uv.y * (((uv.y + fire_aperture) * fire_noise - fire_aperture) * 75.0);
	vec4 fire_color = mix(tip_color, root_color, noise * 0.05);
	// Soft flame outline so the square edges of the particle never show: narrow at
	// the tip, wider at the root, fading out at the top.
	float half_width = mix(0.12, 0.42, uv.y);
	float side = 1.0 - smoothstep(half_width - 0.12, half_width, abs(uv.x - 0.5));
	float top = smoothstep(0.0, 0.35, uv.y);
	float bottom = 1.0 - smoothstep(0.85, 1.0, uv.y);
	ALPHA = clamp(noise, 0.0, 1.0) * side * top * bottom * fire_alpha * COLOR.a;
	ALBEDO = fire_color.rgb * intensity;
}
