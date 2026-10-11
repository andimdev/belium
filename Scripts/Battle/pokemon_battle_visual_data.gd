class_name PokemonBattleVisualData
extends Resource

@export var asset_id: StringName
@export_range(1, 9999, 1) var national_dex_number := 1
@export var form_id: StringName = &"base"
@export var battler_scene: PackedScene
@export var cry: AudioStream

@export_range(1.0, 220.0, 1.0) var enemy_max_height_px := 220.0
@export_range(0.1, 1.0, 0.01) var enemy_height_fill_ratio := 0.95
@export var enemy_position := Vector3.ZERO
@export var enemy_rotation_degrees := Vector3.ZERO
@export_range(0.01, 100.0, 0.01) var enemy_scale := 1.0
