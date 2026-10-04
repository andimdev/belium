shader_type canvas_item;
render_mode unshaded, blend_mix;


float ellipse_shadow(vec2 uv, vec2 center, vec2 radius) {
	vec2 point = (uv - center) / radius;
	return exp(-dot(point, point) * 2.1);
}


void fragment() {
	float left_shadow = ellipse_shadow(UV, vec2(0.430, 0.195), vec2(0.145, 0.067));
	float right_shadow = ellipse_shadow(UV, vec2(0.680, 0.195), vec2(0.145, 0.067));
	float breath = 0.76 + 0.24 * sin(TIME * 1.1 + 2.0);
	float shadow = clamp((left_shadow + right_shadow) * 0.25 * breath, 0.0, 0.95);
	COLOR = vec4(vec3(0.0), shadow);
}
