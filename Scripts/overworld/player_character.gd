class_name OverworldPlayer
extends CharacterBody2D

signal movement_state_changed(previous_state: int, new_state: int)
signal grid_step_started(start_position: Vector2, target_position: Vector2, direction: Vector2)
signal grid_step_completed(world_position: Vector2, direction: Vector2)

const INPUT_BINDINGS: Dictionary[StringName, Array] = {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"run": [KEY_SHIFT],
	&"switch_character": [KEY_ENTER, KEY_KP_ENTER],
}

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: PlayerMovementStateMachine = $MovementStateMachine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var player_camera: Camera2D = $Camera2D

@export_range(1.0, 256.0, 0.5, "or_greater") var grid_cell_size := 20.0
@export var collision_footprint_ratio := Vector2(0.60, 0.40)
@export var auto_anchor_sprite_to_feet := true
@export var sprite_feet_offset := Vector2.ZERO
@export var center_camera_on_sprite := true
@export var camera_focus_offset := Vector2.ZERO
@export var character_id: StringName = &"01Cynthia"

var facing_direction: StringName = &"down"
var last_cardinal_direction := Vector2.DOWN
var control_enabled := true
var movement_locked := false
var _is_stepping := false
var _step_target_global_position := Vector2.ZERO
var _step_direction := Vector2.ZERO
var _step_targets: Array[Vector2] = []
var _requested_step_direction := Vector2.ZERO
var _step_speed := 0.0
var _step_wants_to_run := false
var _queued_direction := Vector2.ZERO
var _alternate_step_pose := false
var _grid_origin := Vector2(10.0, 20.0)
var _grid_origin_configured := false


func _ready() -> void:
	add_to_group(&"grid_movement_actor")
	_ensure_default_input_actions()
	_make_collision_shape_unique()
	if not animated_sprite.frame_changed.is_connected(_refresh_visual_layout):
		animated_sprite.frame_changed.connect(_refresh_visual_layout)
	if not animated_sprite.animation_changed.is_connected(_refresh_visual_layout):
		animated_sprite.animation_changed.connect(_refresh_visual_layout)
	_refresh_visual_layout()
	_configure_foot_collision()
	state_machine.state_changed.connect(_on_state_changed)
	_update_animation()


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled or movement_locked:
		return

	var pressed_direction := Vector2.ZERO
	if event.is_action_pressed(&"move_left"):
		pressed_direction = Vector2.LEFT
	elif event.is_action_pressed(&"move_right"):
		pressed_direction = Vector2.RIGHT
	elif event.is_action_pressed(&"move_up"):
		pressed_direction = Vector2.UP
	elif event.is_action_pressed(&"move_down"):
		pressed_direction = Vector2.DOWN

	if not pressed_direction.is_zero_approx():
		_queued_direction = pressed_direction


func _physics_process(delta: float) -> void:
	if movement_locked:
		velocity = Vector2.ZERO
		state_machine.update_state(Vector2.ZERO, false)
		_update_animation()
		return

	if _is_stepping:
		_advance_grid_step(delta)

	if not _is_stepping:
		var input_direction := _consume_movement_direction()
		if input_direction.is_zero_approx():
			velocity = Vector2.ZERO
			state_machine.update_state(Vector2.ZERO, false)
		else:
			_update_facing_direction(input_direction)
			_try_start_grid_step(input_direction, Input.is_action_pressed(&"run"))

	_update_animation()


func configure_grid(world_cell_size: float) -> void:
	grid_cell_size = maxf(world_cell_size, 1.0)
	_configure_foot_collision()


## Recibe la definición común de la rejilla sin mover al personaje. Cualquier
## offset de colocación se corrige de forma visible durante el primer paso.
func configure_movement_grid(world_cell_size: float, grid_origin: Vector2) -> void:
	grid_cell_size = maxf(world_cell_size, 1.0)
	_grid_origin = grid_origin
	_grid_origin_configured = true
	_configure_foot_collision()


## Coloca el punto de apoyo en el centro horizontal del borde inferior de una
## celda. El tamaño del sprite no interviene: todos los actores se alinean por
## los pies sobre la línea del suelo, aunque sus imágenes sean distintas.
func align_to_movement_grid(world_cell_size: float, grid_origin: Vector2) -> void:
	configure_movement_grid(world_cell_size, grid_origin)
	var relative_position := (global_position - _grid_origin) / grid_cell_size
	global_position = _grid_origin + Vector2(
		roundf(relative_position.x),
		roundf(relative_position.y)
	) * grid_cell_size

	_is_stepping = false
	_step_targets.clear()
	_step_target_global_position = global_position
	_step_direction = Vector2.ZERO
	_requested_step_direction = Vector2.ZERO
	_step_speed = 0.0
	_step_wants_to_run = false
	_queued_direction = Vector2.ZERO
	velocity = Vector2.ZERO
	_configure_foot_collision()
	state_machine.update_state(Vector2.ZERO, false)
	_update_animation()


func is_grid_stepping() -> bool:
	return _is_stepping


func get_visual_world_size() -> Vector2:
	var frame_texture := _get_current_frame_texture()
	if frame_texture == null:
		return Vector2.ZERO
	var local_visual_size := frame_texture.get_size() * animated_sprite.scale.abs()
	return Vector2(
		local_visual_size.x * global_transform.x.length(),
		local_visual_size.y * global_transform.y.length()
	)


func get_footprint_world_size() -> Vector2:
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return Vector2.ZERO
	return Vector2(
		rectangle.size.x * global_transform.x.length(),
		rectangle.size.y * global_transform.y.length()
	)


func _get_current_frame_texture() -> Texture2D:
	if animated_sprite.sprite_frames == null:
		return null
	if not animated_sprite.sprite_frames.has_animation(animated_sprite.animation):
		return null
	return animated_sprite.sprite_frames.get_frame_texture(
		animated_sprite.animation,
		animated_sprite.frame
	)


func _refresh_visual_layout() -> void:
	var frame_texture := _get_current_frame_texture()
	if frame_texture == null:
		return

	var visual_size := frame_texture.get_size() * animated_sprite.scale.abs()
	var visual_center := animated_sprite.position
	if auto_anchor_sprite_to_feet:
		if animated_sprite.centered:
			animated_sprite.position = Vector2(0.0, -visual_size.y * 0.5) + sprite_feet_offset
			visual_center = animated_sprite.position
		else:
			animated_sprite.position = Vector2(-visual_size.x * 0.5, -visual_size.y) + sprite_feet_offset
			visual_center = animated_sprite.position + visual_size * 0.5

	if center_camera_on_sprite:
		player_camera.position = visual_center + camera_focus_offset


func _make_collision_shape_unique() -> void:
	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()


func _configure_foot_collision() -> void:
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		collision_shape.shape = rectangle

	var world_scale := Vector2(
		maxf(global_transform.x.length(), 0.001),
		maxf(global_transform.y.length(), 0.001)
	)
	var safe_ratio := Vector2(
		clampf(collision_footprint_ratio.x, 0.1, 1.0),
		clampf(collision_footprint_ratio.y, 0.1, 1.0)
	)
	var footprint_world_size := Vector2.ONE * grid_cell_size * safe_ratio
	var footprint_local_size := footprint_world_size / world_scale
	rectangle.size = footprint_local_size

	# El origen del CharacterBody representa el punto de apoyo sobre la celda.
	# La colisión queda justo encima de ese punto y no ocupa el torso del sprite.
	collision_shape.position = Vector2(0.0, -footprint_local_size.y * 0.5)


func _consume_movement_direction() -> Vector2:
	if not _queued_direction.is_zero_approx():
		var direction := _queued_direction
		_queued_direction = Vector2.ZERO
		last_cardinal_direction = direction
		return direction
	return _get_cardinal_input_direction()


func _try_start_grid_step(direction: Vector2, wants_to_run: bool) -> void:
	var planned_targets := _build_corrected_step_targets(direction)
	var traversable_targets: Array[Vector2] = []
	var segment_start := global_position
	for target in planned_targets:
		if _would_collide_between(segment_start, target):
			traversable_targets.clear()
			break
		traversable_targets.append(target)
		segment_start = target

	if traversable_targets.is_empty():
		velocity = Vector2.ZERO
		state_machine.update_state(Vector2.ZERO, false)
		return

	var started_from_idle := state_machine.get_animation_prefix() == &"idle"
	_step_targets = traversable_targets
	_requested_step_direction = direction
	_step_wants_to_run = wants_to_run
	_is_stepping = true
	grid_step_started.emit(global_position, _step_targets.back(), direction)
	_begin_next_step_segment(started_from_idle)


func _advance_grid_step(delta: float) -> void:
	var remaining_distance := global_position.distance_to(_step_target_global_position)
	var movement_distance := _step_speed * delta
	if movement_distance + 0.001 < remaining_distance:
		var next_position := global_position.move_toward(
			_step_target_global_position,
			movement_distance
		)
		var collision := move_and_collide(next_position - global_position)
		if collision != null:
			_interrupt_grid_step_on_collision()
		return

	var final_motion := _step_target_global_position - global_position
	if not final_motion.is_zero_approx():
		var final_collision := move_and_collide(final_motion)
		if final_collision != null:
			_interrupt_grid_step_on_collision()
			return
	global_position = _step_target_global_position
	if not _step_targets.is_empty():
		_begin_next_step_segment(false)
		return

	var completed_direction := _requested_step_direction
	_is_stepping = false
	_step_direction = Vector2.ZERO
	_requested_step_direction = Vector2.ZERO
	_step_speed = 0.0
	_step_wants_to_run = false
	velocity = Vector2.ZERO
	grid_step_completed.emit(global_position, completed_direction)


func _interrupt_grid_step_on_collision() -> void:
	# Un NPC puede entrar en la trayectoria después de la comprobación inicial.
	# En ese caso se detiene en el punto seguro alcanzado, sin atravesarlo ni
	# teletransportarse. El próximo input corrige cualquier offset restante.
	_is_stepping = false
	_step_targets.clear()
	_step_direction = Vector2.ZERO
	_requested_step_direction = Vector2.ZERO
	_step_speed = 0.0
	_step_wants_to_run = false
	velocity = Vector2.ZERO
	state_machine.update_state(Vector2.ZERO, false)


func _begin_next_step_segment(started_from_idle: bool) -> void:
	while not _step_targets.is_empty():
		var next_target: Vector2 = _step_targets.pop_front()
		if global_position.distance_to(next_target) <= 0.001:
			continue
		_step_target_global_position = next_target
		_step_direction = (next_target - global_position).normalized()
		_update_facing_direction(_step_direction)
		state_machine.update_state(_step_direction, _step_wants_to_run)
		_step_speed = state_machine.get_movement_speed()
		if started_from_idle:
			_start_step_animation()
		else:
			# Los segmentos de corrección conservan el ritmo de la animación;
			# sólo cambia la dirección cuando X e Y se corrigen por separado.
			_update_animation()
		velocity = _step_direction * _step_speed
		return

	_is_stepping = false
	velocity = Vector2.ZERO


func _build_corrected_step_targets(direction: Vector2) -> Array[Vector2]:
	if not _grid_origin_configured:
		return [global_position + direction * grid_cell_size]

	var targets: Array[Vector2] = []
	var cursor := global_position
	var snapped_x := _nearest_grid_coordinate(cursor.x, _grid_origin.x)
	var snapped_y := _nearest_grid_coordinate(cursor.y, _grid_origin.y)

	if not is_zero_approx(direction.x):
		# Antes de avanzar horizontalmente se corrige la fila, con un segmento
		# vertical independiente. Así nunca aparece un salto diagonal.
		if not is_equal_approx(cursor.y, snapped_y):
			cursor = Vector2(cursor.x, snapped_y)
			targets.append(cursor)
		cursor.x = _next_grid_coordinate(
			cursor.x,
			_grid_origin.x,
			direction.x
		)
		targets.append(cursor)
	else:
		# Para un paso vertical se centra primero la columna mediante un
		# segmento horizontal y luego se avanza hasta la línea de suelo.
		if not is_equal_approx(cursor.x, snapped_x):
			cursor = Vector2(snapped_x, cursor.y)
			targets.append(cursor)
		cursor.y = _next_grid_coordinate(
			cursor.y,
			_grid_origin.y,
			direction.y
		)
		targets.append(cursor)
	return targets


func _nearest_grid_coordinate(value: float, origin: float) -> float:
	return origin + roundf((value - origin) / grid_cell_size) * grid_cell_size


func _next_grid_coordinate(value: float, origin: float, direction: float) -> float:
	var relative_value := (value - origin) / grid_cell_size
	if is_equal_approx(relative_value, roundf(relative_value)):
		return value + signf(direction) * grid_cell_size
	var target_index := ceili(relative_value) if direction > 0.0 else floori(relative_value)
	return origin + float(target_index) * grid_cell_size


func _would_collide_between(from_position: Vector2, to_position: Vector2) -> bool:
	var test_transform := global_transform
	test_transform.origin = from_position
	return test_move(test_transform, to_position - from_position)


func set_control_enabled(enabled: bool) -> void:
	if not enabled and _is_stepping:
		_is_stepping = false
		_step_targets.clear()
		_step_direction = Vector2.ZERO
		_requested_step_direction = Vector2.ZERO
		_step_speed = 0.0
		grid_step_completed.emit(global_position, last_cardinal_direction)

	control_enabled = enabled
	visible = enabled
	player_camera.enabled = enabled
	collision_shape.set_deferred(&"disabled", not enabled)
	set_physics_process(enabled)

	if not enabled:
		velocity = Vector2.ZERO
		_queued_direction = Vector2.ZERO
		state_machine.update_state(Vector2.ZERO, false)

	_update_animation()


## Bloqueo temporal usado por menús y diálogos. Si se activa a mitad de una
## celda, el paso queda congelado y continúa desde el mismo punto al cerrar la
## interfaz, sin teletransportar ni desalinear al personaje de la cuadrícula.
func set_movement_locked(locked: bool) -> void:
	if movement_locked == locked:
		return
	movement_locked = locked
	velocity = Vector2.ZERO
	_queued_direction = Vector2.ZERO

	if locked:
		state_machine.update_state(Vector2.ZERO, false)
	elif _is_stepping:
		state_machine.update_state(_step_direction, _step_wants_to_run)
	else:
		state_machine.update_state(Vector2.ZERO, false)
	_update_animation()


func face_toward(world_position: Vector2) -> void:
	var direction := world_position - global_position
	if direction.is_zero_approx():
		return
	if absf(direction.x) > absf(direction.y):
		last_cardinal_direction = Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
	else:
		last_cardinal_direction = Vector2.DOWN if direction.y > 0.0 else Vector2.UP
	_update_facing_direction(last_cardinal_direction)
	state_machine.update_state(Vector2.ZERO, false)
	_update_animation()


func _get_cardinal_input_direction() -> Vector2:
	var horizontal_axis := Input.get_axis(&"move_left", &"move_right")
	var vertical_axis := Input.get_axis(&"move_up", &"move_down")

	if is_zero_approx(horizontal_axis) and is_zero_approx(vertical_axis):
		return Vector2.ZERO

	var horizontal_direction := Vector2(signf(horizontal_axis), 0.0)
	var vertical_direction := Vector2(0.0, signf(vertical_axis))
	var direction: Vector2

	if not is_zero_approx(horizontal_axis) and not is_zero_approx(vertical_axis):
		var horizontal_was_just_pressed := (
			Input.is_action_just_pressed(&"move_left")
			or Input.is_action_just_pressed(&"move_right")
		)
		var vertical_was_just_pressed := (
			Input.is_action_just_pressed(&"move_up")
			or Input.is_action_just_pressed(&"move_down")
		)

		if horizontal_was_just_pressed:
			direction = horizontal_direction
		elif vertical_was_just_pressed:
			direction = vertical_direction
		elif not is_zero_approx(last_cardinal_direction.x):
			direction = horizontal_direction
		else:
			direction = vertical_direction
	elif not is_zero_approx(horizontal_axis):
		direction = horizontal_direction
	else:
		direction = vertical_direction

	last_cardinal_direction = direction
	return direction


func _update_facing_direction(input_direction: Vector2) -> void:
	if absf(input_direction.x) > absf(input_direction.y):
		facing_direction = &"right" if input_direction.x > 0.0 else &"left"
	else:
		facing_direction = &"down" if input_direction.y > 0.0 else &"up"


func _update_animation() -> void:
	var animation_name := StringName(
		"%s_%s" % [state_machine.get_animation_prefix(), facing_direction]
	)

	if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
		animated_sprite.play(animation_name)


func _start_step_animation() -> void:
	# Un paso por celda puede terminar antes de que la animación alcance su
	# segundo frame. Iniciarlo en una pose de pie adelantado hace visible la
	# marcha incluso con la pulsación más breve. Sólo se llama al partir desde
	# reposo; los pasos sostenidos conservan el flujo normal de la animación.
	_update_animation()
	if animated_sprite.sprite_frames == null:
		return

	var frame_count := animated_sprite.sprite_frames.get_frame_count(
		animated_sprite.animation
	)
	if frame_count <= 1:
		return

	_alternate_step_pose = not _alternate_step_pose
	if frame_count >= 4:
		animated_sprite.frame = 1 if _alternate_step_pose else 3
	else:
		animated_sprite.frame = 1
	animated_sprite.frame_progress = 0.0


func _on_state_changed(previous_state: int, new_state: int) -> void:
	movement_state_changed.emit(previous_state, new_state)


func _ensure_default_input_actions() -> void:
	for action: StringName in INPUT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		for keycode: Key in INPUT_BINDINGS[action]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode

			if not InputMap.action_has_event(action, key_event):
				InputMap.action_add_event(action, key_event)
