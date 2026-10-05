class_name OverworldUIRoot
extends CanvasLayer

signal menu_visibility_changed(is_open: bool)

const MENU_MUSIC_VOLUME_FACTOR := 0.50

## Raíz persistente de la interfaz del mapa. Los elementos que se agreguen a
## Interface permanecen en coordenadas de pantalla, independientes de la
## posición y el zoom de la cámara del mundo.

@export_range(0.0, 2.0, 0.05) var location_enter_duration := 0.45
@export_range(0.0, 10.0, 0.1) var location_visible_duration := 3.0
@export_range(0.0, 2.0, 0.05) var location_exit_duration := 0.4
@export var location_screen_margin := Vector2(25.0, 25.0)

@onready var _location_tooltip: Control = $Interface/TooltipPlace
@onready var _location_label: Label = \
	$Interface/TooltipPlace/TooltipPanel/ContentMargin/Label
@onready var _menu: OverworldMenu = $Interface/Menu

var _environment: Node
var _player: Node
var _save_manager: Node
var _location_tween: Tween
var _last_zone_id: StringName
var _menu_open := false
var _time_refresh_elapsed := 0.0
var _map_music_bus_index := -1
var _map_music_restore_volume_db := 0.0
var _music_bus_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_location_tooltip.visible = false
	_menu.visible = false
	_menu.close_requested.connect(_close_menu)
	_menu.option_activated.connect(_on_menu_option_activated)
	_save_manager = get_node_or_null("/root/SaveManager")
	_map_music_bus_index = AudioServer.get_bus_index(&"Map_Music")
	_environment = get_parent()
	if _environment == null or not _environment.has_signal(
		&"active_camera_zone_changed"
	):
		push_warning("UIRoot: el mapa no publica cambios de región.")
	else:
		_environment.active_camera_zone_changed.connect(
			_on_active_camera_zone_changed
		)
	# La raíz del mapa termina de calcular la región inicial después que sus
	# hijos ejecutan _ready(). Esta llamada diferida también cubre mapas que ya
	# tenían una región activa antes de que se añadiera el UIRoot.
	_sync_initial_location.call_deferred()
	_initialize_map_bindings.call_deferred()


func _process(delta: float) -> void:
	if not _menu_open or not is_instance_valid(_save_manager):
		return
	_time_refresh_elapsed += delta
	if _time_refresh_elapsed < 0.2:
		return
	_time_refresh_elapsed = 0.0
	if _save_manager.has_method("get_play_time_seconds"):
		_menu.set_play_time(_save_manager.call("get_play_time_seconds"))


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var physical_key := key_event.physical_keycode
	if physical_key == 0:
		physical_key = key_event.keycode

	if _menu_open:
		if physical_key in [KEY_Z, KEY_ESCAPE]:
			_close_menu()
			get_viewport().set_input_as_handled()
		elif physical_key == KEY_F:
			_menu.activate_selected_option()
			get_viewport().set_input_as_handled()
		return

	if physical_key in [KEY_ENTER, KEY_KP_ENTER, KEY_F]:
		_open_menu()
		get_viewport().set_input_as_handled()


func show_location(location_name: String) -> void:
	if location_name.is_empty():
		return

	if is_instance_valid(_location_tween):
		_location_tween.kill()

	_location_label.text = location_name
	_location_tooltip.visible = true
	_location_tooltip.modulate.a = 0.0
	_location_tooltip.position = _get_hidden_location_position()

	_location_tween = create_tween()
	_location_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_location_tween.tween_property(
		_location_tooltip,
		"position",
		location_screen_margin,
		location_enter_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_location_tween.parallel().tween_property(
		_location_tooltip,
		"modulate:a",
		1.0,
		location_enter_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_location_tween.tween_interval(location_visible_duration)
	_location_tween.tween_property(
		_location_tooltip,
		"position",
		_get_hidden_location_position(),
		location_exit_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_location_tween.parallel().tween_property(
		_location_tooltip,
		"modulate:a",
		0.0,
		location_exit_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_location_tween.finished.connect(_on_location_animation_finished)


func _sync_initial_location() -> void:
	if not is_instance_valid(_environment):
		return
	if not _environment.has_method("get_active_camera_zone_id"):
		return
	var zone_id: StringName = _environment.get_active_camera_zone_id()
	var display_name := ""
	if _environment.has_method("get_active_camera_zone_display_name"):
		display_name = _environment.get_active_camera_zone_display_name()
	_on_active_camera_zone_changed(zone_id, display_name)


func _initialize_map_bindings() -> void:
	if is_instance_valid(_environment) and _environment.has_method("get_player"):
		_player = _environment.call("get_player")
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"get_play_time_seconds"
	):
		_menu.set_play_time(_save_manager.call("get_play_time_seconds"))


func _on_active_camera_zone_changed(
	zone_id: StringName,
	display_name: String
) -> void:
	if zone_id == _last_zone_id:
		return
	_last_zone_id = zone_id
	# Salir momentáneamente de una región limpia el identificador anterior.
	# Así, volver a entrar a esa misma región vuelve a mostrar su nombre.
	if zone_id.is_empty() or display_name.is_empty():
		return
	show_location(display_name)


func _get_hidden_location_position() -> Vector2:
	return Vector2(
		location_screen_margin.x,
		-_location_tooltip.size.y - 12.0
	)


func _on_location_animation_finished() -> void:
	_location_tween = null
	_location_tooltip.visible = false


func _open_menu() -> void:
	if _menu_open:
		return
	_menu_open = true
	_time_refresh_elapsed = 0.0
	if is_instance_valid(_player) and _player.has_method("set_movement_locked"):
		_player.call("set_movement_locked", true)
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"get_play_time_seconds"
	):
		_menu.set_play_time(_save_manager.call("get_play_time_seconds"))
	_menu.visible = true
	_menu.focus_default_option()
	_set_map_music_ducked(true)
	menu_visibility_changed.emit(true)


func _close_menu() -> void:
	if not _menu_open:
		return
	_menu_open = false
	_menu.visible = false
	if is_instance_valid(_player) and _player.has_method("set_movement_locked"):
		_player.call("set_movement_locked", false)
	_set_map_music_ducked(false)
	menu_visibility_changed.emit(false)


func _on_menu_option_activated(option_id: StringName) -> void:
	if option_id != &"save":
		return
	if not is_instance_valid(_environment) or not _environment.has_method(
		"save_current_game"
	):
		_menu.show_status_message("No se pudo acceder al sistema de guardado.")
		return
	var saved: Variant = _environment.call("save_current_game")
	if saved is Dictionary and not saved.is_empty():
		_menu.show_status_message("Partida guardada correctamente.")
	else:
		_menu.show_status_message("No se pudo guardar la partida.")


func _set_map_music_ducked(ducked: bool) -> void:
	if _map_music_bus_index < 0:
		return
	if is_instance_valid(_music_bus_tween):
		_music_bus_tween.kill()
	var current_volume := AudioServer.get_bus_volume_db(_map_music_bus_index)
	var target_volume: float
	if ducked:
		_map_music_restore_volume_db = current_volume
		target_volume = current_volume + linear_to_db(MENU_MUSIC_VOLUME_FACTOR)
	else:
		target_volume = _map_music_restore_volume_db
	_music_bus_tween = create_tween()
	_music_bus_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_bus_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_music_bus_tween.tween_method(
		_set_map_music_bus_volume,
		current_volume,
		target_volume,
		0.2
	)


func _set_map_music_bus_volume(volume_db: float) -> void:
	if _map_music_bus_index >= 0:
		AudioServer.set_bus_volume_db(_map_music_bus_index, volume_db)


func _exit_tree() -> void:
	if _menu_open and _map_music_bus_index >= 0:
		AudioServer.set_bus_volume_db(
			_map_music_bus_index,
			_map_music_restore_volume_db
		)
