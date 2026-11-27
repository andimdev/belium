shader_type spatial;
// Material del estanque de Hojaverde (leaftown_pond.glb).
// Usa las texturas horneadas en Blender e imita cómo Terrain3D ilumina el césped,
// para que el borde del modelo no se vea más claro que el terreno:
//   - specular = (1 - roughness) * orientación hacia el sol (Godot usa 0.5 fijo por defecto)
//   - profundidad del normal map = 0.5 (normal_depth por defecto de Terrain3D)
//   - difuso Burley y especular Schlick-GGX, igual que Terrain3D
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D roughness_texture : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.5;
// Dirección hacia el sol en el mundo. Terrain3D atenúa el especular cuando el suelo no mira al sol.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

void fragment() {
	vec2 uv = UV;
	ALBEDO = texture(albedo_texture, uv).rgb;
	float rough = texture(roughness_texture, uv).g; // glTF guarda la rugosidad en el canal G
	ROUGHNESS = rough;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = clamp(dot(world_normal, normalize(sun_direction)), 0.0, 1.0);
	SPECULAR = (1.0 - rough) * facing;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
