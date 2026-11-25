extends SceneTree

const MAP := "res://Maps/map_001_3d.tscn"
const DECAL_NODE := "World/Leaftown/Roads/DirtGroundPath"
const GROUND_LAYER := 1 << 19
const BACKUP := "res://Backups/dirt_path_before_decals_20261124/"
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	var map := load(MAP).instantiate() as Node3D
	var terrain := map.get_node("Terrain") as Terrain3D
	var decal := map.get_node(DECAL_NODE) as Decal
	_check(terrain.assets.get_texture_count() == 2, "Solo texturas opacas en Terrain3D.")
	_check((terrain.render_layers & GROUND_LAYER) != 0 and (terrain.render_layers & 1) != 0, "El terreno recibe decals sin perder su capa original.")
	_check(decal.cull_mask == GROUND_LAYER, "El camino solo se proyecta sobre el terreno.")
	for mesh: GeometryInstance3D in map.find_children("*", "GeometryInstance3D", true, false):
		_check((mesh.layers & GROUND_LAYER) == 0, "El decal no afecta a " + str(map.get_path_to(mesh)))
	var image := decal.texture_albedo.get_image()
	if image.is_compressed():
		_check(image.decompress() == OK, "Se puede leer el alfa importado.")
	_check(is_zero_approx(image.get_pixel(0, 0).a), "El PNG mantiene su borde transparente.")
	_check(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a > 0.99, "El centro del camino es visible.")

	var lab := load("res://Resources/Materials/3D/Models/prof_rowan_lab.glb").instantiate() as Node3D
	var reference: StandardMaterial3D
	for mesh: MeshInstance3D in lab.find_children("*", "MeshInstance3D", true, false):
		var material := mesh.get_active_material(0) as StandardMaterial3D
		if material != null and material.resource_name == "Window Glow Mat":
			reference = material
	_check(reference != null, "Referencia nocturna original del laboratorio disponible.")
	var checked := 0
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == "Shared Window Glow":
				_check(material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "Ventana cálida sin sumar blanco.")
				_check(is_equal_approx(material.emission_energy_multiplier, reference.emission_energy_multiplier), "Intensidad original de la ventana restaurada.")
				_check(material.emission_texture != null and material.albedo_texture != null, "Texturas compartidas disponibles.")
				checked += 1
	_check(checked == 12, "Doce superficies nocturnas de las cuatro cabañas verificadas.")
	lab.free()
	_verify_region_migration()

	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture_comparison(map)
	map.free()
	for failure in _failures:
		push_error(failure)
	print("PASS: transparent ground decal, terrain-only mask, warm shared windows, two control pixels changed, heights/colors/trees preserved." if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)


func _verify_region_migration() -> void:
	var region_path := "res://Maps/map_001_3d_data/terrain3d_00-01.res"
	var region := load(region_path) as Terrain3DRegion
	var previous := load(BACKUP + "terrain3d_00-01.res") as Terrain3DRegion
	_check(region.height_map.get_data() == previous.height_map.get_data(), "Alturas intactas.")
	_check(region.color_map.get_data() == previous.color_map.get_data(), "Pintura de color intacta.")
	_check(region.instances == previous.instances, "Árboles intactos.")
	var before := previous.control_map.get_data()
	var after := region.control_map.get_data()
	var changed := 0
	for index in before.size() / 4:
		var original := before.decode_u32(index * 4)
		var current := after.decode_u32(index * 4)
		if original != current:
			changed += 1
			_check(Terrain3DUtil.get_overlay(original) == 2, "Solo se retira Dirt Ground Path.")
			_check(current == (original & ~(Terrain3DUtil.enc_overlay(31) | Terrain3DUtil.enc_blend(255))), "Ningún otro bit del control cambia.")
	_check(changed == 2, "Solo dos marcas de prueba migradas.")
	for file in DirAccess.get_files_at("res://Maps/map_001_3d_data"):
		if not file.ends_with(".res"):
			continue
		var data := (load("res://Maps/map_001_3d_data/" + file) as Terrain3DRegion).control_map.get_data()
		var invalid := 0
		for index in data.size() / 4:
			var bits := data.decode_u32(index * 4)
			if Terrain3DUtil.get_base(bits) > 1 or Terrain3DUtil.get_overlay(bits) > 1:
				invalid += 1
		_check(invalid == 0, "Sin índices de textura huérfanos: " + file)


func _capture_comparison(map: Node3D) -> void:
	var clock_node := map.get_node("Sky/TimeOfDay") as TimeOfDay
	clock_node.game_time_enabled = false
	clock_node.system_sync = false
	clock_node.current_time = 21.0
	root.add_child(map)
	map.get_node("World/CynthiaPlayer3D").set_physics_process(false)
	map.get_node("CameraRig").set_process(false)
	map.get_node("CameraRig").set_physics_process(false)
	var camera := map.get_node("CameraRig/Camera3D") as Camera3D
	camera.top_level = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 42.0
	camera.global_position = Vector3(-36, 30, 6)
	camera.look_at(Vector3(2, 1, 6), Vector3.UP)
	var glow := load("res://Resources/Materials/3D/Shared/Materials/window_glow.tres") as StandardMaterial3D
	# Comparación solo en memoria: jamás guarda estos valores de diagnóstico.
	glow.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	glow.emission_energy_multiplier = 1.0
	await _capture("window_material_before")
	glow.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	glow.emission_energy_multiplier = 1.6
	await _capture("window_material_fixed")
	clock_node.current_time = 12.0
	var controller := map.get_node("World/Leaftown/Buildings/lucas_dawn_house") as GlbLayerController
	controller.refresh_window_lighting()
	camera.size = 7.0
	camera.global_position = Vector3(8.5, 9, -6.5)
	camera.look_at(Vector3(8.5, 0, -6.5), Vector3(0, 0, -1))
	var decal := map.get_node(DECAL_NODE) as Decal
	decal.visible = false
	var bare := await _capture("dirt_path_ground_only")
	decal.visible = true
	var painted := await _capture("dirt_path_transparent")
	# Un punto exterior al dibujo, pero dentro de la caja, debe mantener el suelo.
	var border := Vector2i(camera.unproject_position(Vector3(7.6, 0, -7.4)))
	var center := Vector2i(camera.unproject_position(Vector3(8.5, 0, -6.5)))
	var border_difference := _color_difference(bare.get_pixelv(border), painted.get_pixelv(border))
	var center_difference := _color_difference(bare.get_pixelv(center), painted.get_pixelv(center))
	print("DECAL_DIFF border=", border_difference, " center=", center_difference)
	_check(border_difference < 0.04, "El borde transparente deja ver el terreno original.")
	_check(center_difference > 0.05, "El decal se renderiza sobre Terrain3D.")


func _capture(label: String) -> Image:
	for _frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png("res://.godot/" + label + ".png")
	print("CAPTURE ", label)
	return result


func _color_difference(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
