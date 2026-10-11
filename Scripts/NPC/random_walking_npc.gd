class_name RandomWalkingNPC
extends CharacterBody2D

## NPC de cuadrícula con desplazamientos ocasionales de una sola celda.
## Conserva un radio de paseo pequeño para no abandonar su zona narrativa.

const DIRECTIONS: Array[Vector2] = [
	Vector2.DOWN,
	Vector2.LEFT,
	Vector2.RIGHT,
	Vector2.UP,
]

@export_range(1.0, 128.0, 1.0) var grid_cell_size := 20.0
@export_range(10.0, 160.0, 1.0) var walking_speed := 40.0
@export_range(0.0, 1.0, 0.01) var movement_probability := 0.1
@export_range(0.5, 20.0, 0.1) var minimum_decision_delay := 2.5
@export_range(0.5, 20.0, 0.1) var maximum_decision_delay := 5.5
@export_range(0, 12, 1) var maximum_wander_distance_cells := 3
@export var initial_facing: StringName = &"down"
@export var npc_id: StringName
@export var auto_anchor_sprite_to_feet := true
@export var sprite_feet_offset := Vector2.ZERO
@export var collision_footprint_ratio := Vector2(0.60, 0.40)

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _random := RandomNumberGenerator.new()
var _home_position := Vector2.ZERO
var _step_start := Vector2.ZERO
var _step_target := Vector2.ZERO
var _step_direction := Vector2.ZERO
var _step_targets: Array[Vector2] = []
var _requested_step_direction := Vector2.ZERO
var _decision_remaining := 0.0
var _is_stepping := false
var _facing: StringName = &"down"
var _interaction_locked := false
var _grid_origin := Vector2(10.0, 20.0)
var _grid_origin_configured := false
var _is_rolling_back := false


func _ready() -> void:
	_register_interaction()
	add_to_group(&"grid_movement_actor")
	_random.randomize()
	_make_collision_shape_unique()
	_configure_foot_collision()
	_home_position = global_position
	_facing = initial_facing
	if not _sprite.frame_changed.is_connected(_refresh_visual_layout):
		_sprite.frame_changed.connect(_refresh_visual_layout)
	if not _sprite.animation_changed.is_connected(_refresh_visual_layout):
		_sprite.animation_changed.connect(_refresh_visual_layout)
	_refresh_visual_layout()
	_schedule_next_decision()
	_play_idle_animation()


## Los Pokémon reutilizan la cuadrícula, pero responden con un grito sin
## necesitar un identificador ni un archivo de diálogo humano.
func _register_interaction() -> void:
	add_to_group(&"dialogue_interactable")
	if npc_id.is_empty():
		push_warning(
			"%s pertenece a dialogue_interactable pero no tiene npc_id."
			% get_path()
		)


func _physics_process(delta: float) -> void:
	if _interaction_locked:
		velocity = Vector2.ZERO
		return
	if _is_stepping:
		_advance_step(delta)
		return

	velocity = Vector2.ZERO
	_decision_remaining -= delta
	if _decision_remaining > 0.0:
		return
	_schedule_next_decision()
	if _random.randf() <= movement_probability:
		_try_random_step()


func _try_random_step() -> void:
	var candidates := DIRECTIONS.duplicate()
	candidates.shuffle()
	for direction_value: Variant in candidates:
		var direction := direction_value as Vector2
		if try_start_grid_step(direction):
			return


## Inicia un paso normal o, si el NPC fue colocado fuera de la rejilla, una
## secuencia corta de segmentos rectos que corrige X e Y sin teletransportarlo.
func try_start_grid_step(direction: Vector2) -> bool:
	var planned_targets := _build_corrected_step_targets(direction)
	if planned_targets.is_empty() or not _is_within_wander_area(planned_targets.back()):
		return false
	if not _can_follow_targets(planned_targets):
		return false

	_step_targets = planned_targets
	_requested_step_direction = direction
	_is_rolling_back = false
	_is_stepping = true
	_begin_next_step_segment()
	return true


func _begin_next_step_segment() -> void:
	while not _step_targets.is_empty():
		var next_target: Vector2 = _step_targets.pop_front()
		if global_position.distance_to(next_target) <= 0.001:
			continue
		_step_start = global_position
		_step_target = next_target
		_step_direction = (next_target - global_position).normalized()
		_update_facing(_step_direction)
		_sprite.play(&"walk_%s" % _facing)
		return
	_finish_step()


func _advance_step(delta: float) -> void:
	var next_position := global_position.move_toward(
		_step_target,
		walking_speed * delta
	)
	var collision := move_and_collide(next_position - global_position)
	if collision != null:
		# Si otro cuerpo entra durante el paso, el NPC vuelve caminando al inicio
		# de este segmento. Antes se teletransportaba hasta allí.
		if not _is_rolling_back and global_position.distance_to(_step_start) > 0.001:
			_step_targets.clear()
			_step_target = _step_start
			_step_direction = (_step_start - global_position).normalized()
			_is_rolling_back = true
			_update_facing(_step_direction)
			_sprite.play(&"walk_%s" % _facing)
		else:
			_finish_step()
		return
	if global_position.is_equal_approx(_step_target):
		global_position = _step_target
		if not _step_targets.is_empty():
			_begin_next_step_segment()
		else:
			_finish_step()


func _finish_step() -> void:
	_is_stepping = false
	_step_targets.clear()
	_step_direction = Vector2.ZERO
	_requested_step_direction = Vector2.ZERO
	_is_rolling_back = false
	velocity = Vector2.ZERO
	_play_idle_animation()


func _build_corrected_step_targets(direction: Vector2) -> Array[Vector2]:
	if not _grid_origin_configured:
		return [global_position + direction * grid_cell_size]

	var targets: Array[Vector2] = []
	var cursor := global_position
	var snapped_x := _nearest_grid_coordinate(cursor.x, _grid_origin.x)
	var snapped_y := _nearest_grid_coordinate(cursor.y, _grid_origin.y)
	if not is_zero_approx(direction.x):
		if not is_equal_approx(cursor.y, snapped_y):
			cursor = Vector2(cursor.x, snapped_y)
			targets.append(cursor)
		cursor.x = _next_grid_coordinate(cursor.x, _grid_origin.x, direction.x)
		targets.append(cursor)
	else:
		if not is_equal_approx(cursor.x, snapped_x):
			cursor = Vector2(snapped_x, cursor.y)
			targets.append(cursor)
		cursor.y = _next_grid_coordinate(cursor.y, _grid_origin.y, direction.y)
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


func _can_follow_targets(targets: Array[Vector2]) -> bool:
	var segment_start := global_position
	for target in targets:
		var test_transform := global_transform
		test_transform.origin = segment_start
		if test_move(test_transform, target - segment_start):
			return false
		segment_start = target
	return true


func _is_within_wander_area(target: Vector2) -> bool:
	if maximum_wander_distance_cells <= 0:
		return target.is_equal_approx(_home_position)
	var maximum_distance := grid_cell_size * maximum_wander_distance_cells
	var offset := (target - _home_position).abs()
	return offset.x <= maximum_distance and offset.y <= maximum_distance


func _update_facing(direction: Vector2) -> void:
	# Las escalas anidadas dejan pequeños residuos en el otro eje. Usar el
	# dominante sirve tanto al caminar como al mirar hacia el jugador.
	if absf(direction.x) > absf(direction.y):
		_facing = &"left" if direction.x < 0.0 else &"right"
	else:
		_facing = &"up" if direction.y < 0.0 else &"down"


func _play_idle_animation() -> void:
	_sprite.play(&"idle_%s" % _facing)


func _refresh_visual_layout() -> void:
	if not auto_anchor_sprite_to_feet or _sprite.sprite_frames == null:
		return
	if not _sprite.sprite_frames.has_animation(_sprite.animation):
		return
	var frame_texture := _sprite.sprite_frames.get_frame_texture(
		_sprite.animation,
		_sprite.frame
	)
	if frame_texture == null:
		return

	var visual_size := frame_texture.get_size() * _sprite.scale.abs()
	if _sprite.centered:
		_sprite.position = Vector2(0.0, -visual_size.y * 0.5) + sprite_feet_offset
	else:
		_sprite.position = Vector2(-visual_size.x * 0.5, -visual_size.y) + sprite_feet_offset


func _make_collision_shape_unique() -> void:
	if _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate()


func _configure_foot_collision() -> void:
	var rectangle := _collision_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		_collision_shape.shape = rectangle
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
	_collision_shape.position = Vector2(0.0, -footprint_local_size.y * 0.5)


func _schedule_next_decision() -> void:
	var minimum_delay := minf(minimum_decision_delay, maximum_decision_delay)
	var maximum_delay := maxf(minimum_decision_delay, maximum_decision_delay)
	_decision_remaining = _random.randf_range(minimum_delay, maximum_delay)


func get_npc_id() -> StringName:
	return npc_id


## Recibe la cuadrícula sin cambiar la posición visible del NPC. Su punto de
## hogar sí se registra en la celda más cercana para mantener un radio estable.
func configure_movement_grid(world_cell_size: float, grid_origin: Vector2) -> void:
	grid_cell_size = maxf(world_cell_size, 1.0)
	_grid_origin = grid_origin
	_grid_origin_configured = true
	_configure_foot_collision()
	var relative_home := (_home_position - _grid_origin) / grid_cell_size
	_home_position = _grid_origin + Vector2(
		roundf(relative_home.x),
		roundf(relative_home.y)
	) * grid_cell_size


## Usa el mismo punto de suelo que el personaje jugable. También actualiza el
## origen de paseo para que el radio del NPC no conserve el offset previo.
func align_to_movement_grid(world_cell_size: float, grid_origin: Vector2) -> void:
	configure_movement_grid(world_cell_size, grid_origin)
	var relative_position := (global_position - _grid_origin) / grid_cell_size
	global_position = _grid_origin + Vector2(
		roundf(relative_position.x),
		roundf(relative_position.y)
	) * grid_cell_size
	_home_position = global_position
	_step_start = global_position
	_step_target = global_position
	_step_targets.clear()
	_step_direction = Vector2.ZERO
	_requested_step_direction = Vector2.ZERO
	_is_stepping = false
	_is_rolling_back = false
	velocity = Vector2.ZERO
	_play_idle_animation()


func set_interaction_locked(locked: bool) -> void:
	if _interaction_locked == locked:
		return
	_interaction_locked = locked
	velocity = Vector2.ZERO
	if locked:
		_play_idle_animation()
	elif _is_stepping:
		_sprite.play(&"walk_%s" % _facing)


func face_toward(world_position: Vector2) -> void:
	var direction := world_position - global_position
	if direction.is_zero_approx():
		return
	_update_facing(direction)
	_play_idle_animation()
