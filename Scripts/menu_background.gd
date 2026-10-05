extends Control

## Fondo dibujado en tiempo real para evitar depender de una imagen externa.
## Conserva la composición diagonal y el contraste del menú de referencia.

var _sparkles: Array[Vector3] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_sparkles()
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var width := size.x
	var height := size.y
	var full_rect := PackedVector2Array([
		Vector2.ZERO,
		Vector2(width, 0.0),
		Vector2(width, height),
		Vector2(0.0, height),
	])
	draw_polygon(full_rect, PackedColorArray([
		Color("#328eb7"),
		Color("#e81b91"),
		Color("#c60d60"),
		Color("#5969a9"),
	]))

	# Velos diagonales que dan profundidad al centro sin competir con el menú.
	draw_colored_polygon(PackedVector2Array([
		Vector2(width * 0.23, 0.0),
		Vector2(width * 0.48, 0.0),
		Vector2(width * 0.73, height),
		Vector2(width * 0.42, height),
	]), Color(0.24, 0.72, 0.88, 0.15))
	draw_colored_polygon(PackedVector2Array([
		Vector2(width * 0.62, 0.0),
		Vector2(width * 0.91, 0.0),
		Vector2(width * 0.68, height),
		Vector2(width * 0.45, height),
	]), Color(1.0, 0.1, 0.55, 0.16))

	# Bandas rojas exteriores inspiradas en los laterales del menú original.
	draw_colored_polygon(PackedVector2Array([
		Vector2.ZERO,
		Vector2(width * 0.27, 0.0),
		Vector2(width * 0.055, height),
		Vector2(0.0, height),
	]), Color("#db2c3c"))
	draw_colored_polygon(PackedVector2Array([
		Vector2.ZERO,
		Vector2(width * 0.13, 0.0),
		Vector2(0.0, height * 0.52),
	]), Color("#ef3445"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(width * 0.94, 0.0),
		Vector2(width, 0.0),
		Vector2(width, height),
		Vector2(width * 0.72, height),
	]), Color("#cf2938"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(width, height * 0.42),
		Vector2(width, height),
		Vector2(width * 0.84, height),
	]), Color("#ed3647"))

	for sparkle in _sparkles:
		var sparkle_position := Vector2(
			sparkle.x * width,
			sparkle.y * height
		)
		var sparkle_alpha := 0.12 + sparkle.z * 0.16
		draw_circle(
			sparkle_position,
			1.0 + sparkle.z * 2.2,
			Color(1.0, 1.0, 1.0, sparkle_alpha),
			true
		)


func _build_sparkles() -> void:
	_sparkles.clear()
	var random := RandomNumberGenerator.new()
	random.seed = 201202
	for _index in 58:
		_sparkles.append(Vector3(
			random.randf_range(0.18, 0.93),
			random.randf_range(0.03, 0.94),
			random.randf()
		))
