shader_type spatial;
// Hierba y flores con viento suave para instancias de Terrain3D (MultiMesh).
// Las instancias no pueden reproducir AnimationPlayer, por eso el balanceo
// se calcula aquí, en el vértice.
//
// Datos que vienen del GLB exportado desde Blender:
//   COLOR.r = peso de viento (0 en la raíz, 1 en la punta)
//   COLOR.g = fase propia de cada hoja
//   UV      = degradado base -> punta (V) y variación de tinte por hoja (U)
//
// Requisito: el color de instancia de Terrain3D debe ser blanco, porque Godot
// multiplica el COLOR del vértice por el color de la instancia.
render_mode cull_disabled, specular_disabled, depth_draw_opaque;

group_uniforms color;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Cuánto se desplaza el tinte entre parches de hierba (0 = sin parches).
uniform float patch_tint_range : hint_range(0.0, 1.0) = 0.35;
// Frecuencia espacial de los parches, en radianes por metro.
uniform float patch_tint_frequency : hint_range(0.0, 2.0) = 0.3;
// Mezcla de la normal hacia arriba: suaviza la iluminación del campo.
uniform float normal_up_blend : hint_range(0.0, 1.0) = 0.65;
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.18;

group_uniforms wind;
// Hacia dónde sopla el viento, en el plano XZ del mundo.
// El valor por defecto sigue al viento 2D del juego: hacia la derecha de la
// pantalla, que con la cámara actual es el eje +Z del mundo.
uniform vec2 wind_direction = vec2(0.055, 1.0);
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.0;
// Altura de referencia de la hoja en metros. Los desplazamientos son una
// fracción de esta altura.
uniform float blade_height : hint_range(0.01, 1.0) = 0.08;
uniform float lean_amount : hint_range(0.0, 1.0) = 0.12;
uniform float sway_amount : hint_range(0.0, 1.0) = 0.14;
uniform float gust_amount : hint_range(0.0, 1.0) = 0.25;
// Frecuencia espacial de las ráfagas, en radianes por metro.
uniform float gust_frequency : hint_range(0.0, 0.5) = 0.07;
uniform float gust_speed : hint_range(0.0, 4.0) = 0.6;
uniform float flutter_amount : hint_range(0.0, 0.5) = 0.04;
uniform float flutter_speed : hint_range(0.0, 20.0) = 3.5;

varying float v_patch;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Origen de la mata en el mundo (el MultiMesh ya aplica su transformación).
	vec3 inst_pos = MODEL_MATRIX[3].xyz;

	float weight = clamp(COLOR.r, 0.0, 1.0);
	weight = weight * weight;

	vec2 dir = wind_direction;
	if (dot(dir, dir) < 0.0001) {
		dir = vec2(0.0, 1.0);
	}
	dir = normalize(dir);
	vec2 side = vec2(-dir.y, dir.x);

	float t = TIME * wind_speed;
	float along = dot(inst_pos.xz, dir);
	float across = dot(inst_pos.xz, side);
	float phase_inst = hash21(inst_pos.xz) * 6.2831853;
	float phase_blade = COLOR.g * 6.2831853;

	// Ráfaga lenta que viaja con el viento: dos ondas largas combinadas.
	float g = sin(along * gust_frequency - t * gust_speed) * 0.6
			+ sin(along * gust_frequency * 2.3 - t * gust_speed * 1.7 + across * 0.05) * 0.4;
	float gust = smoothstep(0.0, 1.0, 0.5 + 0.5 * g);

	// Respiración global, con la misma forma que la ráfaga del viento 2D.
	float breathe = 0.91 + sin(t * 0.34) * 0.07 + sin(t * 0.13 + 1.7) * 0.035;

	float sway = sin(t * 1.3 + phase_inst + along * 0.35);
	float bend = (lean_amount + sway * sway_amount + gust * gust_amount) * breathe;
	float side_bend = sin(t * 0.9 + phase_inst * 1.7 + across * 0.3) * sway_amount * 0.5;
	float flutter = sin(t * flutter_speed + phase_blade) * flutter_amount * (0.4 + 0.6 * gust);

	vec2 disp = (dir * (bend + flutter) + side * (side_bend + flutter * 0.6));
	disp *= wind_strength * blade_height * weight;

	// La punta baja un poco al inclinarse, para conservar el largo de la hoja.
	float drop = dot(disp, disp) / max(2.0 * VERTEX.y, 0.02);
	vec3 world_disp = vec3(disp.x, -drop, disp.y);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_disp;

	// Tinte de parche según la posición en el mundo (sin texturas de ruido).
	vec2 wp = inst_pos.xz * patch_tint_frequency;
	v_patch = 0.5
			+ 0.25 * sin(wp.x + 1.7 * sin(wp.y * 0.7))
			+ 0.25 * sin(wp.y * 1.3 - 0.9 * sin(wp.x * 0.8 + 2.0));

	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), normal_up_blend));
}

void fragment() {
	vec2 uv = vec2(clamp(UV.x + (v_patch - 0.5) * patch_tint_range, 0.02, 0.98), UV.y);
	ALBEDO = texture(albedo_texture, uv).rgb * albedo_tint.rgb;
	ROUGHNESS = 1.0;
	// Con cull_disabled Godot invierte la normal de la cara trasera; se
	// restaura para que ambos lados se iluminen igual.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = ALBEDO * backlight_amount;
}
