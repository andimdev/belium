class_name PlayerMovementStateMachine
extends Node

signal state_changed(previous_state: int, new_state: int)

enum MovementState {
	IDLE,
	WALK,
	RUN,
}

@export_range(1.0, 1000.0, 1.0, "or_greater") var walk_speed: float = 130.0
@export_range(1.0, 1000.0, 1.0, "or_greater") var run_speed: float = 220.0

var current_state: MovementState = MovementState.IDLE


func update_state(input_direction: Vector2, wants_to_run: bool) -> void:
	var next_state := MovementState.IDLE

	if not input_direction.is_zero_approx():
		next_state = MovementState.RUN if wants_to_run else MovementState.WALK

	_transition_to(next_state)


func get_movement_speed() -> float:
	match current_state:
		MovementState.WALK:
			return walk_speed
		MovementState.RUN:
			return run_speed
		_:
			return 0.0


func get_animation_prefix() -> StringName:
	match current_state:
		MovementState.WALK:
			return &"walk"
		MovementState.RUN:
			return &"run"
		_:
			return &"idle"


func get_state_label() -> String:
	return MovementState.keys()[current_state].capitalize()


func _transition_to(next_state: MovementState) -> void:
	if next_state == current_state:
		return

	var previous_state := current_state
	current_state = next_state
	state_changed.emit(previous_state, current_state)
