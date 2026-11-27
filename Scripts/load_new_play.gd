extends Control

signal continue_requested(save_data: Dictionary)
signal options_requested
signal new_game_created(save_data: Dictionary)

## Actívalo en el futuro para comenzar la historia sin mostrar este menú cuando
## todavía no exista una partida. Por ahora debe permanecer desactivado.
@export var auto_start_story_without_menu := false

const DEFAULT_MAP_ID: StringName = &"map_001_3d"
const GUI_CLICK_ACTION_GRACE_SECONDS := 0.15

@onready var continue_button: Button = $MenuCenter/Menu/ContinueButton
@onready var new_game_button: Button = $MenuCenter/Menu/NewGameButton
@onready var options_button: Button = $MenuCenter/Menu/OptionsButton
@onready var exit_button: Button = $MenuCenter/Menu/ExitButton
@onready var chapter_value: Label = $MenuCenter/Menu/ContinueButton/StatsGrid/ChapterValue
@onready var play_time_value: Label = $MenuCenter/Menu/ContinueButton/StatsGrid/PlayTimeValue
@onready var medals_value: Label = $MenuCenter/Menu/ContinueButton/StatsGrid/MedalsValue
@onready var pokedex_value: Label = $MenuCenter/Menu/ContinueButton/StatsGrid/PokedexValue
@onready var status_label: Label = $StatusLabel
@onready var gui_click: AudioStreamPlayer = $GUI_Click

var _save_manager: Node
var _save_data: Dictionary = {}
var _menu_buttons: Array[Button] = []
var _action_in_progress := false


func _ready() -> void:
	_save_manager = get_node_or_null("/root/SaveManager")
	_connect_actions()
	_refresh_save_state()
	_rebuild_focus_navigation()

	if auto_start_story_without_menu and _save_data.is_empty():
		_start_new_game.call_deferred()


func _input(event: InputEvent) -> void:
	if event is not InputEventMouseMotion:
		return

	for button in _menu_buttons:
		if button.visible and button.get_global_rect().has_point(event.position):
			if not button.has_focus():
				button.grab_focus()
			return


func _connect_actions() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_start_new_game)
	options_button.pressed.connect(_on_options_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	for button in [continue_button, new_game_button, options_button, exit_button]:
		button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
		button.mouse_exited.connect(_update_button_selection.bind(button))
		button.focus_entered.connect(_update_button_selection.bind(button))
		button.focus_exited.connect(_update_button_selection.bind(button))


func _refresh_save_state() -> void:
	_save_data = {}
	if _save_manager != null:
		var loaded_data: Variant = _save_manager.call("load_save", false)
		if loaded_data is Dictionary:
			_save_data = loaded_data

	continue_button.visible = not _save_data.is_empty()
	if continue_button.visible:
		_populate_continue_card()


func _populate_continue_card() -> void:
	var progress: Dictionary = _save_data.get("progress", {})
	chapter_value.text = str(progress.get("chapter", "—"))
	play_time_value.text = _format_play_time(int(progress.get("play_time_seconds", 0)))
	medals_value.text = str(maxi(int(progress.get("medals", 0)), 0))
	pokedex_value.text = str(maxi(int(progress.get("pokedex_seen", 0)), 0))


func _format_play_time(total_seconds: int) -> String:
	var safe_seconds := maxi(total_seconds, 0)
	var hours := safe_seconds / 3600
	var minutes := (safe_seconds % 3600) / 60
	var seconds := safe_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]


func _rebuild_focus_navigation() -> void:
	_menu_buttons.clear()
	if continue_button.visible:
		_menu_buttons.append(continue_button)
	_menu_buttons.append_array([new_game_button, options_button, exit_button])

	for index in _menu_buttons.size():
		var button := _menu_buttons[index]
		var previous_button := _menu_buttons[posmod(index - 1, _menu_buttons.size())]
		var next_button := _menu_buttons[(index + 1) % _menu_buttons.size()]
		button.focus_neighbor_top = previous_button.get_path()
		button.focus_neighbor_left = previous_button.get_path()
		button.focus_neighbor_bottom = next_button.get_path()
		button.focus_neighbor_right = next_button.get_path()
		button.focus_previous = previous_button.get_path()
		button.focus_next = next_button.get_path()

	_menu_buttons[0].grab_focus.call_deferred()


func _on_button_mouse_entered(button: Button) -> void:
	button.grab_focus()
	_update_button_selection(button)


func _update_button_selection(button: Button) -> void:
	var selection_stroke := button.get_node_or_null("SelectionStroke") as Control
	if selection_stroke != null:
		selection_stroke.visible = button.has_focus()


func _start_new_game() -> void:
	if _action_in_progress:
		return
	_action_in_progress = true
	_play_gui_click()
	_set_buttons_disabled(true)
	status_label.visible = false

	if _save_manager == null:
		_show_error("El servicio de guardado no está disponible.")
		return

	var result: Variant = _save_manager.call("create_new_game")
	if result is not Dictionary or result.is_empty():
		_show_error("No se pudo crear la partida. Revisa los permisos de guardado.")
		return

	var created_save: Dictionary = result
	new_game_created.emit(created_save.duplicate(true))

	await _wait_for_gui_click_before_scene_change()
	await _load_game_map(created_save)


func _on_continue_pressed() -> void:
	if _action_in_progress:
		return
	_action_in_progress = true
	_play_gui_click()
	_set_buttons_disabled(true)
	status_label.visible = false
	continue_requested.emit(_save_data.duplicate(true))
	await _wait_for_gui_click_before_scene_change()
	await _load_game_map(_save_data)


func _on_options_pressed() -> void:
	_play_gui_click()
	options_requested.emit()
	_show_status("La pantalla de opciones estará disponible próximamente.")


func _on_exit_pressed() -> void:
	if _action_in_progress:
		return
	_action_in_progress = true
	_set_buttons_disabled(true)
	_play_gui_click()
	await _wait_for_gui_click_before_scene_change()
	get_tree().quit()


func _play_gui_click() -> void:
	gui_click.play()


func _wait_for_gui_click_before_scene_change() -> void:
	if not gui_click.playing:
		return
	var grace_seconds := GUI_CLICK_ACTION_GRACE_SECONDS
	if gui_click.stream != null and gui_click.stream.get_length() > 0.0:
		grace_seconds = minf(grace_seconds, gui_click.stream.get_length())
	await get_tree().create_timer(grace_seconds).timeout


func _load_game_map(save_data: Dictionary) -> void:
	var scene_loader := get_node_or_null("/root/SceneLoader")
	if scene_loader == null:
		_show_error("El cargador de escenas no está disponible.")
		return

	var progress: Dictionary = save_data.get("progress", {})
	var map_id := StringName(str(progress.get("current_map", "")))
	var spawn_point := StringName(str(progress.get("spawn_point", "")))
	if map_id.is_empty() or not bool(scene_loader.call("has_scene", map_id)):
		# Partidas guardadas en un mapa que ya no está registrado (p. ej. el 2D):
		# se cargan en el mapa por defecto y en su punto de aparición inicial.
		map_id = DEFAULT_MAP_ID
		spawn_point = &""

	var loaded: Variant = await scene_loader.call("load_map", map_id, spawn_point, {
		"save_data": save_data.duplicate(true),
	}, {
		"transition": &"fade",
		"duration": 0.45,
	})
	if not bool(loaded) and is_inside_tree():
		_show_error("No se pudo cargar el mapa.")


func _set_buttons_disabled(disabled: bool) -> void:
	for button in _menu_buttons:
		button.disabled = disabled


func _show_error(message: String) -> void:
	_action_in_progress = false
	_set_buttons_disabled(false)
	status_label.modulate = Color(1.0, 0.42, 0.42, 1.0)
	status_label.text = message
	status_label.visible = true
	new_game_button.grab_focus()


func _show_status(message: String) -> void:
	status_label.modulate = Color(0.82, 0.82, 0.82, 1.0)
	status_label.text = message
	status_label.visible = true
