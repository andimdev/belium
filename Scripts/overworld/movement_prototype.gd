extends Node2D

const WORLD_BOUNDS := Rect2(-640.0, -360.0, 1280.0, 720.0)
const GRID_SIZE := 32

@onready var player: OverworldPlayer = $CyrusPlayer
@onready var status_label: Label = $Interface/MarginContainer/StatusLabel


func _ready() -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.limit_left = int(WORLD_BOUNDS.position.x)
		camera.limit_top = int(WORLD_BOUNDS.position.y)
		camera.limit_right = int(WORLD_BOUNDS.end.x)
		camera.limit_bottom = int(WORLD_BOUNDS.end.y)

	_update_status()


func _process(_delta: float) -> void:
	_update_status()


func _draw() -> void:
	draw_rect(WORLD_BOUNDS, Color("182b2b"))

	var grid_color := Color("203838")
	for x in range(int(WORLD_BOUNDS.position.x), int(WORLD_BOUNDS.end.x) + 1, GRID_SIZE):
		draw_line(
			Vector2(x, WORLD_BOUNDS.position.y),
			Vector2(x, WORLD_BOUNDS.end.y),
			grid_color
		)

	for y in range(int(WORLD_BOUNDS.position.y), int(WORLD_BOUNDS.end.y) + 1, GRID_SIZE):
		draw_line(
			Vector2(WORLD_BOUNDS.position.x, y),
			Vector2(WORLD_BOUNDS.end.x, y),
			grid_color
		)

	draw_circle(Vector2.ZERO, 5.0, Color("7fb7a3"))


func _update_status() -> void:
	status_label.text = (
		"Mover: WASD o flechas  |  Correr: Mayús\n"
		+ "Estado: %s  |  Dirección: %s  |  Posición: (%d, %d)"
		% [
			player.state_machine.get_state_label(),
			String(player.facing_direction).capitalize(),
			int(player.global_position.x),
			int(player.global_position.y),
		]
	)
