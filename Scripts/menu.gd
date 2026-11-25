class_name OverworldMenu
extends Control

signal option_activated(option_id: StringName)
signal close_requested

const MONTH_NAMES: Array[String] = [
	"enero", "febrero", "marzo", "abril", "mayo", "junio",
	"julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
]

## Tiempo jugado. Ya no se muestra en el panel de tiempo (ahora va la hora del
## juego), pero se conserva por si otra pantalla lo necesita.
@export_range(0.0, 359999.0, 1.0) var play_time_seconds := 0.0

@onready var _menu_grid: GridContainer = $MenuCenter/MenuGrid
@onready var _description_label: Label = \
	$DescriptionPanel/DescriptionContent/DescriptionMargin/Description
@onready var _description_icon: TextureRect = \
	$DescriptionPanel/DescriptionContent/DescriptionIcon
@onready var _time_value: Label = $TimePanel/TimeContent/TimeValue
@onready var _date_value: Label = $TimePanel/TimeContent/DateValue
@onready var _gui_click: AudioStreamPlayer = $GUI_Click

var _options: Array[MainMenuOption] = []
var _selected_option: MainMenuOption


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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


## Muestra la hora del juego (HH:MM:SS) y debajo el día y el mes, sin el año.
func set_game_clock(hour: int, minute: int, second: int, day: int, month: int) -> void:
	if not is_instance_valid(_time_value) or not is_instance_valid(_date_value):
		return
	_time_value.text = "%02d:%02d:%02d" % [hour, minute, second]
	_date_value.text = "%d de %s" % [day, MONTH_NAMES[clampi(month, 1, 12) - 1]]


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
	_description_icon.texture = option.icon_texture


func _on_option_selected(option: MainMenuOption) -> void:
	_select_option(option)


func _on_option_activated(option_id: StringName) -> void:
	_gui_click.play()
	option_activated.emit(option_id)

