extends Node

## Persistencia global del perfil local y del primer slot de guardado.

signal save_created(save_data: Dictionary)
signal save_loaded(save_data: Dictionary)
signal save_updated(save_data: Dictionary)
signal save_failed(reason: String)

const SAVE_DIRECTORY := "user://Saved"
const IDENTITY_PATH := SAVE_DIRECTORY + "/player_identity.json"
const SAVE_PATH := SAVE_DIRECTORY + "/save_slot_1.json"
const SAVE_VERSION := 1
const DEFAULT_MAP_ID := "map_001_leaftown_201_sandtown_202"

var _active_save_data: Dictionary = {}
var _play_time_seconds := 0.0
var _tracking_play_time := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _tracking_play_time:
		_play_time_seconds += delta


func has_save() -> bool:
	return not load_save(false).is_empty()


func load_save(emit_signal: bool = true) -> Dictionary:
	var identity := _read_json(IDENTITY_PATH)
	var save_data := _read_json(SAVE_PATH)
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


## Crea una partida nueva. Conserva la identidad local si ya existe.
func create_new_game() -> Dictionary:
	if not _ensure_save_directory():
		_fail("No se pudo crear la carpeta de guardado.")
		return {}

	var identity := _read_json(IDENTITY_PATH)
	if not _is_valid_identity(identity):
		identity = _create_identity()
		if identity.is_empty() or not _write_json_atomic(IDENTITY_PATH, identity):
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
			"play_time_seconds": 0,
			"medals": 0,
			"pokedex_seen": 0,
			"current_map": DEFAULT_MAP_ID,
			"spawn_point": "",
			"player_position": {},
		},
	}

	if not _write_json_atomic(SAVE_PATH, save_data):
		_fail("No se pudo escribir la nueva partida.")
		return {}

	_active_save_data = save_data.duplicate(true)
	_play_time_seconds = 0.0
	_tracking_play_time = false
	save_created.emit(save_data.duplicate(true))
	return save_data


## Comienza a contar tiempo únicamente cuando la partida ya está dentro de un
## mapa. Si se proporciona un guardado, continúa exactamente desde su valor.
func start_play_session(save_data: Dictionary = {}) -> void:
	var session_data := save_data.duplicate(true)
	if session_data.is_empty():
		session_data = _active_save_data.duplicate(true)
	if session_data.is_empty():
		session_data = load_save(false)
	if session_data.is_empty() or not _is_valid_save(session_data):
		return

	_active_save_data = _normalize_save_types(session_data)
	var progress: Dictionary = _active_save_data.get("progress", {})
	_play_time_seconds = maxf(
		float(progress.get("play_time_seconds", 0)),
		0.0
	)
	_tracking_play_time = true


func stop_play_session() -> void:
	_tracking_play_time = false


func get_play_time_seconds() -> int:
	return maxi(floori(_play_time_seconds), 0)


func get_active_save() -> Dictionary:
	return _active_save_data.duplicate(true)


## Actualiza sólo los campos proporcionados. El resto del progreso queda
## intacto para inventario, equipo, medallas y sistemas futuros.
func save_progress(progress_updates: Dictionary = {}) -> Dictionary:
	var save_data := _active_save_data.duplicate(true)
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

	if not _write_json_atomic(SAVE_PATH, save_data):
		_fail("No se pudo actualizar la partida guardada.")
		return {}

	_active_save_data = _normalize_save_types(save_data)
	save_updated.emit(_active_save_data.duplicate(true))
	return _active_save_data.duplicate(true)


func get_save_directory_absolute() -> String:
	return ProjectSettings.globalize_path(SAVE_DIRECTORY)


func _create_identity() -> Dictionary:
	var crypto := Crypto.new()
	var uuid_bytes := crypto.generate_random_bytes(16)
	var secret_bytes := crypto.generate_random_bytes(32)
	if uuid_bytes.size() != 16 or secret_bytes.size() != 32:
		return {}

	# Bits de versión y variante requeridos por UUID v4.
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
		value.substr(0, 8),
		value.substr(8, 4),
		value.substr(12, 4),
		value.substr(16, 4),
		value.substr(20, 12),
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
		push_warning("SaveManager: JSON inválido en %s (línea %s)." % [path, parser.get_error_line()])
		return {}
	var parsed: Variant = parser.data
	if parsed is not Dictionary:
		return {}
	var data: Dictionary = parsed
	return data


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
	if save_data.get("save_version", 0) != SAVE_VERSION:
		return false
	if str(save_data.get("player_id", "")).is_empty():
		return false
	var progress: Variant = save_data.get("progress", null)
	return progress is Dictionary


func _normalize_save_types(save_data: Dictionary) -> Dictionary:
	var normalized := save_data.duplicate(true)
	normalized["save_version"] = int(normalized.get("save_version", SAVE_VERSION))
	var progress: Dictionary = normalized.get("progress", {})
	for field in [&"play_time_seconds", &"medals", &"pokedex_seen"]:
		progress[field] = maxi(int(progress.get(field, 0)), 0)
	normalized["progress"] = progress
	return normalized


func _fail(reason: String) -> void:
	push_error("SaveManager: %s" % reason)
	save_failed.emit(reason)
