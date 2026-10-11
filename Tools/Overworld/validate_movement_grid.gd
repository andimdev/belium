extends SceneTree

const MAP_SCENE := preload(
	"res://Maps/map_001_leaftown_201_sandtown_202.tscn"
)


func _init() -> void:
	call_deferred(&"_run_validation")


func _run_validation() -> void:
	var map := MAP_SCENE.instantiate() as Node2D
	root.add_child(map)
	var player := map.get_node_or_null("Mapa/Casas/CynthiaPlayer") as Node2D
	var npc := map.get_node_or_null("Mapa/Casas/NPCs/OldMan") as Node2D
	if player == null or npc == null:
		_fail(map, "No se encontraron Cynthia y Harry en la escena del mapa.")
		return
	var initial_player_position := player.global_position
	var initial_npc_position := npc.global_position

	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

	var guide := map.get_node_or_null("MovementGridGuide") as TileMapLayer
	if guide == null:
		_fail(map, "Falta MovementGridGuide en la escena del mapa.")
		return

	var cell_size := float(guide.get("grid_cell_size"))
	var origin := guide.get("grid_origin") as Vector2
	if not is_equal_approx(cell_size, 20.0):
		_fail(map, "La celda no mide 20 px en coordenadas del mundo.")
		return
	if not player.global_position.is_equal_approx(initial_player_position):
		_fail(map, "Cynthia fue teletransportada al inicializar la rejilla.")
		return
	if not npc.global_position.is_equal_approx(initial_npc_position):
		_fail(map, "Harry fue teletransportado al inicializar la rejilla.")
		return

	var player_started := false
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		player.call("_try_start_grid_step", direction, false)
		if bool(player.call("is_grid_stepping")):
			player_started = true
			break
	if not player_started:
		_fail(map, "Cynthia no encontró una trayectoria inicial para alinearse.")
		return

	var npc_started := false
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]:
		if bool(npc.call("try_start_grid_step", direction)):
			npc_started = true
			break
	if not npc_started:
		_fail(map, "Harry no encontró una trayectoria inicial para alinearse.")
		return

	var previous_player_position := player.global_position
	var previous_npc_position := npc.global_position
	for frame_index in range(300):
		await physics_frame
		if _moved_diagonally(previous_player_position, player.global_position):
			_fail(map, "Cynthia corrigió X e Y simultáneamente.")
			return
		if _moved_diagonally(previous_npc_position, npc.global_position):
			_fail(map, "Harry corrigió X e Y simultáneamente.")
			return
		previous_player_position = player.global_position
		previous_npc_position = npc.global_position
		if (
			not bool(player.call("is_grid_stepping"))
			and not bool(npc.get("_is_stepping"))
		):
			break
		if frame_index == 299:
			_fail(map, "La corrección suave no terminó dentro del tiempo esperado.")
			return

	if not _is_aligned(player.global_position, origin, cell_size):
		_fail(map, "El primer paso no alineó a Cynthia con la rejilla.")
		return
	if not _is_aligned(npc.global_position, origin, cell_size):
		_fail(map, "El primer paso no alineó a Harry con la rejilla.")
		return
	if not _feet_touch_ground_line(player.global_position, guide.global_position, cell_size):
		_fail(map, "Los pies de Cynthia no quedaron sobre una línea del suelo.")
		return
	if not _feet_touch_ground_line(npc.global_position, guide.global_position, cell_size):
		_fail(map, "Los pies de Harry no quedaron sobre una línea del suelo.")
		return

	var player_cell := Vector2i(
		roundi((player.global_position.x - origin.x) / cell_size),
		roundi((player.global_position.y - origin.y) / cell_size)
	)
	var visible_cells := guide.get_used_cells()
	if not guide.visible or guide.tile_set == null:
		_fail(map, "MovementGridGuide no quedó listo para renderizar.")
		return
	if visible_cells.size() < 100:
		_fail(
			map,
			"La guía generó muy pocas celdas caminables: %d." % visible_cells.size()
		)
		return
	if guide.get_cell_source_id(player_cell) < 0:
		_fail(map, "La celda inicial de Cynthia no aparece en la guía.")
		return

	# Cynthia debe detectar físicamente al NPC antes de iniciar el paso. Se
	# prueba desde una celda adyacente sin modificar realmente su posición.
	if npc.has_method("set_interaction_locked"):
		npc.call("set_interaction_locked", true)
	player.global_position = npc.global_position + Vector2.DOWN * cell_size
	await physics_frame
	var npc_collision: KinematicCollision2D = player.move_and_collide(
		Vector2.UP * cell_size,
		true
	)
	if npc_collision == null or npc_collision.get_collider() != npc:
		_fail(map, "Cynthia no detectó la colisión física de Harry.")
		return

	print(
		"MOVEMENT_GRID_VALIDATED cells=%d npc_collision=true player=%s npc=%s origin=%s"
		% [visible_cells.size(), player.global_position, npc.global_position, origin]
	)
	map.queue_free()
	quit()


func _is_aligned(position: Vector2, origin: Vector2, cell_size: float) -> bool:
	var relative := (position - origin) / cell_size
	return (
		absf(relative.x - roundf(relative.x)) < 0.001
		and absf(relative.y - roundf(relative.y)) < 0.001
	)


func _moved_diagonally(previous: Vector2, current: Vector2) -> bool:
	var movement := current - previous
	return absf(movement.x) > 0.001 and absf(movement.y) > 0.001


func _feet_touch_ground_line(
	position: Vector2,
	grid_top_left: Vector2,
	cell_size: float
) -> bool:
	var horizontal_center := (position.x - grid_top_left.x - cell_size * 0.5) / cell_size
	var ground_line := (position.y - grid_top_left.y) / cell_size
	return (
		absf(horizontal_center - roundf(horizontal_center)) < 0.001
		and absf(ground_line - roundf(ground_line)) < 0.001
	)


func _fail(map: Node2D, reason: String) -> void:
	map.queue_free()
	push_error("MovementGridValidation: %s" % reason)
	quit(1)
