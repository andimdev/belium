class_name OverworldPlayer3D
extends CharacterBody3D

signal grid_step_started(start_position: Vector3, target_position: Vector3, direction: Vector3)
signal grid_step_completed(world_position: Vector3, direction: Vector3)
## Se emite cuando un paso hacia `direction` queda bloqueado (colisión, relieve o hueco).
signal step_blocked(from_position: Vector3, direction: Vector3)

const INPUT_BINDINGS: Dictionary[StringName, Array] = {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"run": [KEY_SHIFT],
}

@export_node_path("MovementGrid3D") var movement_grid_path: NodePath
@export_node_path("Camera3D") var camera_path: NodePath
@export_node_path("Terrain3D") var terrain_path: NodePath
@export_range(0.1, 10.0, 0.1, "or_greater") var fallback_cell_size := 1.0
@export_range(0.1, 20.0, 0.1, "or_greater") var walk_speed := 3.4
@export_range(0.1, 30.0, 0.1, "or_greater") var run_speed := 5.5
@export var control_enabled := true
@export_range(0.0, 0.2, 0.005) var ground_clearance := 0.025
@export_range(0.0, 60.0, 1.0) var maximum_ground_slope_degrees := 40.0

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D

var facing_direction: StringName = &"down"
var _movement_grid: MovementGrid3D
var _view_camera: Camera3D
var _terrain: Terrain3D
var _is_stepping := false
var _step_start := Vector3.ZERO
var _step_target := Vector3.ZERO
var _step_direction := Vector3.ZERO
var _active_speed := 0.0
var _active_running := false
var _scripted_motion := false


func _ready() -> void:
	add_to_group(&"grid_movement_actor_3d")
	_ensure_default_input_actions()
	_movement_grid = get_node_or_null(movement_grid_path) as MovementGrid3D
	_view_camera = get_node_or_null(camera_path) as Camera3D
	_terrain = get_node_or_null(terrain_path) as Terrain3D
	_snap_to_grid()
	_update_idle_animation()


func _physics_process(delta: float) -> void:
	if _is_stepping:
		_advance_step(delta)
		return

	if _scripted_motion:
		return

	if not control_enabled:
		velocity = Vector3.ZERO
		_update_idle_animation()
		return

	var requested_direction := _read_cardinal_direction()
	if requested_direction != Vector3.ZERO:
		_start_step(requested_direction, Input.is_action_pressed(&"run"))
	else:
		velocity = Vector3.ZERO
		_update_idle_animation()


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	if not control_enabled and not _is_stepping:
		velocity = Vector3.ZERO
		_update_idle_animation()


## Camina hasta `target` por movimiento guionado: no pasa por la física, así que
## atraviesa colisiones. Pensado para puertas y cinemáticas; el llamador debe
## haber desactivado el control (`set_control_enabled(false)`).
func walk_scripted(target: Vector3, duration: float) -> void:
	_scripted_motion = true
	var direction := target - global_position
	direction.y = 0.0
	if direction != Vector3.ZERO:
		_update_facing_from_direction(direction.normalized())
	_active_running = false
	_play_movement_animation()
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, maxf(duration, 0.01))
	await tween.finished
	_scripted_motion = false
	_update_idle_animation()


func _start_step(direction: Vector3, running: bool) -> void:
	_step_start = global_position
	_step_direction = direction.normalized()
	_active_running = running
	_active_speed = run_speed if running else walk_speed
	var cell_size := _get_cell_size()
	var proposed_target := global_position + _step_direction * cell_size
	_step_target = _ground_position(_snap_position(proposed_target))
	_update_facing_from_direction(_step_direction)
	if not _step_target.is_finite():
		_update_idle_animation()
		return

	if _movement_grid != null and not _movement_grid.contains_world_position(_step_target):
		_update_idle_animation()
		return

	if not _can_traverse_step(global_position, _step_target):
		step_blocked.emit(global_position, _step_direction)
		_update_idle_animation()
		return

	_is_stepping = true
	_play_movement_animation()
	grid_step_started.emit(_step_start, _step_target, _step_direction)


func _advance_step(delta: float) -> void:
	var remaining := _step_target - global_position
	remaining.y = 0.0
	var distance_remaining := remaining.length()
	var travel_distance := _active_speed * delta
	var reaches_target := distance_remaining <= travel_distance + 0.0005
	var next_position := _step_target if reaches_target else _ground_position(
		global_position + remaining.normalized() * travel_distance
	)
	if not next_position.is_finite():
		global_position = _step_start
		_finish_step(false)
		return
	var motion := next_position - global_position
	velocity = motion / delta
	var collision := move_and_collide(motion)
	if collision != null:
		global_position = _step_start
		_finish_step(false)
	elif reaches_target:
		global_position = _step_target
		_finish_step()


func _finish_step(completed: bool = true) -> void:
	_is_stepping = false
	velocity = Vector3.ZERO
	if completed:
		grid_step_completed.emit(global_position, _step_direction)

	if control_enabled and completed:
		var held_direction := _read_cardinal_direction()
		if held_direction != Vector3.ZERO:
			_start_step(held_direction, Input.is_action_pressed(&"run"))
			return
	_update_idle_animation()


func _read_cardinal_direction() -> Vector3:
	# La grilla conserva sus ejes: la cámara decide qué eje corresponde a cada tecla.
	var screen_right := _screen_right_direction()
	var screen_up := Vector3.UP.cross(screen_right)
	if Input.is_action_just_pressed(&"move_left"):
		return -screen_right
	if Input.is_action_just_pressed(&"move_right"):
		return screen_right
	if Input.is_action_just_pressed(&"move_up"):
		return screen_up
	if Input.is_action_just_pressed(&"move_down"):
		return -screen_up

	var horizontal := Input.get_axis(&"move_left", &"move_right")
	var vertical := Input.get_axis(&"move_up", &"move_down")
	if is_zero_approx(horizontal) and is_zero_approx(vertical):
		return Vector3.ZERO
	if absf(horizontal) >= absf(vertical):
		return screen_right * signf(horizontal)
	return -screen_up * signf(vertical)


func _screen_right_direction() -> Vector3:
	var camera := (
		_view_camera if is_instance_valid(_view_camera) else get_viewport().get_camera_3d()
	)
	if camera == null:
		# Conserva la orientación del mapa de prueba original cuando no hay cámara.
		return Vector3.LEFT
	var right := camera.global_basis.x
	if absf(right.x) >= absf(right.z):
		return Vector3.RIGHT if right.x >= 0.0 else Vector3.LEFT
	return Vector3.BACK if right.z >= 0.0 else Vector3.FORWARD


func _update_facing_from_direction(direction: Vector3) -> void:
	var screen_right := _screen_right_direction()
	var horizontal := direction.dot(screen_right)
	var vertical := direction.dot(Vector3.UP.cross(screen_right))
	if absf(horizontal) > absf(vertical):
		facing_direction = &"right" if horizontal > 0.0 else &"left"
	else:
		facing_direction = &"up" if vertical > 0.0 else &"down"


func _play_movement_animation() -> void:
	var prefix := "run_" if _active_running else "walk_"
	var animation_name := StringName(prefix + String(facing_direction))
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func _update_idle_animation() -> void:
	var animation_name := StringName("idle_" + String(facing_direction))
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)


func _snap_to_grid() -> void:
	var grounded := _ground_position(_snap_position(global_position))
	if grounded.is_finite():
		global_position = grounded
	else:
		control_enabled = false
		push_warning("CynthiaPlayer3D: coloca al personaje sobre una región de Terrain3D sin agujeros.")


func _ground_position(world_position: Vector3) -> Vector3:
	if _terrain == null:
		return world_position
	var height := _terrain.data.get_surface_height(world_position)
	if not is_finite(height):
		return Vector3.INF
	world_position.y = height + ground_clearance
	return world_position


func _can_traverse_step(start: Vector3, target: Vector3) -> bool:
	# Revisa todo el paso, también los agujeros y el relieve entre sus extremos.
	var flat_distance := Vector2(target.x - start.x, target.z - start.z).length()
	var sample_spacing := minf(_get_cell_size() * 0.2, 0.2)
	var samples := maxi(1, int(ceilf(flat_distance / sample_spacing)))
	var previous := start
	for index in range(1, samples + 1):
		var next := _ground_position(start.lerp(target, float(index) / samples))
		if not next.is_finite():
			return false
		var motion := next - previous
		var horizontal_distance := Vector2(motion.x, motion.z).length()
		if (
			_terrain != null
			and absf(motion.y) > horizontal_distance * tan(deg_to_rad(maximum_ground_slope_degrees))
		):
			return false
		var probe := global_transform
		probe.origin = previous
		if test_move(probe, motion):
			return false
		previous = next
	return true


func _snap_position(world_position: Vector3) -> Vector3:
	if _movement_grid != null:
		return _movement_grid.snap_world_position(world_position)
	var snapped_position := world_position
	snapped_position.x = snappedf(world_position.x, fallback_cell_size)
	snapped_position.z = snappedf(world_position.z, fallback_cell_size)
	return snapped_position


func _get_cell_size() -> float:
	if _movement_grid != null:
		return _movement_grid.cell_size
	return fallback_cell_size


func _ensure_default_input_actions() -> void:
	for action: StringName in INPUT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: Key in INPUT_BINDINGS[action]:
			if _action_has_key(action, keycode):
				continue
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode
			InputMap.action_add_event(action, key_event)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false
