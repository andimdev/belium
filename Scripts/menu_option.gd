class_name MainMenuOption
extends Control

signal selected(option: MainMenuOption)
signal activated(option_id: StringName)

@export var option_id: StringName
@export var title := "Opción"
@export_multiline var description := ""
@export var accent_color := Color("#ec2440")
@export var icon_texture: Texture2D

@onready var icon_button: Button = $Content/IconButton
@onready var _icon: TextureRect = $Content/IconButton/Icon
@onready var _title_panel: PanelContainer = $Content/TitlePanel
@onready var _title_label: Label = $Content/TitlePanel/Title
@onready var _selection_arrow: Label = $SelectionArrow

var _is_selected := false
var _rotation_tween: Tween

const SELECTED_ICON_ROTATION := deg_to_rad(45.0)
const ICON_ROTATION_DURATION := 0.28


func _ready() -> void:
	_title_label.text = title
	_icon.texture = icon_texture
	icon_button.tooltip_text = title
	icon_button.focus_entered.connect(_on_focus_entered)
	icon_button.focus_exited.connect(_on_focus_exited)
	icon_button.mouse_entered.connect(icon_button.grab_focus)
	icon_button.pressed.connect(_on_pressed)
	_prepare_visuals()


func set_selected(value: bool) -> void:
	if _is_selected == value:
		return
	_is_selected = value
	_selection_arrow.visible = value
	_title_panel.add_theme_stylebox_override(
		"panel",
		_make_title_style(value)
	)
	_animate_selection(value)


func _prepare_visuals() -> void:
	_icon.pivot_offset = _icon.size * 0.5
	_icon.rotation = SELECTED_ICON_ROTATION if _is_selected else 0.0
	icon_button.add_theme_stylebox_override(
		"normal",
		_make_icon_style(accent_color, false)
	)
	icon_button.add_theme_stylebox_override(
		"hover",
		_make_icon_style(accent_color.lightened(0.08), true)
	)
	icon_button.add_theme_stylebox_override(
		"focus",
		_make_icon_style(accent_color.lightened(0.08), true)
	)
	icon_button.add_theme_stylebox_override(
		"pressed",
		_make_icon_style(accent_color.darkened(0.08), true)
	)
	_title_panel.add_theme_stylebox_override(
		"panel",
		_make_title_style(_is_selected)
	)
	_selection_arrow.visible = _is_selected


func _make_icon_style(color: Color, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 5 if not highlighted else 6
	style.border_width_top = 5 if not highlighted else 6
	style.border_width_right = 5 if not highlighted else 6
	style.border_width_bottom = 5 if not highlighted else 6
	style.border_color = Color(0.96, 0.97, 0.98, 1.0)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18
	style.shadow_color = Color(0.02, 0.02, 0.04, 0.48)
	style.shadow_size = 7 if not highlighted else 10
	style.shadow_offset = Vector2(0.0, 5.0)
	style.anti_aliasing = true
	return style


func _make_title_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#f2253e") if highlighted else Color.TRANSPARENT
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	if highlighted:
		style.shadow_color = Color(0.1, 0.01, 0.03, 0.35)
		style.shadow_size = 4
		style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _animate_selection(value: bool) -> void:
	if is_instance_valid(_rotation_tween):
		_rotation_tween.kill()
	_rotation_tween = create_tween()
	_rotation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_rotation_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_rotation_tween.tween_property(
		_icon,
		"rotation",
		SELECTED_ICON_ROTATION if value else 0.0,
		ICON_ROTATION_DURATION
	)


func _on_focus_entered() -> void:
	selected.emit(self)


func _on_focus_exited() -> void:
	set_selected(false)


func _on_pressed() -> void:
	activated.emit(option_id)
