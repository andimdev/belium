extends Node

## El guardado real sólo se reemplaza al elegir Guardar. Durante la sesión, el
## progreso narrativo vive en un pre-save persistido en disco que funciona como
## copia de trabajo del slot.

signal save_created(save_data: Dictionary)
signal save_loaded(save_data: Dictionary)
signal save_updated(save_data: Dictionary)
signal save_failed(reason: String)
signal pre_save_updated(pre_save_data: Dictionary)
signal pre_save_cleared

const SAVE_DIRECTORY := "user://Saved"
const IDENTITY_PATH := SAVE_DIRECTORY + "/player_identity.json"
const SAVE_PATH := SAVE_DIRECTORY + "/save_slot_1.json"
const PRE_SAVE_PATH := SAVE_DIRECTORY + "/pre_save_slot_1.json"
const SAVE_VERSION := 2
const DEFAULT_MAP_ID := "map_001_3d"
const DEFAULT_CHAPTER_ID := "ChapterI"

var _active_save_data: Dictionary = {}
var _pre_save_data: Dictionary = {}
var _identity_path := IDENTITY_PATH
var _save_path := SAVE_PATH
var _pre_save_path := PRE_SAVE_PATH
var _play_time_seconds := 0.0
var _tracking_play_time := false
var _session_initialized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _tracking_play_time:
		_play_time_seconds += delta


func has_save() -> bool:
	return not load_save(false).is_empty()


func load_save(emit_signal: bool = true) -> Dictionary:
	var identity := _read_json(_identity_path)
	var save_data := _read_json(_save_path)
	if not _is_valid_identity(identity) or not _is_valid_save(save_data):
		return {}
	if save_data.get("player_id", "") != identity.get("player_id", ""):
		push_warning("SaveManager: el guardado no pertenece a la identidad local actual.")
		return {}
	save_data = _normalize_save_types(save_data)
	_active_save_data = save_data.duplicate(true)
	if emit_signal:
		save_loaded.emit(save_data.duplicate(true))
	return save_data


func create_new_game() -> Dictionary:
	if not _ensure_save_directory():
		_fail("No se pudo crear la carpeta de guardado.")
		return {}
	_clear_pre_save(true)
	var identity := _read_json(_identity_path)
	if not _is_valid_identity(identity):
		identity = _create_identity()
		if identity.is_empty() or not _write_json_atomic(_identity_path, identity):
			_fail("No se pudo crear la identidad local del jugador.")
			return {}
	var timestamp := Time.get_datetime_string_from_system(true, true)
	var save_data: Dictionary = {
		"save_version": SAVE_VERSION,
		"player_id": identity.player_id,
		"created_at_utc": timestamp,
		"updated_at_utc": timestamp,
		"progress": {
			"chapter": "Prólogo",
			"chapter_id": DEFAULT_CHAPTER_ID,
			"play_time_seconds": 0,
			"medals": 0,
			"pokedex_seen": 0,
			"current_map": DEFAULT_MAP_ID,
			"current_area": {},
			"spawn_point": "",
			"player_position": {},
			"story_flags": {},
			"dialogue_history": {},
			"dialogue_progress": {"areas": {}},
		},
	}
	if not _write_json_atomic(_save_path, save_data):
		_fail("No se pudo escribir la nueva partida.")
		return {}
	_active_save_data = save_data.duplicate(true)
	_play_time_seconds = 0.0
	_tracking_play_time = false
	_session_initialized = false
	save_created.emit(save_data.duplicate(true))
	return save_data


func start_play_session(save_data: Dictionary = {}) -> void:
	if _tracking_play_time:
		return
	var session_data := save_data.duplicate(true)
	if session_data.is_empty():
		session_data = _active_save_data.duplicate(true)
	if session_data.is_empty():
		session_data = load_save(false)
	if session_data.is_empty() or not _is_valid_save(session_data):
		return
	_active_save_data = _normalize_save_types(session_data)
	if not _session_initialized:
		# Por ahora un pre-save de otra ejecución no se recupera como autosave.
		_clear_pre_save(true)
		_session_initialized = true
	var progress: Dictionary = _active_save_data.get("progress", {})
	_play_time_seconds = maxf(float(progress.get("play_time_seconds", 0)), 0.0)
	_tracking_play_time = true


func stop_play_session() -> void:
	_tracking_play_time = false


func get_play_time_seconds() -> int:
	return maxi(floori(_play_time_seconds), 0)


func get_current_chapter_id() -> StringName:
	var progress: Dictionary = _get_runtime_data().get("progress", {})
	return StringName(str(progress.get("chapter_id", DEFAULT_CHAPTER_ID)))


func get_active_save() -> Dictionary:
	return _get_runtime_data().duplicate(true)


func update_pre_save_context(
		area_id: StringName,
		map_id: StringName,
		area_type: StringName = &"") -> bool:
	var already_existed := not _pre_save_data.is_empty()
	if not _prepare_pre_save():
		return false
	if already_existed and _pre_save_context_matches(area_id, map_id, area_type):
		return true
	_set_pre_save_context(area_id, map_id, area_type)
	return _persist_pre_save()


func has_npc_contact(
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName) -> bool:
	if area_id.is_empty() or character_id.is_empty() or npc_id.is_empty():
		return false
	var npc_state := _get_npc_progress(
		_get_runtime_data(), area_id, character_id, npc_id
	)
	return bool(npc_state.get("interacted", false))


func record_npc_contact(
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName,
		chapter_id: StringName,
		conversation_id: StringName,
		map_id: StringName = &"",
		area_type: StringName = &"") -> bool:
	if area_id.is_empty() or character_id.is_empty() or npc_id.is_empty():
		return false
	if not _prepare_pre_save():
		return false
	_set_pre_save_context(area_id, map_id, area_type)
	var npc_state := _get_npc_progress(
		_pre_save_data, area_id, character_id, npc_id
	)
	if not bool(npc_state.get("interacted", false)):
		npc_state["interacted"] = true
		npc_state["first_interaction_at_utc"] = \
			Time.get_datetime_string_from_system(true, true)
	if not conversation_id.is_empty():
		npc_state["first_conversation_id"] = str(conversation_id)
	_ensure_chapter_state(npc_state, chapter_id)
	_set_npc_progress(_pre_save_data, area_id, character_id, npc_id, npc_state)
	return _persist_pre_save()


func get_story_checkpoint(
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName,
		chapter_id: StringName) -> StringName:
	var npc_state := _get_npc_progress(
		_get_runtime_data(), area_id, character_id, npc_id
	)
	var chapter_state := _get_chapter_state(npc_state, chapter_id)
	return StringName(str(chapter_state.get("checkpointDialogueId", "")))


func set_story_checkpoint(
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName,
		chapter_id: StringName,
		dialogue_id: StringName) -> bool:
	if dialogue_id.is_empty() or not _prepare_pre_save():
		return false
	var npc_state := _get_npc_progress(
		_pre_save_data, area_id, character_id, npc_id
	)
	var chapter_state := _get_chapter_state(npc_state, chapter_id)
	chapter_state["checkpointDialogueId"] = str(dialogue_id)
	_set_chapter_state(npc_state, chapter_id, chapter_state)
	_set_npc_progress(_pre_save_data, area_id, character_id, npc_id, npc_state)
	return _persist_pre_save()


func get_story_reward_state(
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName,
		chapter_id: StringName) -> Dictionary:
	var npc_state := _get_npc_progress(
		_get_runtime_data(), area_id, character_id, npc_id
	)
	var chapter_state := _get_chapter_state(npc_state, chapter_id)
	if not chapter_state.has("reward"):
		return {"has_value": false, "value": false}
	return {"has_value": true, "value": bool(chapter_state.reward)}


func resolve_story_reward(
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName,
		chapter_id: StringName,
		value: bool) -> bool:
	if not _prepare_pre_save():
		return false
	var npc_state := _get_npc_progress(
		_pre_save_data, area_id, character_id, npc_id
	)
	var chapter_state := _get_chapter_state(npc_state, chapter_id)
	chapter_state["reward"] = value
	chapter_state.erase("checkpointDialogueId")
	chapter_state["resolved_at_utc"] = \
		Time.get_datetime_string_from_system(true, true)
	_set_chapter_state(npc_state, chapter_id, chapter_state)
	_set_npc_progress(_pre_save_data, area_id, character_id, npc_id, npc_state)
	return _persist_pre_save()


func apply_dialogue_effects(
		effects: Array,
		_conversation_id: StringName = &"") -> void:
	for effect_value: Variant in effects:
		if effect_value is not Dictionary:
			continue
		var effect := effect_value as Dictionary
		match StringName(str(effect.get("type", ""))):
			&"set_flag":
				set_story_flag(
					StringName(str(effect.get("key", ""))),
					effect.get("value", true)
				)
			&"set_story_checkpoint":
				set_story_checkpoint(
					StringName(str(effect.get("area_id", ""))),
					StringName(str(effect.get("character_id", ""))),
					StringName(str(effect.get("npc_id", ""))),
					StringName(str(effect.get("chapter_id", DEFAULT_CHAPTER_ID))),
					StringName(str(effect.get("dialogue_id", "")))
				)
			&"resolve_story_reward":
				resolve_story_reward(
					StringName(str(effect.get("area_id", ""))),
					StringName(str(effect.get("character_id", ""))),
					StringName(str(effect.get("npc_id", ""))),
					StringName(str(effect.get("chapter_id", DEFAULT_CHAPTER_ID))),
					bool(effect.get("value", false))
				)


func set_story_flag(flag_id: StringName, value: Variant) -> bool:
	if flag_id.is_empty() or not _prepare_pre_save():
		return false
	var progress: Dictionary = _pre_save_data.get("progress", {}).duplicate(true)
	var flags: Dictionary = progress.get("story_flags", {}).duplicate(true)
	flags[str(flag_id)] = value
	progress["story_flags"] = flags
	_pre_save_data["progress"] = progress
	return _persist_pre_save()


func get_story_flag(flag_id: StringName, default_value: Variant = null) -> Variant:
	var progress: Dictionary = _get_runtime_data().get("progress", {})
	var flags: Dictionary = progress.get("story_flags", {})
	return flags.get(str(flag_id), default_value)


func record_dialogue_completed(conversation_id: StringName) -> void:
	if conversation_id.is_empty() or not _prepare_pre_save():
		return
	var progress: Dictionary = _pre_save_data.get("progress", {}).duplicate(true)
	var history: Dictionary = progress.get("dialogue_history", {}).duplicate(true)
	var key := str(conversation_id)
	var previous: Dictionary = history.get(key, {})
	history[key] = {
		"completion_count": int(previous.get("completion_count", 0)) + 1,
		"last_completed_at_utc": Time.get_datetime_string_from_system(true, true),
	}
	progress["dialogue_history"] = history
	_pre_save_data["progress"] = progress
	_persist_pre_save()


func has_completed_dialogue(conversation_id: StringName) -> bool:
	var progress: Dictionary = _get_runtime_data().get("progress", {})
	var history: Dictionary = progress.get("dialogue_history", {})
	var entry: Dictionary = history.get(str(conversation_id), {})
	return int(entry.get("completion_count", 0)) > 0


## El pre-save se usa como base; la posición sólo entra aquí, al guardar.
func save_progress(progress_updates: Dictionary = {}) -> Dictionary:
	var save_data := _get_runtime_data().duplicate(true)
	if save_data.is_empty():
		save_data = load_save(false)
	if save_data.is_empty():
		_fail("No existe una partida activa para guardar.")
		return {}
	var progress: Dictionary = save_data.get("progress", {}).duplicate(true)
	for field: Variant in progress_updates:
		progress[field] = progress_updates[field]
	progress["play_time_seconds"] = get_play_time_seconds()
	save_data["progress"] = progress
	save_data["updated_at_utc"] = Time.get_datetime_string_from_system(true, true)
	if not _write_json_atomic(_save_path, save_data):
		_fail("No se pudo actualizar la partida guardada.")
		return {}
	_active_save_data = _normalize_save_types(save_data)
	_clear_pre_save(true)
	save_updated.emit(_active_save_data.duplicate(true))
	return _active_save_data.duplicate(true)


func get_save_directory_absolute() -> String:
	return ProjectSettings.globalize_path(SAVE_DIRECTORY)


func _prepare_pre_save() -> bool:
	if not _pre_save_data.is_empty():
		return true
	if not _ensure_active_save_data():
		return false
	_pre_save_data = _normalize_save_types(_active_save_data.duplicate(true))
	return true


func _set_pre_save_context(
		area_id: StringName,
		map_id: StringName,
		area_type: StringName) -> void:
	var progress: Dictionary = _pre_save_data.get("progress", {}).duplicate(true)
	if not map_id.is_empty():
		progress["current_map"] = str(map_id)
	if not area_id.is_empty():
		var area_data := {"id": str(area_id)}
		if not area_type.is_empty():
			area_data["type"] = str(area_type)
		progress["current_area"] = area_data
	_pre_save_data["progress"] = progress
	if not area_id.is_empty():
		_set_dialogue_area_metadata(area_id, map_id, area_type)


func _pre_save_context_matches(
		area_id: StringName,
		map_id: StringName,
		area_type: StringName) -> bool:
	var progress: Dictionary = _pre_save_data.get("progress", {})
	if not map_id.is_empty() and str(progress.get("current_map", "")) != str(map_id):
		return false
	var current_area: Dictionary = progress.get("current_area", {})
	if not area_id.is_empty() and str(current_area.get("id", "")) != str(area_id):
		return false
	if not area_type.is_empty() and str(current_area.get("type", "")) != str(area_type):
		return false
	return true


func _persist_pre_save() -> bool:
	if _pre_save_data.is_empty():
		return false
	var did_write := _write_json_atomic(_pre_save_path, _pre_save_data)
	if did_write:
		pre_save_updated.emit(_pre_save_data.duplicate(true))
	return did_write


func _clear_pre_save(delete_from_disk: bool) -> void:
	var had_data := not _pre_save_data.is_empty() or FileAccess.file_exists(_pre_save_path)
	_pre_save_data.clear()
	if delete_from_disk:
		_delete_file(_pre_save_path)
		_delete_file(_pre_save_path + ".tmp")
		_delete_file(_pre_save_path + ".backup")
	if had_data:
		pre_save_cleared.emit()


func _delete_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("SaveManager: no se pudo eliminar %s." % path)


func _get_runtime_data() -> Dictionary:
	return _pre_save_data if not _pre_save_data.is_empty() else _active_save_data


func _set_dialogue_area_metadata(
		area_id: StringName,
		map_id: StringName,
		area_type: StringName) -> void:
	var progress: Dictionary = _pre_save_data.get("progress", {}).duplicate(true)
	var dialogue_progress: Dictionary = progress.get(
		"dialogue_progress", {}
	).duplicate(true)
	var areas: Dictionary = dialogue_progress.get("areas", {}).duplicate(true)
	var area_key := str(area_id)
	var area_data: Dictionary = Dictionary(areas.get(area_key, {})).duplicate(true)
	if not map_id.is_empty():
		area_data["map_id"] = str(map_id)
	if not area_type.is_empty():
		area_data["area_type"] = str(area_type)
	areas[area_key] = area_data
	dialogue_progress["areas"] = areas
	progress["dialogue_progress"] = dialogue_progress
	_pre_save_data["progress"] = progress


func _get_npc_progress(
		data: Dictionary,
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName) -> Dictionary:
	var progress: Dictionary = data.get("progress", {})
	var dialogue_progress: Dictionary = progress.get("dialogue_progress", {})
	var areas: Dictionary = dialogue_progress.get("areas", {})
	var area_data: Dictionary = areas.get(str(area_id), {})
	var characters: Dictionary = area_data.get("characters", {})
	var character_data: Dictionary = characters.get(str(character_id), {})
	var npcs: Dictionary = character_data.get("npcs", {})
	return Dictionary(npcs.get(str(npc_id), {})).duplicate(true)


func _set_npc_progress(
		data: Dictionary,
		area_id: StringName,
		character_id: StringName,
		npc_id: StringName,
		npc_state: Dictionary) -> void:
	var progress: Dictionary = data.get("progress", {}).duplicate(true)
	var dialogue_progress: Dictionary = progress.get(
		"dialogue_progress", {}
	).duplicate(true)
	var areas: Dictionary = dialogue_progress.get("areas", {}).duplicate(true)
	var area_key := str(area_id)
	var area_data: Dictionary = Dictionary(areas.get(area_key, {})).duplicate(true)
	var characters: Dictionary = area_data.get("characters", {}).duplicate(true)
	var character_key := str(character_id)
	var character_data: Dictionary = Dictionary(
		characters.get(character_key, {})
	).duplicate(true)
	var npcs: Dictionary = character_data.get("npcs", {}).duplicate(true)
	npcs[str(npc_id)] = npc_state
	character_data["npcs"] = npcs
	characters[character_key] = character_data
	area_data["characters"] = characters
	areas[area_key] = area_data
	dialogue_progress["areas"] = areas
	progress["dialogue_progress"] = dialogue_progress
	data["progress"] = progress


func _ensure_chapter_state(npc_state: Dictionary, chapter_id: StringName) -> void:
	_set_chapter_state(npc_state, chapter_id, _get_chapter_state(npc_state, chapter_id))


func _get_chapter_state(npc_state: Dictionary, chapter_id: StringName) -> Dictionary:
	var chapters: Dictionary = npc_state.get("chapters", {})
	return Dictionary(chapters.get(str(chapter_id), {})).duplicate(true)


func _set_chapter_state(
		npc_state: Dictionary,
		chapter_id: StringName,
		chapter_state: Dictionary) -> void:
	var chapters: Dictionary = npc_state.get("chapters", {}).duplicate(true)
	chapters[str(chapter_id)] = chapter_state
	npc_state["chapters"] = chapters


func _create_identity() -> Dictionary:
	var crypto := Crypto.new()
	var uuid_bytes := crypto.generate_random_bytes(16)
	var secret_bytes := crypto.generate_random_bytes(32)
	if uuid_bytes.size() != 16 or secret_bytes.size() != 32:
		return {}
	uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40
	uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80
	var player_id := _format_uuid(uuid_bytes)
	var player_secret := secret_bytes.hex_encode()
	return {
		"identity_version": 1,
		"player_id": player_id,
		"player_secret": player_secret,
		"machine_binding": _create_machine_binding(player_secret),
		"created_at_utc": Time.get_datetime_string_from_system(true, true),
	}


func _create_machine_binding(player_secret: String) -> String:
	var device_id := OS.get_unique_id()
	if device_id.is_empty():
		return ""
	var hashing_context := HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing_context.update((device_id + ":" + player_secret).to_utf8_buffer())
	return hashing_context.finish().hex_encode()


func _format_uuid(bytes: PackedByteArray) -> String:
	var value := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		value.substr(0, 8), value.substr(8, 4), value.substr(12, 4),
		value.substr(16, 4), value.substr(20, 12),
	]


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: no se pudo abrir %s." % path)
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_warning("SaveManager: JSON inválido en %s (línea %s)." % [
			path, parser.get_error_line()
		])
		return {}
	return parser.data if parser.data is Dictionary else {}


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	if not _ensure_save_directory():
		return false
	var temporary_path := path + ".tmp"
	var backup_path := path + ".backup"
	var temporary_file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return false
	temporary_file.store_string(JSON.stringify(data, "\t"))
	temporary_file.flush()
	temporary_file.close()
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var had_previous_file := FileAccess.file_exists(path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if had_previous_file:
		if DirAccess.rename_absolute(absolute_path, absolute_backup) != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return false
	var replace_error := DirAccess.rename_absolute(absolute_temporary, absolute_path)
	if replace_error != OK:
		if had_previous_file:
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return false
	return true


func _ensure_save_directory() -> bool:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SAVE_DIRECTORY)):
		return true
	return DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SAVE_DIRECTORY)
	) == OK


func _is_valid_identity(identity: Dictionary) -> bool:
	return (
		identity.get("identity_version", 0) == 1
		and str(identity.get("player_id", "")).length() == 36
		and str(identity.get("player_secret", "")).length() == 64
	)


func _is_valid_save(save_data: Dictionary) -> bool:
	var version := int(save_data.get("save_version", 0))
	if version < 1 or version > SAVE_VERSION:
		return false
	if str(save_data.get("player_id", "")).is_empty():
		return false
	return save_data.get("progress", null) is Dictionary


func _normalize_save_types(save_data: Dictionary) -> Dictionary:
	var normalized := save_data.duplicate(true)
	normalized["save_version"] = SAVE_VERSION
	var progress: Dictionary = normalized.get("progress", {}).duplicate(true)
	for field in [&"play_time_seconds", &"medals", &"pokedex_seen"]:
		progress[field] = maxi(int(progress.get(field, 0)), 0)
	progress["chapter_id"] = str(progress.get("chapter_id", DEFAULT_CHAPTER_ID))
	if (
		not progress.has("current_area")
		or progress.get("current_area") is not Dictionary
	):
		progress["current_area"] = {}
	if (
		not progress.has("story_flags")
		or progress.get("story_flags") is not Dictionary
	):
		progress["story_flags"] = {}
	if (
		not progress.has("dialogue_history")
		or progress.get("dialogue_history") is not Dictionary
	):
		progress["dialogue_history"] = {}
	if (
		not progress.has("dialogue_progress")
		or progress.get("dialogue_progress") is not Dictionary
	):
		progress["dialogue_progress"] = {"areas": {}}
	var dialogue_progress: Dictionary = progress["dialogue_progress"]
	if (
		not dialogue_progress.has("areas")
		or dialogue_progress.get("areas") is not Dictionary
	):
		dialogue_progress["areas"] = {}
	progress["dialogue_progress"] = dialogue_progress
	progress.erase("npc_contacts")
	normalized["progress"] = progress
	return normalized


func _ensure_active_save_data() -> bool:
	if not _active_save_data.is_empty():
		return true
	_active_save_data = load_save(false)
	return not _active_save_data.is_empty()


func _fail(reason: String) -> void:
	push_error("SaveManager: %s" % reason)
	save_failed.emit(reason)
