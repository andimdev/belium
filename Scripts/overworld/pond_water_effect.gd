extends Node2D

const CYCLE_SPEED := 0.62

var effect_size := Vector2(180.0, 80.0)
var _phase := 0.0


func configure(water_size: Vector2) -> void:
	effect_size = water_size
	queue_redraw()


func _process(delta: float) -> void:
	# Todas las variaciones dependen de senos completos. Al volver de TAU a 0
	# conservan posición y velocidad, por lo que el bucle no tiene un corte.
	_phase = fposmod(_phase + delta * CYCLE_SPEED, TAU)
	queue_redraw()


func _draw() -> void:
	if effect_size.x <= 8.0 or effect_size.y <= 8.0:
		return

	var ping_pong := sin(_phase)
	var breathing_tint := 0.075 + ping_pong * 0.016
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
			var horizontal_sway := ping_pong * 0.9
			var secondary_motion := sin(_phase * 2.0 + float(row) * 0.7) * 0.35
			var wave := (
				sin(x * 0.075 + horizontal_sway + float(row) * 1.8) * 1.9
				+ secondary_motion
			)
			points.append(Vector2(x, base_y + wave))
			x += 5.0
		draw_polyline(points, pale_highlight if row % 2 == 0 else blue_highlight, 2.0, false)

	# Los reflejos van y vuelven. Ninguno reaparece de golpe en el otro extremo.
	for glint in 7:
		var travel_width := maxf(effect_size.x - 32.0, 1.0)
		var base_x := travel_width * (float(glint) + 0.5) / 7.0
		var drift := sin(_phase + float(glint) * 0.83) * minf(10.0, travel_width / 18.0)
		var glint_x := 11.0 + clampf(base_x + drift, 0.0, travel_width)
		var glint_y := 9.0 + fposmod(float(glint) * 17.0, maxf(effect_size.y - 18.0, 1.0))
		var brightness := 0.29 + 0.08 * sin(_phase + float(glint) * 0.9)
		var glint_length := 8.0 + 2.0 * sin(_phase + float(glint) * 0.55)
		draw_line(
			Vector2(glint_x, glint_y),
			Vector2(glint_x + glint_length, glint_y),
			Color(0.78, 0.94, 0.95, brightness),
			2.0,
			false
		)
