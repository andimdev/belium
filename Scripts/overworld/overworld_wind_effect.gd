extends Control

## Viento atmosférico en espacio de pantalla. Las estelas comparten una
## corriente dominante y sólo varían de forma gradual, como una misma masa
## de aire, en vez de actuar como partículas independientes y caóticas.

const SEGMENT_COUNT := 14
const WHIRLWIND_SEGMENT_COUNT := 32
const WHIRLWIND_RIBBON_COUNT := 3

@export_range(4, 40, 1) var wisp_count := 20
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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_random.randomize()
	_whirlwind_check_elapsed = _random.randf_range(
		0.0,
		whirlwind_check_interval
	)
	resized.connect(_rebuild_wisps)
	call_deferred("_rebuild_wisps")


func _process(delta: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

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
			wisp.position.x > size.x + margin
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
		)
		var points := _build_wisp_points(wisp, flow, normal)
		var tint := wind_color.lerp(Color.WHITE, wisp.brightness)

		for segment in SEGMENT_COUNT:
			var progress := (float(segment) + 0.5) / float(SEGMENT_COUNT)
			var taper := pow(sin(progress * PI), 0.72)
			var segment_alpha := opacity * taper
			var segment_width: float = wisp.width * (0.45 + taper * 0.55)
			# Halo frío muy tenue para que la estela se lea tanto sobre césped
			# claro como sobre árboles, sin parecer una línea sólida.
			draw_line(
				points[segment],
				points[segment + 1],
				Color(0.34, 0.65, 0.72, segment_alpha * 0.24),
				segment_width + 1.4,
				true
			)
			draw_line(
				points[segment],
				points[segment + 1],
				Color(tint, segment_alpha),
				segment_width,
				true
			)

	_draw_whirlwind(flow, normal)


func _draw_whirlwind(flow: Vector2, normal: Vector2) -> void:
	if _whirlwind.is_empty():
		return

	var age: float = _whirlwind.age
	var duration: float = _whirlwind.duration
	var progress := clampf(age / duration, 0.0, 1.0)
	var visibility := smoothstep(0.0, 0.12, progress) * (
		1.0 - smoothstep(0.82, 1.0, progress)
	)
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

	# Tres cintas entrelazadas forman un pequeño vórtice legible sin convertir
	# el cielo en un tornado sólido.
	for ribbon in WHIRLWIND_RIBBON_COUNT:
		var points := PackedVector2Array()
		var ribbon_phase := phase + float(ribbon) * TAU / float(
			WHIRLWIND_RIBBON_COUNT
		)
		for segment in range(WHIRLWIND_SEGMENT_COUNT + 1):
			var ribbon_progress := float(segment) / float(
				WHIRLWIND_SEGMENT_COUNT
			)
			var along := lerpf(-length * 0.72, length * 0.28, ribbon_progress)
			var envelope := pow(sin(ribbon_progress * PI), 0.68)
			var curl := sin(
				ribbon_progress * TAU * 1.65 + ribbon_phase
			) * radius * envelope
			points.append(center + flow * along + normal * curl)

		var ribbon_alpha := visibility * (0.22 + float(ribbon) * 0.035)
		draw_polyline(
			points,
			Color(tint, ribbon_alpha),
			1.45 + float(ribbon) * 0.25,
			true
		)

	# Un arco corto y motas orbitando refuerzan el giro en el núcleo.
	draw_arc(
		center,
		radius * 0.72,
		phase,
		phase + PI * 1.55,
		20,
		Color(tint, visibility * 0.34),
		1.8,
		true
	)
	for mote in 6:
		var mote_angle := phase * 0.82 + float(mote) * TAU / 6.0
		var mote_radius := radius * (0.42 + float(mote % 3) * 0.2)
		var mote_position := (
			center
			+ flow * cos(mote_angle) * mote_radius * 1.55
			+ normal * sin(mote_angle) * mote_radius
		)
		draw_circle(
			mote_position,
			1.15 + float(mote % 2) * 0.45,
			Color(tint, visibility * 0.3),
			true
		)


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
		_wisps.append({
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
		})
	queue_redraw()


func _respawn_wisp(wisp: Dictionary) -> void:
	var margin: float = wisp.length + _random.randf_range(80.0, 230.0)
	wisp.position = Vector2(
		-margin,
		_random.randf_range(-size.y * 0.03, size.y * 1.03)
	)


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
		"rotation_speed": _random.randf_range(4.2, 6.2),
		"vertical_drift": _random.randf_range(-18.0, 18.0),
	}
