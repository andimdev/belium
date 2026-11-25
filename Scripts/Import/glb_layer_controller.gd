class_name GlbLayerController
extends Node

## Controla en tiempo de ejecución las capas visibles y las animaciones de una
## escena importada desde un GLB (cabaña, árbol, mapa completo...).
##
## No toca el archivo importado ni sus materiales compartidos: cambia propiedades
## de los nodos y reproduce animaciones con el AnimationPlayer que Godot generó.
## Funciona antes de que la escena entre al árbol, así que se puede configurar
## el estado de cada GLB antes de cargar el mapa y cambiarlo después.
##
## Uso por código:
##     var cabin := (load("res://Resources/Materials/3D/Models/cabin_1.glb") as PackedScene).instantiate() as Node3D
##     var layers := GlbLayerController.attach(cabin, {"snow": true, "night_lights": false})
##     add_child(cabin)
##     layers.set_layer("night_lights", true)
##     layers.play_animation(&"Door_Open")
##
## Cambio global (todos los GLB con controlador a la vez):
##     GlbLayerController.set_layer_everywhere(get_tree(), "snow", true)

signal layer_changed(layer: String, enabled: bool)
signal variant_changed(group: String, variant: String)
signal animation_started(animation_name: StringName)
signal animation_finished(animation_name: StringName)

const GROUP_NAME := &"glb_layers"
const CONTROLLER_NODE_NAME := "GlbLayerController"
const LOOP_SUFFIXES := ["-loop", "_loop"]

@export_group("Escena")
## GLB que se controla. Si se deja vacío se usa el nodo padre.
@export var target: Node3D

@export_group("Capas")
## Capas que se encienden o apagan de forma independiente.
## Clave: nombre lógico. Valor: patrones de nombre de nodo ("*" y "?" permitidos,
## sin distinguir mayúsculas). Los sufijos numéricos de Godot ("Plank_002") se ignoran.
## Si un nodo tiene hijos (como "Window Light"), se oculta con todos ellos.
@export var layers: Dictionary = {
	"snow": ["Snow"],
	"night_lights": ["Window Light"],
}
## Grupos excluyentes: dentro de cada grupo solo una variante queda visible.
@export var variant_groups: Dictionary = {
	"season": {
		"default": ["Branches"],
		"autumn": ["Branches Autumn"],
		"spring": ["Branches Spring"],
	},
}
## Estado inicial de las capas y de los grupos al crear el controlador.
@export var initial_layers: Dictionary = {"snow": false, "night_lights": false}
@export var initial_variants: Dictionary = {"season": "default"}
## Si el controlador se coloca desde el editor, aplica el estado inicial en `_ready`.
@export var apply_initial_state_on_ready := true

@export_group("Ventanas por horario")
## Activa Window Light según el reloj de Sky3D. Desactivado por defecto para
## conservar el control manual en otros GLB (árboles, interiores, etc.).
@export var automatic_window_lights := false
## Asigna el nodo Sky/TimeOfDay del mapa; no modifica su velocidad ni System Sync.
@export_node_path("TimeOfDay") var time_of_day_path: NodePath
## Franja [encendido, apagado). Puede atravesar medianoche; horas iguales = apagado.
@export_range(0, 23, 1) var window_lights_on_hour: int = 18
@export_range(0, 23, 1) var window_lights_off_hour: int = 7
## Duración del fundido al cambiar de franja. La carga inicial sigue siendo inmediata.
@export_range(0.0, 5.0, 0.1) var window_lights_fade_seconds := 1.0
## Luces o grupos Node3D externos al GLB que comparten el horario de las ventanas.
## Anima la energía hasta el valor configurado; conserva posición, color y sombras.
## Asigna el grupo Lights completo para incluir todas las casas, también nuevas
## luces que se agreguen en el editor antes de ejecutar el mapa.
@export var night_light_paths: Array[NodePath] = []

@export_group("Animación")
## Se detecta solo (primer AnimationPlayer del GLB) si se deja vacío.
@export var animation_player: AnimationPlayer
## Mezcla entre animaciones, en segundos (0.3 a 0.5 se ve natural).
@export_range(0.0, 2.0, 0.05, "or_greater") var default_blend_time := 0.4
## Fuerza bucle en animaciones cuyo nombre termina en "-loop" o "_loop".
@export var force_loop_on_suffix := true

var _layer_state: Dictionary = {}
var _variant_state: Dictionary = {}
var _node_cache: Dictionary = {}
var _state_applied := false
var _suffix_regex := RegEx.new()
var _time_of_day: TimeOfDay
var _night_light_roots: Array[Node3D] = []
var _window_fade_geometry: Dictionary[GeometryInstance3D, float] = {}
var _night_light_energy: Dictionary[Light3D, float] = {}
var _window_light_blend := 0.0
var _window_light_tween: Tween


func _init() -> void:
	name = CONTROLLER_NODE_NAME
	add_to_group(GROUP_NAME)
	_suffix_regex.compile("^(.+?)[_.\\s]?\\d+$")


func _ready() -> void:
	set_process(false)
	if apply_initial_state_on_ready and not _state_applied:
		apply_initial_state()
	_connect_window_clock()


func _process(_delta: float) -> void:
	if not automatic_window_lights or not is_instance_valid(_time_of_day):
		return
	if _time_of_day.system_sync:
		# El reloj del SO no espera el Timer del cielo (0,5 s en este mapa).
		# Comprueba el límite en cada frame, incluso si el juego está pausado.
		# _apply_window_lighting no recorre las luces mientras no cambie la franja.
		_apply_window_lighting(_get_system_hour())
	# Sin System Sync, time_changed sigue siendo la autoridad del reloj de juego.


func _exit_tree() -> void:
	if _window_light_tween != null:
		_window_light_tween.kill()
	if is_instance_valid(_time_of_day):
		if _time_of_day.time_changed.is_connected(_on_window_clock_changed):
			_time_of_day.time_changed.disconnect(_on_window_clock_changed)
	_time_of_day = null
	_night_light_roots.clear()
	_window_fade_geometry.clear()
	_night_light_energy.clear()


func _connect_window_clock() -> void:
	if not automatic_window_lights:
		return
	_time_of_day = get_node_or_null(time_of_day_path) as TimeOfDay
	if _time_of_day == null:
		push_warning("GlbLayerController: asigna un nodo TimeOfDay para el horario de ventanas.")
		return
	if not layers.has("night_lights"):
		push_warning("GlbLayerController: falta la capa 'night_lights' para el horario de ventanas.")
		return
	for light_path: NodePath in night_light_paths:
		var light_root := get_node_or_null(light_path) as Node3D
		if light_root == null:
			push_warning("GlbLayerController: no se encontró el grupo de luces '%s'." % light_path)
		else:
			_night_light_roots.append(light_root)
	_cache_window_fade_nodes()
	if not _time_of_day.time_changed.is_connected(_on_window_clock_changed):
		_time_of_day.time_changed.connect(_on_window_clock_changed)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	refresh_window_lighting()


func _cache_window_fade_nodes() -> void:
	var pending: Array[Node] = []
	for window_root: Node in _get_nodes("layer:night_lights", layers["night_lights"], null):
		pending.append(window_root)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is GeometryInstance3D and not _window_fade_geometry.has(node):
			var geometry := node as GeometryInstance3D
			_window_fade_geometry[geometry] = geometry.transparency
	for light_root: Node3D in _night_light_roots:
		pending.append(light_root)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node is Light3D and not _night_light_energy.has(node):
			var light := node as Light3D
			_night_light_energy[light] = light.light_energy


## Aplica el estado inmediatamente, sin esperar el primer tick del reloj.
func refresh_window_lighting() -> void:
	if not automatic_window_lights or not is_instance_valid(_time_of_day):
		return
	var hour := _time_of_day.current_time
	if _time_of_day.system_sync:
		# Sky3D puede conservar la hora del último guardado hasta su primer tick.
		hour = _get_system_hour()
	_apply_window_lighting(hour, true)


func _get_system_hour() -> float:
	var system_time := Time.get_time_dict_from_system()
	return (
		float(system_time.hour)
		+ float(system_time.minute) / 60.0
		+ float(system_time.second) / 3600.0
	)


func _on_window_clock_changed(hour: float) -> void:
	if automatic_window_lights:
		# Una señal atrasada de Sky3D nunca debe volver a encender los focos
		# después de que el reloj real ya haya cruzado las 07:00.
		_apply_window_lighting(_get_system_hour() if _time_of_day.system_sync else hour)


func _apply_window_lighting(hour: float, force: bool = false) -> void:
	var enabled := _window_lights_enabled_at(hour)
	# Sky3D emite cada tick: solo recorremos las casas cuando cambia la franja.
	if (
		not force
		and _layer_state.has("night_lights")
		and is_layer_enabled("night_lights") == enabled
	):
		return
	if _window_light_tween != null:
		_window_light_tween.kill()
		_window_light_tween = null
	_layer_state["night_lights"] = enabled
	var target_blend := 1.0 if enabled else 0.0
	if force or window_lights_fade_seconds <= 0.0:
		_set_window_light_blend(target_blend)
		_set_window_light_visibility(enabled)
	else:
		# Mantiene las capas visibles hasta terminar de desaparecer. Un cambio de
		# hora durante el fundido parte del nivel actual, sin saltos ni tweens solapados.
		_set_window_light_visibility(true)
		_window_light_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Un segundo real; no se alarga con cámara lenta ni con un menú en pausa.
		_window_light_tween.set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_window_light_tween.tween_method(
			_set_window_light_blend, _window_light_blend, target_blend, window_lights_fade_seconds
		)
		_window_light_tween.tween_callback(_set_window_light_visibility.bind(enabled))
	layer_changed.emit("night_lights", enabled)


func _set_window_light_blend(blend: float) -> void:
	_window_light_blend = clampf(blend, 0.0, 1.0)
	# Opacidad por instancia (Forward+): no duplica ni modifica materiales del GLB.
	for geometry: GeometryInstance3D in _window_fade_geometry:
		if is_instance_valid(geometry):
			geometry.transparency = 1.0 - (1.0 - _window_fade_geometry[geometry]) * _window_light_blend
	for light: Light3D in _night_light_energy:
		if is_instance_valid(light):
			light.light_energy = _night_light_energy[light] * _window_light_blend


func _set_window_light_visibility(enabled: bool) -> void:
	for window_root: Node3D in _get_nodes("layer:night_lights", layers["night_lights"], null):
		if is_instance_valid(window_root):
			window_root.visible = enabled
	for light_root: Node3D in _night_light_roots:
		if is_instance_valid(light_root):
			light_root.visible = enabled


func _window_lights_enabled_at(hour: float) -> bool:
	var wrapped_hour := fposmod(hour, 24.0)
	if window_lights_on_hour < window_lights_off_hour:
		return wrapped_hour >= window_lights_on_hour and wrapped_hour < window_lights_off_hour
	if window_lights_on_hour > window_lights_off_hour:
		return wrapped_hour >= window_lights_on_hour or wrapped_hour < window_lights_off_hour
	return false


## Crea (o reutiliza) el controlador de `scene_root` y aplica `state`.
## `state` mezcla capas y grupos: {"snow": true, "night_lights": false, "season": "autumn"}.
## Se puede llamar antes o después de agregar `scene_root` al árbol.
static func attach(scene_root: Node3D, state: Dictionary = {}) -> GlbLayerController:
	var controller := scene_root.get_node_or_null(CONTROLLER_NODE_NAME) as GlbLayerController
	if controller == null:
		controller = GlbLayerController.new()
		controller.target = scene_root
		scene_root.add_child(controller)
		controller.apply_initial_state()
	controller.apply_state(state, true)
	return controller


## Cambia una capa en todos los GLB que tengan controlador dentro del árbol.
static func set_layer_everywhere(tree: SceneTree, layer: String, enabled: bool) -> void:
	tree.call_group(GROUP_NAME, "set_layer", layer, enabled)


## Cambia la variante de un grupo en todos los GLB con controlador.
static func set_variant_everywhere(tree: SceneTree, group: String, variant: String) -> void:
	tree.call_group(GROUP_NAME, "set_variant", group, variant)


## Aplica un estado completo ({"snow": true, "season": "spring"}) a todos los GLB.
## Las claves que un GLB no conoce se ignoran sin avisos.
static func apply_state_everywhere(tree: SceneTree, state: Dictionary) -> void:
	tree.call_group(GROUP_NAME, "apply_state", state)


# --- Capas ----------------------------------------------------------------

func apply_initial_state() -> void:
	_state_applied = true
	apply_state(initial_layers)
	apply_state(initial_variants)


## Aplica capas (valor bool) y grupos (valor String) en una sola llamada.
func apply_state(state: Dictionary, strict: bool = false) -> void:
	for key: Variant in state:
		var key_name := String(key)
		var value: Variant = state[key]
		if layers.has(key_name):
			set_layer(key_name, bool(value))
		elif variant_groups.has(key_name):
			set_variant(key_name, String(value))
		elif strict:
			push_warning(
				"GlbLayerController: '%s' no es una capa ni un grupo de '%s'."
				% [key_name, _describe_target()]
			)


## Muestra u oculta una capa. Con `scope` solo afecta a ese subárbol
## (por ejemplo, una cabaña concreta dentro del GLB del mapa); en ese caso
## no se actualiza el estado global de la capa.
func set_layer(layer: String, enabled: bool, scope: Node = null) -> void:
	if not layers.has(layer):
		push_warning("GlbLayerController: la capa '%s' no existe." % layer)
		return
	var patterns: Array = layers[layer]
	for node: Variant in _get_nodes("layer:" + layer, patterns, scope):
		if is_instance_valid(node):
			(node as Node3D).visible = enabled
	if scope == null:
		_layer_state[layer] = enabled
	layer_changed.emit(layer, enabled)


func toggle_layer(layer: String, scope: Node = null) -> bool:
	var enabled := not is_layer_enabled(layer)
	set_layer(layer, enabled, scope)
	return enabled


## Último estado global aplicado a la capa (false si nunca se aplicó).
func is_layer_enabled(layer: String) -> bool:
	return bool(_layer_state.get(layer, false))


## Indica si el GLB contiene al menos un nodo de esa capa.
func has_layer(layer: String) -> bool:
	if not layers.has(layer):
		return false
	var patterns: Array = layers[layer]
	return not _get_nodes("layer:" + layer, patterns, null).is_empty()


## Deja visible solo `variant` dentro de `group` (por ejemplo "season" -> "autumn").
func set_variant(group: String, variant: String, scope: Node = null) -> void:
	if not variant_groups.has(group):
		push_warning("GlbLayerController: el grupo '%s' no existe." % group)
		return
	var options: Dictionary = variant_groups[group]
	if not options.has(variant):
		push_warning(
			"GlbLayerController: '%s' no es una variante de '%s'. Disponibles: %s"
			% [variant, group, ", ".join(PackedStringArray(options.keys()))]
		)
		return
	for option: Variant in options:
		var option_name := String(option)
		var is_selected := option_name == variant
		var patterns: Array = options[option]
		for node: Variant in _get_nodes("variant:%s/%s" % [group, option_name], patterns, scope):
			if is_instance_valid(node):
				(node as Node3D).visible = is_selected
	if scope == null:
		_variant_state[group] = variant
	variant_changed.emit(group, variant)


func get_variant(group: String) -> String:
	return String(_variant_state.get(group, ""))


func get_variant_options(group: String) -> PackedStringArray:
	if not variant_groups.has(group):
		return PackedStringArray()
	var options: Dictionary = variant_groups[group]
	return PackedStringArray(options.keys())


## Estado global actual (capas y grupos), útil para guardar la partida.
func get_state() -> Dictionary:
	var state := _layer_state.duplicate()
	state.merge(_variant_state)
	return state


## Vuelve a buscar los nodos (si el GLB cambió) y, opcionalmente, reaplica el estado.
func refresh(reapply: bool = true) -> void:
	_node_cache.clear()
	if reapply:
		apply_state(get_state())


# --- Animaciones ----------------------------------------------------------

func get_animation_player() -> AnimationPlayer:
	if animation_player == null or not is_instance_valid(animation_player):
		animation_player = _find_animation_player()
	if animation_player != null:
		_bind_player(animation_player)
	return animation_player


func get_animation_names() -> PackedStringArray:
	var player := get_animation_player()
	if player == null:
		return PackedStringArray()
	return player.get_animation_list()


## Acepta el nombre con o sin sufijo de bucle: "Arbol_Brisa" y "Arbol_Brisa-loop".
func has_animation(animation_name: StringName) -> bool:
	return resolve_animation(animation_name) != &""


func resolve_animation(animation_name: StringName) -> StringName:
	var player := get_animation_player()
	if player == null:
		return &""
	var base_name := String(animation_name)
	var candidates: Array[String] = [base_name]
	for suffix: String in LOOP_SUFFIXES:
		if base_name.ends_with(suffix):
			candidates.append(base_name.trim_suffix(suffix))
		else:
			candidates.append(base_name + suffix)
	for candidate: String in candidates:
		if player.has_animation(candidate):
			return StringName(candidate)
	return &""


## Reproduce una animación con mezcla suave desde la anterior.
## `blend_time` < 0 usa `default_blend_time`. Si ya está sonando y `restart` es
## false, no la reinicia. Devuelve false si no existe o no hay AnimationPlayer.
func play_animation(
	animation_name: StringName,
	blend_time: float = -1.0,
	speed: float = 1.0,
	from_end: bool = false,
	restart: bool = false
) -> bool:
	var player := get_animation_player()
	if player == null:
		push_warning("GlbLayerController: '%s' no tiene AnimationPlayer." % _describe_target())
		return false
	var resolved := resolve_animation(animation_name)
	if resolved == &"":
		push_warning(
			"GlbLayerController: no existe la animación '%s'. Disponibles: %s"
			% [animation_name, ", ".join(player.get_animation_list())]
		)
		return false
	if not restart and player.is_playing() and player.current_animation == String(resolved):
		return true
	_ensure_loop(player, resolved)
	var blend := default_blend_time if blend_time < 0.0 else blend_time
	player.play(resolved, blend, speed, from_end)
	animation_started.emit(resolved)
	return true


## Encola una animación para que arranque cuando termine la actual.
func queue_animation(animation_name: StringName) -> bool:
	var player := get_animation_player()
	var resolved := resolve_animation(animation_name)
	if player == null or resolved == &"":
		return false
	_ensure_loop(player, resolved)
	player.queue(resolved)
	return true


## Detiene la animación. Con `keep_pose` los huesos quedan como estaban.
func stop_animation(keep_pose: bool = true) -> void:
	var player := get_animation_player()
	if player != null:
		player.stop(keep_pose)


func is_animation_playing(animation_name: StringName = &"") -> bool:
	var player := get_animation_player()
	if player == null or not player.is_playing():
		return false
	if animation_name == &"":
		return true
	return player.current_animation == String(resolve_animation(animation_name))


# --- Internos -------------------------------------------------------------

func _get_target() -> Node3D:
	if target == null or not is_instance_valid(target):
		target = get_parent() as Node3D
	return target


func _describe_target() -> String:
	var root_node := _get_target()
	return String(root_node.name) if root_node != null else "(sin escena)"


func _find_animation_player() -> AnimationPlayer:
	var root_node := _get_target()
	if root_node == null:
		return null
	var found := root_node.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


func _bind_player(player: AnimationPlayer) -> void:
	if not player.animation_finished.is_connected(_on_animation_finished):
		player.animation_finished.connect(_on_animation_finished)


func _on_animation_finished(finished_name: StringName) -> void:
	animation_finished.emit(finished_name)


func _ensure_loop(player: AnimationPlayer, resolved: StringName) -> void:
	if not force_loop_on_suffix:
		return
	var lowered := String(resolved).to_lower()
	for suffix: String in LOOP_SUFFIXES:
		if lowered.ends_with(suffix):
			var animation := player.get_animation(resolved)
			if animation != null and animation.loop_mode == Animation.LOOP_NONE:
				animation.loop_mode = Animation.LOOP_LINEAR
			return


func _get_nodes(cache_key: String, patterns: Array, scope: Node) -> Array:
	if not _node_cache.has(cache_key):
		_node_cache[cache_key] = _scan(patterns)
	var all_nodes: Array = _node_cache[cache_key]
	if scope == null:
		return all_nodes
	var scoped: Array = []
	for node: Variant in all_nodes:
		if is_instance_valid(node) and (node == scope or scope.is_ancestor_of(node as Node)):
			scoped.append(node)
	return scoped


func _scan(patterns: Array) -> Array:
	var matches: Array = []
	var root_node := _get_target()
	if root_node == null:
		return matches
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var current: Node = pending.pop_back() as Node
		for child: Node in current.get_children():
			pending.append(child)
		if current == root_node or current is not Node3D:
			continue
		if _name_matches(String(current.name), patterns):
			matches.append(current)
	return matches


func _name_matches(node_name: String, patterns: Array) -> bool:
	var base_name := _strip_numeric_suffix(node_name)
	for pattern: Variant in patterns:
		var text := String(pattern)
		if node_name.matchn(text) or base_name.matchn(text):
			return true
	return false


func _strip_numeric_suffix(node_name: String) -> String:
	var result := _suffix_regex.search(node_name)
	if result == null:
		return node_name
	return result.get_string(1)
