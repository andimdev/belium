extends Node2D

const DURATION := 0.62
const BLADE_COUNT := 12

var _elapsed := 0.0
var _effect_width := 20.0
var _blade_offsets := PackedFloat32Array()
var _blade_heights := PackedFloat32Array()
var _blade_directions := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func configure(effect_width: float) -> void:
	_effect_width = maxf(effect_width, 12.0)
	_rng.seed = Time.get_ticks_usec() + get_instance_id()
	_blade_offsets.clear()
	_blade_heights.clear()
	_blade_directions.clear()
	for index in BLADE_COUNT:
		_blade_offsets.append(_rng.randf_range(-_effect_width * 0.48, _effect_width * 0.48))
		_blade_heights.append(_rng.randf_range(8.0, 14.0))
		var direction := -1.0 if index % 2 == 0 else 1.0
		_blade_directions.append(direction * _rng.randf_range(0.9, 1.35))
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _blade_offsets.is_empty():
		return

	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	var sway := sin(progress * PI)
	var opacity := pow(1.0 - progress, 0.85)
	var dark_grass := Color(0.12, 0.31, 0.22, 1.0 * opacity)
	var middle_grass := Color(0.25, 0.55, 0.32, 0.95 * opacity)
	var light_grass := Color(0.62, 0.86, 0.48, 0.95 * opacity)

	# Una curva en la base hace legible el movimiento incluso sobre tiles densos.
	draw_arc(
		Vector2(0.0, 5.0),
		_effect_width * (0.34 + sway * 0.13),
		PI * 1.08,
		PI * 1.92,
		14,
		Color(middle_grass, 0.7 * opacity),
		2.0,
		false
	)

	for index in BLADE_COUNT:
		var base := Vector2(_blade_offsets[index], 7.0)
		var bend := _blade_directions[index] * (1.5 + sway * 6.5)
		var tip := base + Vector2(bend, -_blade_heights[index] + progress * 2.0)
		var middle := base.lerp(tip, 0.55) + Vector2(bend * 0.35, 0.0)
		var blade_color := light_grass if index % 3 == 0 else dark_grass
		if index % 3 == 1:
			blade_color = middle_grass
		draw_polyline(PackedVector2Array([base, middle, tip]), blade_color, 2.0, false)

		if index % 2 == 0:
			var fleck_position := tip + Vector2(
				_blade_directions[index] * sway * 5.0,
				-progress * 5.0
			)
			draw_circle(fleck_position, 1.35, light_grass)
