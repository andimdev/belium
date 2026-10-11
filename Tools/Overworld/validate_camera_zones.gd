extends SceneTree

const MAP_PATH := "res://Maps/map_001_leaftown_201_sandtown_202.tscn"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	# Deliberately leave the scene outside the tree: no save-session, music,
	# weather or player callbacks should run during this geometry validation.
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		push_error("No se pudo cargar el mapa.")
		quit(1)
		return
	var map := packed.instantiate() as Node2D
	var arena := map.get_node("CameraZones/SandTown") as OverworldCameraZone
	var route := map.get_node("CameraZones/Route201") as OverworldCameraZone
	var floor_layer := map.get_node("Mapa/Piso/piso_abajo") as TileMapLayer
	map.call("_collect_camera_zones")
	_check(map.call("_find_camera_zone", Vector2(1510, -400)) == route, "Antes del acceso debe seguir siendo Ruta 201.")
	_check(map.call("_find_camera_zone", Vector2(1520, -400)) == arena, "El acceso exacto debe seleccionar Pueblo Arena sin huecos.")
	_check(map.call("_find_camera_zone", Vector2(2070, -414)) == arena, "El centro del pueblo debe seleccionar Pueblo Arena.")
	_check(not arena.contains_world_point(Vector2(2070, -47)), "Se debe conservar el extremo sur de la región dibujada.")
	_check(arena.collision_layer == 0 and arena.collision_mask == 0, "El área de cámara no debe participar en colisiones.")
	_check(arena.transition_duration == 2, "La transición configurada debe durar dos segundos.")
	_check(route.hidden_boundary_rows.z == 0, "La salida de Ruta 201 no debe ocultarse como si fuera un borde exterior.")
	var bounds := arena.get_world_camera_bounds(Vector2(20, 20))
	_check(bounds.is_equal_approx(Rect2(1420, -680, 1100, 860)), "Los límites finales de Arena deben descontar cinco filas de 20px.")
	for zone: OverworldCameraZone in [arena, route]:
		_validate_bounds(zone, floor_layer, float(map.get("camera_zoom_multiplier")))

	var external_tilesets := {}
	for layer: TileMapLayer in map.find_children("*", "TileMapLayer", true, false):
		if layer.tile_set != null and layer.tile_set.resource_path.ends_with(".res"):
			external_tilesets[layer.tile_set.resource_path] = true
	_check(external_tilesets.size() == 8, "Deben estar disponibles los ocho TileSets binarios extraídos.")
	_check(FileAccess.get_file_as_bytes(MAP_PATH).size() < 500 * 1024, "La escena debe quedar por debajo del umbral de 500 KiB.")
	map.free()
	if _failures.is_empty():
		print("PASS: regiones Ruta 201/Arena, límites con terreno, proporciones de pantalla y ocho TileSets externos.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _validate_bounds(zone: OverworldCameraZone, floor_layer: TileMapLayer, zoom_multiplier: float) -> void:
	var bounds := zone.get_world_camera_bounds(Vector2(20, 20))
	_check(bounds.has_area(), "%s necesita límites con área positiva." % zone.zone_id)
	for y in range(int(bounds.position.y), int(bounds.end.y), 20):
		for x in range(int(bounds.position.x), int(bounds.end.x), 20):
			var cell := floor_layer.local_to_map(floor_layer.to_local(Vector2(x + 10, y + 10)))
			if floor_layer.get_cell_source_id(cell) == -1:
				_check(false, "%s incluye terreno vacío en %s." % [zone.zone_id, cell])
				return
	for viewport_size: Vector2 in [Vector2(1080, 720), Vector2(1280, 720), Vector2(720, 1080)]:
		var zoom := maxf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y) * zoom_multiplier
		var visible_size := viewport_size / zoom
		_check(visible_size.x <= bounds.size.x and visible_size.y <= bounds.size.y, "El encuadre debe caber en los límites sin mostrar el exterior.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
