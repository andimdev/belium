shader_type canvas_item;

// Los recursos de iconos tienen colores de origen distintos. Para que todos
// pertenezcan al mismo lenguaje visual del menú conservamos solo su alfa y
// aplicamos un color uniforme configurable desde cada material.
uniform vec4 icon_color : source_color = vec4(1.0);

void fragment() {
	float source_alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(icon_color.rgb, icon_color.a * source_alpha);
}
