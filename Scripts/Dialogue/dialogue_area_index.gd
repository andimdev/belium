class_name DialogueAreaIndex
extends Resource

@export var place_id: StringName
@export var entries: Array[Dictionary] = []
@export var object_entries: Array[Dictionary] = []


func find_object_conversation_path(object_id: StringName) -> String:
	for entry in object_entries:
		if StringName(str(entry.get("object_id", ""))) == object_id:
			return str(entry.get("resource_path", ""))
	return ""


func find_conversation_path(
	npc_id: StringName,
	character_id: StringName,
	chapter_id: StringName
) -> String:
	for entry in entries:
		if StringName(str(entry.get("npc_id", ""))) != npc_id:
			continue
		if StringName(str(entry.get("character_id", ""))) != character_id:
			continue
		if StringName(str(entry.get("chapter_id", ""))) != chapter_id:
			continue
		return str(entry.get("resource_path", ""))
	return ""

