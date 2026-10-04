class_name OverworldPlayer
extends CharacterBody2D

signal movement_state_changed(previous_state: int, new_state: int)

const INPUT_BINDINGS: Dictionary[StringName, Array] = {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"run": [KEY_SHIFT],
	&"switch_character": [KEY_ENTER, KEY_KP_ENTER],
}

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: PlayerMovementStateMachine = $MovementStateMachine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var player_camera: Camera2D = $Camera2D

var facing_direction: StringName = &"down"
var last_cardinal_direction := Vector2.DOWN
var control_enabled := true


func _ready() -> void:
	_ensure_default_input_actions()
	state_machine.state_changed.connect(_on_state_changed)
	_update_animation()


func _physics_process(_delta: float) -> void:
	var input_direction := _get_cardinal_input_direction()

	state_machine.update_state(input_direction, Input.is_action_pressed(&"run"))
	velocity = input_direction * state_machine.get_movement_speed()

	if not input_direction.is_zero_approx():
		_update_facing_direction(input_direction)

	move_and_slide()
	_update_animation()


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	visible = enabled
	player_camera.enabled = enabled
	collision_shape.set_deferred(&"disabled", not enabled)
	set_physics_process(enabled)

	if not enabled:
		velocity = Vector2.ZERO
		state_machine.update_state(Vector2.ZERO, false)

	_update_animation()


func _get_cardinal_input_direction() -> Vector2:
	var horizontal_axis := Input.get_axis(&"move_left", &"move_right")
	var vertical_axis := Input.get_axis(&"move_up", &"move_down")

	if is_zero_approx(horizontal_axis) and is_zero_approx(vertical_axis):
		return Vector2.ZERO

	var horizontal_direction := Vector2(signf(horizontal_axis), 0.0)
	var vertical_direction := Vector2(0.0, signf(vertical_axis))
	var direction: Vector2

	if not is_zero_approx(horizontal_axis) and not is_zero_approx(vertical_axis):
		var horizontal_was_just_pressed := (
			Input.is_action_just_pressed(&"move_left")
			or Input.is_action_just_pressed(&"move_right")
		)
		var vertical_was_just_pressed := (
			Input.is_action_just_pressed(&"move_up")
			or Input.is_action_just_pressed(&"move_down")
		)

		if horizontal_was_just_pressed:
			direction = horizontal_direction
		elif vertical_was_just_pressed:
			direction = vertical_direction
		elif not is_zero_approx(last_cardinal_direction.x):
			direction = horizontal_direction
		else:
			direction = vertical_direction
	elif not is_zero_approx(horizontal_axis):
		direction = horizontal_direction
	else:
		direction = vertical_direction

	last_cardinal_direction = direction
	return direction


func _update_facing_direction(input_direction: Vector2) -> void:
	if absf(input_direction.x) > absf(input_direction.y):
		facing_direction = &"right" if input_direction.x > 0.0 else &"left"
	else:
		facing_direction = &"down" if input_direction.y > 0.0 else &"up"


func _update_animation() -> void:
	var animation_name := StringName(
		"%s_%s" % [state_machine.get_animation_prefix(), facing_direction]
	)

	if animated_sprite.animation != animation_name or not animated_sprite.is_playing():
		animated_sprite.play(animation_name)


func _on_state_changed(previous_state: int, new_state: int) -> void:
	movement_state_changed.emit(previous_state, new_state)


func _ensure_default_input_actions() -> void:
	for action: StringName in INPUT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		for keycode: Key in INPUT_BINDINGS[action]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode

			if not InputMap.action_has_event(action, key_event):
				InputMap.action_add_event(action, key_event)
