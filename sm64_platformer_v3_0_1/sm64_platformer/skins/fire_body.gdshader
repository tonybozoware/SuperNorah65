shader_type spatial;
// Fire skin body: smouldering, cracked embers that churn upward over each body
// part, with a hot rim. Object-space 3D noise, locked to the body.

uniform vec4 char_color : source_color = vec4(0.08, 0.02, 0.01, 1.0);
uniform vec4 ember_color : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float noise_scale = 7.0;
uniform float rise_speed = 1.2;
uniform float crack_width = 0.18;
uniform float emission_amount = 3.0;
uniform float rim_power = 2.5;
uniform float rim_strength = 1.5;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0.0, 0.0, 0.0)), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 p = obj_pos * noise_scale - vec3(0.0, TIME * rise_speed, 0.0);
	float n = fbm(p + fbm(p * 0.7 + TIME * 0.3));         // warped so it churns
	float cracks = 1.0 - smoothstep(0.0, crack_width, abs(n - 0.5));
	float heat = clamp(cracks + pow(n, 3.0) * 0.6, 0.0, 1.0);
	vec3 glow = mix(ember_color.rgb, hot_color.rgb, pow(heat, 2.0));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power) * rim_strength;
	ALBEDO = mix(char_color.rgb, glow * 0.4, heat);
	EMISSION = glow * (heat * emission_amount + rim);
	ROUGHNESS = 0.9;
}
