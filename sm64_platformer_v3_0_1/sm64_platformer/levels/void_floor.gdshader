shader_type spatial;
// Without this, the floor would pick up the environment's sky reflections; it
// draws its own reflection below instead.
render_mode ambient_light_disabled;
// Endless glossy black floor with water ripples. Ripples are sent in by
// void_floor.gd (world x, world z, start time, strength) and drawn as expanding
// rings that bend the floor's reflection, so they show as light catching on
// dark water. The reflection is the floor's own: a faint glow toward the horizon,
// so the void stays black. The floor fades to black in the distance (no fog
// needed). Everything is in world space, so the floor can follow the player
// without the pattern moving.

uniform vec4 ripples[24];   // x, z, start time, strength (0 = unused)
uniform float now = 0.0;             // seconds, from void_floor.gd
uniform vec4 floor_color : source_color = vec4(0.01, 0.01, 0.012, 1.0);
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.06;
uniform float ripple_speed = 2.4;     // m/s the ring spreads
uniform float ripple_life = 2.4;      // s
uniform float wavelength = 0.32;      // m between crests
uniform float ring_width = 0.55;      // m, how thick each ring's band of crests is
uniform float ripple_height = 0.07;   // normal tilt strength
uniform vec4 glow_color : source_color = vec4(0.55, 0.62, 0.8, 1.0);   // what the water reflects
uniform float glow_strength = 0.35;
uniform float fade_start = 25.0;      // m from the camera
uniform float fade_end = 60.0;        // fully black from here

// Reflection, from void_floor.gd's mirror camera.
uniform bool reflection_on = true;
uniform sampler2D reflection_tex : source_color, filter_linear, repeat_disable;
uniform mat4 mirror_vp;                      // mirror camera's view-projection
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.45;   // dark water: dim
uniform float reflection_min : hint_range(0.0, 1.0) = 0.25;       // share looking straight down
uniform float reflection_blur = 0.004;       // softness, in screen fractions
uniform float ripple_distortion = 0.035;     // how far ripples bend the reflection

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grad = vec2(0.0);
	float k = TAU / wavelength;
	for (int i = 0; i < 24; i++) {
		vec4 r = ripples[i];
		float age = now - r.z;
		if (r.w <= 0.0 || age < 0.0 || age > ripple_life) {
			continue;
		}
		vec2 to = world_pos.xz - r.xy;
		float d = length(to);
		if (d < 0.0001) {
			continue;
		}
		float x = d - age * ripple_speed;                  // distance from the ring
		float env = exp(-(x * x) / (ring_width * ring_width));
		float fade = pow(1.0 - age / ripple_life, 2.0) * r.w;
		// Slope of h(x) = sin(kx) * env, along the ring's outward direction.
		float dh = (k * cos(k * x) - 2.0 * x / (ring_width * ring_width) * sin(k * x)) * env * fade;
		grad += (to / d) * dh;
	}
	vec3 n = normalize(vec3(-grad.x * ripple_height, 1.0, -grad.y * ripple_height));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Own reflection: look along the mirrored view direction; the closer it runs to
	// the horizon, the more glow it catches. Ripples tilt n, which bends this.
	vec3 view_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 refl = reflect(view_dir, n);
	float horizon = pow(1.0 - clamp(refl.y, 0.0, 1.0), 6.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(-view_dir, n), 0.0, 1.0), 5.0);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);

	vec3 mirrored = vec3(0.0);
	if (reflection_on) {
		vec4 clip = mirror_vp * vec4(world_pos, 1.0);
		vec2 ruv = vec2(clip.x, -clip.y) / clip.w * 0.5 + 0.5;
		ruv += grad * ripple_height * ripple_distortion;
		// Soft: a small 9-tap blur.
		float b = reflection_blur;
		vec3 acc = texture(reflection_tex, ruv).rgb * 0.25;
		acc += (texture(reflection_tex, ruv + vec2(b, 0.0)).rgb + texture(reflection_tex, ruv - vec2(b, 0.0)).rgb
			+ texture(reflection_tex, ruv + vec2(0.0, b)).rgb + texture(reflection_tex, ruv - vec2(0.0, b)).rgb) * 0.125;
		acc += (texture(reflection_tex, ruv + vec2(b, b)).rgb + texture(reflection_tex, ruv - vec2(b, b)).rgb
			+ texture(reflection_tex, ruv + vec2(b, -b)).rgb + texture(reflection_tex, ruv - vec2(b, -b)).rgb) * 0.0625;
		float edge = step(0.0, clip.w) * step(0.0, ruv.x) * step(ruv.x, 1.0) * step(0.0, ruv.y) * step(ruv.y, 1.0);
		mirrored = acc * edge * reflection_strength * mix(reflection_min, 1.0, fresnel);
	}

	ALBEDO = floor_color.rgb;
	ROUGHNESS = roughness_amount;
	SPECULAR = 0.7 * fade;
	EMISSION = (glow_color.rgb * horizon * fresnel * glow_strength + mirrored) * fade;
}
