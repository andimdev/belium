class_name OverworldMenu
extends Control

signal option_activated(option_id: StringName)
signal close_requested

@export_range(0.0, 359999.0, 1.0) var play_time_seconds := 0.0

@onready var _menu_grid: GridContainer = $MenuCenter/MenuGrid
@onready var _description_label: Label = \
	$DescriptionPanel/DescriptionMargin/Description
@onready var _time_value: Label = $TimePanel/TimeContent/TimeValue
@onready var _gui_click: AudioStreamPlayer = $GUI_Click

var _options: Array[MainMenuOption] = []
var _selected_option: MainMenuOption


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_time_label()
	for child in _menu_grid.get_children():
		if child is not MainMenuOption:
			continue
		var option := child as MainMenuOption
		_options.append(option)
		option.selected.connect(_on_option_selected)
		option.activated.connect(_on_option_activated)

	if not _options.is_empty():
		_select_option(_options[0])
		_options[0].icon_button.grab_focus.call_deferred()


func set_play_time(total_seconds: float) -> void:
	play_time_seconds = maxf(total_seconds, 0.0)
	_update_time_label()


func focus_default_option() -> void:
	if _options.is_empty():
		return
	_select_option(_options[0])
	_options[0].icon_button.grab_focus.call_deferred()


func show_status_message(message: String) -> void:
	_description_label.text = message


func activate_selected_option() -> void:
	if is_instance_valid(_selected_option):
		_selected_option.icon_button.emit_signal(&"pressed")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func _select_option(option: MainMenuOption) -> void:
	if _selected_option == option:
		option.set_selected(true)
		return
	if is_instance_valid(_selected_option):
		_selected_option.set_selected(false)
	_selected_option = option
	_selected_option.set_selected(true)
	_description_label.text = option.description


func _on_option_selected(option: MainMenuOption) -> void:
	_select_option(option)


func _on_option_activated(option_id: StringName) -> void:
	_gui_click.play()
	option_activated.emit(option_id)


func _update_time_label() -> void:
	if not is_instance_valid(_time_value):
		return
	var total_minutes := floori(play_time_seconds / 60.0)
	var hours := total_minutes / 60
	var minutes := total_minutes % 60
	var seconds := floori(play_time_seconds) % 60
	_time_value.text = "%02d:%02d:%02d" % [hours, minutes, seconds]
