class_name OverworldCloudEffect
extends Control

## Nubes procedurales muy suaves en espacio de pantalla. No requieren sprites
## y permanecen detrás del UIRoot porque viven en la capa atmosférica.

const CLOUD_CURVE_SEGMENTS := 24

@export_range(0, 32, 1) var cloud_count := 0
@export var cloud_direction := Vector2(1.0, -0.025)
@export_range(1.0, 40.0, 0.5) var minimum_speed := 4.0
@export_range(1.0, 40.0, 0.5) var maximum_speed := 10.0

var _clouds: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()
var _opacity := 0.05
var _size_scale := 0.7
var _profile_tween: Tween
var _previous_canvas_transform := Transform2D.IDENTITY
var _has_previous_canvas_transform := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_random.randomize()
	resized.connect(_rebuild_clouds)
	reset_camera_tracking()
	call_deferred("_rebuild_clouds")


func _process(delta: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _clouds.is_empty():
		return
	_apply_camera_motion()
	var flow := cloud_direction.normalized()
	for cloud in _clouds:
		cloud.age = float(cloud.get("age", 0.0)) + delta
		cloud.position += flow * float(cloud.speed) * delta
		var margin: float = float(cloud.width) * _size_scale + 80.0
		if (
			cloud.position.x < -margin
			or cloud.position.x > size.x + margin
			or cloud.position.y < -margin
			or cloud.position.y > size.y + margin
		):
			_respawn_cloud(cloud)
	queue_redraw()


func _draw() -> void:
	for cloud in _clouds:
		_draw_cloud(cloud)


func set_weather_profile(
	count: int,
	opacity: float,
	size_scale: float,
	transition_duration: float = 5.0
) -> void:
	var target_count := clampi(count, 0, 32)
	var target_opacity := clampf(opacity, 0.0, 0.24)
	var target_size_scale := clampf(size_scale, 0.25, 1.8)
	if is_instance_valid(_profile_tween):
		_profile_tween.kill()
	if transition_duration <= 0.0 or not is_inside_tree():
		_set_visible_cloud_count(target_count)
		_set_cloud_opacity(target_opacity)
		_set_cloud_size(target_size_scale)
		return
	_profile_tween = create_tween()
	_profile_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_profile_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_profile_tween.tween_method(
		_set_visible_cloud_count,
		_clouds.size(),
		target_count,
		transition_duration
	)
	_profile_tween.parallel().tween_method(
		_set_cloud_opacity,
		_opacity,
		target_opacity,
		transition_duration
	)
	_profile_tween.parallel().tween_method(
		_set_cloud_size,
		_size_scale,
		target_size_scale,
		transition_duration
	)


func _rebuild_clouds() -> void:
	_clouds.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for index in cloud_count:
		_clouds.append(_create_cloud(index))
	queue_redraw()


func _create_cloud(index: int) -> Dictionary:
	return {
			"position": Vector2(
				_random.randf_range(-size.x * 0.15, size.x * 1.08),
				_random.randf_range(size.y * 0.04, size.y * 0.72)
			),
			"width": _random.randf_range(90.0, 170.0),
			"height": _random.randf_range(24.0, 42.0),
			"speed": _random.randf_range(minimum_speed, maximum_speed),
			"alpha_factor": _random.randf_range(0.72, 1.0),
			"phase": _random.randf_range(0.0, TAU),
			"index": index,
			"age": _random.randf_range(0.6, 1.4),
		}


func _set_visible_cloud_count(value: int) -> void:
	var desired_count := clampi(value, 0, 32)
	while _clouds.size() < desired_count:
		_clouds.append(_create_cloud(_clouds.size()))
	while _clouds.size() > desired_count:
		_clouds.pop_back()
	cloud_count = desired_count
	queue_redraw()


func _set_cloud_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 0.24)
	queue_redraw()


func _set_cloud_size(value: float) -> void:
	_size_scale = clampf(value, 0.25, 1.8)
	queue_redraw()


func _draw_cloud(cloud: Dictionary) -> void:
	var center: Vector2 = cloud.position
	var width: float = cloud.width * _size_scale
	var height: float = cloud.height * _size_scale
	var phase: float = cloud.phase
	var alpha: float = (
		_opacity
		* cloud.alpha_factor
		* _get_edge_visibility(cloud)
		* smoothstep(0.0, 0.65, float(cloud.get("age", 0.0)))
	)
	var base_color := Color(0.91, 0.95, 1.0, alpha * 0.82)
	var highlight := Color(1.0, 1.0, 1.0, alpha * 0.24)

	# Una curva cerrada genera toda la silueta. No hay rectángulos ni piezas
	# rígidas: la combinación de ondas forma bordes redondeados e irregulares.
	draw_colored_polygon(
		_build_cloud_shape(center, width, height, phase),
		base_color
	)
	draw_colored_polygon(
		_build_cloud_shape(
			center + Vector2(-width * 0.035, -height * 0.13),
			width * 0.72,
			height * 0.58,
			phase + 1.17
		),
		highlight
	)


func _build_cloud_shape(
	center: Vector2,
	width: float,
	height: float,
	phase: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for segment in range(CLOUD_CURVE_SEGMENTS + 1):
		var progress := float(segment) / float(CLOUD_CURVE_SEGMENTS)
		var edge_envelope := pow(maxf(sin(progress * PI), 0.0), 0.58)
		var crown := (
			0.54
			+ sin(progress * TAU * 1.75 + phase) * 0.13
			+ sin(progress * TAU * 3.10 - phase * 0.47) * 0.075
		)
		points.append(center + Vector2(
			(progress - 0.5) * width,
			height * 0.16 - height * edge_envelope * crown
		))
	for segment in range(CLOUD_CURVE_SEGMENTS, -1, -1):
		var progress := float(segment) / float(CLOUD_CURVE_SEGMENTS)
		var edge_envelope := pow(maxf(sin(progress * PI), 0.0), 0.62)
		var lower_curve := (
			0.20
			+ sin(progress * TAU * 2.15 + phase * 0.63) * 0.035
		)
		points.append(center + Vector2(
			(progress - 0.5) * width,
			height * 0.16 + height * edge_envelope * lower_curve
		))
	return points


func _get_edge_visibility(cloud: Dictionary) -> float:
	var margin: float = float(cloud.width) * _size_scale + 20.0
	var horizontal := smoothstep(
		-margin,
		28.0,
		float(cloud.position.x)
	) * (1.0 - smoothstep(
		size.x - 28.0,
		size.x + margin,
		float(cloud.position.x)
	))
	var vertical := smoothstep(
		-margin,
		22.0,
		float(cloud.position.y)
	) * (1.0 - smoothstep(
		size.y - 22.0,
		size.y + margin,
		float(cloud.position.y)
	))
	return horizontal * vertical


func _respawn_cloud(cloud: Dictionary) -> void:
	cloud.position = Vector2(
		_random.randf_range(12.0, maxf(size.x - 12.0, 12.0)),
		_random.randf_range(size.y * 0.04, size.y * 0.72)
	)
	cloud.width = _random.randf_range(90.0, 170.0)
	cloud.height = _random.randf_range(24.0, 42.0)
	cloud.speed = _random.randf_range(minimum_speed, maximum_speed)
	cloud.alpha_factor = _random.randf_range(0.72, 1.0)
	cloud.phase = _random.randf_range(0.0, TAU)
	cloud.age = 0.0


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
	for cloud in _clouds:
		cloud.position = compensation * Vector2(cloud.position)
		var margin: float = float(cloud.width) * _size_scale + 80.0
		cloud.position = _wrap_after_camera_motion(cloud.position, margin)
	_previous_canvas_transform = current_transform


func _wrap_after_camera_motion(position: Vector2, margin: float) -> Vector2:
	# Una transición de cámara puede sacar muchas nubes de pantalla a la vez.
	# Reubicarlas por envoltura conserva su edad y opacidad, evitando que todas
	# reaparezcan desde cero simultáneamente.
	var horizontal_span := size.x + margin * 2.0
	var vertical_span := size.y + margin * 2.0
	if horizontal_span > 0.0:
		position.x = fposmod(position.x + margin, horizontal_span) - margin
	if vertical_span > 0.0:
		position.y = fposmod(position.y + margin, vertical_span) - margin
	return position
