shader_type spatial;
// Galaxy skin: a looping space video wrapped onto each body part. The video is
// sampled in object space (triplanar), so it is locked to the body and moves with
// every limb, flip and spin. A cool rim glow outlines him against the stage.

uniform sampler2D video_tex : source_color, repeat_enable, filter_linear;
uniform float tex_scale = 1.6;                // video repeats per metre of body
uniform float triplanar_sharpness = 4.0;
uniform float brightness = 1.6;
uniform float emission_amount = 1.2;          // >1 blooms when glow is on
uniform vec4 rim_color : source_color = vec4(0.45, 0.65, 1.0, 1.0);
uniform float rim_power = 3.0;
uniform float rim_strength = 1.2;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(obj_normal), vec3(triplanar_sharpness));
	w /= (w.x + w.y + w.z);
	vec3 p = obj_pos * tex_scale + 0.5;
	vec3 c = texture(video_tex, p.zy).rgb * w.x
		+ texture(video_tex, p.xz).rgb * w.y
		+ texture(video_tex, p.xy).rgb * w.z;
	c *= brightness;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power) * rim_strength;
	ALBEDO = c * 0.25;
	EMISSION = c * emission_amount + rim_color.rgb * rim;
	ROUGHNESS = 0.35;
}
