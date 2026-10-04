extends Node2D

var effect_size := Vector2(180.0, 80.0)
var _phase := 0.0


func configure(water_size: Vector2) -> void:
	effect_size = water_size
	queue_redraw()


func _process(delta: float) -> void:
	# Movimiento perceptible pero todavía propio de un estanque pequeño.
	_phase = fposmod(_phase + delta * 1.05, TAU)
	queue_redraw()


func _draw() -> void:
	if effect_size.x <= 8.0 or effect_size.y <= 8.0:
		return

	var breathing_tint := 0.075 + sin(_phase * 0.65) * 0.02
	draw_rect(
		Rect2(Vector2.ZERO, effect_size),
		Color(0.12, 0.48, 0.58, breathing_tint)
	)

	var pale_highlight := Color(0.67, 0.93, 0.96, 0.48)
	var blue_highlight := Color(0.18, 0.61, 0.76, 0.36)
	var row_spacing := effect_size.y / 5.0

	for row in 4:
		var points := PackedVector2Array()
		var base_y := row_spacing * float(row + 1)
		var x := 5.0
		while x <= effect_size.x - 5.0:
			var wave := sin(x * 0.075 + _phase + float(row) * 1.8) * 2.2
			points.append(Vector2(x, base_y + wave))
			x += 5.0
		draw_polyline(points, pale_highlight if row % 2 == 0 else blue_highlight, 2.0, false)

	# Reflejos cortos que se desplazan despacio sin sugerir oleaje grande.
	for glint in 7:
		var travel_width := maxf(effect_size.x - 24.0, 1.0)
		var glint_x := 8.0 + fposmod(float(glint) * 31.0 + _phase * 10.0, travel_width)
		var glint_y := 9.0 + fposmod(float(glint) * 17.0, maxf(effect_size.y - 18.0, 1.0))
		var brightness := 0.29 + 0.1 * sin(_phase + float(glint))
		draw_line(
			Vector2(glint_x, glint_y),
			Vector2(glint_x + 10.0, glint_y),
			Color(0.78, 0.94, 0.95, brightness),
			2.0,
			false
		)
