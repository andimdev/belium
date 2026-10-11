extends SceneTree

const SaveManagerScript := preload("res://Scripts/Save/save_manager.gd")
const CONVERSATION_PATH := (
	"res://Resources/Dialogue/Compiled/Conversations/leaftown/"
	+ "0001_Npc001OldManHarry_01Cynthia_ChapterI.res"
)
const INDEX_PATH := "res://Resources/Dialogue/Compiled/Indexes/leaftown.res"
const TEST_SAVE_PATH := "res://codex_dialogue_test_save.json"
const TEST_PRE_SAVE_PATH := "res://codex_dialogue_test_pre_save.json"
const TEST_IDENTITY_PATH := "res://codex_dialogue_test_identity.json"


func _init() -> void:
	var error_message := _validate_compiled_graph()
	if error_message.is_empty():
		error_message = _validate_pre_save_model()
	_cleanup_test_files()
	if not error_message.is_empty():
		push_error("DialogueValidation: %s" % error_message)
		quit(1)
		return
	print("DIALOGUE_SYSTEM_VALIDATED")
	quit()


func _validate_compiled_graph() -> String:
	var conversation := load(CONVERSATION_PATH) as Resource
	if conversation == null:
		return "No se pudo cargar la conversación compilada."
	if StringName(str(conversation.get("character_id"))) != &"01Cynthia":
		return "La conversación no pertenece a 01Cynthia."
	if StringName(str(conversation.get("chapter_id"))) != &"ChapterI":
		return "La conversación no pertenece a ChapterI."
	var checkpoint_entry: StringName = conversation.call(
		"get_story_entry_node", &"I_Content002"
	)
	if checkpoint_entry != &"story_I_Content002_npc":
		return "El checkpoint I_Content002 no resuelve al nodo correcto."
	var first_node: Dictionary = conversation.call(
		"get_node_data", &"first_contact_npc"
	)
	if StringName(str(first_node.get("next_node_id", ""))) != \
			&"first_contact_character":
		return "El primer saludo no encadena la respuesta del personaje."
	var first_reply: Dictionary = conversation.call(
		"get_node_data", &"first_contact_character"
	)
	if StringName(str(first_reply.get("next_node_id", ""))) != \
			&"story_I_Content001_npc":
		return "La Story no comienza después del primer contacto."
	var choice_node: Dictionary = conversation.call(
		"get_node_data", &"story_I_Content002_npc"
	)
	var choices: Array = choice_node.get("choices", [])
	if choices.size() != 3:
		return "I_Content002 no contiene sus tres choices."
	var checkpoint_effects: Array = choice_node.get("effects", [])
	if checkpoint_effects.is_empty() or str(
		(checkpoint_effects[0] as Dictionary).get("type", "")
	) != "set_story_checkpoint":
		return "I_Content002 no registra checkpointDialogueId."
	var rejection: Dictionary = conversation.call(
		"get_node_data", &"branch_I_Content002_I_Content005_npc"
	)
	var rejection_effects: Array = rejection.get("effects", [])
	if rejection_effects.is_empty():
		return "I_Content005 no resuelve reward=false."
	var rejection_effect := rejection_effects[0] as Dictionary
	if str(rejection_effect.get("type", "")) != "resolve_story_reward":
		return "I_Content005 usa un efecto incorrecto."
	if bool(rejection_effect.get("value", true)):
		return "I_Content005 no conserva reward=false."
	var index := load(INDEX_PATH) as Resource
	if index == null:
		return "No se pudo cargar el índice de leaftown."
	var resolved_path := str(index.call(
		"find_conversation_path",
		&"Npc001OldManHarry",
		&"01Cynthia",
		&"ChapterI"
	))
	if resolved_path != CONVERSATION_PATH:
		return "El índice no discrimina NPC, personaje y capítulo."
	var random_entry: StringName = conversation.call("get_random_entry_node")
	if random_entry != &"random_I_Random001_npc":
		return "El diálogo random compilado no está disponible."
	var random_node: Dictionary = conversation.call(
		"get_node_data", random_entry
	)
	if not str(random_node.get("text", "")).contains("girasoles"):
		return "El contenido del diálogo random no coincide con el JSON."
	return ""


func _validate_pre_save_model() -> String:
	var manager := SaveManagerScript.new()
	manager._save_path = TEST_SAVE_PATH
	manager._pre_save_path = TEST_PRE_SAVE_PATH
	manager._identity_path = TEST_IDENTITY_PATH
	manager._active_save_data = {
		# Reproduce un slot anterior a dialogue_progress para validar la migración.
		"save_version": 1,
		"player_id": "00000000-0000-4000-8000-000000000000",
		"progress": {
			"chapter": "Prólogo",
			"play_time_seconds": 0,
			"medals": 0,
			"pokedex_seen": 0,
			"current_map": "map_test",
			"player_position": {"x": 20.0, "y": 20.0},
		},
	}
	if not manager.update_pre_save_context(&"leaftown", &"map_test", &"town"):
		return "No se creó el pre-save al actualizar área."
	if not FileAccess.file_exists(TEST_PRE_SAVE_PATH):
		return "El pre-save no se persistió en disco."
	if not manager.record_npc_contact(
		&"leaftown",
		&"01Cynthia",
		&"Npc001OldManHarry",
		&"ChapterI",
		&"leaftown.Npc001OldManHarry.01Cynthia.ChapterI"
	):
		return "No se registró el primer contacto."
	if not manager.has_npc_contact(
		&"leaftown", &"01Cynthia", &"Npc001OldManHarry"
	):
		return "El primer contacto no se puede consultar."
	manager.set_story_checkpoint(
		&"leaftown",
		&"01Cynthia",
		&"Npc001OldManHarry",
		&"ChapterI",
		&"I_Content002"
	)
	if manager.get_story_checkpoint(
		&"leaftown", &"01Cynthia", &"Npc001OldManHarry", &"ChapterI"
	) != &"I_Content002":
		return "El checkpoint no persistió."
	var pending: Dictionary = manager.get_story_reward_state(
		&"leaftown", &"01Cynthia", &"Npc001OldManHarry", &"ChapterI"
	)
	if bool(pending.has_value):
		return "reward ausente dejó de ser un estado pendiente."
	manager.resolve_story_reward(
		&"leaftown",
		&"01Cynthia",
		&"Npc001OldManHarry",
		&"ChapterI",
		false
	)
	var rejected: Dictionary = manager.get_story_reward_state(
		&"leaftown", &"01Cynthia", &"Npc001OldManHarry", &"ChapterI"
	)
	if not bool(rejected.has_value) or bool(rejected.value):
		return "reward=false no se conservó como resultado terminal."
	# Un segundo personaje y otro capítulo deben mantener estados independientes.
	manager.record_npc_contact(
		&"leaftown", &"02Belium", &"Npc001OldManHarry", &"ChapterII", &"test"
	)
	manager.resolve_story_reward(
		&"leaftown",
		&"02Belium",
		&"Npc001OldManHarry",
		&"ChapterII",
		true
	)
	var other_result: Dictionary = manager.get_story_reward_state(
		&"leaftown", &"02Belium", &"Npc001OldManHarry", &"ChapterII"
	)
	if not bool(other_result.has_value) or not bool(other_result.value):
		return "El estado no distingue personaje y capítulo."
	var untouched: Dictionary = manager.get_story_reward_state(
		&"leaftown", &"02Belium", &"Npc001OldManHarry", &"ChapterI"
	)
	if bool(untouched.has_value):
		return "El resultado se filtró entre capítulos."
	var saved: Dictionary = manager.save_progress({
		"player_position": {"x": 80.0, "y": 100.0}
	})
	if saved.is_empty() or FileAccess.file_exists(TEST_PRE_SAVE_PATH):
		return "Guardar no consolidó y eliminó el pre-save."
	var saved_progress: Dictionary = saved.get("progress", {})
	var dialogue_progress: Dictionary = saved_progress.get("dialogue_progress", {})
	if not (dialogue_progress.get("areas", {}) as Dictionary).has("leaftown"):
		return "El guardado definitivo perdió el progreso narrativo."
	manager.free()
	return ""


func _cleanup_test_files() -> void:
	for path in [
		TEST_SAVE_PATH,
		TEST_SAVE_PATH + ".tmp",
		TEST_SAVE_PATH + ".backup",
		TEST_PRE_SAVE_PATH,
		TEST_PRE_SAVE_PATH + ".tmp",
		TEST_PRE_SAVE_PATH + ".backup",
		TEST_IDENTITY_PATH,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
