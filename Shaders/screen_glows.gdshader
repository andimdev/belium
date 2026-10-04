shader_type canvas_item;
render_mode unshaded, blend_add;


float ellipse_glow(vec2 uv, vec2 center, vec2 radius, float softness) {
	vec2 point = (uv - center) / radius;
	return exp(-dot(point, point) * softness);
}


float eye_glow(vec2 uv, vec2 center, float rotation) {
	vec2 point = uv - center;
	float cosine = cos(rotation);
	float sine = sin(rotation);
	point = vec2(
		cosine * point.x - sine * point.y,
		sine * point.x + cosine * point.y
	);
	vec2 outer_point = point / vec2(0.115, 0.037);
	vec2 core_point = point / vec2(0.064, 0.014);
	float outer = exp(-dot(outer_point, outer_point) * 2.2);
	float core = exp(-dot(core_point, core_point) * 3.0);
	return outer * 0.55 + core;
}


void fragment() {
	float slow_pulse = 0.78 + 0.22 * sin(TIME * 1.35);
	float quick_pulse = 0.84 + 0.16 * sin(TIME * 2.1 + 1.3);

	float cyrus_outer = ellipse_glow(UV, vec2(0.17, 0.43), vec2(0.22, 0.34), 2.4);
	float cyrus_highlight = ellipse_glow(UV, vec2(0.145, 0.29), vec2(0.13, 0.24), 3.0);
	float cyrus = (cyrus_outer * 0.16 + cyrus_highlight * 0.3) * slow_pulse;

	float beam_line = exp(-abs(UV.x - 0.548) * 58.0);
	float beam_vertical_mask = smoothstep(0.075, 0.14, UV.y) * (1.0 - smoothstep(0.78, 0.9, UV.y));
	float beam_halo = ellipse_glow(UV, vec2(0.548, 0.48), vec2(0.055, 0.40), 1.8);
	float pillar = (beam_line * beam_vertical_mask * 0.42 + beam_halo * 0.33) * quick_pulse;

	float left_eye = eye_glow(UV, vec2(0.430, 0.195), -0.11);
	float right_eye = eye_glow(UV, vec2(0.680, 0.195), 0.11);
	float eyes = (left_eye + right_eye) * (0.80 + 0.20 * sin(TIME * 1.7 + 0.5));

	vec3 purple = vec3(0.62, 0.18, 1.0);
	vec3 pale_purple = vec3(0.86, 0.68, 1.0);
	vec3 white = vec3(1.0, 0.97, 1.0);
	vec3 glow_color = purple * cyrus + mix(purple, white, 0.58) * pillar;
	glow_color += mix(pale_purple, white, 0.72) * eyes * 0.8;
	float alpha = clamp((cyrus + pillar + eyes * 0.35) * 1.35, 0.0, 0.72);

	COLOR = vec4(glow_color, alpha);
}
