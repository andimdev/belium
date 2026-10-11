extends Node2D

const GrassStepEffect := preload("res://Scripts/Overworld/grass_step_effect.gd")
const PondWaterEffect := preload("res://Scripts/Overworld/pond_water_effect.gd")
const TallGrassCut := preload("res://Resources/Tileset/tall_grass_cut.png")
const TALL_GRASS_CUSTOM_DATA := &"is_tall_grass"
const INVALID_GRASS_CELL := Vector2i(2147483647, 2147483647)

signal active_camera_zone_changed(zone_id: StringName, display_name: String)

@export_node_path("Node2D") var player_path: NodePath
@export_node_path("TileMapLayer") var tall_grass_layer_path: NodePath
@export_node_path("TileMapLayer") var camera_bounds_layer_path: NodePath
@export_node_path("Node") var camera_zones_root_path: NodePath
@export var map_id: StringName
@export var grass_foot_offset_y := -5.0
@export var pond_water_rect := Rect2()
@export_range(1.0, 2.0, 0.01) var camera_zoom_multiplier := 1.15
@export_range(0.5, 3.0, 0.05) var interaction_distance_cells := 1.45

var _player: Node2D
var _tall_grass_layer: TileMapLayer
var _camera_bounds_layer: TileMapLayer
var _player_camera: Camera2D
var _camera_zones: Array[OverworldCameraZone] = []
var _active_camera_zone: OverworldCameraZone
var _fallback_camera_bounds := Rect2()
var _camera_cell_size := Vector2.ONE
var _current_camera_bounds := Rect2()
var _applied_camera_limits := Rect2()
var _camera_follow_position := Vector2.ZERO
var _camera_transition_tween: Tween
var _grass_actor_states: Dictionary = {}


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_tall_grass_layer = get_node_or_null(tall_grass_layer_path) as TileMapLayer
	_camera_bounds_layer = get_node_or_null(camera_bounds_layer_path) as TileMapLayer
	if _player == null:
		push_warning("OverworldEnvironmentEffects: no se encontró el jugador configurado.")
	if _tall_grass_layer == null:
		push_warning("OverworldEnvironmentEffects: no se encontró la capa de hierba alta.")
	if _camera_bounds_layer == null:
		_camera_bounds_layer = _tall_grass_layer
	_initialize_save_session()
	_collect_camera_zones()

	if _player != null and _camera_bounds_layer != null:
		var cell_size := _get_world_cell_size(_camera_bounds_layer)
		_camera_cell_size = cell_size
		if _player.has_method("configure_grid"):
			_player.call("configure_grid", minf(cell_size.x, cell_size.y))
		_player_camera = _player.get_node_or_null("Camera2D") as Camera2D
		if _player_camera != null:
			_camera_follow_position = _player_camera.position
		_fallback_camera_bounds = _get_layer_world_bounds(_camera_bounds_layer)
		_update_camera_zone(true)
		if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
			get_viewport().size_changed.connect(_on_viewport_size_changed)

	if pond_water_rect.has_area():
		var pond_effect := PondWaterEffect.new()
		pond_effect.name = "PondWaterEffect"
		pond_effect.position = pond_water_rect.position
		pond_effect.z_index = 8
		pond_effect.configure(pond_water_rect.size)
		add_child(pond_effect)


func _collect_camera_zones() -> void:
	_camera_zones.clear()
	var zones_root := get_node_or_null(camera_zones_root_path)
	if zones_root == null:
		return
	for child in zones_root.get_children():
		if child is OverworldCameraZone:
			_camera_zones.append(child)


func _update_camera_zone(immediate: bool = false) -> void:
	if not is_instance_valid(_player_camera) or not is_instance_valid(_player):
		return

	var next_zone := _find_camera_zone(_player.global_position)
	if not immediate and next_zone == _active_camera_zone:
		return
	var previous_zone := _active_camera_zone
	_active_camera_zone = next_zone

	var camera_bounds := _fallback_camera_bounds
	var transition_duration := 0.0
	if _active_camera_zone != null:
		camera_bounds = _active_camera_zone.get_world_camera_bounds(_camera_cell_size)
		transition_duration = _active_camera_zone.transition_duration
	_apply_camera_bounds(camera_bounds, 0.0 if immediate else transition_duration)
	if _active_camera_zone != previous_zone:
		active_camera_zone_changed.emit(
			get_active_camera_zone_id(),
			get_active_camera_zone_display_name()
		)


func _find_camera_zone(world_point: Vector2) -> OverworldCameraZone:
	var selected_zone: OverworldCameraZone
	for zone in _camera_zones:
		if not zone.contains_world_point(world_point):
			continue
		if selected_zone == null or zone.priority > selected_zone.priority:
			selected_zone = zone
	return selected_zone


func _apply_camera_bounds(world_bounds: Rect2, transition_duration: float) -> void:
	if not world_bounds.has_area():
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	# Usa la dimensión más restrictiva: es el máximo alejamiento posible que
	# todavía mantiene los cuatro bordes de la vista dentro del entorno.
	var zoom_factor := maxf(
		viewport_size.x / world_bounds.size.x,
		viewport_size.y / world_bounds.size.y
	) * camera_zoom_multiplier
	var target_zoom := Vector2.ONE * zoom_factor
	_player_camera.position_smoothing_enabled = false
	_player_camera.limit_smoothed = false

	if is_instance_valid(_camera_transition_tween):
		_camera_transition_tween.kill()
	if transition_duration <= 0.0 or not _current_camera_bounds.has_area():
		_player_camera.position = _camera_follow_position
		_set_camera_limits(world_bounds)
		_player_camera.zoom = target_zoom
	else:
		var start_center := _player_camera.get_screen_center_position()
		var start_zoom := _player_camera.zoom
		var transition_limits := _applied_camera_limits.merge(world_bounds)
		_apply_camera_limits(transition_limits)
		_set_camera_world_position(start_center)
		_current_camera_bounds = world_bounds

		_camera_transition_tween = create_tween()
		# Progreso uniforme: evita el arranque casi detenido y la aceleración
		# brusca que producía la curva quintíca entre regiones. El centro visible
		# también se interpola para que los límites no retengan la cámara y la
		# suelten de golpe cerca del final.
		_camera_transition_tween.set_trans(Tween.TRANS_LINEAR)
		_camera_transition_tween.tween_method(
			_update_camera_transition.bind(
				start_center,
				world_bounds,
				start_zoom,
				target_zoom
			),
			0.0,
			1.0,
			transition_duration
		)
		_camera_transition_tween.finished.connect(
			_finish_camera_transition.bind(world_bounds, target_zoom)
		)


func _update_camera_transition(
	progress: float,
	start_center: Vector2,
	target_bounds: Rect2,
	start_zoom: Vector2,
	target_zoom: Vector2
) -> void:
	var current_zoom := start_zoom.lerp(target_zoom, progress)
	_player_camera.zoom = current_zoom
	var target_center := _get_camera_center_for_bounds(target_bounds, target_zoom)
	_set_camera_world_position(start_center.lerp(target_center, progress))


func _finish_camera_transition(target_bounds: Rect2, target_zoom: Vector2) -> void:
	_camera_transition_tween = null
	_player_camera.position = _camera_follow_position
	_player_camera.zoom = target_zoom
	_set_camera_limits(target_bounds)


func _get_camera_center_for_bounds(world_bounds: Rect2, zoom: Vector2) -> Vector2:
	var viewport_world_size := get_viewport_rect().size / zoom
	var half_viewport := viewport_world_size * 0.5
	var minimum_center := world_bounds.position + half_viewport
	var maximum_center := world_bounds.end - half_viewport
	var follow_center := _get_camera_follow_world_position()
	var camera_center := follow_center
	if minimum_center.x <= maximum_center.x:
		camera_center.x = clampf(follow_center.x, minimum_center.x, maximum_center.x)
	else:
		camera_center.x = world_bounds.get_center().x
	if minimum_center.y <= maximum_center.y:
		camera_center.y = clampf(follow_center.y, minimum_center.y, maximum_center.y)
	else:
		camera_center.y = world_bounds.get_center().y
	return camera_center


func _get_camera_follow_world_position() -> Vector2:
	var camera_parent := _player_camera.get_parent() as Node2D
	if camera_parent == null:
		return _player.global_position
	return camera_parent.to_global(_camera_follow_position)


func _set_camera_world_position(world_position: Vector2) -> void:
	var camera_parent := _player_camera.get_parent() as Node2D
	if camera_parent == null:
		_player_camera.global_position = world_position
		return
	_player_camera.position = camera_parent.to_local(world_position)


func _set_camera_limits(world_bounds: Rect2) -> void:
	_current_camera_bounds = world_bounds
	_apply_camera_limits(world_bounds)


func _apply_camera_limits(world_bounds: Rect2) -> void:
	_applied_camera_limits = world_bounds
	_player_camera.limit_left = floori(world_bounds.position.x)
	_player_camera.limit_top = floori(world_bounds.position.y)
	_player_camera.limit_right = ceili(world_bounds.end.x)
	_player_camera.limit_bottom = ceili(world_bounds.end.y)


func _on_viewport_size_changed() -> void:
	_update_camera_zone(true)


func get_active_camera_zone_id() -> StringName:
	return _active_camera_zone.zone_id if _active_camera_zone != null else &""


func get_active_camera_zone_display_name() -> String:
	return _active_camera_zone.display_name if _active_camera_zone != null else ""


func get_player() -> Node2D:
	return _player


func get_interactable_in_front() -> Node2D:
	if not is_instance_valid(_player):
		return null
	var facing := Vector2.DOWN
	var facing_value: Variant = _player.get("last_cardinal_direction")
	if facing_value is Vector2 and not (facing_value as Vector2).is_zero_approx():
		facing = (facing_value as Vector2).normalized()
	var cell_size := maxf(_player.get("grid_cell_size"), 1.0)
	var maximum_forward := cell_size * interaction_distance_cells
	var maximum_side := cell_size * 0.72
	var nearest: Node2D
	var nearest_forward := INF
	for candidate_value: Variant in get_tree().get_nodes_in_group(
		&"dialogue_interactable"
	):
		var candidate := candidate_value as Node2D
		if candidate == null or not is_ancestor_of(candidate) or not candidate.is_visible_in_tree():
			continue
		if candidate.has_method("can_interact_from") and not bool(
			candidate.call("can_interact_from", _player)
		):
			continue
		var offset := candidate.global_position - _player.global_position
		var forward_distance := offset.dot(facing)
		if forward_distance <= 0.0 or forward_distance > maximum_forward:
			continue
		var side_distance := absf(offset.cross(facing))
		if side_distance > maximum_side:
			continue
		if forward_distance < nearest_forward:
			nearest_forward = forward_distance
			nearest = candidate
	return nearest


func save_current_game() -> Dictionary:
	if not is_instance_valid(_player):
		return {}
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("save_progress"):
		return {}
	var position_data := {
		"x": _player.global_position.x,
		"y": _player.global_position.y,
	}
	var saved: Variant = save_manager.call("save_progress", {
		"current_map": str(map_id),
		"player_position": position_data,
		"spawn_point": "",
	})
	return saved if saved is Dictionary else {}


func get_active_camera_bounds() -> Rect2:
	if _active_camera_zone != null:
		return _active_camera_zone.get_world_camera_bounds(_camera_cell_size)
	return _fallback_camera_bounds


func _get_world_cell_size(layer: TileMapLayer) -> Vector2:
	if layer.tile_set == null:
		return Vector2.ONE
	var tile_size := Vector2(layer.tile_set.tile_size)
	var origin := layer.to_global(Vector2.ZERO)
	return Vector2(
		origin.distance_to(layer.to_global(Vector2(tile_size.x, 0.0))),
		origin.distance_to(layer.to_global(Vector2(0.0, tile_size.y)))
	)


func _get_layer_world_bounds(layer: TileMapLayer) -> Rect2:
	var used_rect := layer.get_used_rect()
	var tile_size := Vector2(layer.tile_set.tile_size)
	var local_start := Vector2(used_rect.position) * tile_size
	var local_end := Vector2(used_rect.end) * tile_size
	var world_corners := PackedVector2Array([
		layer.to_global(local_start),
		layer.to_global(Vector2(local_end.x, local_start.y)),
		layer.to_global(local_end),
		layer.to_global(Vector2(local_start.x, local_end.y)),
	])
	var minimum := world_corners[0]
	var maximum := world_corners[0]
	for corner in world_corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _initialize_save_session() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null:
		return
	var save_data := _get_scene_save_data()
	if save_data.is_empty():
		return
	if save_manager.has_method("start_play_session"):
		save_manager.call("start_play_session", save_data)
	_restore_saved_player_position(save_data)


func _get_scene_save_data() -> Dictionary:
	var payload: Variant = get_meta(&"scene_payload", {})
	if payload is not Dictionary:
		return {}
	var payload_dictionary := payload as Dictionary
	var data: Variant = payload_dictionary.get("data", {})
	if data is not Dictionary:
		return {}
	var save_data: Variant = (data as Dictionary).get("save_data", {})
	return save_data.duplicate(true) if save_data is Dictionary else {}


func _restore_saved_player_position(save_data: Dictionary) -> void:
	if not is_instance_valid(_player):
		return
	var progress: Dictionary = save_data.get("progress", {})
	var saved_map_id := StringName(str(progress.get("current_map", "")))
	if not map_id.is_empty() and saved_map_id != map_id:
		return
	var position_data: Variant = progress.get("player_position", {})
	if position_data is not Dictionary:
		return
	var position_dictionary := position_data as Dictionary
	if not position_dictionary.has("x") or not position_dictionary.has("y"):
		return
	_player.global_position = Vector2(
		float(position_dictionary.x),
		float(position_dictionary.y)
	)


func _physics_process(_delta: float) -> void:
	_update_camera_zone()


func _process(_delta: float) -> void:
	# Se actualiza después del movimiento de física, antes de dibujar el frame.
	# Así el recorte cambia de celda en el mismo frame que los pies del actor.
	_update_tall_grass_actors()


func _update_tall_grass_actors() -> void:
	if not is_instance_valid(_tall_grass_layer):
		return
	var active_actor_ids: Dictionary = {}
	for candidate in get_tree().get_nodes_in_group(&"grid_movement_actor"):
		var actor := candidate as Node2D
		if actor == null or not is_ancestor_of(actor):
			continue
		var actor_id := actor.get_instance_id()
		var state: Dictionary = _grass_actor_states.get(actor_id, {})
		var foreground_value: Variant = state.get("foreground")
		var foreground: Sprite2D
		if is_instance_valid(foreground_value):
			foreground = foreground_value as Sprite2D
		if not is_instance_valid(foreground):
			foreground = _create_grass_foreground(actor)
			if foreground == null:
				continue
			state = {"foreground": foreground, "last_cell": INVALID_GRASS_CELL}
		active_actor_ids[actor_id] = true
		_update_actor_grass(actor, foreground, state)
		_grass_actor_states[actor_id] = state

	# Los recortes son hijos del sprite: desaparecen al eliminar al actor.
	# Si sale de este mapa sin destruirse, también se retira su recorte.
	for actor_id in _grass_actor_states.keys():
		if active_actor_ids.has(actor_id):
			continue
		var foreground_value: Variant = _grass_actor_states[actor_id].get("foreground")
		if is_instance_valid(foreground_value):
			(foreground_value as Sprite2D).queue_free()
		_grass_actor_states.erase(actor_id)


func _create_grass_foreground(actor: Node2D) -> Sprite2D:
	var visual := actor.get_node_or_null("AnimatedSprite2D") as Node2D
	if visual == null:
		for child in actor.find_children("*", "", true, false):
			if child is AnimatedSprite2D or child is Sprite2D:
				visual = child as Node2D
				break
	if visual == null:
		return null

	var foreground := Sprite2D.new()
	foreground.name = "TallGrassFootOverlay"
	foreground.texture = TallGrassCut
	foreground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	foreground.visible = false
	# Un hijo se dibuja delante de su padre con el mismo Z. Conserva el orden
	# del actor frente al entorno, sin elevar la hierba por encima de los árboles.
	visual.add_child(foreground)
	return foreground


func _update_actor_grass(actor: Node2D, foreground: Sprite2D, state: Dictionary) -> void:
	var visual := foreground.get_parent() as Node2D
	if not visual.is_visible_in_tree() or not _tall_grass_layer.is_visible_in_tree():
		foreground.hide()
		state["last_cell"] = INVALID_GRASS_CELL
		return

	# El origen de grid_movement_actor es el apoyo de los pies, con independencia
	# del tamaño, la animación o la escala interna de su imagen.
	var foot_position := actor.global_position + Vector2(0.0, grass_foot_offset_y)
	var local_foot_position := _tall_grass_layer.to_local(foot_position)
	var current_cell := _tall_grass_layer.local_to_map(local_foot_position)
	if not _is_tall_grass_cell(current_cell):
		foreground.hide()
		state["last_cell"] = INVALID_GRASS_CELL
		return

	# El recorte toma el tamaño y la transformación de la celda real. Su posición
	# queda fija en esa celda hasta cambiar a la siguiente, sin deslizarse sobre
	# la textura inferior ni heredar el escalado particular de Cynthia o un NPC.
	var tile_scale := Vector2(_tall_grass_layer.tile_set.tile_size) / TallGrassCut.get_size()
	foreground.global_transform = _tall_grass_layer.global_transform * Transform2D(
		Vector2(tile_scale.x, 0.0),
		Vector2(0.0, tile_scale.y),
		_tall_grass_layer.map_to_local(current_cell)
	)
	foreground.show()
	if current_cell != state["last_cell"]:
		_spawn_grass_effect(current_cell)
	state["last_cell"] = current_cell


func _is_tall_grass_cell(cell: Vector2i) -> bool:
	var tile_data := _tall_grass_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return bool(tile_data.get_custom_data(TALL_GRASS_CUSTOM_DATA))


func _spawn_grass_effect(cell: Vector2i) -> void:
	var effect := GrassStepEffect.new()
	effect.name = "GrassStepEffect_%d" % effect.get_instance_id()
	var tile_width := float(_tall_grass_layer.tile_set.tile_size.x)
	effect.configure(tile_width)
	# Al ser hijo de la propia capa de hierba hereda su escala y profundidad.
	# De esta forma los árboles, casas y demás capas superiores lo ocultan.
	_tall_grass_layer.add_child(effect)
	effect.add_to_group(&"grass_step_effect")
	effect.position = _tall_grass_layer.map_to_local(cell)
