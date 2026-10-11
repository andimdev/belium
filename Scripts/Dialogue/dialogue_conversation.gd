class_name DialogueConversation
extends Resource

@export var schema_version := 1
@export var conversation_id: StringName
@export var dialogue_number := ""
@export var npc_id: StringName
@export var character_id: StringName
@export var place_id: StringName
@export var chapter_id: StringName
@export var dialogue_kind: StringName = &"story_bundle"
@export var entry_node_id: StringName
@export var first_contact_entry_node_id: StringName
@export var story_entry_node_id: StringName
@export var story_dialogue_nodes: Dictionary = {}
@export var random_entry_node_ids: Array[StringName] = []
@export var speaker_profiles: Array[Resource] = []
@export var nodes: Array[Dictionary] = []


func get_node_data(node_id: StringName) -> Dictionary:
	for node_data in nodes:
		if StringName(str(node_data.get("node_id", ""))) == node_id:
			return node_data.duplicate(true)
	return {}


func get_speaker_profile(character_id: StringName) -> Resource:
	for profile in speaker_profiles:
		if (
			profile != null
			and StringName(str(profile.get("character_id"))) == character_id
		):
			return profile
	return null


func get_story_entry_node(checkpoint_dialogue_id: StringName = &"") -> StringName:
	if not checkpoint_dialogue_id.is_empty():
		return StringName(str(story_dialogue_nodes.get(
			String(checkpoint_dialogue_id),
			""
		)))
	return story_entry_node_id


func get_random_entry_node() -> StringName:
	if random_entry_node_ids.is_empty():
		return &""
	return random_entry_node_ids.pick_random()

