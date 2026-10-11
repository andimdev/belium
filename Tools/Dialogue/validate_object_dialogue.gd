extends SceneTree

const MAP_SCENE := preload("res://Maps/map_001_leaftown_201_sandtown_202.tscn")
const SOURCE_PATH := "res://Dialogues/0001_Carteles_Leaftown201SandTown202.json"
const OBJECT_ROOT := "Mapa/Piso/fondo_casa/Colisiones_fondo/"
const TEST_SAVE := "res://.godot/object_dialogue_validation_save.json"
const TEST_PRE_SAVE := "res://.godot/object_dialogue_validation_pre_save.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_validation")


func _run_validation() -> void:
	var save_manager := root.get_node("SaveManager")
	save_manager.set("_save_path", TEST_SAVE)
	save_manager.set("_pre_save_path", TEST_PRE_SAVE)
	save_manager.set("_active_save_data", {})
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	var map := MAP_SCENE.instantiate() as Node2D
	root.add_child(map)
	await process_frame
	await process_frame
	var player := map.get_node("Mapa/Casas/CynthiaPlayer") as Node2D
	player.set_physics_process(false)
	var ui := map.get_node("UIRoot")
	var runner := ui.get_node("DialogueRunner")
	var panel := ui.get_node("Interface/DialoguePanel") as Control
	var npc := map.get_node("Mapa/Casas/NPCs/OldMan")
	npc.set_physics_process(false)
	var signs := [
		{"node": "colision_cartel_leaftown", "id": "welcome_leaftown", "key": KEY_F},
		{"node": "colision_cartel_001_201", "id": "tracks_trainers_201", "key": KEY_ENTER},
	]
	for entry: Dictionary in signs:
		var sign := map.get_node(OBJECT_ROOT + str(entry.node) + "/Dialogue") as Node2D
		_check(sign.call("get_object_id") == StringName(entry.id), "El cartel no conserva su Object Id.")
		player.global_position = sign.global_position + Vector2.DOWN * 20.0
		player.set("last_cardinal_direction", Vector2.UP)
		_check(map.call("get_interactable_in_front") == sign, "El cartel no se detecta desde la celda contigua.")
		_check(not runner.call("is_active"), "Acercarse al cartel no debe abrirlo sin pulsar F/Enter.")
		_send_key(ui, int(entry.key))
		_check(bool(runner.call("is_active")), "F/Enter no abrió el cartel.")
		_check(bool(player.get("movement_locked")), "El jugador debe quedar bloqueado durante la lectura.")
		_check(not bool(ui.get("_menu_open")), "La lectura no debe abrir el menú.")
		_check(panel.get("_full_dialogue_text") == source[entry.id].text, "El texto o sus saltos de línea no coinciden con el JSON.")
		var speaker := panel.get_node("MainDialogue/ContentMargin/DialogueContent/SpeakerName") as Control
		_check(not speaker.visible, "Un cartel no debe mostrar el nombre de un NPC.")
		_check(not (panel.get_node("SidePanel") as Control).visible, "El cartel no necesita opciones.")
		_send_key(ui, KEY_ESCAPE)
		_check(bool(runner.call("is_active")), "Escape no debe saltarse la lectura.")
		for press in range(64):
			if not runner.call("is_active"):
				break
			_send_key(ui, int(entry.key))
		_check(not runner.call("is_active"), "La última confirmación debe cerrar el cartel.")
		_check(not bool(player.get("movement_locked")), "Al cerrar debe devolverse el control.")
		_send_key(ui, int(entry.key))
		_check(bool(runner.call("is_active")), "Los carteles deben poder releerse.")
		runner.call("cancel")
		player.set("last_cardinal_direction", Vector2.DOWN)
		_check(map.call("get_interactable_in_front") != sign, "Mirar en sentido contrario no debe seleccionar el cartel.")
		player.global_position = sign.global_position + Vector2.UP * 20.0
		_check(map.call("get_interactable_in_front") != sign, "El cartel configurado para lectura frontal no debe leerse por detrás.")
		player.global_position = sign.global_position + Vector2.DOWN * 60.0
		player.set("last_cardinal_direction", Vector2.UP)
		_check(map.call("get_interactable_in_front") != sign, "No debe leerse un cartel a tres celdas.")

	_check((save_manager.get("_pre_save_data") as Dictionary).is_empty(), "Leer objetos no debe registrar contacto ni progreso de NPC.")
	_check(not FileAccess.file_exists(TEST_PRE_SAVE), "Leer objetos no debe escribir un pre-save.")
	# El encabezado vuelve a mostrarse al hablar otra vez con un personaje.
	panel.call("set_speaker", "Harry", Color("65584a"))
	_check((panel.get_node("MainDialogue/ContentMargin/DialogueContent/SpeakerName") as Control).visible, "El nombre del NPC debe reaparecer tras leer un cartel.")
	map.queue_free()
	if _failures.is_empty():
		print("OBJECT_DIALOGUE_VALIDATED signs=2 input=F/Enter repeatable=true movement_lock=true npc_state_unchanged=true")
	quit(0 if _failures.is_empty() else 1)


func _send_key(ui: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = key as Key
	ui.call("_unhandled_input", event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("ObjectDialogueValidation: " + message)
