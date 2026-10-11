extends Control

## Viento atmosférico en espacio de pantalla. Las estelas comparten una
## corriente dominante y sólo varían de forma gradual, como una misma masa
## de aire, en vez de actuar como partículas independientes y caóticas.

const SEGMENT_COUNT := 14
const WHIRLWIND_SEGMENT_COUNT := 56
const WHIRLWIND_CORE_SEGMENTS := 40
const WHIRLWIND_RIBBON_COUNT := 4

@export_range(0, 240, 1) var wisp_count := 20
@export var wind_direction := Vector2(1.0, -0.055)
@export_range(10.0, 300.0, 1.0) var minimum_speed := 92.0
@export_range(10.0, 300.0, 1.0) var maximum_speed := 138.0
@export var wind_color := Color(0.82, 0.94, 1.0)
## Se evalúa una vez por intervalo, nunca una vez por fotograma.
@export_range(0.0, 1.0, 0.01) var whirlwind_spawn_probability := 0.01
@export_range(0.5, 30.0, 0.1) var whirlwind_check_interval := 2.5

var _wisps: Array[Dictionary] = []
var _elapsed := 0.0
var _random := RandomNumberGenerator.new()
var _whirlwind_check_elapsed := 0.0
var _whirlwind: Dictionary = {}
var _density_tween: Tween
var _previous_canvas_transform := Transform2D.IDENTITY
var _has_previous_canvas_transform := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_random.randomize()
	_whirlwind_check_elapsed = _random.randf_range(
		0.0,
		whirlwind_check_interval
	)
	resized.connect(_rebuild_wisps)
	reset_camera_tracking()
	call_deferred("_rebuild_wisps")


func _process(delta: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	_apply_camera_motion()
	_elapsed += delta
	_update_whirlwind(delta)
	if _wisps.is_empty():
		queue_redraw()
		return

	var flow := wind_direction.normalized()
	var normal := Vector2(-flow.y, flow.x)
	# Dos ondas largas producen ráfagas perceptibles sin cambios repentinos.
	var gust_strength := (
		0.91
		+ sin(_elapsed * 0.34) * 0.07
		+ sin(_elapsed * 0.13 + 1.7) * 0.035
	)

	for wisp in _wisps:
		wisp.age = float(wisp.get("age", 0.0)) + delta
		var group_phase: float = float(wisp.group) * 1.37
		var group_flow := 1.0 + sin(_elapsed * 0.22 + group_phase) * 0.045
		var side_flow: float = sin(
			_elapsed * wisp.side_frequency + wisp.phase
		) * wisp.side_speed
		wisp.position += (
			flow * wisp.speed * gust_strength * group_flow
			+ normal * side_flow
		) * delta

		var margin: float = wisp.length + 90.0
		if (
			wisp.position.x < -margin
			or wisp.position.x > size.x + margin
			or wisp.position.y < -margin
			or wisp.position.y > size.y + margin
		):
			_respawn_wisp(wisp)

	queue_redraw()


func _draw() -> void:
	if _wisps.is_empty():
		return

	var flow := wind_direction.normalized()
	var normal := Vector2(-flow.y, flow.x)
	var shared_visibility := 0.90 + sin(_elapsed * 0.29) * 0.10
	var density_alpha := clampf(
		sqrt(24.0 / maxf(float(_wisps.size()), 1.0)),
		0.34,
		1.0
	)

	for wisp in _wisps:
		var edge_visibility := _get_edge_visibility(wisp)
		if edge_visibility <= 0.001:
			continue

		var group_wave := (
			sin(_elapsed * 0.30 + float(wisp.group) * 1.37) + 1.0
		) * 0.5
		var band_visibility := lerpf(
			0.58,
			1.0,
			smoothstep(0.08, 0.92, group_wave)
		)
		var opacity: float = (
			wisp.alpha
			* edge_visibility
			* shared_visibility
			* band_visibility
			* density_alpha
			* smoothstep(0.0, 0.45, float(wisp.get("age", 0.0)))
		)
		var points := _build_wisp_points(wisp, flow, normal)
		var tint := wind_color.lerp(Color.WHITE, wisp.brightness)
		var halo_colors := PackedColorArray()
		var line_colors := PackedColorArray()
		for point_index in points.size():
			var progress := float(point_index) / float(points.size() - 1)
			var taper := pow(maxf(sin(progress * PI), 0.0), 0.72)
			var point_alpha := opacity * taper
			halo_colors.append(
				Color(0.34, 0.65, 0.72, point_alpha * 0.24)
			)
			line_colors.append(Color(tint, point_alpha))

		# Dos trazados completos sustituyen los 28 draw calls anteriores por
		# partícula. En noches densas esto reduce mucho el costo de renderizado.
		draw_polyline_colors(
			points,
			halo_colors,
			wisp.width + 1.4,
			true
		)
		draw_polyline_colors(points, line_colors, wisp.width, true)

	_draw_whirlwind(flow, normal)


func _draw_whirlwind(flow: Vector2, normal: Vector2) -> void:
	if _whirlwind.is_empty():
		return

	var age: float = _whirlwind.age
	var duration: float = _whirlwind.duration
	var progress := clampf(age / duration, 0.0, 1.0)
	var visibility := smoothstep(0.0, 0.12, progress) * (
		1.0 - smoothstep(0.82, 1.0, progress)
	) * float(_whirlwind.opacity_factor)
	if visibility <= 0.001:
		return

	var center: Vector2 = (
		_whirlwind.start
		+ flow * _whirlwind.speed * age
		+ normal * sin(progress * PI) * _whirlwind.vertical_drift
	)
	var tint := wind_color.lerp(Color.WHITE, 0.68)
	var phase: float = _whirlwind.phase + age * _whirlwind.rotation_speed
	var radius: float = _whirlwind.radius
	var length: float = _whirlwind.length
	var ribbon_opacities: PackedFloat32Array = _whirlwind.ribbon_opacities
	var ribbon_radius_scales: PackedFloat32Array = (
		_whirlwind.ribbon_radius_scales
	)
	var ribbon_irregularities: PackedFloat32Array = (
		_whirlwind.ribbon_irregularities
	)
	var ribbon_frequency_offsets: PackedFloat32Array = (
		_whirlwind.ribbon_frequency_offsets
	)
	var ribbon_length_scales: PackedFloat32Array = (
		_whirlwind.ribbon_length_scales
	)
	var ribbon_widths: PackedFloat32Array = _whirlwind.ribbon_widths
	var ribbon_phases: PackedFloat32Array = _whirlwind.ribbon_phases

	# Las cintas comparten el giro principal, pero cada una tiene longitud,
	# radio, opacidad y una ondulación secundaria estables. Así el vórtice se
	# siente natural sin cambiar su forma de manera brusca entre fotogramas.
	for ribbon in WHIRLWIND_RIBBON_COUNT:
		var points := PackedVector2Array()
		var halo_colors := PackedColorArray()
		var line_colors := PackedColorArray()
		var ribbon_phase := phase + float(ribbon) * TAU / float(
			WHIRLWIND_RIBBON_COUNT
		) + ribbon_phases[ribbon]
		var radius_scale := ribbon_radius_scales[ribbon]
		var irregularity := ribbon_irregularities[ribbon]
		var turn_count := 1.48 + ribbon_frequency_offsets[ribbon]
		var ribbon_length := length * ribbon_length_scales[ribbon]
		for segment in range(WHIRLWIND_SEGMENT_COUNT + 1):
			var ribbon_progress := float(segment) / float(
				WHIRLWIND_SEGMENT_COUNT
			)
			var envelope := pow(
				maxf(sin(ribbon_progress * PI), 0.0),
				0.64
			)
			var along := lerpf(
				-ribbon_length * 0.76,
				ribbon_length * 0.30,
				ribbon_progress
			)
			var secondary_wave := sin(
				ribbon_progress * TAU * 3.35
				+ ribbon_phases[ribbon] * 1.71
				+ phase * 0.14
			) * 0.15 * irregularity
			var curl := (
				sin(ribbon_progress * TAU * turn_count + ribbon_phase)
				+ secondary_wave
			) * radius * radius_scale * envelope
			var axial_wobble := sin(
				ribbon_progress * TAU * 2.20
				+ ribbon_phases[ribbon] * 0.83
			) * radius * 0.085 * irregularity * envelope
			points.append(
				center + flow * (along + axial_wobble) + normal * curl
			)

			var alpha_envelope := pow(
				maxf(sin(ribbon_progress * PI), 0.0),
				0.76
			)
			var soft_variation := 0.82 + sin(
				ribbon_progress * TAU * 1.35
				+ ribbon_phases[ribbon]
			) * 0.18
			var point_alpha := (
				visibility
				* ribbon_opacities[ribbon]
				* alpha_envelope
				* soft_variation
				* 0.31
			)
			halo_colors.append(Color(tint, point_alpha * 0.18))
			line_colors.append(Color(tint, point_alpha))

		draw_polyline_colors(
			points,
			halo_colors,
			ribbon_widths[ribbon] + 2.6,
			true
		)
		draw_polyline_colors(
			points,
			line_colors,
			ribbon_widths[ribbon],
			true
		)

	_draw_whirlwind_core(center, flow, normal, tint, visibility, radius, phase)

	# Motas pequeñas y de distinta transparencia acompañan al giro sin formar
	# el anillo rígido que tenía la versión anterior.
	for mote in 9:
		var mote_phase := float(_whirlwind.mote_phase)
		var mote_angle := phase * 0.78 + float(mote) * 2.17 + mote_phase
		var mote_radius := radius * (
			0.30 + fposmod(float(mote) * 0.37 + mote_phase, 0.72)
		)
		var mote_position := (
			center
			+ flow * cos(mote_angle) * mote_radius * 1.42
			+ normal * sin(mote_angle) * mote_radius * 0.88
		)
		var mote_opacity := (
			0.11
			+ (sin(float(mote) * 1.93 + mote_phase) + 1.0) * 0.045
		)
		draw_circle(
			mote_position,
			0.65 + float(mote % 3) * 0.22,
			Color(tint, visibility * mote_opacity),
			true
		)


func _draw_whirlwind_core(
	center: Vector2,
	flow: Vector2,
	normal: Vector2,
	tint: Color,
	visibility: float,
	radius: float,
	phase: float
) -> void:
	var points := PackedVector2Array()
	var halo_colors := PackedColorArray()
	var line_colors := PackedColorArray()
	var irregular_phase: float = _whirlwind.irregular_phase
	for segment in range(WHIRLWIND_CORE_SEGMENTS + 1):
		var core_progress := float(segment) / float(WHIRLWIND_CORE_SEGMENTS)
		var angle := phase + core_progress * TAU * 1.34
		var spiral_radius := radius * lerpf(0.10, 0.70, core_progress) * (
			1.0
			+ sin(core_progress * TAU * 2.65 + irregular_phase) * 0.07
		)
		points.append(
			center
			+ flow * cos(angle) * spiral_radius * 1.34
			+ normal * sin(angle) * spiral_radius
		)
		var alpha_envelope := pow(
			maxf(sin(core_progress * PI), 0.0),
			0.68
		)
		var point_alpha := visibility * alpha_envelope * 0.29
		halo_colors.append(Color(tint, point_alpha * 0.18))
		line_colors.append(Color(tint, point_alpha))
	draw_polyline_colors(points, halo_colors, 3.4, true)
	draw_polyline_colors(points, line_colors, 1.05, true)


func _build_wisp_points(
	wisp: Dictionary,
	flow: Vector2,
	normal: Vector2
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for segment in range(SEGMENT_COUNT + 1):
		var progress := float(segment) / float(SEGMENT_COUNT)
		var distance: float = wisp.length * (progress - 1.0)
		var curve_profile := sin(progress * PI)
		var bend: float = sin(
			progress * PI * wisp.curve_frequency
			+ wisp.phase
			+ _elapsed * wisp.shape_speed
		) * wisp.curve_amplitude * curve_profile
		points.append(wisp.position + flow * distance + normal * bend)
	return points


func _get_edge_visibility(wisp: Dictionary) -> float:
	var margin: float = wisp.length + 70.0
	var horizontal_fade := smoothstep(
		-margin,
		35.0,
		wisp.position.x
	) * (1.0 - smoothstep(size.x - 35.0, size.x + margin, wisp.position.x))
	var vertical_fade := smoothstep(
		-margin,
		25.0,
		wisp.position.y
	) * (1.0 - smoothstep(size.y - 25.0, size.y + margin, wisp.position.y))
	return horizontal_fade * vertical_fade


func _rebuild_wisps() -> void:
	_wisps.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		return

	for index in wisp_count:
		_wisps.append(_create_wisp(index))
	queue_redraw()


func _create_wisp(index: int) -> Dictionary:
	return {
			"position": Vector2(
				_random.randf_range(-size.x * 0.18, size.x * 1.05),
				_random.randf_range(-size.y * 0.04, size.y * 1.04)
			),
			"speed": _random.randf_range(minimum_speed, maximum_speed),
			"length": _random.randf_range(54.0, 128.0),
			"width": _random.randf_range(0.9, 1.75),
			"alpha": _random.randf_range(0.075, 0.15),
			"brightness": _random.randf_range(0.18, 0.72),
			"curve_amplitude": _random.randf_range(2.0, 6.5),
			"curve_frequency": _random.randf_range(0.72, 1.18),
			"shape_speed": _random.randf_range(0.08, 0.19),
			"side_speed": _random.randf_range(0.35, 1.4),
			"side_frequency": _random.randf_range(0.18, 0.32),
			"phase": _random.randf_range(0.0, TAU),
			"group": index % 4,
			"age": _random.randf_range(0.45, 1.2),
		}


## Cambia la densidad y la probabilidad de ráfagas sin reemplazar el efecto.
## El ajuste gradual evita saltos visibles al cruzar un límite horario.
func set_weather_profile(
	particle_count: int,
	whirlwind_probability: float,
	transition_duration: float = 4.0
) -> void:
	var target_count := clampi(particle_count, 0, 240)
	var target_whirlwind_probability := clampf(
		whirlwind_probability,
		0.0,
		1.0
	)
	if is_instance_valid(_density_tween):
		_density_tween.kill()
	if transition_duration <= 0.0 or not is_inside_tree():
		_set_visible_wisp_count(target_count)
		_set_whirlwind_probability(target_whirlwind_probability)
		return
	_density_tween = create_tween()
	_density_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_density_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_density_tween.tween_method(
		_set_visible_wisp_count,
		_wisps.size(),
		target_count,
		transition_duration
	)
	_density_tween.parallel().tween_method(
		_set_whirlwind_probability,
		whirlwind_spawn_probability,
		target_whirlwind_probability,
		transition_duration
	)


func _set_visible_wisp_count(value: int) -> void:
	var desired_count := clampi(value, 0, 240)
	while _wisps.size() < desired_count:
		_wisps.append(_create_wisp(_wisps.size()))
	while _wisps.size() > desired_count:
		_wisps.pop_back()
	wisp_count = desired_count
	queue_redraw()


func _set_whirlwind_probability(value: float) -> void:
	whirlwind_spawn_probability = clampf(value, 0.0, 1.0)


func _respawn_wisp(wisp: Dictionary) -> void:
	wisp.position = Vector2(
		_random.randf_range(8.0, maxf(size.x - 8.0, 8.0)),
		_random.randf_range(8.0, maxf(size.y - 8.0, 8.0))
	)
	wisp.speed = _random.randf_range(minimum_speed, maximum_speed)
	wisp.length = _random.randf_range(54.0, 128.0)
	wisp.width = _random.randf_range(0.9, 1.75)
	wisp.alpha = _random.randf_range(0.075, 0.15)
	wisp.brightness = _random.randf_range(0.18, 0.72)
	wisp.curve_amplitude = _random.randf_range(2.0, 6.5)
	wisp.curve_frequency = _random.randf_range(0.72, 1.18)
	wisp.shape_speed = _random.randf_range(0.08, 0.19)
	wisp.side_speed = _random.randf_range(0.35, 1.4)
	wisp.side_frequency = _random.randf_range(0.18, 0.32)
	wisp.phase = _random.randf_range(0.0, TAU)
	wisp.age = 0.0


func reset_camera_tracking() -> void:
	_previous_canvas_transform = get_viewport().get_canvas_transform()
	_has_previous_canvas_transform = true


func _apply_camera_motion() -> void:
	var current_transform := get_viewport().get_canvas_transform()
	if not _has_previous_canvas_transform:
		_previous_canvas_transform = current_transform
		_has_previous_canvas_transform = true
		return
	if current_transform.is_equal_approx(_previous_canvas_transform):
		return
	var compensation := (
		current_transform * _previous_canvas_transform.affine_inverse()
	)
	for wisp in _wisps:
		wisp.position = compensation * Vector2(wisp.position)
		wisp.position = _wrap_after_camera_motion(
			wisp.position,
			float(wisp.length) + 90.0
		)
	if not _whirlwind.is_empty():
		_whirlwind.start = compensation * Vector2(_whirlwind.start)
		_wrap_whirlwind_after_camera_motion()
	_previous_canvas_transform = current_transform


func _wrap_whirlwind_after_camera_motion() -> void:
	var flow := wind_direction.normalized()
	var normal := Vector2(-flow.y, flow.x)
	var age: float = _whirlwind.age
	var progress := clampf(age / float(_whirlwind.duration), 0.0, 1.0)
	var center := (
		Vector2(_whirlwind.start)
		+ flow * float(_whirlwind.speed) * age
		+ normal * sin(progress * PI) * float(_whirlwind.vertical_drift)
	)
	var margin: float = (
		float(_whirlwind.length) + float(_whirlwind.radius) * 2.0
	)
	var wrapped_center := _wrap_after_camera_motion(center, margin)
	_whirlwind.start = Vector2(_whirlwind.start) + wrapped_center - center


func _wrap_after_camera_motion(position: Vector2, margin: float) -> Vector2:
	var horizontal_span := size.x + margin * 2.0
	var vertical_span := size.y + margin * 2.0
	if horizontal_span > 0.0:
		position.x = fposmod(position.x + margin, horizontal_span) - margin
	if vertical_span > 0.0:
		position.y = fposmod(position.y + margin, vertical_span) - margin
	return position


func _update_whirlwind(delta: float) -> void:
	if not _whirlwind.is_empty():
		_whirlwind.age = float(_whirlwind.age) + delta
		if float(_whirlwind.age) >= float(_whirlwind.duration):
			_whirlwind.clear()
			_whirlwind_check_elapsed = 0.0
		return

	_whirlwind_check_elapsed += delta
	if _whirlwind_check_elapsed < whirlwind_check_interval:
		return
	_whirlwind_check_elapsed -= whirlwind_check_interval
	if _random.randf() < whirlwind_spawn_probability:
		_spawn_whirlwind()


func _spawn_whirlwind() -> void:
	var flow := wind_direction.normalized()
	var radius := _random.randf_range(20.0, 30.0)
	var length := _random.randf_range(125.0, 175.0)
	var speed := _random.randf_range(265.0, 345.0)
	var ribbon_opacities := PackedFloat32Array()
	var ribbon_radius_scales := PackedFloat32Array()
	var ribbon_irregularities := PackedFloat32Array()
	var ribbon_frequency_offsets := PackedFloat32Array()
	var ribbon_length_scales := PackedFloat32Array()
	var ribbon_widths := PackedFloat32Array()
	var ribbon_phases := PackedFloat32Array()
	var translucent_ribbon := _random.randi_range(
		0,
		WHIRLWIND_RIBBON_COUNT - 1
	)
	for ribbon in WHIRLWIND_RIBBON_COUNT:
		var opacity_factor := _random.randf_range(0.68, 1.0)
		if ribbon == translucent_ribbon:
			opacity_factor *= _random.randf_range(0.45, 0.62)
		ribbon_opacities.append(opacity_factor)
		ribbon_radius_scales.append(_random.randf_range(0.82, 1.16))
		ribbon_irregularities.append(_random.randf_range(0.72, 1.24))
		ribbon_frequency_offsets.append(_random.randf_range(-0.10, 0.12))
		ribbon_length_scales.append(_random.randf_range(0.91, 1.08))
		ribbon_widths.append(_random.randf_range(0.82, 1.24))
		ribbon_phases.append(_random.randf_range(-0.22, 0.22))
	var start := Vector2(
		-length - radius * 2.0,
		_random.randf_range(size.y * 0.2, size.y * 0.8)
	)
	var horizontal_distance := size.x + length * 2.0 + radius * 4.0
	var travel_distance := horizontal_distance / maxf(absf(flow.x), 0.2)
	_whirlwind = {
		"age": 0.0,
		"duration": travel_distance / speed,
		"start": start,
		"speed": speed,
		"radius": radius,
		"length": length,
		"phase": _random.randf_range(0.0, TAU),
		"rotation_speed": _random.randf_range(2.35, 3.75),
		"vertical_drift": _random.randf_range(-18.0, 18.0),
		"opacity_factor": _random.randf_range(0.58, 1.0),
		"irregular_phase": _random.randf_range(0.0, TAU),
		"mote_phase": _random.randf_range(0.0, TAU),
		"ribbon_opacities": ribbon_opacities,
		"ribbon_radius_scales": ribbon_radius_scales,
		"ribbon_irregularities": ribbon_irregularities,
		"ribbon_frequency_offsets": ribbon_frequency_offsets,
		"ribbon_length_scales": ribbon_length_scales,
		"ribbon_widths": ribbon_widths,
		"ribbon_phases": ribbon_phases,
	}
