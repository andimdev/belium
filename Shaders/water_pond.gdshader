// Agua para estanque cuadrado (PlaneMesh con UV 0..1), sin texturas externas.
// El ruido es simplex (sin rejilla cuadrada) y se calcula aqui, asi se ve igual en el editor y en el juego.
// `rows` = cantidad de filas de espuma que avanzan hacia la orilla (0 = ninguna). Se puede cambiar por material.
// Idea base: shader CC0 "Simple Water with Mesh form" (DASTER). Ruido simplex 2D: Ashima Arts / Ian McEwan (MIT).
shader_type spatial;
render_mode cull_disabled;

const int MAX_ROWS = 8;

uniform int rows : hint_range(0, 8) = 0;   // filas de espuma (0..8)

uniform vec4 shallow_color : source_color = vec4(0.14, 0.66, 0.74, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.17, 0.42, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float plane_size = 10.0;          // lado del PlaneMesh en metros
uniform float depth_falloff = 3.5;        // metros desde la orilla hasta el color profundo
uniform float opacity : hint_range(0.0, 1.0) = 0.92;
uniform float foam_glow : hint_range(0.0, 1.0) = 0.35;   // la espuma se ve aunque haya poca luz
uniform float base_glow : hint_range(0.0, 1.0) = 0.20;   // el agua nunca queda negra de noche
uniform float gloss_roughness : hint_range(0.0, 1.0) = 0.30;   // menos = mas reflejo del cielo
uniform float gloss_specular : hint_range(0.0, 1.0) = 0.35;

uniform float ripple_cell = 0.25;         // tamano (m) de las arrugas mas grandes; las otras son mitad y cuarto
uniform float ripple_height = 0.009;      // intensidad de las arrugas
uniform float ripple_speed = 0.05;        // m/s a los que se desplazan

uniform float wobble_cell = 2.4;          // metros por celda del ruido que deforma las filas
uniform float lace_cell = 0.45;           // metros por celda de las burbujas

uniform float shore_width = 0.35;         // espuma pegada a la orilla (m)
uniform float shore_pulse = 0.35;         // cuanto respira esa franja (0..1)
uniform float shore_pulse_speed = 0.8;

uniform float row_far = 3.8;              // distancia a la orilla donde nace cada fila (m)
uniform float row_near = 0.25;            // distancia donde muere
uniform float row_width = 0.55;           // grosor maximo de cada fila (m)
uniform float row_trail = 0.6;            // estela que deja cada fila hacia atras (m)
uniform float row_round = 2.5;            // radio con el que se redondean las filas lejos de la orilla (m)
uniform float row_speed = 0.07;           // ciclos por segundo (cada fila usa un multiplo propio)
uniform float row_wobble = 0.5;           // irregularidad lateral de las filas (m)
uniform float row_drift = 0.08;           // velocidad a la que el ruido de cada fila se desplaza
uniform float lace_cut = 0.55;            // mas alto = mas huecos entre burbujas
uniform float lace_fill = 0.45;           // mas alto = filas mas solidas en el centro

float hash11(float x) {
	return fract(sin(x * 12.9898 + 4.1414) * 43758.5453);
}

vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289_2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute3(vec3 x) { return mod289_3(((x * 34.0) + 10.0) * x); }

// ruido simplex 2D, aprox. -1..1
float snoise(vec2 v) {
	const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
	vec2 i = floor(v + dot(v, C.yy));
	vec2 x0 = v - i + dot(i, C.xx);
	float s = step(x0.y, x0.x);
	vec2 i1 = vec2(s, 1.0 - s);
	vec4 x12 = x0.xyxy + C.xxzz;
	x12 = vec4(x12.xy - i1, x12.zw);
	i = mod289_2(i);
	vec3 p = permute3(permute3(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
	vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
	m = m * m;
	m = m * m;
	vec3 x = 2.0 * fract(p * C.www) - 1.0;
	vec3 h = abs(x) - 0.5;
	vec3 ox = floor(x + 0.5);
	vec3 a0 = x - ox;
	m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
	vec3 g;
	g.x = a0.x * x0.x + h.x * x0.y;
	g.yz = a0.yz * x12.xz + h.yz * x12.yw;
	return 130.0 * dot(m, g);
}

float sn01(vec2 p) {
	return 0.5 + 0.5 * snoise(p);
}

// dos octavas, 0..1 (burbujas)
float noise2(vec2 p) {
	return 0.65 * sn01(p) + 0.35 * sn01(p * 2.7 + vec2(5.2, 1.3));
}

// altura de las arrugas en metros; las octavas mas finas que un pixel se apagan para que no centelleen
float ripple_h(vec2 p, float t, float pix) {
	float h = 0.0;
	float amp = 1.0;
	float lam = ripple_cell;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float fade = 1.0 - smoothstep(0.2, 0.5, pix / lam);
		vec2 drift = vec2(cos(fi * 2.1 + 0.5), sin(fi * 2.1 + 0.5)) * ripple_speed * (1.0 + 0.4 * fi);
		h += amp * fade * snoise((p + drift * t) / lam + vec2(fi * 17.3));
		amp *= 0.5;
		lam *= 0.5;
	}
	return h * ripple_height;
}

void fragment() {
	vec2 p = UV * plane_size;
	float d = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)) * plane_size;   // metros hasta la orilla
	float t = TIME;
	vec2 fw = fwidth(p);
	float pix = max(fw.x, fw.y);   // metros por pixel en pantalla

	// Distancia para las filas: igual que la orilla cerca de ella, cada vez mas redondeada hacia el centro
	vec2 q = abs(p - vec2(plane_size * 0.5)) - vec2(plane_size * 0.5 - row_round);
	float d_round = row_round - (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
	float d_rows = mix(d, d_round, smoothstep(0.4, 3.5, d));

	// Color: turquesa en la orilla, azul profundo hacia el centro
	float g = smoothstep(0.0, depth_falloff, d);
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, g);
	float tone = sn01(p / 5.0 + vec2(t * 0.02, -t * 0.015));
	base *= 0.88 + 0.24 * tone;

	// Filas de espuma
	float foam = 0.0;
	for (int i = 0; i < MAX_ROWS; i++) {
		if (i >= rows) {
			break;
		}
		float k = float(i);
		float h = hash11(k + 1.0);
		float ph = fract(t * row_speed * (0.7 + 0.6 * h) + h * 3.7 + k * 0.31);   // 0 = nace lejos, 1 = llega a la orilla
		float center = mix(row_far, row_near, ph) + sin(t * (0.9 + 0.5 * h) + k * 2.0) * 0.07;

		vec2 dir = vec2(cos(h * 6.2831), sin(h * 6.2831));
		vec2 nuv = p / wobble_cell + vec2(k * 7.3, k * 3.1) + dir * t * row_drift;
		float w1 = snoise(nuv);
		float w2 = snoise(nuv * 2.7 + vec2(0.5));
		float w3 = snoise(nuv * 6.0 + vec2(0.2, 0.8));
		float dd = d_rows + (w1 * 0.55 + w2 * 0.3 + w3 * 0.15) * row_wobble;

		float hw = row_width * mix(0.55, 1.0, ph) * 0.5;
		float band = 1.0 - smoothstep(hw * 0.35, hw, abs(dd - center));
		float behind = dd - center;                                   // > 0: detras de la fila (hacia el centro)
		float trail = smoothstep(-hw, 0.0, behind) * (1.0 - smoothstep(0.0, row_trail, behind));
		float dens = max(band, trail * 0.45);
		float env = smoothstep(0.0, 0.15, ph) * (1.0 - smoothstep(0.78, 1.0, ph));

		vec2 luv = p / lace_cell + vec2(k * 11.7, k * 5.3) + vec2(-0.9, 0.7) * t * (0.3 + 0.1 * k);
		float lace = noise2(luv);
		lace = (lace - 0.5) * 1.5 + 0.5;
		float f = dens * smoothstep(lace_cut - 0.12, lace_cut + 0.12, lace + (dens - 0.5) * lace_fill);

		foam = 1.0 - (1.0 - foam) * (1.0 - f * env);
	}

	// Espuma pegada a la orilla (irregular, respira)
	float sw = shore_width * (1.0 + shore_pulse * sin(t * shore_pulse_speed));
	float sl = noise2(p / lace_cell + vec2(3.7, 1.2) + vec2(0.3, -0.4) * t);
	sl = (sl - 0.5) * 1.5 + 0.5;
	float sd = d + snoise(p / wobble_cell * 2.0 + vec2(t * 0.1)) * 0.125;
	float sband = 1.0 - smoothstep(sw * 0.4, sw, sd);
	float shore = sband * smoothstep(0.30, 0.50, sl + sband * 0.35);
	foam = max(foam, shore);

	// Arrugas suaves en la superficie
	float e = 0.02;
	float h0 = ripple_h(p, t, pix);
	float hx = ripple_h(p + vec2(e, 0.0), t, pix);
	float hy = ripple_h(p + vec2(0.0, e), t, pix);
	vec2 gr = vec2(hx - h0, hy - h0) / e;
	vec3 nn = normalize(vec3(-gr, 1.0));

	vec3 col = mix(base, foam_color.rgb, foam);
	ALBEDO = col;
	ALPHA = mix(opacity, 1.0, foam);
	ROUGHNESS = mix(gloss_roughness, 0.6, foam);
	SPECULAR = mix(gloss_specular, 0.15, foam);
	METALLIC = 0.0;
	NORMAL_MAP = nn * 0.5 + 0.5;
	EMISSION = base * (1.0 - foam) * base_glow + foam_color.rgb * foam * foam_glow;
}
