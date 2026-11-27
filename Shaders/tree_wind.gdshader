shader_type spatial;
render_mode cull_disabled;

// Balanceo suave para árboles dibujados con MultiMesh (TreeMultiMeshBuilder).
// Sustituye a la animación con huesos del GLB. Cada árbol se desfasa según su
// posición en el mundo, así que no se mueven todos a la vez.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = true;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

uniform float wind_strength = 0.03;
uniform float wind_speed = 1.2;
uniform float wind_min_height = 0.6;
uniform vec2 wind_direction = vec2(0.7071, 0.7071);

void vertex() {
	vec3 tree_origin = MODEL_MATRIX[3].xyz;
	float phase = tree_origin.x * 0.37 + tree_origin.z * 0.53;
	float height = max(VERTEX.y - wind_min_height, 0.0);
	float wave = sin(TIME * wind_speed + phase) * 0.7
		+ sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.3;
	VERTEX.xz += wind_direction * (wave * wind_strength * height);
}

void fragment() {
	vec4 color = albedo_color;
	if (use_albedo_tex) {
		color *= texture(albedo_tex, UV);
	}
	ALBEDO = color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
