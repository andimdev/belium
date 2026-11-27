extends Node

## Cargador global de escenas, interfaces, mapas y overlays.
##
## Se utiliza mediante el Autoload `SceneLoader`. El catálogo de escenas puede
## ampliarse aquí o en tiempo de ejecución con `register_scene()`.

signal load_started(scene_id: StringName, path: String)
signal load_progress(scene_id: StringName, progress: float)
signal load_failed(scene_id: StringName, path: String, reason: String)
signal scene_changed(scene_id: StringName, scene: Node, payload: Dictionary)
signal load_finished(scene_id: StringName, scene: Node)
signal overlay_opened(scene_id: StringName, overlay: Node)
signal overlay_closed(scene_id: StringName)
signal transition_started(transition_name: StringName, phase: StringName)
signal transition_finished(transition_name: StringName, phase: StringName)

enum SceneCategory {
	INTERFACE,
	MAP,
	OVERLAY,
}

## UIRoot usa la capa 100. Los overlays globales deben quedar por encima de la
## interfaz del mapa y las transiciones, a su vez, por encima de todo lo demás.
const OVERLAY_CANVAS_LAYER := 110
const TRANSITION_CANVAS_LAYER := 120

## Cambia este identificador para definir qué interfaz abre al iniciar el juego.
const INITIAL_SCENE_ID: StringName = &"initial_credits"

## Catálogo inicial. Se pueden agregar entradas sin modificar el cargador.
## transition acepta "none", "fade" o el nombre de un driver registrado.
const INITIAL_SCENES: Dictionary = {
	&"initial_credits": {
		"path": "res://Scenes/Interface/credits.tscn",
		"category": SceneCategory.INTERFACE,
		"transition": &"fade",
		"threaded": false,
	},
	&"press_start": {
		"path": "res://Scenes/Interface/press_start.tscn",
		"category": SceneCategory.INTERFACE,
		"transition": &"none",
		"threaded": false,
	},
	&"load_new_play": {
		"path": "res://Scenes/Interface/load_new_play.tscn",
		"category": SceneCategory.INTERFACE,
		"transition": &"fade",
		"threaded": false,
	},
	&"map_001_3d": {
		"path": "res://Maps/map_001_3d.tscn",
		"category": SceneCategory.MAP,
		"transition": &"fade",
		"threaded": true,
	},
}

const DEFAULT_OPTIONS: Dictionary = {
	"transition": &"fade",
	"duration": 0.45,
	"color": Color.BLACK,
	"record_history": true,
	"pause_during_transition": false,
	"payload": {},
}

var current_scene_id: StringName = &""
var last_payload: Dictionary = {}
var is_busy: bool = false

var _scene_catalog: Dictionary = {}
var _history: Array[StringName] = []
var _overlay_stack: Array[Dictionary] = []
var _transition_drivers: Dictionary = {}
var _startup_requested := false

var _overlay_layer: CanvasLayer
var _transition_layer: CanvasLayer
var _fade_rect: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scene_catalog = INITIAL_SCENES.duplicate(true)
	_build_persistent_layers()

## Lo invoca Bootstrap. También puede llamarse manualmente en pruebas.
func start() -> bool:
	if _startup_requested:
		return false
	_startup_requested = true
	return await go_to(INITIAL_SCENE_ID, {
		"transition": &"none",
		"record_history": false,
	})

## Registra o reemplaza una entrada del catálogo durante la ejecución.
func register_scene(
	scene_id: StringName,
	path: String,
	category: SceneCategory = SceneCategory.INTERFACE,
	default_transition: StringName = &"fade"
) -> bool:
	if scene_id.is_empty() or not _is_valid_scene_path(path):
		push_error("SceneLoader: no se pudo registrar '%s' (%s)." % [scene_id, path])
		return false

	_scene_catalog[scene_id] = {
		"path": path,
		"category": category,
		"transition": default_transition,
	}
	return true

func unregister_scene(scene_id: StringName) -> void:
	_scene_catalog.erase(scene_id)

func has_scene(scene_id: StringName) -> bool:
	return _scene_catalog.has(scene_id)

func get_scene_info(scene_id: StringName) -> Dictionary:
	return _scene_catalog.get(scene_id, {}).duplicate(true)

## Reemplaza la escena actual por una entrada registrada.
##
## Ejemplo:
## await SceneLoader.go_to(&"main_menu", {"transition": &"fade"})
func go_to(scene_id: StringName, options: Dictionary = {}) -> bool:
	if is_busy:
		push_warning("SceneLoader: se ignoró '%s' porque ya hay una carga en curso." % scene_id)
		return false
	if not _scene_catalog.has(scene_id):
		_fail(scene_id, "", "La escena no está registrada.")
		return false

	var scene_info: Dictionary = _scene_catalog[scene_id]
	var effective_options := _resolve_options(scene_info, options)
	return await _replace_scene(scene_id, scene_info.path, effective_options)

## Permite cargar una ruta todavía no agregada al catálogo.
func go_to_path(path: String, options: Dictionary = {}) -> bool:
	var temporary_id := StringName(path.get_file().get_basename())
	if is_busy:
		push_warning("SceneLoader: se ignoró '%s' porque ya hay una carga en curso." % path)
		return false
	if not _is_valid_scene_path(path):
		_fail(temporary_id, path, "La ruta no contiene una PackedScene válida.")
		return false

	return await _replace_scene(
		temporary_id,
		path,
		_resolve_options({}, options)
	)

## Atajo semántico para menús, HUDs o cualquier interfaz que reemplace la actual.
func open_interface(
	scene_id: StringName,
	payload: Dictionary = {},
	options: Dictionary = {}
) -> bool:
	var merged := options.duplicate(true)
	merged["payload"] = payload
	return await go_to(scene_id, merged)

## Atajo para mapas. El mapa recibe `spawn_point` y `data` en el payload.
func load_map(
	scene_id: StringName,
	spawn_point: StringName = &"",
	payload: Dictionary = {},
	options: Dictionary = {}
) -> bool:
	if _scene_catalog.has(scene_id):
		var info: Dictionary = _scene_catalog[scene_id]
		if info.get("category", SceneCategory.MAP) != SceneCategory.MAP:
			push_warning("SceneLoader: '%s' no está catalogada como MAP." % scene_id)

	var merged := options.duplicate(true)
	merged["payload"] = {
		"spawn_point": spawn_point,
		"data": payload.duplicate(true),
	}
	return await go_to(scene_id, merged)

## Agrega una escena sobre la actual sin reemplazarla (pausa, inventario, diálogo...).
func show_overlay(scene_id: StringName, options: Dictionary = {}) -> Node:
	if is_busy:
		return null
	if not _scene_catalog.has(scene_id):
		_fail(scene_id, "", "El overlay no está registrado.")
		return null

	var scene_info: Dictionary = _scene_catalog[scene_id]
	if scene_info.get("category", SceneCategory.OVERLAY) != SceneCategory.OVERLAY:
		push_warning("SceneLoader: '%s' no está catalogada como OVERLAY." % scene_id)
	var path: String = scene_info.path
	var effective_options := _resolve_options(scene_info, options)
	is_busy = true
	load_started.emit(scene_id, path)

	var packed_scene := await _load_packed_scene(scene_id, path)
	if packed_scene == null:
		is_busy = false
		return null

	await _play_transition(&"out", effective_options)
	var overlay := packed_scene.instantiate()
	var payload: Dictionary = effective_options.payload.duplicate(true)
	overlay.set_meta(&"scene_payload", payload)
	_overlay_layer.add_child(overlay)
	_overlay_stack.append({"id": scene_id, "node": overlay})
	overlay_opened.emit(scene_id, overlay)
	await _play_transition(&"in", effective_options)

	is_busy = false
	load_finished.emit(scene_id, overlay)
	return overlay

## Cierra el último overlay o uno específico si se proporciona su nodo.
func close_overlay(overlay: Node = null, options: Dictionary = {}) -> bool:
	if is_busy or _overlay_stack.is_empty():
		return false

	var index := _overlay_stack.size() - 1
	if overlay != null:
		index = -1
		for candidate_index in range(_overlay_stack.size() - 1, -1, -1):
			if _overlay_stack[candidate_index].node == overlay:
				index = candidate_index
				break
		if index < 0:
			return false

	is_busy = true
	var entry: Dictionary = _overlay_stack[index]
	var effective_options := _resolve_options({}, options)
	await _play_transition(&"out", effective_options)
	_overlay_stack.remove_at(index)
	if is_instance_valid(entry.node):
		entry.node.queue_free()
	overlay_closed.emit(entry.id)
	await _play_transition(&"in", effective_options)
	is_busy = false
	return true

## Regresa a la última escena reemplazada.
func go_back(options: Dictionary = {}) -> bool:
	if _history.is_empty() or is_busy:
		return false
	var previous_id: StringName = _history.pop_back()
	var merged := options.duplicate(true)
	merged["record_history"] = false
	return await go_to(previous_id, merged)

## Inicia una carga en segundo plano para eliminar esperas posteriores.
func preload_scene(scene_id: StringName) -> bool:
	if not _scene_catalog.has(scene_id):
		return false
	var scene_info: Dictionary = _scene_catalog[scene_id]
	var path: String = scene_info.path
	if ResourceLoader.has_cached(path):
		return true
	if not scene_info.get("threaded", true):
		return ResourceLoader.load(path, "PackedScene") is PackedScene
	var error := ResourceLoader.load_threaded_request(
		path,
		"PackedScene",
		true,
		ResourceLoader.CACHE_MODE_REUSE
	)
	return error == OK or error == ERR_BUSY

## Drivers externos permiten sumar wipe, iris, glitch, animaciones, etc.
## El nodo debe implementar `play_out(options)` y `play_in(options)`.
func register_transition_driver(transition_name: StringName, driver: Node) -> bool:
	if transition_name in [&"none", &"fade"] or not is_instance_valid(driver):
		return false
	if not driver.has_method("play_out") or not driver.has_method("play_in"):
		push_error("SceneLoader: el driver '%s' no implementa play_out/play_in." % transition_name)
		return false
	_transition_drivers[transition_name] = driver
	return true

func unregister_transition_driver(transition_name: StringName) -> void:
	_transition_drivers.erase(transition_name)

func get_payload() -> Dictionary:
	return last_payload.duplicate(true)

func _replace_scene(scene_id: StringName, path: String, options: Dictionary) -> bool:
	is_busy = true
	load_started.emit(scene_id, path)

	var packed_scene := await _load_packed_scene(scene_id, path)
	if packed_scene == null:
		is_busy = false
		return false

	var should_pause: bool = options.pause_during_transition
	var previous_pause_state := get_tree().paused
	if should_pause:
		get_tree().paused = true

	await _play_transition(&"out", options)
	var new_scene := packed_scene.instantiate()
	if new_scene == null:
		if should_pause:
			get_tree().paused = previous_pause_state
		_fail(scene_id, path, "PackedScene.instantiate() devolvió null.")
		await _play_transition(&"in", options)
		is_busy = false
		return false

	var payload: Dictionary = options.payload.duplicate(true)
	new_scene.set_meta(&"scene_payload", payload)
	last_payload = payload

	var previous_scene := get_tree().current_scene
	if options.record_history and not current_scene_id.is_empty():
		_history.append(current_scene_id)

	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	current_scene_id = scene_id
	if is_instance_valid(previous_scene):
		previous_scene.queue_free()

	scene_changed.emit(scene_id, new_scene, payload)
	await get_tree().process_frame
	await _play_transition(&"in", options)
	if should_pause:
		get_tree().paused = previous_pause_state

	is_busy = false
	load_finished.emit(scene_id, new_scene)
	return true


func _load_packed_scene(scene_id: StringName, path: String) -> PackedScene:
	if not _is_valid_scene_path(path):
		_fail(scene_id, path, "La ruta no existe o no es una PackedScene.")
		return null
	var scene_info: Dictionary = _scene_catalog.get(scene_id, {})

	if ResourceLoader.has_cached(path):
		load_progress.emit(scene_id, 1.0)
		return ResourceLoader.load(path, "PackedScene") as PackedScene
	if not scene_info.get("threaded", true):
		load_progress.emit(scene_id, 0.0)
		var direct_scene := ResourceLoader.load(path, "PackedScene") as PackedScene
		if direct_scene == null:
			_fail(scene_id, path, "La carga directa falló.")
			return null
		load_progress.emit(scene_id, 1.0)
		return direct_scene

	var request_error := ResourceLoader.load_threaded_request(
		path,
		"PackedScene",
		true,
		ResourceLoader.CACHE_MODE_REUSE
	)
	if request_error != OK and request_error != ERR_BUSY:
		_fail(scene_id, path, "No se pudo iniciar la carga asíncrona (%s)." % request_error)
		return null

	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if not progress.is_empty():
			load_progress.emit(scene_id, float(progress[0]))

		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				break
			ResourceLoader.THREAD_LOAD_FAILED:
				_fail(scene_id, path, "La carga asíncrona falló.")
				return null
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_fail(scene_id, path, "El recurso dejó de ser válido durante la carga.")
				return null

		await get_tree().process_frame

	load_progress.emit(scene_id, 1.0)
	return ResourceLoader.load_threaded_get(path) as PackedScene

func _play_transition(phase: StringName, options: Dictionary) -> void:
	var transition_name: StringName = options.transition
	if transition_name == &"none":
		return

	transition_started.emit(transition_name, phase)
	if transition_name == &"fade":
		await _play_fade(phase == &"out", options)
	elif _transition_drivers.has(transition_name):
		var driver: Node = _transition_drivers[transition_name]
		if phase == &"out":
			await driver.play_out(options)
		else:
			await driver.play_in(options)
	else:
		push_warning("SceneLoader: transición '%s' desconocida; se usará fade." % transition_name)
		await _play_fade(phase == &"out", options)
	transition_finished.emit(transition_name, phase)

func _play_fade(fade_out: bool, options: Dictionary) -> void:
	var duration: float = maxf(float(options.duration), 0.0)
	var fade_color: Color = options.color
	_fade_rect.color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)
	_fade_rect.modulate.a = 0.0 if fade_out else 1.0
	_fade_rect.show()

	if duration <= 0.0:
		_fade_rect.modulate.a = 1.0 if fade_out else 0.0
	else:
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			_fade_rect,
			"modulate:a",
			1.0 if fade_out else 0.0,
			duration
		)
		await tween.finished

	if not fade_out:
		_fade_rect.hide()

func _resolve_options(scene_info: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := DEFAULT_OPTIONS.duplicate(true)
	if scene_info.has("transition"):
		result["transition"] = scene_info.transition
	result.merge(overrides, true)
	return result

func _is_valid_scene_path(path: String) -> bool:
	return not path.is_empty() and path.ends_with(".tscn") and ResourceLoader.exists(path, "PackedScene")

func _fail(scene_id: StringName, path: String, reason: String) -> void:
	push_error("SceneLoader [%s]: %s" % [scene_id, reason])
	load_failed.emit(scene_id, path, reason)

func _build_persistent_layers() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "SceneOverlays"
	_overlay_layer.layer = OVERLAY_CANVAS_LAYER
	add_child(_overlay_layer)

	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "SceneTransitions"
	_transition_layer.layer = TRANSITION_CANVAS_LAYER
	add_child(_transition_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "Fade"
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_rect.color = Color.BLACK
	_fade_rect.hide()
	_transition_layer.add_child(_fade_rect)
