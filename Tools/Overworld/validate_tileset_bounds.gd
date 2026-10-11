extends SceneTree

const MAP_PATH := "res://Maps/map_001_leaftown_201_sandtown_202.tscn"
const UTILS_PATH := "res://Resources/Tileset/utils_2_.png"


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	# Keep the map outside the tree to avoid gameplay and save-session callbacks.
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		quit(1)
		return
	var map := packed.instantiate()
	var checked_sources := {}
	var failures: Array[String] = []
	var cells_checked := 0
	var utils_cells := 0
	var utils_sources := 0
	var utils_image := Image.new()
	if utils_image.load_png_from_buffer(FileAccess.get_file_as_bytes(UTILS_PATH)) != OK:
		map.free()
		push_error("No se pudo leer el PNG original de utils_2_.")
		quit(1)
		return
	var actual_utils_size := utils_image.get_size()
	for layer: TileMapLayer in map.find_children("*", "TileMapLayer", true, false):
		if layer.tile_set == null:
			continue
		for source_index in range(layer.tile_set.get_source_count()):
			var source_id := layer.tile_set.get_source_id(source_index)
			var atlas := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			if atlas == null or checked_sources.has(atlas.get_instance_id()):
				continue
			checked_sources[atlas.get_instance_id()] = true
			if atlas.texture == null:
				failures.append("Fuente sin textura: %s, source %d." % [map.get_path_to(layer), source_id])
				continue
			if atlas.has_tiles_outside_texture():
				failures.append("Tiles fuera de la textura: %s, source %d." % [map.get_path_to(layer), source_id])
			if atlas.texture.resource_path == UTILS_PATH:
				utils_sources += 1
				if Vector2i(atlas.texture.get_size()) != actual_utils_size:
					failures.append("El tamaño importado de utils_2_ no coincide con el PNG; reimportar.")
		for cell in layer.get_used_cells():
			cells_checked += 1
			var source_id := layer.get_cell_source_id(cell)
			if not layer.tile_set.has_source(source_id):
				failures.append("Celda %s de %s: fuente inexistente %d." % [cell, map.get_path_to(layer), source_id])
				continue
			var atlas := layer.tile_set.get_source(source_id) as TileSetAtlasSource
			if atlas == null:
				continue
			var coords := layer.get_cell_atlas_coords(cell)
			if not atlas.has_tile(coords):
				failures.append("Celda %s de %s: tile inexistente %s." % [cell, map.get_path_to(layer), coords])
				continue
			# Rotations/flips are flags, not alternative tile identifiers.
			var flags := TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE
			var alternative := layer.get_cell_alternative_tile(cell) & ~flags
			if not atlas.has_alternative_tile(coords, alternative):
				failures.append("Celda %s de %s: alternativa inexistente %d." % [cell, map.get_path_to(layer), alternative])
			if atlas.texture != null and atlas.texture.resource_path == UTILS_PATH:
				utils_cells += 1
	map.free()
	if failures.is_empty():
		print("PASS: %d fuentes y %d celdas válidas. utils_2_: %s, %d fuentes, %d celdas en uso." % [checked_sources.size(), cells_checked, actual_utils_size, utils_sources, utils_cells])
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
