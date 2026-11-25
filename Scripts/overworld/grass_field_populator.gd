@tool
class_name GrassFieldPopulator
extends Node3D

## Puebla Terrain3D con el plano de hierba exportado desde Blender.
##
## Repite el plano de 25.455 m como un mosaico sobre el área indicada. Cada
## baldosa usa una de 8 variantes (4 giros de 90° y espejo) elegida por un hash
## determinista, salvo la baldosa del origen, que conserva el plano tal como se
## exportó. La hierba se coloca SOBRE la textura verde del terreno: no se toca
## ninguna capa de textura. Se omiten las zonas con la capa de tierra pintada,
## el decal del camino y las cabañas.
##
## Los mesh assets ("Hierba" y "Tulipan") se buscan por NOMBRE en Terrain3DAssets,
## nunca por posición: si faltan, se crean solos con su escena, material y LODs.
## Las tarjetas de textura generadas por el dock se ignoran.
##
## En el editor se rellena sola al abrir la escena si el terreno aún no tiene
## la hierba; después guarda la escena (Ctrl+S) para que Terrain3D conserve los
## datos. Los botones del inspector permiten repoblar, limpiar o guardar.

const FORMAT_NAME := "hierba_plano_instancias v1"

@export_node_path("Terrain3D") var terrain_path: NodePath = NodePath("../../../../Terrain")
@export_file("*.json") var instances_json: String = "res://Resources/Vegetation/hierba_plano_instancias.json"

@export_group("Mesh assets de Terrain3D")
## Nombre del mesh asset de hierba (se busca por nombre, no por posición).
@export var grass_asset_name := "Hierba"
## Nombre del mesh asset de tulipán.
@export var tulip_asset_name := "Tulipan"
@export_file("*.glb") var grass_scene := "res://Resources/Materials/3D/Models/hierba_mechon.glb"
@export_file("*.tres") var grass_material := "res://Resources/Materials/3D/Shared/Materials/hierba.tres"
@export_file("*.glb") var tulip_scene := "res://Resources/Materials/3D/Models/tulipan.glb"
@export_file("*.tres") var tulip_material := "res://Resources/Materials/3D/Shared/Materials/tulipan.tres"
## Distancia hasta la que se dibuja el LOD0 (más detalle), en metros. Solo al crear el asset.
@export var grass_lod0_range := 14.0
@export var tulip_lod0_range := 16.0
## Distancia máxima de dibujado (m): lo que ve la cámara, con tope de 75 m. Solo al crear el asset.
@export var draw_distance := 75.0
## Si el terreno tiene menos mechones que esto, se considera vacío y se repuebla.
@export var min_valid_instances := 1000

@export_group("Área a cubrir (XZ, metros de mundo)")
@export var area_min := Vector2(-40.0, -60.0)
@export var area_max := Vector2(80.0, 70.0)

@export_group("Exclusiones")
## Nodos cuyos CollisionShape3D (caja) y Decal se tratan como zonas sin hierba.
@export var exclusion_roots: Array[NodePath] = [NodePath("../../Collisions"), NodePath("../../Roads")]
## Margen extra alrededor de cada zona excluida, en metros.
@export var exclusion_margin := 0.4
## Id de la textura de tierra de Terrain3D (no se cubre con hierba).
@export var dirt_texture_id := 1
@export_range(0.05, 1.0, 0.05) var dirt_block_threshold := 0.3

@export_group("Tulipanes")
## Máximo de tulipanes por baldosa de 25.455 m. Cada baldosa recibe de 0 a este valor.
@export_range(0, 5) var max_tulips_per_tile := 5
## Escala del tulipán (1.0 = 20 cm). 0.52 = 10.4 cm, 0.96 = 19.2 cm.
@export var tulip_scale_range := Vector2(0.52, 0.96)

@export_group("Generación")
@export var random_seed := 20260124
## Resolución con la que se comprueban altura, tierra y exclusiones.
@export_range(0.25, 1.0, 0.05) var ground_sample_step := 0.5
## Rellena sola al cargar si el terreno no tiene hierba todavía.
@export var populate_when_empty := true
@export_tool_button("Repoblar hierba", "Reload") var _repopulate_button := repopulate
@export_tool_button("Limpiar hierba", "Clear") var _clear_button := clear_field
@export_tool_button("Guardar datos del terreno", "Save") var _save_button := save_terrain_data


# Ids resueltos por nombre en cada repoblado (la posición en la lista puede cambiar).
var _grass_id := -1
var _tulip_id := -1


func _ready() -> void:
	if populate_when_empty:
		_populate_if_empty.call_deferred()


func _populate_if_empty() -> void:
	var terrain := await _wait_for_terrain()
	if terrain == null:
		return
	if not _resolve_assets(terrain):
		return
	var existing := _count_instances(terrain, _grass_id)
	if existing >= min_valid_instances:
		return
	if not Engine.is_editor_hint():
		push_warning("GrassField: el terreno no tenía hierba guardada (%d mechones); se genera ahora. Ábrelo en el editor, guarda la escena y se evita esta espera." % existing)
	repopulate()


func repopulate() -> void:
	var terrain := _find_terrain()
	if terrain == null:
		push_error("GrassField: no se encontró el nodo Terrain3D.")
		return
	var plane := _load_plane()
	if plane.is_empty():
		return
	if not _resolve_assets(terrain):
		return

	var started := Time.get_ticks_msec()
	var instancer := terrain.get_instancer()
	var data := terrain.get_data()
	# Limpia lo que hubiera en estos dos assets (p. ej. restos de un intento anterior).
	instancer.clear_by_mesh(_grass_id)
	instancer.clear_by_mesh(_tulip_id)

	var exclusion_rects := _collect_exclusions()
	var variants := _build_variants(plane)
	var side: float = plane["side"]
	var ix_min := floori(area_min.x / side + 0.5)
	var ix_max := floori(area_max.x / side + 0.5)
	var iz_min := floori(area_min.y / side + 0.5)
	var iz_max := floori(area_max.y / side + 0.5)

	var grass_total := 0
	var tulip_total := 0
	for iz in range(iz_min, iz_max + 1):
		for ix in range(ix_min, ix_max + 1):
			var counts := _populate_tile(instancer, data, plane, variants, exclusion_rects, ix, iz)
			grass_total += counts.x
			tulip_total += counts.y

	instancer.update_mmis(-1, Vector2i.MAX, true)
	print("GrassField: %d mechones y %d tulipanes añadidos en %d ms. Guarda la escena (Ctrl+S) para conservarlos." % [
		grass_total, tulip_total, Time.get_ticks_msec() - started
	])
	print("GrassField: estado de los mesh assets -> %s" % _describe_assets(terrain))
	_mark_scene_unsaved()


func clear_field() -> void:
	var terrain := _find_terrain()
	if terrain == null:
		return
	var assets := terrain.get_assets()
	var instancer := terrain.get_instancer()
	for asset_name in [grass_asset_name, tulip_asset_name]:
		var id := _find_mesh_id(assets, asset_name)
		if id >= 0:
			instancer.clear_by_mesh(id)
	instancer.update_mmis(-1, Vector2i.MAX, true)
	print("GrassField: hierba y tulipanes eliminados.")
	_mark_scene_unsaved()


func save_terrain_data() -> void:
	var terrain := _find_terrain()
	if terrain == null:
		return
	var data := terrain.get_data()
	var directory := str(terrain.get("data_directory"))
	if data != null and data.has_method("save_directory") and directory != "":
		data.call("save_directory", directory)
		print("GrassField: datos del terreno guardados en %s" % directory)
	else:
		push_warning("GrassField: guarda la escena con Ctrl+S para que Terrain3D escriba los datos.")


# --- Mesh assets -------------------------------------------------------------

## Localiza (o crea) los assets de hierba y tulipán y fija _grass_id/_tulip_id.
func _resolve_assets(terrain: Terrain3D) -> bool:
	var assets := terrain.get_assets()
	if assets == null:
		push_error("GrassField: el terreno no tiene Terrain3DAssets.")
		return false
	_grass_id = _ensure_mesh_asset(assets, grass_asset_name, grass_scene, grass_material, grass_lod0_range)
	_tulip_id = _ensure_mesh_asset(assets, tulip_asset_name, tulip_scene, tulip_material, tulip_lod0_range)
	return _grass_id >= 0 and _tulip_id >= 0


## Posición del mesh asset con ese nombre, o -1. Ignora huecos y tarjetas generadas.
func _find_mesh_id(assets: Terrain3DAssets, asset_name: String) -> int:
	var list := assets.mesh_list
	for i in list.size():
		var asset: Terrain3DMeshAsset = list[i]
		if asset == null:
			continue
		if int(asset.get("generated_type")) != 0:
			continue
		if str(asset.get("name")) == asset_name:
			return i
	return -1


func _ensure_mesh_asset(assets: Terrain3DAssets, asset_name: String, scene_path: String, material_path: String, lod0_range: float) -> int:
	var found := _find_mesh_id(assets, asset_name)
	if found >= 0:
		return found
	var scene := load(scene_path) as PackedScene
	var material := load(material_path) as Material
	if scene == null or material == null:
		push_error("GrassField: no se pudo cargar %s o %s para crear el asset '%s'." % [scene_path, material_path, asset_name])
		return -1
	var asset := Terrain3DMeshAsset.new()
	asset.set("name", asset_name)
	asset.set("scene_file", scene)
	asset.set("material_override", material)
	asset.set("cast_shadows", 0)
	asset.set("last_lod", 1)
	asset.set("last_shadow_lod", 0)
	asset.set("lod0_range", lod0_range)
	asset.set("lod1_range", draw_distance)
	asset.set("fade_margin", 4.0)
	assets.set_mesh_asset(assets.mesh_list.size(), asset)
	_mark_scene_unsaved()
	var created := _find_mesh_id(assets, asset_name)
	if created < 0:
		push_error("GrassField: Terrain3D no aceptó el asset '%s'." % asset_name)
	else:
		print("GrassField: creado el mesh asset '%s' (id %d)." % [asset_name, created])
	return created


func _describe_assets(terrain: Terrain3D) -> String:
	var parts := PackedStringArray()
	var list := terrain.get_assets().mesh_list
	for i in list.size():
		var asset: Terrain3DMeshAsset = list[i]
		if asset == null:
			parts.append("%d:(vacío)" % i)
			continue
		var label := str(asset.get("name"))
		if label == "":
			label = "(sin nombre)"
		parts.append("%d:%s=%d" % [i, label, asset.get_instance_count()])
	return ", ".join(parts)


## En el editor, marca la escena como modificada para que Ctrl+S guarde assets e instancias.
func _mark_scene_unsaved() -> void:
	if not Engine.is_editor_hint():
		return
	if Engine.has_singleton("EditorInterface"):
		var editor_interface: Object = Engine.get_singleton("EditorInterface")
		editor_interface.call("mark_scene_as_unsaved")


# --- Población ---------------------------------------------------------------

## Devuelve Vector2i(mechones, tulipanes) añadidos en la baldosa.
func _populate_tile(
	instancer: Terrain3DInstancer,
	data: Terrain3DData,
	plane: Dictionary,
	variants: Dictionary,
	exclusion_rects: Array[Rect2],
	ix: int,
	iz: int
) -> Vector2i:
	var side: float = plane["side"]
	var half := side * 0.5
	var center_x := ix * side
	var center_z := iz * side
	var origin_tile := ix == 0 and iz == 0
	var variant := 0
	if not origin_tile:
		variant = absi(hash(Vector3i(ix, iz, random_seed))) % 8

	# Caché del suelo de la baldosa: altura y casillas bloqueadas.
	var step := ground_sample_step
	var inv := 1.0 / step
	var x0 := center_x - half - step
	var z0 := center_z - half - step
	var n := int(ceil((side + step * 2.0) * inv)) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var blocked := PackedByteArray()
	blocked.resize(n * n)
	var tile_rect := Rect2(center_x - half, center_z - half, side, side).grow(exclusion_margin + step)
	var local_rects: Array[Rect2] = []
	for rect in exclusion_rects:
		if rect.intersects(tile_rect):
			local_rects.append(rect)

	for gz in n:
		var pz := z0 + (gz + 0.5) * step
		for gx in n:
			var px := x0 + (gx + 0.5) * step
			var probe := Vector3(px, 0.0, pz)
			var index := gz * n + gx
			var h: float = data.get_surface_height(probe)
			if is_nan(h):
				heights[index] = 0.0
				blocked[index] = 1
				continue
			heights[index] = h
			var tex: Vector3 = data.get_texture_id(probe)
			if is_nan(tex.x):
				blocked[index] = 1
				continue
			var dirt := 0.0
			if int(tex.x) == dirt_texture_id:
				dirt += 1.0 - tex.z
			if int(tex.y) == dirt_texture_id:
				dirt += tex.z
			if dirt > dirt_block_threshold:
				blocked[index] = 1
				continue
			var point := Vector2(px, pz)
			for rect in local_rects:
				if rect.has_point(point):
					blocked[index] = 1
					break

	# Mechones.
	var positions: PackedVector3Array = variants["positions"][variant]
	var bases: Array[Basis] = variants["bases"][variant]
	var transforms: Array[Transform3D] = []
	for i in positions.size():
		var offset := positions[i]
		var wx := center_x + offset.x
		var wz := center_z + offset.z
		if wx < area_min.x or wx > area_max.x or wz < area_min.y or wz > area_max.y:
			continue
		var kx := clampi(int((wx - x0) * inv), 0, n - 1)
		var kz := clampi(int((wz - z0) * inv), 0, n - 1)
		var cell := kz * n + kx
		if blocked[cell] != 0:
			continue
		transforms.append(Transform3D(bases[i], Vector3(wx, heights[cell], wz)))
	if not transforms.is_empty():
		var colors := PackedColorArray()
		colors.resize(transforms.size())
		colors.fill(Color.WHITE)
		instancer.add_transforms(_grass_id, transforms, colors, false)

	# Tulipanes: 0..max por baldosa; la del origen conserva los 3 del plano.
	var tulip_transforms: Array[Transform3D] = []
	if origin_tile:
		for row: Array in plane["tulips"]:
			var spot := Vector3(row[0], 0.0, row[2])
			var cell := _cell_index(spot.x, spot.z, x0, z0, inv, n)
			if blocked[cell] != 0:
				continue
			var tulip_basis := Basis(Vector3.UP, float(row[3])).scaled(Vector3.ONE * float(row[4]))
			tulip_transforms.append(Transform3D(tulip_basis, Vector3(spot.x, heights[cell], spot.z)))
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(ix, iz, random_seed ^ 0x5bd1e995))
		var wanted := rng.randi_range(0, max_tulips_per_tile)
		for _k in wanted:
			var tx := center_x + rng.randf_range(-half, half)
			var tz := center_z + rng.randf_range(-half, half)
			var yaw := rng.randf_range(-PI, PI)
			var scale_value := rng.randf_range(tulip_scale_range.x, tulip_scale_range.y)
			if tx < area_min.x or tx > area_max.x or tz < area_min.y or tz > area_max.y:
				continue
			var cell := _cell_index(tx, tz, x0, z0, inv, n)
			if blocked[cell] != 0:
				continue
			var tulip_basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value)
			tulip_transforms.append(Transform3D(tulip_basis, Vector3(tx, heights[cell], tz)))
	if not tulip_transforms.is_empty():
		var tulip_colors := PackedColorArray()
		tulip_colors.resize(tulip_transforms.size())
		tulip_colors.fill(Color.WHITE)
		instancer.add_transforms(_tulip_id, tulip_transforms, tulip_colors, false)

	return Vector2i(transforms.size(), tulip_transforms.size())


func _cell_index(wx: float, wz: float, x0: float, z0: float, inv: float, n: int) -> int:
	var kx := clampi(int((wx - x0) * inv), 0, n - 1)
	var kz := clampi(int((wz - z0) * inv), 0, n - 1)
	return kz * n + kx


## Prepara las 8 variantes (4 giros x espejo) de posiciones y bases del plano.
func _build_variants(plane: Dictionary) -> Dictionary:
	var rows: Array = plane["grass"]
	var count := rows.size()
	var base_positions := PackedVector3Array()
	base_positions.resize(count)
	var base_yaw := PackedFloat32Array()
	base_yaw.resize(count)
	var base_scale := PackedFloat32Array()
	base_scale.resize(count)
	for i in count:
		var row: Array = rows[i]
		base_positions[i] = Vector3(row[0], 0.0, row[2])
		base_yaw[i] = row[3]
		base_scale[i] = row[4]

	var all_positions: Array[PackedVector3Array] = []
	var all_bases: Array = []
	for variant in 8:
		var turns := variant % 4
		var mirrored := variant >= 4
		var angle := turns * PI * 0.5
		var turn := Basis(Vector3.UP, angle)
		var positions := PackedVector3Array()
		positions.resize(count)
		var bases: Array[Basis] = []
		bases.resize(count)
		for i in count:
			var p := base_positions[i]
			if mirrored:
				p.x = -p.x
			positions[i] = turn * p
			var yaw := -base_yaw[i] if mirrored else base_yaw[i]
			bases[i] = Basis(Vector3.UP, yaw + angle).scaled(Vector3.ONE * base_scale[i])
		all_positions.append(positions)
		all_bases.append(bases)
	return {"positions": all_positions, "bases": all_bases}


func _load_plane() -> Dictionary:
	if not FileAccess.file_exists(instances_json):
		push_error("GrassField: no existe %s" % instances_json)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(instances_json))
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("formato", "")) != FORMAT_NAME:
		push_error("GrassField: formato de JSON no reconocido en %s" % instances_json)
		return {}
	var columns: Array = parsed.get("columnas", [])
	if columns != ["x", "y", "z", "yaw", "escala"]:
		push_error("GrassField: columnas inesperadas: %s" % str(columns))
		return {}
	return {
		"side": float(parsed["plano"]["lado_m"]),
		"grass": parsed["mechon"]["instancias"],
		"tulips": parsed["tulipan"]["instancias"],
	}


# --- Exclusiones -------------------------------------------------------------

func _collect_exclusions() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var grow := exclusion_margin + ground_sample_step * 0.5
	for path in exclusion_roots:
		var root := get_node_or_null(path)
		if root != null:
			_gather_rects(root, rects, grow)
	return rects


func _gather_rects(node: Node, rects: Array[Rect2], grow: float) -> void:
	if node is CollisionShape3D and node.shape is BoxShape3D:
		var box_size: Vector3 = node.shape.size
		rects.append(_footprint(node.global_transform, Vector2(box_size.x, box_size.z) * 0.5, grow))
	elif node is Decal:
		var decal_size: Vector3 = node.size
		rects.append(_footprint(node.global_transform, Vector2(decal_size.x, decal_size.z) * 0.5, grow))
	for child in node.get_children():
		_gather_rects(child, rects, grow)


func _footprint(xform: Transform3D, half: Vector2, grow: float) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := xform * Vector3(half.x * sx, 0.0, half.y * sz)
			low = low.min(Vector2(corner.x, corner.z))
			high = high.max(Vector2(corner.x, corner.z))
	return Rect2(low, high - low).grow(grow)


# --- Terrain3D ---------------------------------------------------------------

func _find_terrain() -> Terrain3D:
	var node := get_node_or_null(terrain_path)
	if node is Terrain3D:
		return node
	var root: Node = null
	if is_inside_tree():
		root = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	return _search_terrain(root) if root != null else null


func _search_terrain(node: Node) -> Terrain3D:
	if node is Terrain3D:
		return node
	for child in node.get_children():
		var found := _search_terrain(child)
		if found != null:
			return found
	return null


func _wait_for_terrain() -> Terrain3D:
	for _frame in 180:
		var terrain := _find_terrain()
		if terrain != null and _terrain_ready(terrain):
			return terrain
		if not is_inside_tree():
			return null
		await get_tree().process_frame
	push_warning("GrassField: Terrain3D no estuvo listo a tiempo.")
	return null


func _terrain_ready(terrain: Terrain3D) -> bool:
	var data := terrain.get_data()
	var assets := terrain.get_assets()
	if data == null or assets == null or terrain.get_instancer() == null:
		return false
	return data.get_region_count() > 0


func _count_instances(terrain: Terrain3D, mesh_id: int) -> int:
	var list := terrain.get_assets().mesh_list
	if mesh_id < 0 or mesh_id >= list.size():
		return 0
	var asset: Terrain3DMeshAsset = list[mesh_id]
	if asset == null:
		return 0
	return asset.get_instance_count()
