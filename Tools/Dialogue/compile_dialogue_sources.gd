extends SceneTree

const SpeakerProfileResource := preload(
	"res://Scripts/Dialogue/dialogue_speaker_profile.gd"
)
const ConversationResource := preload(
	"res://Scripts/Dialogue/dialogue_conversation.gd"
)
const AreaIndexResource := preload(
	"res://Scripts/Dialogue/dialogue_area_index.gd"
)

const SOURCE_DIRECTORY := "res://Dialogues"
const OUTPUT_ROOT := "res://Resources/Dialogue/Compiled"
const CHARACTER_OUTPUT_DIRECTORY := OUTPUT_ROOT + "/Characters"
const CONVERSATION_OUTPUT_DIRECTORY := OUTPUT_ROOT + "/Conversations"
const INDEX_OUTPUT_DIRECTORY := OUTPUT_ROOT + "/Indexes"
const OBJECT_OUTPUT_DIRECTORY := OUTPUT_ROOT + "/Objects"

var _source_documents: Array[Dictionary] = []
var _object_documents: Array[Dictionary] = []
var _object_entries: Dictionary = {}
var _object_ids: Dictionary = {}
var _object_dialogue_ids: Dictionary = {}
var _documents_by_key: Dictionary = {}
var _profile_paths: Dictionary = {}
var _area_entries: Dictionary = {}
var _generated_paths: Dictionary = {}


func _init() -> void:
	call_deferred("_compile")


func _compile() -> void:
	var error_message := _ensure_output_directories()
	if error_message.is_empty():
		error_message = _load_source_documents()
	if error_message.is_empty():
		error_message = _compile_character_profiles()
	if error_message.is_empty():
		error_message = _compile_conversations()
	if error_message.is_empty():
		error_message = _compile_object_conversations()
	if error_message.is_empty():
		error_message = _compile_area_indexes()
	if error_message.is_empty():
		error_message = _remove_stale_generated_resources(OUTPUT_ROOT)
	if not error_message.is_empty():
		push_error("DialogueCompiler: %s" % error_message)
		quit(1)
		return
	print("DIALOGUE_RESOURCES_COMPILED")
	quit()


func _ensure_output_directories() -> String:
	for path in [
		CHARACTER_OUTPUT_DIRECTORY,
		CONVERSATION_OUTPUT_DIRECTORY,
		INDEX_OUTPUT_DIRECTORY,
		OBJECT_OUTPUT_DIRECTORY,
	]:
		if DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(path)
		) != OK:
			return "No se pudo crear el directorio %s." % path
	return ""


func _load_source_documents() -> String:
	var directory := DirAccess.open(ProjectSettings.globalize_path(SOURCE_DIRECTORY))
	if directory == null:
		return "No se pudo abrir %s." % SOURCE_DIRECTORY
	var filenames := directory.get_files()
	filenames.sort()
	for filename in filenames:
		if filename.get_extension().to_lower() != "json":
			continue
		var metadata := _parse_source_filename(filename)
		if metadata.is_empty():
			return "%s no cumple [número]_[actorId]_[área].json." % filename
		var data := _read_json_dictionary("%s/%s" % [SOURCE_DIRECTORY, filename])
		if data.is_empty():
			return "No se pudo leer %s." % filename
		if not data.has("npcId") and not data.has("characterId"):
			var object_error := _load_object_document(data, metadata, filename)
			if not object_error.is_empty():
				return object_error
			continue
		var actor_id := _get_actor_id(data)
		if actor_id.is_empty():
			return "%s no contiene npcId ni characterId." % filename
		if actor_id != StringName(metadata.actor_id):
			return "El ID interno de %s no coincide con su nombre de archivo." % filename
		data["_source_filename"] = filename
		data["_dialogue_number"] = metadata.dialogue_number
		data["_place_id"] = metadata.place_id
		var document_key := _document_key(
			metadata.dialogue_number,
			metadata.place_id,
			str(actor_id)
		)
		if _documents_by_key.has(document_key):
			return "Hay una fuente duplicada para %s." % document_key
		_documents_by_key[document_key] = data
		_source_documents.append(data)
	return "" if not _source_documents.is_empty() or not _object_documents.is_empty() else "No hay diálogos JSON."


func _load_object_document(data: Dictionary, metadata: Dictionary, filename: String) -> String:
	for object_key: String in data:
		if not _is_safe_identifier(object_key):
			return "%s: ID de objeto inválido: %s." % [filename, object_key]
		var value: Variant = data[object_key]
		if value is not Dictionary:
			return "%s.%s debe contener un objeto con dialogueId y text." % [filename, object_key]
		var entry := value as Dictionary
		if entry.get("dialogueId") is not String or not _is_safe_identifier(entry.dialogueId):
			return "%s.%s necesita un dialogueId válido." % [filename, object_key]
		if entry.get("text") is not String or str(entry.text).strip_edges().is_empty():
			return "%s.%s necesita text no vacío." % [filename, object_key]
		var object_scope := "%s|%s" % [metadata.place_id, object_key]
		var dialogue_scope := "%s|%s" % [metadata.place_id, entry.dialogueId]
		if _object_ids.has(object_scope):
			return "%s: objeto duplicado en el mismo placeId: %s." % [filename, object_key]
		if _object_dialogue_ids.has(dialogue_scope):
			return "%s: dialogueId de objeto duplicado en el mismo placeId: %s." % [filename, entry.dialogueId]
		_object_ids[object_scope] = true
		_object_dialogue_ids[dialogue_scope] = true
	_object_documents.append({"metadata": metadata, "entries": data})
	return ""


func _is_safe_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true


func _compile_character_profiles() -> String:
	for document in _source_documents:
		var actor_id := _get_actor_id(document)
		if _profile_paths.has(actor_id):
			continue
		var profile: Resource = SpeakerProfileResource.new()
		profile.set("character_id", actor_id)
		profile.set("display_name", _get_display_name(document, actor_id))
		profile.set(
			"appearance_description",
			str(document.get("appearanceDescription", ""))
		)
		var fallback_color := "#65584A" if document.has("npcId") else "#20242B"
		profile.set(
			"dialogue_color",
			Color.from_string(
				str(document.get("dialogueColor", fallback_color)),
				Color.from_string(fallback_color, Color("20242b"))
			)
		)
		var output_path := "%s/%s.res" % [
			CHARACTER_OUTPUT_DIRECTORY,
			str(actor_id),
		]
		if ResourceSaver.save(profile, output_path, ResourceSaver.FLAG_COMPRESS) != OK:
			return "No se pudo guardar %s." % output_path
		_profile_paths[actor_id] = output_path
		_generated_paths[output_path] = true
	return ""


func _compile_conversations() -> String:
	var conversation_count := 0
	for npc_document in _source_documents:
		if not npc_document.has("npcId"):
			continue
		var dialogs_value: Variant = npc_document.get("dialogs", {})
		if dialogs_value is not Dictionary:
			return "%s.dialogs debe ser un objeto." % npc_document._source_filename
		var dialogs := dialogs_value as Dictionary
		for chapter_value: Variant in dialogs:
			var chapter_id := str(chapter_value)
			var chapter_value_data: Variant = dialogs[chapter_value]
			if chapter_value_data is not Dictionary:
				return "%s.%s debe ser un objeto." % [
					npc_document._source_filename, chapter_id
				]
			var chapter_data := chapter_value_data as Dictionary
			for character_value: Variant in chapter_data:
				var character_id := str(character_value)
				var bundle_value: Variant = chapter_data[character_value]
				if bundle_value is not Dictionary:
					return "%s.%s.%s debe ser un objeto." % [
						npc_document._source_filename, chapter_id, character_id
					]
				var character_document := _find_matching_character(
					npc_document, character_id
				)
				if character_document.is_empty():
					return "No existe el JSON de %s para %s en %s." % [
						character_id,
						npc_document._dialogue_number,
						npc_document._place_id,
					]
				var error_message := _save_conversation(
					npc_document,
					character_document,
					StringName(chapter_id),
					bundle_value as Dictionary
				)
				if not error_message.is_empty():
					return error_message
				conversation_count += 1
	return "" if conversation_count > 0 or not _object_documents.is_empty() else "No se compiló ninguna conversación."


func _compile_object_conversations() -> String:
	for document in _object_documents:
		var metadata: Dictionary = document.metadata
		var place_id := str(metadata.place_id)
		var directory_path := "%s/%s" % [OBJECT_OUTPUT_DIRECTORY, place_id]
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path)) != OK:
			return "No se pudo crear %s." % directory_path
		for object_id: String in document.entries:
			var entry: Dictionary = document.entries[object_id]
			var conversation: Resource = ConversationResource.new()
			conversation.set("dialogue_kind", &"object")
			conversation.set("dialogue_number", str(metadata.dialogue_number))
			conversation.set("place_id", StringName(place_id))
			conversation.set("conversation_id", StringName("%s.object.%s.%s" % [
				place_id, object_id, entry.dialogueId
			]))
			conversation.set("entry_node_id", StringName(entry.dialogueId))
			var nodes: Array[Dictionary] = [
				_node(StringName(entry.dialogueId), &"", str(entry.text), &"")
			]
			conversation.set("nodes", nodes)
			var output_path := "%s/%s_%s_%s.res" % [
				directory_path, metadata.dialogue_number, metadata.actor_id, object_id
			]
			if ResourceSaver.save(conversation, output_path, ResourceSaver.FLAG_COMPRESS) != OK:
				return "No se pudo guardar %s." % output_path
			_generated_paths[output_path] = true
			if not _area_entries.has(place_id):
				var empty_entries: Array[Dictionary] = []
				_area_entries[place_id] = empty_entries
			if not _object_entries.has(place_id):
				var empty_objects: Array[Dictionary] = []
				_object_entries[place_id] = empty_objects
			_object_entries[place_id].append({
				"object_id": object_id,
				"dialogue_id": str(entry.dialogueId),
				"resource_path": output_path,
			})
	return ""


func _save_conversation(
		npc_document: Dictionary,
		character_document: Dictionary,
		chapter_id: StringName,
		bundle: Dictionary) -> String:
	var npc_id := StringName(str(npc_document.npcId))
	var character_id := StringName(str(character_document.characterId))
	var place_id := StringName(str(npc_document._place_id))
	var story_value: Variant = bundle.get("Story", [])
	var random_value: Variant = bundle.get("random", [])
	if not _is_dictionary_array(story_value) or not _is_dictionary_array(random_value):
		return "%s/%s/%s: Story y random deben ser arrays de objetos." % [
			place_id, chapter_id, character_id
		]
	var story: Array[Dictionary] = _dictionary_array(story_value)
	var random_dialogues: Array[Dictionary] = _dictionary_array(random_value)
	var npc_response_block: Variant = character_document.get(str(npc_id), {})
	if npc_response_block is not Dictionary:
		return "%s no contiene el bloque %s." % [
			character_document._source_filename, npc_id
		]
	var response_block := npc_response_block as Dictionary
	var responses_value: Variant = response_block.get("responses", {})
	if responses_value is not Dictionary:
		return "%s.responses debe ser un objeto." % character_document._source_filename
	var character_responses := responses_value as Dictionary
	var nodes: Array[Dictionary] = []
	var story_node_map: Dictionary = {}
	var validation_error := _validate_story(story)
	if not validation_error.is_empty():
		return "%s: %s" % [npc_document._source_filename, validation_error]
	validation_error = _validate_random_dialogues(random_dialogues, story)
	if not validation_error.is_empty():
		return "%s: %s" % [npc_document._source_filename, validation_error]
	for story_entry in story:
		var source_id := str(story_entry.get("dialogueId", ""))
		story_node_map[source_id] = _story_npc_node_id(source_id)
	var story_entry_id := &""
	if not story.is_empty():
		story_entry_id = StringName(str(story_node_map[story[0].dialogueId]))
	var context := {
		"area_id": str(place_id),
		"character_id": str(character_id),
		"npc_id": str(npc_id),
		"chapter_id": str(chapter_id),
	}
	var first_contact_entry := _compile_first_contact(
		npc_document,
		response_block,
		npc_id,
		character_id,
		story_entry_id,
		nodes
	)
	_compile_story_nodes(
		story,
		story_node_map,
		character_responses,
		npc_id,
		character_id,
		context,
		nodes
	)
	var random_entry_ids := _compile_random_nodes(
		random_dialogues,
		character_responses,
		npc_id,
		character_id,
		nodes
	)
	var conversation: Resource = ConversationResource.new()
	conversation.set("schema_version", 2)
	conversation.set("dialogue_number", str(npc_document._dialogue_number))
	conversation.set("npc_id", npc_id)
	conversation.set("character_id", character_id)
	conversation.set("place_id", place_id)
	conversation.set("chapter_id", chapter_id)
	conversation.set("dialogue_kind", &"story_bundle")
	conversation.set("conversation_id", StringName("%s.%s.%s.%s" % [
		place_id, npc_id, character_id, chapter_id
	]))
	conversation.set("first_contact_entry_node_id", first_contact_entry)
	conversation.set("story_entry_node_id", story_entry_id)
	conversation.set("entry_node_id", first_contact_entry)
	conversation.set("story_dialogue_nodes", story_node_map)
	conversation.set("random_entry_node_ids", random_entry_ids)
	conversation.set("nodes", nodes)
	var profiles: Array[Resource] = []
	for participant_id in [npc_id, character_id]:
		var profile := load(str(_profile_paths.get(participant_id, ""))) as Resource
		if profile == null:
			return "No se pudo cargar el perfil %s." % participant_id
		profiles.append(profile)
	conversation.set("speaker_profiles", profiles)
	var area_directory := "%s/%s" % [CONVERSATION_OUTPUT_DIRECTORY, place_id]
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(area_directory)
	) != OK:
		return "No se pudo crear %s." % area_directory
	var output_path := "%s/%s_%s_%s_%s.res" % [
		area_directory,
		npc_document._dialogue_number,
		npc_id,
		character_id,
		chapter_id,
	]
	if ResourceSaver.save(
		conversation, output_path, ResourceSaver.FLAG_COMPRESS
	) != OK:
		return "No se pudo guardar %s." % output_path
	_generated_paths[output_path] = true
	_add_area_entry(place_id, {
		"dialogue_number": str(npc_document._dialogue_number),
		"npc_id": npc_id,
		"character_id": character_id,
		"chapter_id": chapter_id,
		"resource_path": output_path,
	})
	return ""


func _compile_first_contact(
		npc_document: Dictionary,
		response_block: Dictionary,
		npc_id: StringName,
		character_id: StringName,
		story_entry_id: StringName,
		nodes: Array[Dictionary]) -> StringName:
	var greeting := str(npc_document.get("firstDialogueEver", ""))
	var reply := str(response_block.get(
		"responseFirstDialogueEver",
		response_block.get("reponseFirstDialogueEver", "")
	))
	if greeting.is_empty():
		return story_entry_id
	var first_npc_id := &"first_contact_npc"
	var first_character_id := &"first_contact_character"
	var next_id := first_character_id if not reply.is_empty() else story_entry_id
	nodes.append(_node(first_npc_id, npc_id, greeting, next_id))
	if not reply.is_empty():
		nodes.append(_node(
			first_character_id, character_id, reply, story_entry_id
		))
	return first_npc_id


func _compile_story_nodes(
		story: Array[Dictionary],
		story_node_map: Dictionary,
		character_responses: Dictionary,
		npc_id: StringName,
		character_id: StringName,
		context: Dictionary,
		nodes: Array[Dictionary]) -> void:
	for index in story.size():
		var entry := story[index]
		var source_id := str(entry.dialogueId)
		var npc_node_id := StringName(str(story_node_map[source_id]))
		var continuation := &""
		if index + 1 < story.size():
			continuation = StringName(str(story_node_map[story[index + 1].dialogueId]))
		var effects := _story_effects(entry, context, source_id)
		var choices: Array[Dictionary] = []
		var choices_value: Variant = entry.get("choices", [])
		if choices_value is Array and not choices_value.is_empty():
			var nested_responses: Dictionary = entry.get("responses", {})
			for choice_value: Variant in choices_value:
				var choice := choice_value as Dictionary
				var target_source_id := str(choice.nextDialogueId)
				var target_node_id := _branch_npc_node_id(source_id, target_source_id)
				choices.append({
					"text": str(choice.label),
					"next_node_id": target_node_id,
					"effects": [],
				})
				var nested := nested_responses[target_source_id] as Dictionary
				var nested_effects := _story_effects(
					nested, context, target_source_id
				)
				var closes := bool(nested.get("closeDialogue", false))
				var character_text := str(character_responses.get(target_source_id, ""))
				var nested_next := &"" if closes else continuation
				if not character_text.is_empty():
					var character_node_id := _branch_character_node_id(
						source_id, target_source_id
					)
					nodes.append(_node(
						target_node_id,
						npc_id,
						str(nested.get("dialogue", "")),
						character_node_id,
						[],
						nested_effects
					))
					nodes.append(_node(
						character_node_id,
						character_id,
						character_text,
						nested_next
					))
				else:
					nodes.append(_node(
						target_node_id,
						npc_id,
						str(nested.get("dialogue", "")),
						nested_next,
						[],
						nested_effects
					))
			nodes.append(_node(
				npc_node_id,
				npc_id,
				str(entry.get("dialogue", "")),
				&"",
				choices,
				effects
			))
			continue
		var closes := bool(entry.get("closeDialogue", false))
		var next_id := &"" if closes else continuation
		var character_text := str(character_responses.get(source_id, ""))
		if not character_text.is_empty():
			var character_node_id := _story_character_node_id(source_id)
			nodes.append(_node(
				npc_node_id,
				npc_id,
				str(entry.get("dialogue", "")),
				character_node_id,
				[],
				effects
			))
			nodes.append(_node(
				character_node_id, character_id, character_text, next_id
			))
		else:
			nodes.append(_node(
				npc_node_id,
				npc_id,
				str(entry.get("dialogue", "")),
				next_id,
				[],
				effects
			))


func _compile_random_nodes(
		random_dialogues: Array[Dictionary],
		character_responses: Dictionary,
		npc_id: StringName,
		character_id: StringName,
		nodes: Array[Dictionary]) -> Array[StringName]:
	var entry_ids: Array[StringName] = []
	for index in random_dialogues.size():
		var entry := random_dialogues[index]
		var source_id := str(entry.get("dialogueId", "random_%d" % index))
		var npc_node_id := StringName("random_%s_npc" % source_id)
		entry_ids.append(npc_node_id)
		var response := str(character_responses.get(source_id, ""))
		var next_id := &""
		if not response.is_empty():
			next_id = StringName("random_%s_character" % source_id)
		nodes.append(_node(
			npc_node_id, npc_id, str(entry.get("dialogue", "")), next_id
		))
		if not response.is_empty():
			nodes.append(_node(next_id, character_id, response, &""))
	return entry_ids


func _validate_story(story: Array[Dictionary]) -> String:
	var ids: Dictionary = {}
	for entry in story:
		var dialogue_id := str(entry.get("dialogueId", ""))
		if dialogue_id.is_empty():
			return "Cada diálogo Story necesita dialogueId."
		if ids.has(dialogue_id):
			return "dialogueId duplicado: %s." % dialogue_id
		ids[dialogue_id] = true
		if str(entry.get("dialogue", "")).is_empty():
			return "%s no contiene dialogue." % dialogue_id
		var choices_value: Variant = entry.get("choices", [])
		if choices_value is not Array:
			return "%s.choices debe ser un array." % dialogue_id
		var choices := choices_value as Array
		if choices.size() > 5:
			return "%s excede el máximo de cinco choices." % dialogue_id
		if choices.is_empty():
			continue
		var responses_value: Variant = entry.get("responses", {})
		if responses_value is not Dictionary:
			return "%s.responses debe ser un objeto." % dialogue_id
		var responses := responses_value as Dictionary
		var choice_targets: Dictionary = {}
		for choice_value: Variant in choices:
			if choice_value is not Dictionary:
				return "%s contiene un choice inválido." % dialogue_id
			var choice := choice_value as Dictionary
			var target := str(choice.get("nextDialogueId", ""))
			if target.is_empty() or not responses.has(target):
				return "%s apunta a una response inexistente: %s." % [
					dialogue_id, target
				]
			if choice_targets.has(target):
				return "%s repite el destino %s." % [dialogue_id, target]
			choice_targets[target] = true
	return ""


func _validate_random_dialogues(
		random_dialogues: Array[Dictionary],
		story: Array[Dictionary]) -> String:
	var used_ids: Dictionary = {}
	for story_entry in story:
		used_ids[str(story_entry.get("dialogueId", ""))] = true
	for entry in random_dialogues:
		var dialogue_id := str(entry.get("dialogueId", ""))
		if dialogue_id.is_empty():
			return "Cada diálogo random necesita dialogueId."
		if used_ids.has(dialogue_id):
			return "dialogueId duplicado entre Story/random: %s." % dialogue_id
		if str(entry.get("dialogue", "")).is_empty():
			return "%s no contiene dialogue." % dialogue_id
		used_ids[dialogue_id] = true
	return ""


func _story_effects(
		entry: Dictionary,
		context: Dictionary,
		dialogue_id: String) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	if bool(entry.get("resumeCheckpoint", false)):
		var checkpoint := context.duplicate(true)
		checkpoint["type"] = "set_story_checkpoint"
		checkpoint["dialogue_id"] = dialogue_id
		effects.append(checkpoint)
	if entry.has("reward"):
		var resolution := context.duplicate(true)
		resolution["type"] = "resolve_story_reward"
		resolution["value"] = bool(entry.reward)
		effects.append(resolution)
	return effects


func _node(
		node_id: StringName,
		speaker_id: StringName,
		text: String,
		next_node_id: StringName,
		choices: Array[Dictionary] = [],
		effects: Array[Dictionary] = []) -> Dictionary:
	return {
		"node_id": node_id,
		"speaker_id": speaker_id,
		"text": text,
		"next_node_id": next_node_id,
		"conditions": [],
		"choices": choices,
		"effects": effects,
	}


func _compile_area_indexes() -> String:
	for place_value: Variant in _area_entries:
		var place_id := str(place_value)
		var index: Resource = AreaIndexResource.new()
		index.set("place_id", StringName(place_id))
		var entries: Array[Dictionary] = _area_entries[place_value]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return "%s|%s|%s" % [a.dialogue_number, a.character_id, a.chapter_id] \
				< "%s|%s|%s" % [b.dialogue_number, b.character_id, b.chapter_id]
		)
		index.set("entries", entries)
		var object_entries: Array[Dictionary] = []
		for entry: Dictionary in _object_entries.get(place_id, []):
			object_entries.append(entry)
		index.set("object_entries", object_entries)
		var output_path := "%s/%s.res" % [INDEX_OUTPUT_DIRECTORY, place_id]
		if ResourceSaver.save(index, output_path, ResourceSaver.FLAG_COMPRESS) != OK:
			return "No se pudo guardar %s." % output_path
		_generated_paths[output_path] = true
	return ""


func _remove_stale_generated_resources(directory_path: String) -> String:
	var directory := DirAccess.open(ProjectSettings.globalize_path(directory_path))
	if directory == null:
		return "No se pudo revisar %s para limpiar recursos obsoletos." % directory_path
	for filename in directory.get_files():
		if filename.get_extension().to_lower() != "res":
			continue
		var resource_path := "%s/%s" % [directory_path, filename]
		if _generated_paths.has(resource_path):
			continue
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(resource_path)
		)
		if remove_error != OK:
			return "No se pudo eliminar el recurso obsoleto %s." % resource_path
	for child_directory in directory.get_directories():
		if child_directory.begins_with("."):
			continue
		var error_message := _remove_stale_generated_resources(
			"%s/%s" % [directory_path, child_directory]
		)
		if not error_message.is_empty():
			return error_message
	return ""


func _add_area_entry(place_id: StringName, entry: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var existing: Variant = _area_entries.get(str(place_id), [])
	if existing is Array:
		for value: Variant in existing:
			if value is Dictionary:
				entries.append((value as Dictionary).duplicate(true))
	entries.append(entry)
	_area_entries[str(place_id)] = entries


func _find_matching_character(
		npc_document: Dictionary,
		character_id: String) -> Dictionary:
	var key := _document_key(
		str(npc_document._dialogue_number),
		str(npc_document._place_id),
		character_id
	)
	var value: Variant = _documents_by_key.get(key, {})
	return value as Dictionary if value is Dictionary else {}


func _parse_source_filename(filename: String) -> Dictionary:
	var basename := filename.get_basename()
	var first_separator := basename.find("_")
	if first_separator <= 0:
		return {}
	var second_separator := basename.find("_", first_separator + 1)
	if second_separator <= first_separator + 1:
		return {}
	var dialogue_number := basename.substr(0, first_separator)
	var actor_id := basename.substr(
		first_separator + 1,
		second_separator - first_separator - 1
	)
	var place_id := basename.substr(second_separator + 1)
	if not dialogue_number.is_valid_int() or actor_id.is_empty() or place_id.is_empty():
		return {}
	if not _is_safe_identifier(actor_id) or not _is_safe_identifier(place_id):
		return {}
	return {
		"dialogue_number": dialogue_number,
		"actor_id": actor_id,
		"place_id": place_id,
	}


func _document_key(number: String, place_id: String, actor_id: String) -> String:
	return "%s|%s|%s" % [number, place_id, actor_id]


func _get_actor_id(document: Dictionary) -> StringName:
	return StringName(str(document.get(
		"npcId" if document.has("npcId") else "characterId", ""
	)))


func _get_display_name(document: Dictionary, fallback: StringName) -> String:
	var key := "npcName" if document.has("npcId") else "characterName"
	return str(document.get(key, fallback))


func _is_dictionary_array(value: Variant) -> bool:
	if value is not Array:
		return false
	for item: Variant in value:
		if item is not Dictionary:
			return false
	return true


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in value:
		result.append((item as Dictionary).duplicate(true))
	return result


func _story_npc_node_id(source_id: String) -> StringName:
	return StringName("story_%s_npc" % source_id)


func _story_character_node_id(source_id: String) -> StringName:
	return StringName("story_%s_character" % source_id)


func _branch_npc_node_id(parent_id: String, source_id: String) -> StringName:
	return StringName("branch_%s_%s_npc" % [parent_id, source_id])


func _branch_character_node_id(parent_id: String, source_id: String) -> StringName:
	return StringName("branch_%s_%s_character" % [parent_id, source_id])


func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error("%s:%d: %s" % [
			path, json.get_error_line(), json.get_error_message()
		])
		return {}
	return json.data if json.data is Dictionary else {}
