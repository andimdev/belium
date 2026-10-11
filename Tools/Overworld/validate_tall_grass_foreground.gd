extends SceneTree

const MAP_SCENE := preload("res://Maps/map_001_leaftown_201_sandtown_202.tscn")
const NPC_SCENE := preload("res://Scenes/NPC/npc_old_man.tscn")

var _map: Node2D
var _grass: TileMapLayer
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_validation")


func _run_validation() -> void:
	_map = MAP_SCENE.instantiate() as Node2D
	root.add_child(_map)
	_grass = _map.get_node(_map.get("tall_grass_layer_path")) as TileMapLayer
	var player := _map.get_node("Mapa/Casas/CynthiaPlayer") as Node2D
	var npc := _map.get_node("Mapa/Casas/NPCs/OldMan") as Node2D
	player.set_physics_process(false)
	npc.set_physics_process(false)
	await physics_frame
	await process_frame
	await process_frame

	var grass_cells: Array[Vector2i] = []
	var clear_cell := Vector2i.ZERO
	for cell in _grass.get_used_cells():
		if bool(_map.call("_is_tall_grass_cell", cell)):
			grass_cells.append(cell)
		else:
			clear_cell = cell
	_check(grass_cells.size() >= 2, "El mapa debe contener al menos dos celdas de hierba alta.")
	if grass_cells.size() < 2:
		_finish()
		return
	var first_cell := grass_cells[0]
	var second_cell := grass_cells[1]
	for cell in grass_cells:
		if bool(_map.call("_is_tall_grass_cell", cell + Vector2i.RIGHT)):
			first_cell = cell
			second_cell = cell + Vector2i.RIGHT
			break

	player.global_position = _feet_for_cell(clear_cell)
	npc.global_position = _feet_for_cell(clear_cell)
	await _render_update()
	_check(not _overlay(player).visible, "Cynthia muestra el recorte fuera de la hierba.")

	player.global_position = _feet_for_cell(first_cell)
	npc.global_position = _feet_for_cell(second_cell)
	await _render_update()
	_validate_actor(player, first_cell)
	_validate_actor(npc, second_cell)
	var original_overlay_id := _overlay(player).get_instance_id()
	var effects_before := get_nodes_in_group(&"grass_step_effect").size()
	_check(effects_before >= 2, "La entrada de ambos actores debe activar la animación de pisada.")
	await _render_update()
	_check(
		get_nodes_in_group(&"grass_step_effect").size() <= effects_before,
		"Estar quieto no debe crear otra animación de pisada."
	)

	# Un desplazamiento parcial conserva el tile alineado con la capa inferior.
	player.global_position += Vector2.RIGHT * 3.0
	await _render_update()
	_validate_actor(player, first_cell)
	player.global_position = _feet_for_cell(second_cell)
	await _render_update()
	_validate_actor(player, second_cell)
	_check(
		_overlay(player).get_instance_id() == original_overlay_id,
		"Cada actor debe reutilizar el mismo sprite al cambiar de celda."
	)
	_check(
		get_nodes_in_group(&"grass_step_effect").size() > effects_before,
		"Cambiar de celda debe mantener la animación de caminar por la hierba."
	)
	for effect in get_nodes_in_group(&"grass_step_effect"):
		_check(effect.get_parent() == _grass, "La animación de pisada debe conservar la capa de hierba.")

	player.hide()
	await _render_update()
	_check(not _overlay(player).visible, "Un personaje oculto no debe dejar hierba flotante.")
	player.show()
	player.global_position = _feet_for_cell(clear_cell)
	await _render_update()
	_check(not _overlay(player).visible, "El recorte debe ocultarse al salir de la hierba.")
	# Comprueba los cuatro bordes justo antes y después de que los pies crucen.
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var edge := _grass.map_to_local(first_cell) + Vector2(direction) * Vector2(_grass.tile_set.tile_size) * 0.5
		var probe_offset := Vector2(0.0, float(_map.get("grass_foot_offset_y")))
		player.global_position = _grass.to_global(edge - Vector2(direction) * 0.05) - probe_offset
		await _render_update()
		_validate_actor(player, first_cell)
		player.global_position = _grass.to_global(edge + Vector2(direction) * 0.05) - probe_offset
		await _render_update()
		if bool(_map.call("_is_tall_grass_cell", first_cell + direction)):
			_validate_actor(player, first_cell + direction)
		else:
			_check(not _overlay(player).visible, "Al cruzar el borde hacia suelo normal, debe ocultarse.")

	# Un futuro Pokémon puede usar un Sprite2D anidado y el mismo grupo común.
	var creature := Node2D.new()
	creature.name = "TestCreature"
	creature.add_to_group(&"grid_movement_actor")
	var creature_visual := Sprite2D.new()
	creature_visual.name = "PokemonVisual"
	creature.add_child(creature_visual)
	_map.add_child(creature)
	creature.global_position = _feet_for_cell(first_cell)
	await _render_update()
	var creature_overlay := creature_visual.get_node_or_null("TallGrassFootOverlay") as Sprite2D
	_check(creature_overlay != null and creature_overlay.visible, "Un NPC genérico debe mostrar el recorte.")
	creature.queue_free()
	await _render_update()

	# Un NPC creado durante el juego también se registra, aunque su escala sea otra.
	var visitor := NPC_SCENE.instantiate() as Node2D
	visitor.scale = Vector2(0.35, 0.9)
	_map.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.global_position = _feet_for_cell(first_cell)
	await _render_update()
	_validate_actor(visitor, first_cell)
	visitor.queue_free()
	await _render_update()
	await _render_update()
	_check(
		(_map.get("_grass_actor_states") as Dictionary).size() == 2,
		"Eliminar un NPC debe limpiar su recorte y su registro."
	)
	_finish()


func _render_update() -> void:
	await process_frame
	await process_frame


func _feet_for_cell(cell: Vector2i) -> Vector2:
	return _grass.to_global(
		_grass.map_to_local(cell) + Vector2(0.0, _grass.tile_set.tile_size.y * 0.5)
	)


func _overlay(actor: Node2D) -> Sprite2D:
	return actor.get_node("AnimatedSprite2D/TallGrassFootOverlay") as Sprite2D


func _validate_actor(actor: Node2D, cell: Vector2i) -> void:
	var foreground := _overlay(actor)
	_check(foreground.visible, "%s debe mostrar hierba en sus pies." % actor.name)
	_check(
		foreground.global_position.is_equal_approx(_grass.to_global(_grass.map_to_local(cell))),
		"%s tiene el recorte desalineado con el tile." % actor.name
	)
	var rendered_size := Vector2(
		foreground.global_transform.x.length(), foreground.global_transform.y.length()
	) * foreground.texture.get_size()
	_check(rendered_size.is_equal_approx(Vector2(20.0, 20.0)), "El recorte debe medir 20x20 px reales.")
	_check(
		foreground.z_index == 0 and foreground.z_as_relative and not foreground.show_behind_parent,
		"El recorte debe ir delante del sprite, conservando su orden respecto al entorno."
	)
	_check(
		actor.find_children("TallGrassFootOverlay", "Sprite2D", true, false).size() == 1,
		"Cada actor debe tener exactamente un recorte."
	)
	var bottom_center := foreground.to_global(Vector2(0.0, foreground.texture.get_height() * 0.5))
	_check(bottom_center.is_equal_approx(_feet_for_cell(cell)), "La base del recorte debe tocar el suelo de la celda.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("TallGrassForegroundValidation: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("TALL_GRASS_FOREGROUND_VALIDATED player=true npc=true dynamic_npc=true creature=true four_edges=true tile_size=20 step_effect=true")
	_map.queue_free()
	quit(0 if _failures.is_empty() else 1)
