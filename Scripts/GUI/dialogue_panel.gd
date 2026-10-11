class_name DialoguePanel
extends Control

signal option_focused(index: int, option_text: String)
signal option_selected(index: int, option_text: String)
signal dialogue_reveal_finished

const TextFormat := preload("res://Scripts/Dialogue/dialogue_text_format.gd")

@export_range(1.0, 240.0, 1.0) var characters_per_second := 36.0
@export_range(1.0, 12.0, 0.5) var fast_forward_multiplier := 4.0
@export var location_text_color := TextFormat.LOCATION_COLOR
@export var character_text_color := TextFormat.CHARACTER_COLOR
@export var playable_speaker_color := Color("28839c")
@export var npc_speaker_color := Color("986030")

@onready var dialogue_label: RichTextLabel = \
	$MainDialogue/ContentMargin/DialogueContent/DialogueText
@onready var _speaker_name_label: RichTextLabel = \
	$MainDialogue/ContentMargin/DialogueContent/SpeakerName
@onready var _more_indicator: Label = \
	$MainDialogue/ContentMargin/DialogueContent/MoreIndicator
@onready var _dialogue_content: Control = \
	$MainDialogue/ContentMargin/DialogueContent
@onready var _main_dialogue: PanelContainer = $MainDialogue
@onready var _main_inner_border: Panel = $MainDialogue/InnerBorder
@onready var _side_panel: PanelContainer = $SidePanel
@onready var _options_scroll: ScrollContainer = \
	$SidePanel/ContentMargin/Layout/OptionsScroll
@onready var _options_container: VBoxContainer = \
	$SidePanel/ContentMargin/Layout/OptionsScroll/Options
@onready var _speaker_text_offset_top := dialogue_label.offset_top

var _option_buttons: Array[Button] = []
var _option_labels: Array[RichTextLabel] = []
var _option_texts: Array[String] = []
var _selection_cursors: Array[Label] = []
var _selected_index := -1
var _full_dialogue_text := ""
var _full_wrapped_lines: Array[String] = []
var _dialogue_pages: Array[String] = []
var _page_formats: Array[Dictionary] = []
var _current_page_text := ""
var _current_page_index := 0
var _reveal_progress := 0.0
var _revealed_character_count := -1
var _is_revealing := false
var _waiting_for_page_advance := false
var _main_panel_style: StyleBoxFlat
var _main_inner_style: StyleBoxFlat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TextFormat.configure_label(
		dialogue_label, dialogue_label.get_theme_font("normal_font"),
		dialogue_label.get_theme_font_size("normal_font_size")
	)
	TextFormat.configure_label(
		_speaker_name_label, _speaker_name_label.get_theme_font("normal_font"),
		_speaker_name_label.get_theme_font_size("normal_font_size")
	)
	_speaker_name_label.add_theme_color_override("default_color", npc_speaker_color)
	_prepare_speaker_styles()
	_collect_options()
	_configure_focus_navigation()
	_dialogue_content.resized.connect(_on_dialogue_content_resized)
	_start_initial_dialogue.call_deferred()
	focus_default_option.call_deferred()


func _process(delta: float) -> void:
	if not visible or not _is_revealing or _waiting_for_page_advance:
		return
	var speed_multiplier := 1.0
	if (
		Input.is_key_pressed(KEY_Z)
		or Input.is_key_pressed(KEY_SHIFT)
	):
		speed_multiplier = fast_forward_multiplier
	_reveal_progress = minf(
		_reveal_progress + characters_per_second * speed_multiplier * delta,
		float(_current_page_text.length())
	)
	var character_count := floori(_reveal_progress)
	if character_count != _revealed_character_count:
		_revealed_character_count = character_count
		_update_visible_dialogue()
	if character_count >= _current_page_text.length():
		_complete_current_page()


func focus_default_option() -> void:
	if _option_buttons.is_empty():
		return
	_select_option(0)
	_option_buttons[0].grab_focus()


func set_speaker(display_name: String, dialogue_color: Color, is_playable_character: bool = false) -> void:
	var name_runs := TextFormat.parse(display_name)
	# En el encabezado manda el rol de quien habla, incluso si su nombre trae
	# asteriscos. Las menciones dentro del cuerpo conservan su formato habitual.
	for run in name_runs:
		run["kind"] = ""
	_speaker_name_label.text = TextFormat.to_bbcode(name_runs)
	_speaker_name_label.add_theme_color_override(
		"default_color", playable_speaker_color if is_playable_character else npc_speaker_color
	)
	var has_speaker := not TextFormat.plain_text(name_runs).is_empty()
	_speaker_name_label.visible = has_speaker
	# Sin hablante se recupera el espacio del encabezado. La alineación vertical
	# centra la página completa en el panel, sin desplazarla durante el revelado.
	dialogue_label.offset_top = _speaker_text_offset_top if has_speaker else 0.0
	dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _main_panel_style != null:
		_main_panel_style.border_color = dialogue_color
	if _main_inner_style != null:
		_main_inner_style.border_color = dialogue_color.lightened(0.58)


func set_dialogue_options(option_labels: Array[String]) -> void:
	_selected_index = -1
	for index in _option_buttons.size():
		var row := _option_buttons[index].get_parent() as Control
		var should_show := index < option_labels.size()
		row.visible = should_show
		_selection_cursors[index].visible = false
		if should_show:
			_set_option_text(index, option_labels[index])
	_side_panel.visible = not option_labels.is_empty()
	if option_labels.is_empty():
		get_viewport().gui_release_focus()
	else:
		focus_default_option.call_deferred()


func activate_selected_option() -> void:
	if _selected_index < 0 or _selected_index >= _option_buttons.size():
		return
	_option_buttons[_selected_index].emit_signal(&"pressed")


func is_revealing_dialogue() -> bool:
	return _is_revealing


func set_dialogue_text(text: String, animate: bool = true) -> void:
	_full_dialogue_text = text
	_rebuild_wrapped_dialogue()
	_current_page_index = 0
	if _dialogue_pages.is_empty():
		_current_page_text = ""
		_reveal_progress = 0.0
		_revealed_character_count = 0
		_is_revealing = false
		_waiting_for_page_advance = false
		dialogue_label.text = ""
		_more_indicator.visible = false
		return
	_start_dialogue_page(0, animate)


func finish_dialogue_reveal() -> void:
	if _dialogue_pages.is_empty() or not _is_revealing:
		return
	if _waiting_for_page_advance:
		_start_dialogue_page(_current_page_index + 1, true)
		return
	_complete_current_page()


func is_waiting_for_page_advance() -> bool:
	return _waiting_for_page_advance


func get_dialogue_page_index() -> int:
	return _current_page_index


func get_dialogue_page_count() -> int:
	return _dialogue_pages.size()


func get_selected_option_index() -> int:
	return _selected_index


func _collect_options() -> void:
	_option_buttons.clear()
	_option_labels.clear()
	_option_texts.clear()
	_selection_cursors.clear()
	for row in _options_container.get_children():
		var button := row.get_node_or_null("OptionButton") as Button
		var cursor := row.get_node_or_null("SelectionCursor") as Label
		if button == null or cursor == null:
			continue
		var index := _option_buttons.size()
		_option_buttons.append(button)
		_selection_cursors.append(cursor)
		var formatted_label := RichTextLabel.new()
		formatted_label.name = "FormattedText"
		button.add_child(formatted_label)
		formatted_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		formatted_label.offset_left = 8.0
		formatted_label.offset_right = -8.0
		formatted_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		TextFormat.configure_label(formatted_label, button.get_theme_font("font"), button.get_theme_font_size("font_size"))
		formatted_label.add_theme_color_override("default_color", button.get_theme_color("font_color"))
		_option_labels.append(formatted_label)
		_option_texts.append("")
		_set_option_text(index, button.text)
		button.text = ""
		button.focus_entered.connect(_select_option.bind(index))
		button.mouse_entered.connect(_on_option_mouse_entered.bind(button, index))
		button.pressed.connect(_activate_option.bind(index))
		cursor.visible = false


func _set_option_text(index: int, text: String) -> void:
	_option_texts[index] = text
	_option_labels[index].text = TextFormat.to_bbcode(TextFormat.parse(text), location_text_color, character_text_color)
	_option_buttons[index].tooltip_text = TextFormat.plain_text(TextFormat.parse(text))


func _prepare_speaker_styles() -> void:
	var panel_style := _main_dialogue.get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		_main_panel_style = panel_style.duplicate() as StyleBoxFlat
		_main_dialogue.add_theme_stylebox_override("panel", _main_panel_style)
	var inner_style := _main_inner_border.get_theme_stylebox("panel")
	if inner_style is StyleBoxFlat:
		_main_inner_style = inner_style.duplicate() as StyleBoxFlat
		_main_inner_border.add_theme_stylebox_override("panel", _main_inner_style)


func _configure_focus_navigation() -> void:
	if _option_buttons.is_empty():
		return
	for index in _option_buttons.size():
		var previous := _option_buttons[posmod(index - 1, _option_buttons.size())]
		var next := _option_buttons[(index + 1) % _option_buttons.size()]
		var button := _option_buttons[index]
		button.focus_neighbor_top = previous.get_path()
		button.focus_neighbor_left = previous.get_path()
		button.focus_neighbor_bottom = next.get_path()
		button.focus_neighbor_right = next.get_path()
		button.focus_previous = previous.get_path()
		button.focus_next = next.get_path()


func _select_option(index: int) -> void:
	if index < 0 or index >= _option_buttons.size():
		return
	if _selected_index == index:
		return
	_selected_index = index
	for cursor_index in _selection_cursors.size():
		_selection_cursors[cursor_index].visible = cursor_index == index
	_options_scroll.ensure_control_visible(
		_option_buttons[index].get_parent() as Control
	)
	option_focused.emit(index, _option_texts[index])


func _on_option_mouse_entered(button: Button, index: int) -> void:
	_select_option(index)
	button.grab_focus()


func _activate_option(index: int) -> void:
	_select_option(index)
	option_selected.emit(index, _option_texts[index])


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _selected_index < 0:
		return
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var physical_key := key_event.physical_keycode
	if physical_key == 0:
		physical_key = key_event.keycode
	if physical_key == KEY_F:
		_option_buttons[_selected_index].emit_signal(&"pressed")
		get_viewport().set_input_as_handled()


func _start_initial_dialogue() -> void:
	set_dialogue_text(dialogue_label.text, true)


func _on_dialogue_content_resized() -> void:
	if _full_dialogue_text.is_empty():
		return
	var previous_page_index := _current_page_index
	var was_waiting := _waiting_for_page_advance
	var was_finished := not _is_revealing
	_rebuild_wrapped_dialogue()
	if _dialogue_pages.is_empty():
		return
	_current_page_index = mini(previous_page_index, _dialogue_pages.size() - 1)
	_current_page_text = _dialogue_pages[_current_page_index]
	_render_current_page()
	if was_waiting or was_finished:
		_reveal_progress = float(_current_page_text.length())
		_revealed_character_count = _current_page_text.length()
		_update_visible_dialogue()
		_waiting_for_page_advance = (
			_current_page_index < _dialogue_pages.size() - 1
		)
		_is_revealing = _waiting_for_page_advance
	else:
		_reveal_progress = minf(
			_reveal_progress,
			float(_current_page_text.length())
		)
		_revealed_character_count = floori(_reveal_progress)
		_update_visible_dialogue()


func _rebuild_wrapped_dialogue() -> void:
	var runs := TextFormat.parse(_full_dialogue_text)
	var plain := TextFormat.plain_text(runs)
	_full_wrapped_lines.clear()
	_dialogue_pages.clear()
	_page_formats.clear()
	if plain.is_empty():
		return
	# Medir con el mismo motor y las mismas fuentes que se usan para dibujar
	# permite partir una cita larga sin perder su cursiva ni contar las marcas.
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.visible_characters = -1
	dialogue_label.text = TextFormat.to_bbcode(runs, location_text_color, character_text_color)
	var ranges: Array[Vector2i] = []
	for line_index in dialogue_label.get_line_count():
		ranges.append(dialogue_label.get_line_range(line_index))
	var page_runs: Array[Dictionary] = []
	for line_index in ranges.size():
		var bounds := ranges[line_index]
		# RichTextLabel puede incluir su fin de párrafo virtual en el último rango.
		bounds.x = clampi(bounds.x, 0, plain.length())
		bounds.y = clampi(bounds.y, bounds.x, plain.length())
		# La nueva línea separa páginas/filas, pero no crea una tercera fila vacía.
		while bounds.y > bounds.x and plain[bounds.y - 1] in "\n\r":
			bounds.y -= 1
		_full_wrapped_lines.append(plain.substr(bounds.x, bounds.y - bounds.x))
		if line_index % 2 == 1:
			TextFormat.append_run(page_runs, "\n")
		for run in TextFormat.slice(runs, bounds.x, bounds.y):
			TextFormat.append_run(page_runs, run.text, run.kind, run.italic)
		if line_index % 2 == 1 or line_index == ranges.size() - 1:
			_dialogue_pages.append(TextFormat.plain_text(page_runs))
			_page_formats.append({"runs": page_runs})
			page_runs = []
	# Cada página ya contiene sus dos líneas exactas; el revelado no las mueve.
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_OFF


func _render_current_page() -> void:
	dialogue_label.text = TextFormat.to_bbcode(
		_page_formats[_current_page_index].runs, location_text_color, character_text_color
	)


func _start_dialogue_page(page_index: int, animate: bool) -> void:
	_current_page_index = clampi(page_index, 0, _dialogue_pages.size() - 1)
	_current_page_text = _dialogue_pages[_current_page_index]
	_render_current_page()
	_reveal_progress = 0.0 if animate else float(_current_page_text.length())
	_revealed_character_count = -1
	_waiting_for_page_advance = false
	_is_revealing = animate
	_update_visible_dialogue()
	if not animate:
		_complete_current_page()


func _complete_current_page() -> void:
	_reveal_progress = float(_current_page_text.length())
	_revealed_character_count = _current_page_text.length()
	_update_visible_dialogue()
	var has_more_pages := _current_page_index < _dialogue_pages.size() - 1
	_waiting_for_page_advance = has_more_pages
	_is_revealing = has_more_pages
	_more_indicator.visible = has_more_pages
	if not has_more_pages:
		dialogue_reveal_finished.emit()


func _update_visible_dialogue() -> void:
	var safe_count := clampi(
		_revealed_character_count,
		0,
		_current_page_text.length()
	)
	dialogue_label.visible_characters = safe_count
	_more_indicator.visible = _current_page_index < _dialogue_pages.size() - 1
