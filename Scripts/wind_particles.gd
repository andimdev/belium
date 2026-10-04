extends Control

const PARTICLE_COUNT := 30
const BASE_COLOR := Color(0.82, 0.68, 1.0)
const STRAIGHT := 0
const WAVY := 1
const IRREGULAR := 2

var _particles: Array[Dictionary] = []
var _elapsed := 0.0

func _ready() -> void:
	resized.connect(_reset_particles)
	_reset_particles()

func _process(delta: float) -> void:
	_elapsed += delta
	for particle in _particles:
		var position: Vector2 = particle.position
		var angle: float = particle.heading + sin(
			_elapsed * particle.turn_speed + particle.phase
		) * particle.turn_amount
		var direction := Vector2.RIGHT.rotated(angle)
		var normal := Vector2(-direction.y, direction.x)
		var speed: float = particle.base_speed + sin(
			_elapsed * particle.gust_frequency + particle.phase * 1.7
		) * particle.speed_variation
		var turbulence: float = sin(
			_elapsed * particle.turbulence_frequency + particle.phase
		) * particle.side_drift

		position += (direction * maxf(speed, 12.0) + normal * turbulence) * delta

		particle.position = position
		particle.direction = direction

		var margin: float = particle.length + 70.0
		if (
			position.x > size.x + margin
			or position.x < -margin
			or position.y > size.y + margin
			or position.y < -margin
		):
			_respawn_particle(particle)
	queue_redraw()

func _draw() -> void:
	for particle in _particles:
		var vertical_position: float = particle.position.y / maxf(size.y, 1.0)
		if vertical_position < 0.075 or vertical_position > 0.925:
			continue

		var brightness: float = particle.brightness
		var tint := BASE_COLOR.lerp(Color.WHITE, brightness)
		var pulse := 0.82 + 0.18 * sin(
			_elapsed * particle.shimmer_speed + particle.phase
		)
		var color := Color(tint, particle.alpha * pulse)
		var points := _build_particle_shape(particle)
		draw_polyline(points, color, particle.width, true)

func _build_particle_shape(particle: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var direction: Vector2 = particle.direction
	var normal := Vector2(-direction.y, direction.x)
	var segment_count := 1 if particle.style == STRAIGHT else 8

	for segment in range(segment_count + 1):
		var progress := float(segment) / float(segment_count)
		var point: Vector2 = particle.position - direction * particle.length * progress
		var bend := 0.0

		if particle.style == WAVY:
			bend = sin(
				progress * TAU * particle.wave_count
				+ _elapsed * particle.shape_speed
				+ particle.phase
			) * particle.shape_amplitude * progress
		elif particle.style == IRREGULAR:
			bend = (
				sin(progress * 8.5 + particle.phase)
				+ sin(progress * 19.0 - particle.phase * 0.7) * 0.42
				+ sin(_elapsed * particle.shape_speed + progress * 4.0) * 0.25
			) * particle.shape_amplitude * progress

		points.append(point + normal * bend)

	return points

func _reset_particles() -> void:
	_particles.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		return

	for index in PARTICLE_COUNT:
		var is_reverse := randf() < 0.14
		var heading := randf_range(-0.42, 0.42)
		if is_reverse:
			heading += PI

		var particle: Dictionary = {
			"position": Vector2(randf_range(0.0, size.x), randf_range(size.y * 0.06, size.y * 0.94)),
			"direction": Vector2.RIGHT.rotated(heading),
			"heading": heading,
			"base_speed": randf_range(28.0, 145.0),
			"speed_variation": randf_range(8.0, 42.0),
			"gust_frequency": randf_range(0.35, 1.25),
			"length": randf_range(10.0, 68.0),
			"alpha": randf_range(0.065, 0.19),
			"width": randf_range(0.65, 1.65),
			"brightness": randf_range(0.05, 0.6),
			"style": index % 3,
			"turn_speed": randf_range(0.25, 0.9),
			"turn_amount": randf_range(0.035, 0.2),
			"turbulence_frequency": randf_range(0.7, 2.4),
			"side_drift": randf_range(2.0, 16.0),
			"shape_amplitude": randf_range(1.0, 7.0),
			"shape_speed": randf_range(0.5, 2.2),
			"wave_count": randf_range(0.7, 1.7),
			"shimmer_speed": randf_range(0.5, 1.8),
			"phase": float(index) * 0.73 + randf_range(-0.35, 0.35),
		}
		_particles.append(particle)

func _respawn_particle(particle: Dictionary) -> void:
	var direction: Vector2 = particle.direction
	var margin: float = particle.length + randf_range(30.0, 150.0)
	if direction.x >= 0.0:
		particle.position = Vector2(-margin, randf_range(0.04, 0.96) * size.y)
	else:
		particle.position = Vector2(size.x + margin, randf_range(0.04, 0.96) * size.y)

	particle.base_speed = randf_range(28.0, 145.0)
	particle.speed_variation = randf_range(8.0, 42.0)
