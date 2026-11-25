extends SceneTree

const MAP_PATH := "res://Maps/map_001_3d.tscn"
const CONTROLLER_PATH := "World/Leaftown/Buildings/lucas_dawn_house"
const LIGHTS_PATH := "World/Leaftown/Lights"

var _failures: Array[String] = []
var _changes := 0


# Reloj de prueba: permite cruzar 07:00 sin tocar la hora del dispositivo ni
# emitir time_changed. La lógica es la misma que usa el controlador real.
class TestClockController extends GlbLayerController:
	var system_hour := 6.0 + 59.0 / 60.0 + 59.0 / 3600.0

	func _get_system_hour() -> float:
		return system_hour


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	var packed := load(MAP_PATH) as PackedScene
	# Verifica el estado inicial antes del primer frame/tick del reloj.
	for hour: float in [0.0, 6.999, 7.0, 12.0, 17.999, 18.0, 23.999]:
		var startup_map := _new_map(packed, hour)
		_check_state(startup_map, hour >= 18.0 or hour < 7.0, "startup %.3f" % hour)
		startup_map.free()

	var map := _new_map(packed, 12.0)
	var controller := map.get_node(CONTROLLER_PATH) as GlbLayerController
	var clock_node := map.get_node("Sky/TimeOfDay") as TimeOfDay
	var lights := map.get_node(LIGHTS_PATH) as Node3D
	var original_light_settings: Array[Dictionary] = []
	var all_spots := lights.find_children("*", "SpotLight3D", true, false)
	_check(all_spots.size() == 8, "Se verifican los ocho focos de las cuatro casas.")
	for light: SpotLight3D in all_spots:
		original_light_settings.append(_light_settings(light))
	controller.layer_changed.connect(func(layer: String, _enabled: bool):
		if layer == "night_lights":
			_changes += 1
	)
	for hour: float in [17.999, 18.0, 19.0, 23.999, 0.0, 6.999, 7.0, 12.0]:
		clock_node.current_time = hour
		_finish_fade(controller)
		_check_state(map, hour >= 18.0 or hour < 7.0, "transition %.3f" % hour)
	_check(_changes == 2, "Solo aplica cambios al entrar/salir de la franja nocturna.")
	# Cambios manuales/saltos hacia atrás del reloj también se reflejan.
	clock_node.current_time = 6.5
	_finish_fade(controller)
	_check_state(map, true, "reverse clock to 06:30")
	clock_node.current_time = 15.0
	_finish_fade(controller)
	_check_state(map, false, "jump clock to 15:00")
	_check_smooth_fade(map, clock_node, controller, 18.0, true)
	_check_smooth_fade(map, clock_node, controller, 7.0, false)
	# Retomar el nivel actual al invertir un fundido, sin saltos de opacidad/energía.
	clock_node.current_time = 18.0
	var interrupted: Tween = controller.get("_window_light_tween")
	interrupted.pause()
	interrupted.custom_step(0.4)
	var intermediate_blend: float = controller.get("_window_light_blend")
	clock_node.current_time = 7.0
	_check(is_equal_approx(controller.get("_window_light_blend"), intermediate_blend), "Invertir el fundido no causa un salto.")
	_finish_fade(controller)
	_check_state(map, false, "interrupted fade ends hidden")
	for index in all_spots.size():
		_check(original_light_settings[index] == _light_settings(all_spots[index]),
			"El horario conserva todos los ajustes visuales del foco %d." % index)
	_inspect_spotlights(map)
	map.free()

	# System Sync: no usar la hora vieja del archivo mientras llega el primer tick.
	var system_map := packed.instantiate() as Node3D
	var system_clock := system_map.get_node("Sky/TimeOfDay") as TimeOfDay
	system_clock.game_time_enabled = false
	system_clock.system_sync = true
	var local_hour: int = Time.get_time_dict_from_system().hour
	var local_night := local_hour >= 18 or local_hour < 7
	system_clock.current_time = 12.0 if local_night else 22.0
	root.add_child(system_map)
	_check_state(system_map, local_night, "System Sync ignores stale scene time")
	system_map.free()

	# Otros GLB mantienen el modo manual si no se activa el horario.
	var manual_map := packed.instantiate() as Node3D
	var manual_controller := manual_map.get_node(CONTROLLER_PATH) as GlbLayerController
	manual_controller.automatic_window_lights = false
	manual_map.get_node("Sky/TimeOfDay").game_time_enabled = false
	root.add_child(manual_map)
	manual_controller.set_layer("night_lights", true)
	manual_map.get_node("Sky/TimeOfDay").current_time = 12.0
	_check(manual_controller.is_layer_enabled("night_lights"), "El modo manual no lo sobrescribe el reloj.")
	manual_map.free()

	_check_added_house(packed)
	await _check_system_clock_boundary()

	if "--capture" in OS.get_cmdline_user_args():
		var preview := _new_map(packed, 21.0)
		var actor := preview.get_node("World/CynthiaPlayer3D") as Node3D
		actor.global_position = Vector3(-2, 0.025, 18)
		for _frame in range(60):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/window_lighting_night.png")
		print("CAPTURE res://.godot/window_lighting_night.png")
		preview.free()
	for failure: String in _failures:
		push_error(failure)
	print("PASS: 8 focos/4 casas + nueva casa; 07:00 sin tick de Sky3D; fundido de 1s real incluso en pausa; 18:00, medianoche, startup y modo manual." if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)


func _check_added_house(packed: PackedScene) -> void:
	var map := packed.instantiate() as Node3D
	var clock_node := map.get_node("Sky/TimeOfDay") as TimeOfDay
	clock_node.game_time_enabled = false
	clock_node.system_sync = false
	clock_node.current_time = 21.0
	var new_house_lights := Node3D.new()
	new_house_lights.name = "FutureHouseLights"
	var extra_light := SpotLight3D.new()
	extra_light.light_energy = 1.7
	new_house_lights.add_child(extra_light)
	map.get_node(LIGHTS_PATH).add_child(new_house_lights)
	root.add_child(map)
	_check_state(map, true, "nueva casa bajo Lights incluida al cargar")
	clock_node.set_time(7, 0, 0)
	_finish_fade(map.get_node(CONTROLLER_PATH))
	_check_state(map, false, "nueva casa apagada a las 07:00")
	map.free()


func _check_system_clock_boundary() -> void:
	var fixture := Node3D.new()
	var clock_node := TimeOfDay.new()
	clock_node.name = "Clock"
	clock_node.game_time_enabled = false
	clock_node.system_sync = true
	clock_node.current_time = 6.9
	clock_node.update_interval = 10.0
	fixture.add_child(clock_node)
	var windows := MeshInstance3D.new()
	windows.name = "Window Light"
	windows.mesh = QuadMesh.new()
	fixture.add_child(windows)
	var lights := Node3D.new()
	lights.name = "Lights"
	var spot := SpotLight3D.new()
	spot.light_energy = 0.583
	lights.add_child(spot)
	fixture.add_child(lights)
	var controller := TestClockController.new()
	controller.automatic_window_lights = true
	controller.time_of_day_path = NodePath("../Clock")
	controller.night_light_paths = [NodePath("../Lights")]
	fixture.add_child(controller)
	root.add_child(fixture)
	_check(spot.is_visible_in_tree() and is_equal_approx(spot.light_energy, 0.583), "06:59:59 sigue encendido.")
	controller.system_hour = 7.0
	controller._process(0.016)
	_check(not controller.is_layer_enabled("night_lights"), "07:00:00 inicia el apagado en el mismo frame, sin esperar a Sky3D.")
	var fade: Tween = controller.get("_window_light_tween")
	_check(fade != null, "07:00 inicia el tween de apagado.")
	if fade == null:
		fixture.free()
		return
	fade.pause()
	fade.custom_step(0.5)
	_check(is_equal_approx(spot.light_energy, 0.583 * 0.5), "07:00:00,5 foco al 50%.")
	_check(is_equal_approx(windows.transparency, 0.5), "07:00:00,5 ventana al 50%.")
	clock_node.current_time = 6.99
	_check(controller.get("_window_light_tween") == fade, "Un tick atrasado no revierte ni reinicia el apagado.")
	fade.custom_step(0.51)
	_check(is_zero_approx(spot.light_energy) and not spot.is_visible_in_tree(), "07:00:01 foco sin energía y oculto.")
	_check(not windows.visible, "07:00:01 ventana oculta.")
	_check(is_equal_approx(clock_node.current_time, 6.99), "Las luces no fuerzan actualizaciones del cielo.")

	# También se encienden a las 18 sin esperar el temporizador del cielo.
	controller.system_hour = 18.0
	controller._process(0.016)
	_finish_fade(controller)
	_check(is_equal_approx(spot.light_energy, 0.583), "18:00 restaura la intensidad configurada.")

	# Prueba con frames reales: la pausa y Engine.time_scale no estiran el segundo.
	# Dejar atrás el frame de carga de todos los mapas antes de medir tiempos.
	for _frame in range(10):
		await process_frame
	var original_time_scale := Engine.time_scale
	var original_paused := paused
	Engine.time_scale = 0.1
	paused = true
	for _frame in range(10):
		await process_frame
	controller.system_hour = 7.0
	await process_frame
	await process_frame
	fade = controller.get("_window_light_tween")
	_check(not controller.is_layer_enabled("night_lights"), "El horario también se comprueba durante pausa.")
	var started := Time.get_ticks_usec()
	var measured := [-1.0]
	fade.finished.connect(func(): measured[0] = float(Time.get_ticks_usec() - started) / 1000000.0)
	await create_timer(1.2, true, false, true).timeout
	_check(measured[0] >= 0.9 and measured[0] < 1.2, "El fundido dura aproximadamente 1 segundo real en pausa y a escala 0,1: %s s." % measured[0])
	_check(is_zero_approx(spot.light_energy) and not spot.is_visible_in_tree(), "Apagado real terminado sin esperar a reanudar el juego.")
	paused = original_paused
	Engine.time_scale = original_time_scale
	print("CHECK 07:00 sin tick; fundido real con pausa y escala 0,1: ", measured[0], " s")
	fixture.free()


func _new_map(packed: PackedScene, hour: float) -> Node3D:
	var map := packed.instantiate() as Node3D
	var clock_node := map.get_node("Sky/TimeOfDay") as TimeOfDay
	clock_node.game_time_enabled = false
	clock_node.system_sync = false
	clock_node.current_time = hour
	root.add_child(map)
	return map


func _check_state(map: Node3D, expected: bool, description: String) -> void:
	var controller := map.get_node(CONTROLLER_PATH) as GlbLayerController
	var windows: Array = controller.call("_scan", ["Window Light"])
	_check(windows.size() == 4, description + ": cuatro casas controladas.")
	for window: Node3D in windows:
		_check(window.visible == expected, description + ": " + str(window.get_path()))
	var lights := map.get_node(LIGHTS_PATH) as Node3D
	_check(lights.visible == expected, description + ": grupo de focos.")
	for light: SpotLight3D in lights.find_children("*", "SpotLight3D", true, false):
		var label := description + ": " + str(light.get_path())
		_check(light.is_visible_in_tree() == expected, label)
		if not controller.get("_night_light_energy").has(light):
			_check(false, label + " no está vinculado al horario.")
			continue
		var original_energy: float = controller.get("_night_light_energy")[light]
		_check(is_equal_approx(light.light_energy, original_energy if expected else 0.0), label + ": energía")
	_check(controller.is_layer_enabled("night_lights") == expected, description + ": estado del controlador.")
	print("CHECK ", description, " expected_lights=", expected)


func _finish_fade(controller: GlbLayerController) -> void:
	var tween: Tween = controller.get("_window_light_tween")
	if tween != null and tween.is_valid():
		tween.pause()
		tween.custom_step(controller.window_lights_fade_seconds + 0.01)


func _check_smooth_fade(map: Node3D, clock_node: TimeOfDay, controller: GlbLayerController, hour: float, enabled: bool) -> void:
	_check(is_equal_approx(controller.window_lights_fade_seconds, 1.0), "El fundido dura 1 segundo.")
	clock_node.current_time = hour
	var tween: Tween = controller.get("_window_light_tween")
	tween.pause()
	tween.custom_step(0.5)
	var blend: float = controller.get("_window_light_blend")
	_check(is_equal_approx(blend, 0.5), "Opacidad/intensidad intermedia a los 0,5 segundos.")
	for geometry: GeometryInstance3D in controller.get("_window_fade_geometry"):
		var original_transparency: float = controller.get("_window_fade_geometry")[geometry]
		_check(is_equal_approx(geometry.transparency, 1.0 - (1.0 - original_transparency) * blend), "La geometría de ventanas se desvanece sin cambiar materiales.")
	for light: Light3D in controller.get("_night_light_energy"):
		_check(is_equal_approx(light.light_energy, controller.get("_night_light_energy")[light] * blend), "El foco sigue el mismo nivel de fundido que la ventana.")
	tween.custom_step(0.49)
	_check(map.get_node(LIGHTS_PATH).visible, "Las luces no se ocultan antes de terminar el fundido.")
	tween.custom_step(0.02)
	_check_state(map, enabled, "fade finishes after 1 second")


func _light_settings(light: SpotLight3D) -> Dictionary:
	return {"transform": light.transform, "color": light.light_color, "energy": light.light_energy,
		"range": light.spot_range, "attenuation": light.spot_attenuation,
		"angle": light.spot_angle, "shadows": light.shadow_enabled,
		"shadow_blur": light.shadow_blur, "shadow_opacity": light.shadow_opacity}


func _inspect_spotlights(map: Node3D) -> void:
	var house := map.get_node(CONTROLLER_PATH) as Node3D
	for mesh: MeshInstance3D in house.find_children("*", "MeshInstance3D", true, false):
		if "Window" in mesh.name or "Wall Front" in mesh.name:
			print("MESH ", house.get_path_to(mesh), " bounds=", mesh.global_transform * mesh.get_aabb())
	for light: SpotLight3D in map.get_node(LIGHTS_PATH).find_children("*", "SpotLight3D", true, false):
		print("SPOT ", map.get_path_to(light), " position=", light.global_position,
			" direction=", -light.global_basis.z.normalized(), " color=", light.light_color,
			" range=", light.spot_range, " attenuation=", light.spot_attenuation)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
