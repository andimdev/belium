class_name OverworldUIRoot
extends CanvasLayer

signal menu_visibility_changed(is_open: bool)
signal dialogue_visibility_changed(is_open: bool)
signal battle_mode_changed(is_active: bool)
signal battle_command_selected(command_id: StringName)

enum InterfaceMode {
	OVERWORLD,
	MENU,
	DIALOGUE,
	BATTLE,
}

const MENU_MUSIC_VOLUME_FACTOR := 0.50
const DIALOGUE_INDEX_ROOT := "res://Resources/Dialogue/Compiled/Indexes"
const BATTLE_WEATHER_TRANSITION_DURATION := 5.0

## Raíz persistente de la interfaz del mapa. Los elementos que se agreguen a
## Interface permanecen en coordenadas de pantalla, independientes de la
## posición y el zoom de la cámara del mundo.

@export_range(0.0, 2.0, 0.05) var location_enter_duration := 0.45
@export_range(0.0, 10.0, 0.1) var location_visible_duration := 3.0
@export_range(0.0, 2.0, 0.05) var location_exit_duration := 0.4
@export var location_screen_margin := Vector2(25.0, 25.0)
## Reloj del juego (Sky3D TimeOfDay) que muestra el menú. Si se deja vacío, se
## busca un TimeOfDay dentro del mapa, que es el padre de este UIRoot.
@export_node_path("TimeOfDay") var time_of_day_path: NodePath

@onready var _location_tooltip: Control = $Interface/TooltipPlace
@onready var _location_label: Label = \
	$Interface/TooltipPlace/TooltipPanel/ContentMargin/Label
@onready var _menu: OverworldMenu = $Interface/Menu
@onready var _dialogue_runner: DialogueRunner = $DialogueRunner

var _environment: Node
var _time_of_day: TimeOfDay
var _player: Node
var _save_manager: Node
var _location_tween: Tween
var _last_zone_id: StringName
var _menu_open := false
var _time_refresh_elapsed := 0.0
var _map_music_bus_index := -1
var _map_music_restore_volume_db := 0.0
var _music_bus_tween: Tween
var _active_interactable: Node
var _dialogue_area_index: Resource
var _active_dialogue_npc_id: StringName
var _active_dialogue_character_id: StringName
var _active_dialogue_place_id: StringName
var _initial_zone_synced := false
var _interface_mode := InterfaceMode.OVERWORLD
var _world_environment_manager: Node
var _battle_previous_environment_process_mode := Node.PROCESS_MODE_INHERIT
var _battle_previous_player_movement_locked := false
var _battle_previous_map_music_muted := false
var _battle_previous_overworld_suspended := false
var _battle_restore_location_tooltip := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_location_tooltip.visible = false
	_menu.visible = false
	_menu.close_requested.connect(_close_menu)
	_menu.option_activated.connect(_on_menu_option_activated)
	_dialogue_runner.conversation_finished.connect(_on_conversation_finished)
	_dialogue_runner.effects_requested.connect(_on_dialogue_effects_requested)
	_save_manager = get_node_or_null("/root/SaveManager")
	_world_environment_manager = get_node_or_null("/root/WorldEnvironment")
	if (
		is_instance_valid(_world_environment_manager)
		and _world_environment_manager.has_signal(&"weather_changed")
	):
		_world_environment_manager.connect(
			&"weather_changed",
			Callable(self, "_on_world_weather_changed")
		)
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
	_sync_battle_weather.call_deferred(0.0)


func _process(delta: float) -> void:
	if not _menu_open:
		return
	_refresh_menu_clock()
	if not is_instance_valid(_save_manager):
		return
	_time_refresh_elapsed += delta
	if _time_refresh_elapsed < 0.2:
		return
	_time_refresh_elapsed = 0.0
	if _save_manager.has_method("get_play_time_seconds"):
		_menu.set_play_time(_save_manager.call("get_play_time_seconds"))


func get_interface_mode() -> int:
	return _interface_mode


func is_battle_mode_active() -> bool:
	return _interface_mode == InterfaceMode.BATTLE


## Presenta el control 2D para batallas estándar. Un lado admite uno o dos
## Pokémon; los diseños 3v1/4v1 se definirán cuando sus reglas estén cerradas.
func show_battle_screen(
	player_slots: int = 1,
	enemy_slots: int = 1
) -> bool:
	if not enter_battle_mode():
		return false
	return true


## Entra en el estado modal de batalla sin crear todavía la presentación de
## combate. show_battle_screen() coordina este método con la presentación.
## Devuelve false si otra interfaz exclusiva sigue activa o si el mapa aún no
## tiene un jugador válido que pueda bloquearse de forma segura.
func enter_battle_mode() -> bool:
	if is_battle_mode_active():
		return true
	if (
		_interface_mode != InterfaceMode.OVERWORLD
		or _menu_open
		or _dialogue_runner.is_active()
	):
		push_warning(
			"UIRoot: no se puede iniciar una batalla mientras otra interfaz modal está activa."
		)
		return false
	if not is_instance_valid(_environment):
		push_warning("UIRoot: no se puede suspender un mapa inexistente.")
		return false
	if not is_instance_valid(_player) and _environment.has_method("get_player"):
		_player = _environment.call("get_player")
	if (
		not is_instance_valid(_player)
		or not _player.has_method("set_movement_locked")
	):
		push_warning("UIRoot: no se puede iniciar una batalla sin bloquear al jugador.")
		return false

	_battle_previous_player_movement_locked = bool(_player.get("movement_locked"))
	_battle_previous_environment_process_mode = _environment.process_mode
	_battle_previous_map_music_muted = false
	if _map_music_bus_index >= 0:
		_battle_previous_map_music_muted = AudioServer.is_bus_mute(
			_map_music_bus_index
		)
	_battle_previous_overworld_suspended = false
	if (
		is_instance_valid(_world_environment_manager)
		and _world_environment_manager.has_method("is_overworld_suspended")
	):
		_battle_previous_overworld_suspended = bool(
			_world_environment_manager.call("is_overworld_suspended")
		)
	_battle_restore_location_tooltip = _location_tooltip.visible
	_sync_battle_weather(0.0)

	_interface_mode = InterfaceMode.BATTLE
	if is_instance_valid(_location_tween):
		_location_tween.kill()
		_location_tween = null
	_location_tooltip.visible = false
	_player.call("set_movement_locked", true)
	_environment.process_mode = Node.PROCESS_MODE_DISABLED
	if (
		is_instance_valid(_world_environment_manager)
		and _world_environment_manager.has_method("set_overworld_suspended")
	):
		_world_environment_manager.call("set_overworld_suspended", true)
	if _map_music_bus_index >= 0:
		AudioServer.set_bus_mute(_map_music_bus_index, true)
	battle_mode_changed.emit(true)
	return true


## Restaura el estado persistente capturado por enter_battle_mode(). Si había un
## aviso de ubicación visible, vuelve a reproducirlo desde el inicio.
## Es seguro llamar a este método más de una vez.
func exit_battle_mode() -> void:
	_leave_battle_mode(true, true)


func _leave_battle_mode(
	emit_change: bool,
	restore_interface: bool
) -> void:
	if not is_battle_mode_active():
		return

	if is_instance_valid(_environment):
		_environment.process_mode = _battle_previous_environment_process_mode
	if (
		is_instance_valid(_world_environment_manager)
		and _world_environment_manager.has_method("set_overworld_suspended")
	):
		_world_environment_manager.call(
			"set_overworld_suspended",
			_battle_previous_overworld_suspended
		)
	if _map_music_bus_index >= 0:
		AudioServer.set_bus_mute(
			_map_music_bus_index,
			_battle_previous_map_music_muted
		)
	if is_instance_valid(_player) and _player.has_method("set_movement_locked"):
		_player.call(
			"set_movement_locked",
			_battle_previous_player_movement_locked
		)

	_interface_mode = InterfaceMode.OVERWORLD
	if (
		restore_interface
		and _battle_restore_location_tooltip
		and not _location_label.text.is_empty()
	):
		show_location(_location_label.text)
	_battle_restore_location_tooltip = false
	if emit_change:
		battle_mode_changed.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	# BattleScreen será responsable de sus propias acciones. UIRoot sólo evita
	# que una tecla de combate abra a la vez el menú o un diálogo del mapa.
	if is_battle_mode_active():
		return
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var physical_key := key_event.physical_keycode
	if physical_key == 0:
		physical_key = key_event.keycode

	if _dialogue_runner.is_active():
		if physical_key in [KEY_ENTER, KEY_KP_ENTER, KEY_F]:
			_dialogue_runner.advance()
			get_viewport().set_input_as_handled()
		elif physical_key in [KEY_Z, KEY_SHIFT, KEY_ESCAPE]:
			# Z y Shift sólo aceleran la escritura mientras se mantienen pulsadas.
			# Escape se consume para que una conversación no pueda cancelarse.
			get_viewport().set_input_as_handled()
		return

	if _menu_open:
		if physical_key in [KEY_Z, KEY_ESCAPE]:
			_close_menu()
			get_viewport().set_input_as_handled()
		elif physical_key == KEY_F:
			_menu.activate_selected_option()
			get_viewport().set_input_as_handled()
		return

	if physical_key in [KEY_ENTER, KEY_KP_ENTER, KEY_F]:
		if not _try_start_dialogue():
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
	_bind_time_of_day()
	if is_instance_valid(_environment) and _environment.has_method("get_player"):
		_player = _environment.call("get_player")
	if (
		is_instance_valid(_player)
		and _player.has_signal(&"grid_step_completed")
		and not _player.grid_step_completed.is_connected(
			_on_player_grid_step_completed
		)
	):
		_player.grid_step_completed.connect(_on_player_grid_step_completed)
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"get_play_time_seconds"
	):
		_menu.set_play_time(_save_manager.call("get_play_time_seconds"))


func _bind_time_of_day() -> void:
	_time_of_day = get_node_or_null(time_of_day_path) as TimeOfDay
	if _time_of_day == null and is_instance_valid(_environment):
		_time_of_day = _find_time_of_day(_environment)
	if _time_of_day == null:
		push_warning("UIRoot: no se encontró un TimeOfDay; el menú mostrará el reloj del sistema.")


func _find_time_of_day(root: Node) -> TimeOfDay:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is TimeOfDay:
			return current as TimeOfDay
		pending.append_array(current.get_children())
	return null


## Pasa al menú la hora y la fecha del juego. Con Sky3D se lee su TimeOfDay (con
## System Sync activo coincide con el reloj del sistema); sin él, se usa el reloj
## del sistema.
func _refresh_menu_clock() -> void:
	var total_seconds := 0
	var day := 1
	var month := 1
	if is_instance_valid(_time_of_day):
		# current_time es un decimal en horas: 12:15:38 puede reconstruirse como
		# 12:15:37,9999, así que se redondea con 1 ms de margen.
		total_seconds = clampi(floori(_time_of_day.current_time * 3600.0 + 0.001), 0, 86399)
		day = _time_of_day.day
		month = _time_of_day.month
	else:
		var now := Time.get_datetime_dict_from_system()
		total_seconds = int(now.hour) * 3600 + int(now.minute) * 60 + int(now.second)
		day = int(now.day)
		month = int(now.month)
	_menu.set_game_clock(
		total_seconds / 3600,
		(total_seconds % 3600) / 60,
		total_seconds % 60,
		day,
		month
	)


func _on_active_camera_zone_changed(
	zone_id: StringName,
	display_name: String
) -> void:
	if zone_id == _last_zone_id:
		return
	_last_zone_id = zone_id
	_load_dialogue_area_index(zone_id)
	if not zone_id.is_empty():
		if _initial_zone_synced:
			_update_pre_save_location()
		else:
			_initial_zone_synced = true
	# Salir momentáneamente de una región limpia el identificador anterior.
	# Así, volver a entrar a esa misma región vuelve a mostrar su nombre.
	if zone_id.is_empty() or display_name.is_empty():
		return
	show_location(display_name)


func _on_player_grid_step_completed(
		_world_position: Vector2,
		_direction: Vector2) -> void:
	_update_pre_save_location()


func _update_pre_save_location() -> void:
	if (
		not is_instance_valid(_save_manager)
		or not _save_manager.has_method("update_pre_save_context")
		or _last_zone_id.is_empty()
	):
		return
	_save_manager.call(
		"update_pre_save_context",
		_last_zone_id,
		_get_map_id(),
		_get_area_type(_last_zone_id)
	)


func _get_hidden_location_position() -> Vector2:
	return Vector2(
		location_screen_margin.x,
		-_location_tooltip.size.y - 12.0
	)


func _on_location_animation_finished() -> void:
	_location_tween = null
	_location_tooltip.visible = false


func _open_menu() -> void:
	if (
		_interface_mode != InterfaceMode.OVERWORLD
		or _menu_open
		or _dialogue_runner.is_active()
	):
		return
	_menu_open = true
	_interface_mode = InterfaceMode.MENU
	_time_refresh_elapsed = 0.0
	if is_instance_valid(_player) and _player.has_method("set_movement_locked"):
		_player.call("set_movement_locked", true)
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"get_play_time_seconds"
	):
		_menu.set_play_time(_save_manager.call("get_play_time_seconds"))
	_refresh_menu_clock()
	_menu.visible = true
	_menu.focus_default_option()
	_set_map_music_ducked(true)
	menu_visibility_changed.emit(true)


func _close_menu() -> void:
	if not _menu_open:
		return
	_menu_open = false
	_menu.visible = false
	_interface_mode = InterfaceMode.OVERWORLD
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


func _on_battle_command_selected(command_id: StringName) -> void:
	battle_command_selected.emit(command_id)


func _on_world_weather_changed(
	_weather_id: StringName,
	profile: Dictionary
) -> void:
	var duration := 0.0


func _sync_battle_weather(transition_duration: float = 0.0) -> void:
	if (
		not is_instance_valid(_world_environment_manager)
		or not _world_environment_manager.has_method(
			"get_current_weather_profile"
		)
	):
		return
	var profile: Dictionary = _world_environment_manager.call(
		"get_current_weather_profile"
	)


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


func _try_start_dialogue() -> bool:
	if _interface_mode != InterfaceMode.OVERWORLD:
		return false
	if not is_instance_valid(_environment) or not _environment.has_method(
		"get_interactable_in_front"
	):
		return false
	var interactable := _environment.call("get_interactable_in_front") as Node
	if interactable == null:
		return false
	if not is_instance_valid(_player):
		return true
	# Pokémon y futuras interacciones sin panel tienen prioridad sobre la
	# búsqueda de diálogos. La misma pulsación no debe abrir también el menú.
	if interactable.has_method("interact_in_overworld"):
		return bool(interactable.call("interact_in_overworld", _player))
	if interactable.has_method("get_object_id"):
		return _try_start_object_dialogue(interactable)
	if not interactable.has_method("get_npc_id"):
		return false
	var npc_id := StringName(str(interactable.call("get_npc_id")))
	if npc_id.is_empty():
		push_warning(
			"UIRoot: %s fue detectado como interactuable, pero su npc_id está vacío."
			% interactable.get_path()
		)
		return true
	var character_id := StringName(str(_player.get("character_id")))
	var chapter_id := &"ChapterI"
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"get_current_chapter_id"
	):
		chapter_id = StringName(str(_save_manager.call(
			"get_current_chapter_id"
		)))
	var has_first_contact := false
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"has_npc_contact"
	):
		has_first_contact = bool(_save_manager.call(
			"has_npc_contact",
			_last_zone_id,
			character_id,
			npc_id
		))
	var conversation_path := ""
	if _dialogue_area_index != null and _dialogue_area_index.has_method(
		"find_conversation_path"
	):
		conversation_path = str(_dialogue_area_index.call(
			"find_conversation_path",
			npc_id,
			character_id,
			chapter_id
		))
	if conversation_path.is_empty():
		# Hay un NPC enfrente, pero todavía no existe texto para este estado. La
		# interacción se consume para no abrir el menú accidentalmente.
		return true
	var conversation := load(conversation_path) as Resource
	if conversation == null:
		push_warning("UIRoot: no se pudo cargar %s." % conversation_path)
		return true
	var entry_node_id := &""
	var reward_state := {"has_value": false, "value": false}
	if is_instance_valid(_save_manager) and _save_manager.has_method(
		"get_story_reward_state"
	):
		reward_state = _save_manager.call(
			"get_story_reward_state",
			_last_zone_id,
			character_id,
			npc_id,
			chapter_id
		)
	if bool(reward_state.get("has_value", false)):
		if conversation.has_method("get_random_entry_node"):
			entry_node_id = conversation.call("get_random_entry_node")
	elif not has_first_contact:
		entry_node_id = StringName(str(conversation.get(
			"first_contact_entry_node_id"
		)))
	else:
		var checkpoint_id := &""
		if is_instance_valid(_save_manager) and _save_manager.has_method(
			"get_story_checkpoint"
		):
			checkpoint_id = StringName(str(_save_manager.call(
				"get_story_checkpoint",
				_last_zone_id,
				character_id,
				npc_id,
				chapter_id
			)))
		if conversation.has_method("get_story_entry_node"):
			entry_node_id = conversation.call(
				"get_story_entry_node", checkpoint_id
			)
	if entry_node_id.is_empty():
		# El estado está resuelto y todavía no hay diálogos random para este NPC.
		return true
	if (
		not has_first_contact
		and is_instance_valid(_save_manager)
		and _save_manager.has_method("record_npc_contact")
	):
		_save_manager.call(
			"record_npc_contact",
			_last_zone_id,
			character_id,
			npc_id,
			chapter_id,
			StringName(str(conversation.get("conversation_id"))),
			_get_map_id(),
			_get_area_type(_last_zone_id)
		)

	_active_interactable = interactable
	_active_dialogue_npc_id = npc_id
	_active_dialogue_character_id = character_id
	_active_dialogue_place_id = _last_zone_id
	if is_instance_valid(_player) and _player.has_method("set_movement_locked"):
		_player.call("set_movement_locked", true)
	if interactable.has_method("set_interaction_locked"):
		interactable.call("set_interaction_locked", true)
	if interactable.has_method("face_toward") and is_instance_valid(_player):
		interactable.call("face_toward", _player.global_position)
	if is_instance_valid(_player) and _player.has_method("face_toward"):
		_player.call("face_toward", interactable.global_position)

	if not _dialogue_runner.start(conversation, entry_node_id):
		_release_dialogue_characters()
		return false
	_interface_mode = InterfaceMode.DIALOGUE
	dialogue_visibility_changed.emit(true)
	return true


func _try_start_object_dialogue(interactable: Node) -> bool:
	var object_id := StringName(str(interactable.call("get_object_id")))
	var place_id := StringName(str(interactable.call("get_dialogue_place_id")))
	if place_id.is_empty():
		place_id = _last_zone_id
	var index: Resource = _dialogue_area_index if place_id == _last_zone_id else null
	if index == null and not place_id.is_empty():
		var index_path := "%s/%s.res" % [DIALOGUE_INDEX_ROOT, place_id]
		if ResourceLoader.exists(index_path):
			index = load(index_path) as Resource
	var conversation_path := ""
	if index != null and index.has_method("find_object_conversation_path"):
		conversation_path = str(index.call("find_object_conversation_path", object_id))
	if conversation_path.is_empty():
		push_warning("UIRoot: no hay texto compilado para el objeto '%s' en '%s' (%s)." % [
			object_id, place_id, interactable.get_path()
		])
		# Se consume la lectura para que un ID mal configurado no abra el menú.
		return true
	var conversation := load(conversation_path) as Resource
	if conversation == null:
		push_warning("UIRoot: no se pudo cargar %s." % conversation_path)
		return true
	_active_interactable = interactable
	_active_dialogue_npc_id = &""
	_active_dialogue_character_id = &""
	_active_dialogue_place_id = place_id
	if _player.has_method("set_movement_locked"):
		_player.call("set_movement_locked", true)
	if not _dialogue_runner.start(conversation):
		_release_dialogue_characters()
		return true
	_interface_mode = InterfaceMode.DIALOGUE
	dialogue_visibility_changed.emit(true)
	return true


func _on_conversation_finished(
	conversation_id: StringName,
	completed: bool
) -> void:
	if completed and not _active_dialogue_npc_id.is_empty() and is_instance_valid(_save_manager):
		if _save_manager.has_method("record_dialogue_completed"):
			_save_manager.call("record_dialogue_completed", conversation_id)
	_release_dialogue_characters()
	if _interface_mode == InterfaceMode.DIALOGUE:
		_interface_mode = InterfaceMode.OVERWORLD
	dialogue_visibility_changed.emit(false)


func _on_dialogue_effects_requested(
	effects: Array,
	conversation_id: StringName
) -> void:
	if not is_instance_valid(_save_manager):
		return
	if _save_manager.has_method("apply_dialogue_effects"):
		_save_manager.call("apply_dialogue_effects", effects, conversation_id)


func _release_dialogue_characters() -> void:
	if is_instance_valid(_active_interactable) and _active_interactable.has_method(
		"set_interaction_locked"
	):
		_active_interactable.call("set_interaction_locked", false)
	_active_interactable = null
	_active_dialogue_npc_id = &""
	_active_dialogue_character_id = &""
	_active_dialogue_place_id = &""
	if is_instance_valid(_player) and _player.has_method("set_movement_locked"):
		_player.call("set_movement_locked", false)


func _load_dialogue_area_index(place_id: StringName) -> void:
	_dialogue_area_index = null
	if place_id.is_empty():
		return
	var index_path := "%s/%s.res" % [DIALOGUE_INDEX_ROOT, place_id]
	if not ResourceLoader.exists(index_path):
		return
	_dialogue_area_index = load(index_path) as Resource


func _get_map_id() -> StringName:
	if not is_instance_valid(_environment):
		return &""
	return StringName(str(_environment.get("map_id")))


func _get_area_type(area_id: StringName) -> StringName:
	var normalized := str(area_id).to_lower()
	if normalized.begins_with("route_") or normalized.begins_with("ruta_"):
		return &"route"
	if normalized.ends_with("town") or normalized.begins_with("town_"):
		return &"town"
	if normalized.ends_with("city") or normalized.begins_with("city_"):
		return &"city"
	if normalized.contains("sea") or normalized.contains("mar"):
		return &"sea"
	return &"area"


func _exit_tree() -> void:
	_leave_battle_mode(false, false)
	if _dialogue_runner.is_active():
		_release_dialogue_characters()
	if _menu_open and _map_music_bus_index >= 0:
		AudioServer.set_bus_volume_db(
			_map_music_bus_index,
			_map_music_restore_volume_db
		)
