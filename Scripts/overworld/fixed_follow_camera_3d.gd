class_name FixedFollowCamera3D
extends Node3D

## Sigue únicamente la traslación del personaje. La orientación permanece fija,
## por lo que la cámara nunca orbita ni hereda giros del actor.

@export_node_path("Node3D") var target_path: NodePath
@export var focus_offset := Vector3(0.0, 0.85, 0.0)
@export_range(0.1, 30.0, 0.1, "or_greater") var follow_smoothing := 8.0
@export var snap_on_ready := true

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target != null and snap_on_ready:
		global_position = _desired_position()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var weight := 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(_desired_position(), weight)


func _desired_position() -> Vector3:
	return _target.global_position + focus_offset
