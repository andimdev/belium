class_name MovementGridGuide
extends TileMapLayer

## Guía visual de la cuadrícula real de movimiento.
##
## Cada tile blanco representa una celda de 20 x 20 px a la que puede llegar
## la huella de los pies del jugador. La capa no inventa otra navegación:
## consulta las mismas colisiones físicas que usan CharacterBody2D.test_move.

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]
const GRID_SOURCE_ID := 0
const GRID_ATLAS_COORDS := Vector2i.ZERO

@export_category("Referencias del mapa")
@export_node_path("CharacterBody2D") var player_path: NodePath
@export_node_path("TileMapLayer") var bounds_layer_path: NodePath

@export_category("Guía visual")
@export var show_grid := false
@export_range(0.05, 1.0, 0.05) var line_opacity := 0.55
@export_range(1, 4, 1) var line_width_pixels := 1

var grid_cell_size := 20.0
# El origen lógico es el centro horizontal del primer cuadro, pero su borde
# inferior en vertical. Es el punto del suelo donde se apoyan los pies.
var grid_origin := Vector2(10.0, 20.0)

var _player: CharacterBody2D
var _player_collision: CollisionShape2D
var _bounds_layer: TileMapLayer
var _bounds_cells := Rect2i()
var _excluded_rids: Array[RID] = []
var _standable_cache: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	visible = show_grid
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	call_deferred(&"_initialize_grid")


func _initialize_grid() -> void:
	_player = _resolve_player()
	_bounds_layer = _resolve_bounds_layer()
	if _player == null:
		push_warning("MovementGridGuide: no se encontró el jugador configurado.")
		return
	if _bounds_layer == null or _bounds_layer.tile_set == null:
		push_warning("MovementGridGuide: no se encontró la capa límite del mapa.")
		return

	var world_cell_size := _get_world_cell_size(_bounds_layer)
	grid_cell_size = minf(world_cell_size.x, world_cell_size.y)
	var first_cell_center := _bounds_layer.to_global(
		_bounds_layer.map_to_local(Vector2i.ZERO)
	)
	var local_tile_size := Vector2(_bounds_layer.tile_set.tile_size)
	var half_cell_down := (
		_bounds_layer.to_global(Vector2(0.0, local_tile_size.y * 0.5))
		- _bounds_layer.to_global(Vector2.ZERO)
	)
	grid_origin = first_cell_center + half_cell_down
	_bounds_cells = _bounds_layer.get_used_rect()
	# La textura de la guía conserva su esquina en el origen del TileMap. El
	# actor, en cambio, se apoya en el centro del borde inferior de cada tile.
	global_position = _bounds_layer.to_global(Vector2.ZERO)

	_create_grid_tileset(roundi(grid_cell_size))
	_configure_grid_actors()

	_player_collision = _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _player_collision == null or _player_collision.shape == null:
		push_warning("MovementGridGuide: el jugador no tiene una colisión utilizable.")
		return

	_collect_excluded_actor_rids()
	# Las formas físicas de TileMapLayer y StaticBody2D quedan listas en el
	# siguiente frame de física. A partir de allí se calcula el área alcanzable.
	await get_tree().physics_frame
	_build_reachable_grid()


func _resolve_player() -> CharacterBody2D:
	var configured_player := get_node_or_null(player_path) as CharacterBody2D
	if configured_player != null:
		return configured_player
	# Respaldo para escenas que fueron guardadas con el NodePath vacío.
	for candidate in get_tree().get_nodes_in_group(&"grid_movement_actor"):
		var actor := candidate as CharacterBody2D
		if (
			actor != null
			and get_parent().is_ancestor_of(actor)
			and actor is OverworldPlayer
		):
			return actor
	return null


func _resolve_bounds_layer() -> TileMapLayer:
	var configured_layer := get_node_or_null(bounds_layer_path) as TileMapLayer
	if configured_layer != null:
		return configured_layer
	# El mapa ya declara cuál TileMapLayer contiene sus límites de cámara. Se
	# reutiliza esa referencia para que la guía no dependa de un path duplicado.
	var map_root := get_parent()
	var map_bounds_path: Variant = map_root.get("camera_bounds_layer_path")
	if map_bounds_path is NodePath and not (map_bounds_path as NodePath).is_empty():
		return map_root.get_node_or_null(map_bounds_path as NodePath) as TileMapLayer
	return null


func _create_grid_tileset(cell_size_pixels: int) -> void:
	var safe_cell_size := maxi(cell_size_pixels, 1)
	var safe_line_width := mini(line_width_pixels, safe_cell_size)
	var image := Image.create(
		safe_cell_size,
		safe_cell_size,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	var line_color := Color(1.0, 1.0, 1.0, line_opacity)

	# Sólo se dibujan los bordes superior e izquierdo. Las celdas adyacentes
	# completan la rejilla sin duplicar líneas y volverlas de dos píxeles.
	for offset in range(safe_line_width):
		for coordinate in range(safe_cell_size):
			image.set_pixel(coordinate, offset, line_color)
			image.set_pixel(offset, coordinate, line_color)

	var atlas_texture := ImageTexture.create_from_image(image)
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = atlas_texture
	atlas_source.texture_region_size = Vector2i.ONE * safe_cell_size
	atlas_source.create_tile(GRID_ATLAS_COORDS)

	var movement_tileset := TileSet.new()
	movement_tileset.tile_size = Vector2i.ONE * safe_cell_size
	movement_tileset.add_source(atlas_source, GRID_SOURCE_ID)
	tile_set = movement_tileset


func _configure_grid_actors() -> void:
	for candidate in get_tree().get_nodes_in_group(&"grid_movement_actor"):
		var actor := candidate as Node2D
		if actor == null or not get_parent().is_ancestor_of(actor):
			continue
		# Sólo se comparte la definición de la rejilla. No se modifica aquí la
		# posición del actor: si fue colocado fuera de ella, su primer movimiento
		# recorrerá suavemente los segmentos necesarios para corregirse.
		if actor.has_method("configure_movement_grid"):
			actor.call("configure_movement_grid", grid_cell_size, grid_origin)


func _collect_excluded_actor_rids() -> void:
	_excluded_rids.clear()
	for candidate in get_tree().get_nodes_in_group(&"grid_movement_actor"):
		var actor := candidate as CollisionObject2D
		if actor == null or not get_parent().is_ancestor_of(actor):
			continue
		_excluded_rids.append(actor.get_rid())


func _build_reachable_grid() -> void:
	clear()
	_standable_cache.clear()
	if not show_grid or _bounds_cells.size.x <= 0 or _bounds_cells.size.y <= 0:
		return

	var start_cell := _world_to_grid_cell(_player.global_position)
	start_cell = _find_nearest_standable_cell(start_cell)
	if not _bounds_cells.has_point(start_cell):
		push_warning("MovementGridGuide: no se encontró una celda inicial caminable.")
		return

	var frontier: Array[Vector2i] = [start_cell]
	var reachable: Dictionary[Vector2i, bool] = {start_cell: true}
	var read_index := 0

	while read_index < frontier.size():
		var current_cell := frontier[read_index]
		read_index += 1
		set_cell(
			current_cell,
			GRID_SOURCE_ID,
			GRID_ATLAS_COORDS,
			0
		)

		for direction in CARDINAL_DIRECTIONS:
			var next_cell := current_cell + direction
			if reachable.has(next_cell) or not _bounds_cells.has_point(next_cell):
				continue
			if not _can_stand_on_cell(next_cell):
				continue
			if not _can_travel_between_cells(current_cell, next_cell):
				continue
			reachable[next_cell] = true
			frontier.append(next_cell)


func _find_nearest_standable_cell(desired_cell: Vector2i) -> Vector2i:
	if _bounds_cells.has_point(desired_cell) and _can_stand_on_cell(desired_cell):
		return desired_cell
	for radius in range(1, 7):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if absi(x) != radius and absi(y) != radius:
					continue
				var candidate := desired_cell + Vector2i(x, y)
				if _bounds_cells.has_point(candidate) and _can_stand_on_cell(candidate):
					return candidate
	return Vector2i(2147483647, 2147483647)


func _can_stand_on_cell(cell: Vector2i) -> bool:
	if _standable_cache.has(cell):
		return _standable_cache[cell]
	var query := _make_shape_query(_grid_cell_to_world(cell))
	var hits := get_world_2d().direct_space_state.intersect_shape(query, 1)
	var is_standable := hits.is_empty()
	_standable_cache[cell] = is_standable
	return is_standable


func _can_travel_between_cells(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var from_world := _grid_cell_to_world(from_cell)
	var to_world := _grid_cell_to_world(to_cell)
	var query := _make_shape_query(from_world)
	query.motion = to_world - from_world
	var travel_result := get_world_2d().direct_space_state.cast_motion(query)
	return travel_result.size() >= 1 and travel_result[0] >= 0.999


func _make_shape_query(body_world_position: Vector2) -> PhysicsShapeQueryParameters2D:
	var shape_transform := _player_collision.global_transform
	shape_transform.origin += body_world_position - _player.global_position
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _player_collision.shape
	query.transform = shape_transform
	query.collision_mask = _player.collision_mask
	query.exclude = _excluded_rids
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.01
	return query


func _get_world_cell_size(layer: TileMapLayer) -> Vector2:
	var local_tile_size := Vector2(layer.tile_set.tile_size)
	var world_origin := layer.to_global(Vector2.ZERO)
	return Vector2(
		world_origin.distance_to(layer.to_global(Vector2(local_tile_size.x, 0.0))),
		world_origin.distance_to(layer.to_global(Vector2(0.0, local_tile_size.y)))
	)


func _world_to_grid_cell(world_position: Vector2) -> Vector2i:
	var relative_position := (world_position - grid_origin) / grid_cell_size
	return Vector2i(
		roundi(relative_position.x),
		roundi(relative_position.y)
	)


func _grid_cell_to_world(cell: Vector2i) -> Vector2:
	return grid_origin + Vector2(cell) * grid_cell_size
