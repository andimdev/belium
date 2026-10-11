extends SceneTree

const MAP_SCENE := preload(
	"res://Maps/map_001_leaftown_201_sandtown_202.tscn"
)
const TEST_SAVE_PATH := "res://codex_npc_interaction_save.json"
const TEST_PRE_SAVE_PATH := "res://codex_npc_interaction_pre_save.json"


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager == null:
		push_error("NpcInteractionValidation: no existe SaveManager.")
		quit(1)
		return
	save_manager._save_path = TEST_SAVE_PATH
	save_manager._pre_save_path = TEST_PRE_SAVE_PATH
	save_manager._active_save_data = {
		"save_version": 2,
		"player_id": "00000000-0000-4000-8000-000000000000",
		"progress": {
			"chapter": "Prólogo",
			"chapter_id": "ChapterI",
			"play_time_seconds": 0,
			"medals": 0,
			"pokedex_seen": 0,
			"dialogue_progress": {"areas": {}},
		},
	}
	var map := MAP_SCENE.instantiate() as Node2D
	root.add_child(map)
	await process_frame
	await process_frame
	var player := map.get_node_or_null("Mapa/Casas/CynthiaPlayer") as Node2D
	var npc := map.get_node_or_null("Mapa/Casas/NPCs/OldMan") as Node2D
	if player == null or npc == null:
		_fail(map, "No se encontraron Cynthia y Harry dentro del mapa.")
		return
	if not npc.has_method("get_npc_id"):
		_fail(map, "Harry no implementa get_npc_id().")
		return
	if StringName(str(npc.call("get_npc_id"))) != &"Npc001OldManHarry":
		_fail(map, "La instancia de Harry perdió su npcId.")
		return
	if not npc.is_in_group(&"dialogue_interactable"):
		_fail(map, "Harry no pertenece al grupo dialogue_interactable.")
		return
	if player.has_method("set_movement_locked"):
		player.call("set_movement_locked", true)
	if npc.has_method("set_interaction_locked"):
		npc.call("set_interaction_locked", true)
	player.global_position = npc.global_position + Vector2(0.0, 20.0)
	player.set("last_cardinal_direction", Vector2.UP)
	var detected: Variant = map.call("get_interactable_in_front")
	if detected != npc:
		_fail(map, "Harry no fue detectado desde la celda adyacente.")
		return
	var ui_root := map.get_node_or_null("UIRoot") as CanvasLayer
	if ui_root == null:
		_fail(map, "No se encontró UIRoot dentro del mapa.")
		return
	ui_root.call("_on_active_camera_zone_changed", &"leaftown", "Pueblo Hojaverde")
	var started := bool(ui_root.call("_try_start_dialogue"))
	var runner := ui_root.get_node_or_null("DialogueRunner") as DialogueRunner
	if not started or runner == null or not runner.is_active():
		_fail(map, "UIRoot detectó a Harry pero no abrió el panel de diálogo.")
		return
	map.queue_free()
	_cleanup_test_files()
	print("NPC_DIALOGUE_INTERACTION_VALIDATED")
	quit()


func _fail(map: Node2D, reason: String) -> void:
	map.queue_free()
	_cleanup_test_files()
	push_error("NpcInteractionValidation: %s" % reason)
	quit(1)


func _cleanup_test_files() -> void:
	for path in [
		TEST_SAVE_PATH,
		TEST_SAVE_PATH + ".tmp",
		TEST_SAVE_PATH + ".backup",
		TEST_PRE_SAVE_PATH,
		TEST_PRE_SAVE_PATH + ".tmp",
		TEST_PRE_SAVE_PATH + ".backup",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
