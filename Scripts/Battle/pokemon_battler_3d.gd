class_name PokemonBattler3D
extends Node3D

signal action_finished(action_id: StringName)

@export var animation_map: Dictionary = {
	&"idle": &"idle",
	&"battle_enter": &"battle_enter",
}

var _animation_player: AnimationPlayer
var _current_action: StringName


func _ready() -> void:
	_animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("PokemonBattler3D: el modelo no contiene AnimationPlayer.")
		return
	_animation_player.animation_finished.connect(_on_animation_finished)


func play_idle() -> bool:
	return play_action(&"idle", true)


func play_action(action_id: StringName, loop: bool = false) -> bool:
	if _animation_player == null:
		return false
	var animation_name := StringName(str(animation_map.get(action_id, action_id)))
	if not _animation_player.has_animation(animation_name):
		push_warning(
			"PokemonBattler3D: no existe la animación lógica '%s' (%s)."
			% [action_id, animation_name]
		)
		return false
	var animation := _animation_player.get_animation(animation_name)
	animation.loop_mode = (
		Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	)
	_current_action = action_id
	_animation_player.play(animation_name)
	return true


func stop() -> void:
	if _animation_player != null:
		_animation_player.stop()
	_current_action = &""


func get_visual_world_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for candidate in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.get_aabb()
		for endpoint_index in range(8):
			points.append(mesh_instance.to_global(bounds.get_endpoint(endpoint_index)))
	return points


func _on_animation_finished(_animation_name: StringName) -> void:
	var completed_action := _current_action
	_current_action = &""
	if not completed_action.is_empty():
		action_finished.emit(completed_action)
