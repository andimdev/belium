extends Node2D

const GrassStepEffect := preload("res://Scripts/overworld/grass_step_effect.gd")
const PondWaterEffect := preload("res://Scripts/overworld/pond_water_effect.gd")

@export_node_path("Node2D") var player_path: NodePath
@export_node_path("TileMapLayer") var tall_grass_layer_path: NodePath
@export var tall_grass_source_id := 0
@export var tall_grass_atlas_coordinates := PackedVector2Array()
@export var grass_foot_offset_y := -5.0
@export var pond_water_rect := Rect2()

var _player: Node2D
var _tall_grass_layer: TileMapLayer
var _last_grass_cell := Vector2i(2147483647, 2147483647)
var _was_in_tall_grass := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_tall_grass_layer = get_node_or_null(tall_grass_layer_path) as TileMapLayer
	if _player == null:
		push_warning("OverworldEnvironmentEffects: no se encontró el jugador configurado.")
	if _tall_grass_layer == null:
		push_warning("OverworldEnvironmentEffects: no se encontró la capa de hierba alta.")

	if pond_water_rect.has_area():
		var pond_effect := PondWaterEffect.new()
		pond_effect.name = "PondWaterEffect"
		pond_effect.position = pond_water_rect.position
		pond_effect.z_index = 8
		pond_effect.configure(pond_water_rect.size)
		add_child(pond_effect)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_tall_grass_layer):
		return

	var foot_position := _player.global_position + Vector2(0.0, grass_foot_offset_y)
	var local_foot_position := _tall_grass_layer.to_local(foot_position)
	var current_cell := _tall_grass_layer.local_to_map(local_foot_position)
	var is_in_tall_grass := _is_tall_grass_cell(current_cell)

	if is_in_tall_grass and (not _was_in_tall_grass or current_cell != _last_grass_cell):
		_spawn_grass_effect(current_cell)

	_last_grass_cell = current_cell
	_was_in_tall_grass = is_in_tall_grass


func _is_tall_grass_cell(cell: Vector2i) -> bool:
	if _tall_grass_layer.get_cell_source_id(cell) != tall_grass_source_id:
		return false
	var atlas_coordinates := _tall_grass_layer.get_cell_atlas_coords(cell)
	for configured_coordinates in tall_grass_atlas_coordinates:
		if atlas_coordinates == Vector2i(configured_coordinates):
			return true
	return false


func _spawn_grass_effect(cell: Vector2i) -> void:
	var effect := GrassStepEffect.new()
	effect.name = "GrassStepEffect_%d" % effect.get_instance_id()
	effect.z_index = 20
	var tile_width := float(_tall_grass_layer.tile_set.tile_size.x)
	tile_width *= absf(_tall_grass_layer.global_scale.x)
	effect.configure(tile_width)
	add_child(effect)
	effect.add_to_group(&"grass_step_effect")
	effect.global_position = _tall_grass_layer.to_global(
		_tall_grass_layer.map_to_local(cell)
	)
