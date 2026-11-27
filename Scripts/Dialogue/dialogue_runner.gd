class_name DialogueRunner
extends Node

signal conversation_started(conversation_id: StringName)
signal speaker_changed(character_id: StringName, display_name: String)
signal effects_requested(effects: Array, conversation_id: StringName)
signal conversation_finished(conversation_id: StringName, completed: bool)

@export_node_path("Control") var panel_path: NodePath

@onready var _panel: DialoguePanel = get_node(panel_path) as DialoguePanel

var _conversation: Resource
var _conversation_id: StringName
var _current_node: Dictionary = {}
var _current_choices: Array = []
var _current_effects_committed := false
var _active := false


func _ready() -> void:
	_panel.visible = false
	_panel.option_selected.connect(_on_option_selected)


func start(
		conversation: Resource,
		requested_entry_node_id: StringName = &"") -> bool:
	if conversation == null or not conversation.has_method("get_node_data"):
		return false
	var entry_node_id := requested_entry_node_id
	if entry_node_id.is_empty():
		entry_node_id = StringName(str(conversation.get("entry_node_id")))
	if entry_node_id.is_empty():
		return false

	_conversation = conversation
	_conversation_id = StringName(str(conversation.get("conversation_id")))
	_active = true
	_panel.visible = true
	if not _show_node(entry_node_id):
		cancel()
		return false
	conversation_started.emit(_conversation_id)
	return true


func advance() -> void:
	if not _active:
		return
	if _panel.is_revealing_dialogue():
		_panel.finish_dialogue_reveal()
		return
	if not _current_choices.is_empty():
		_panel.activate_selected_option()
		return

	_commit_current_node_effects()
	var next_node_id := StringName(str(_current_node.get("next_node_id", "")))
	if next_node_id.is_empty():
		_finish(true)
		return
	if not _show_node(next_node_id):
		push_warning(
			"DialogueRunner: no existe el nodo %s en %s."
			% [next_node_id, _conversation_id]
		)
		_finish(false)


func cancel() -> void:
	if not _active:
		return
	_finish(false)


func is_active() -> bool:
	return _active


func has_choices() -> bool:
	return not _current_choices.is_empty()


func _show_node(node_id: StringName) -> bool:
	var node_value: Variant = _conversation.call("get_node_data", node_id)
	if node_value is not Dictionary or node_value.is_empty():
		return false
	_current_node = (node_value as Dictionary).duplicate(true)
	_current_effects_committed = false

	var speaker_id := StringName(str(_current_node.get("speaker_id", "")))
	var profile := _conversation.call("get_speaker_profile", speaker_id) as Resource
	var display_name := str(speaker_id)
	var dialogue_color := Color("20242b")
	if profile != null:
		display_name = str(profile.get("display_name"))
		var color_value: Variant = profile.get("dialogue_color")
		if color_value is Color:
			dialogue_color = color_value
	var playable_id := StringName(str(_conversation.get("character_id")))
	var is_playable_character := not speaker_id.is_empty() and speaker_id == playable_id
	_panel.set_speaker(display_name, dialogue_color, is_playable_character)
	speaker_changed.emit(speaker_id, display_name)

	_current_choices = _current_node.get("choices", []).duplicate(true)
	var choice_labels: Array[String] = []
	for choice_value: Variant in _current_choices:
		if choice_value is Dictionary:
			choice_labels.append(str((choice_value as Dictionary).get("text", "")))
	_panel.set_dialogue_options(choice_labels)
	_panel.set_dialogue_text(str(_current_node.get("text", "")), true)
	return true


func _on_option_selected(index: int, _option_text: String) -> void:
	if not _active or index < 0 or index >= _current_choices.size():
		return
	if _panel.is_revealing_dialogue():
		_panel.finish_dialogue_reveal()
		return
	var choice_value: Variant = _current_choices[index]
	if choice_value is not Dictionary:
		return
	var choice := choice_value as Dictionary
	_commit_current_node_effects()
	_request_effects(choice.get("effects", []))
	var next_node_id := StringName(str(choice.get("next_node_id", "")))
	if next_node_id.is_empty():
		_finish(true)
	elif not _show_node(next_node_id):
		_finish(false)


func _commit_current_node_effects() -> void:
	if _current_effects_committed:
		return
	_current_effects_committed = true
	_request_effects(_current_node.get("effects", []))


func _request_effects(value: Variant) -> void:
	if value is not Array or value.is_empty():
		return
	effects_requested.emit((value as Array).duplicate(true), _conversation_id)


func _finish(completed: bool) -> void:
	var finished_id := _conversation_id
	_panel.visible = false
	_panel.set_dialogue_options([])
	_active = false
	_conversation = null
	_conversation_id = &""
	_current_node.clear()
	_current_choices.clear()
	_current_effects_committed = false
	conversation_finished.emit(finished_id, completed)
