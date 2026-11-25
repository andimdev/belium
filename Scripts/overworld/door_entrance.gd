class_name DoorEntrance
extends Area3D

## Puerta de una cabaña: se abre, Cynthia entra, la puerta se cierra y se pasa
## al mapa del interior.
##
## Estructura: un DoorEntrance por puerta, con un CollisionShape3D hijo (caja)
## colocado sobre la baldosa que está justo frente a la puerta. Esa caja es el
## disparador: se ve en el editor y se mueve o redimensiona a mano.
##
## La secuencia empieza cuando Cynthia, con su centro dentro de la caja, empuja
## hacia la puerta. El paso lo bloquea la colisión del edificio (que NO se toca)
## y el jugador avisa con `step_blocked`. Cynthia entra con un movimiento
## guionado (`walk_scripted`), que no pasa por la física y atraviesa la caja.
## El Area3D no usa la física: se desactiva su monitoreo y solo se lee la forma.
##
## Mientras no exista el mapa del interior (`interior_scene_id` vacío) se usa la
## variante TEMPORAL: fundido a negro y cierre del juego. Ver
## `_temporary_fade_and_quit()`, que hay que borrar junto con su llamada.

signal entry_started
signal entry_finished

const ANIMATION_OPEN := &"Door_Open"
const ANIMATION_CLOSE := &"Door_Close"
const DOOR_NODE_NAME := "Door"
const FALLBACK_WALK_DISTANCE := 1.6

## Cabaña (instancia del GLB) cuya puerta se anima.
@export_node_path("Node3D") var house_path: NodePath
@export_node_path("OverworldPlayer3D") var player_path: NodePath
## Dirección en la que se entra. +X es el «norte» de este mapa.
@export var enter_direction := Vector3.RIGHT
## Metros que camina Cynthia desde la caja hasta la puerta. 0 = automático:
## hasta el centro de la hoja de la puerta, medido en la dirección de entrada.
@export_range(0.0, 4.0, 0.01, "or_greater") var walk_distance := 0.0
## Mapa del interior registrado en SceneLoader. Vacío = variante temporal.
@export var interior_scene_id: StringName = &""
@export var interior_spawn: StringName = &"entrance"

var _house: Node3D
var _player: OverworldPlayer3D
var _animation_player: AnimationPlayer
var _trigger_shape: CollisionShape3D
var _busy := false


func _ready() -> void:
	# Solo se lee la forma de la caja: sin monitoreo ni capas de física.
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0

	_house = get_node_or_null(house_path) as Node3D
	_player = get_node_or_null(player_path) as OverworldPlayer3D
	if _house == null or _player == null:
		push_warning("DoorEntrance '%s': revisa house_path y player_path." % name)
		return

	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node != null and shape_node.shape is BoxShape3D:
			_trigger_shape = shape_node
			break
	if _trigger_shape == null:
		push_warning("DoorEntrance '%s': falta un CollisionShape3D hijo con BoxShape3D." % name)
		return

	for candidate: Node in _house.find_children("*", "AnimationPlayer", true, false):
		var player := candidate as AnimationPlayer
		if player.has_animation(ANIMATION_OPEN) and player.has_animation(ANIMATION_CLOSE):
			_animation_player = player
			break
	if _animation_player == null:
		push_warning("DoorEntrance '%s': '%s' no tiene Door_Open/Door_Close." % [name, _house.name])
		return

	_player.step_blocked.connect(_on_step_blocked)


func _on_step_blocked(_from_position: Vector3, direction: Vector3) -> void:
	if _busy or direction.dot(enter_direction.normalized()) < 0.9:
		return
	if not _is_player_in_trigger():
		return
	_enter()


## Compara el centro de Cynthia con la caja en el plano horizontal; la altura
## no cuenta, así que la caja puede ser tan baja o alta como se quiera.
func _is_player_in_trigger() -> bool:
	var box := _trigger_shape.shape as BoxShape3D
	if box == null:
		return false
	var local_position := _trigger_shape.global_transform.affine_inverse() * _player.global_position
	var half_size := box.size * 0.5
	return absf(local_position.x) <= half_size.x and absf(local_position.z) <= half_size.z


func _enter() -> void:
	_busy = true
	entry_started.emit()
	_player.set_control_enabled(false)

	# La distancia se mide ahora, con la puerta aún cerrada.
	var direction := enter_direction.normalized()
	var distance := walk_distance if walk_distance > 0.0 else _distance_to_door_center(direction)

	_animation_player.play(ANIMATION_OPEN)
	await _animation_player.animation_finished

	var walk_time := distance / maxf(_player.walk_speed, 0.1)
	await _player.walk_scripted(_player.global_position + direction * distance, walk_time)
	_player.animated_sprite.visible = false

	_animation_player.play(ANIMATION_CLOSE)
	await _animation_player.animation_finished

	await _finish_entry()
	entry_finished.emit()


## Distancia, en la dirección de entrada, desde Cynthia hasta el centro de la
## hoja de la puerta (caja envolvente de la malla `Door` en reposo).
func _distance_to_door_center(direction: Vector3) -> float:
	var door := _house.find_child(DOOR_NODE_NAME, true, false) as MeshInstance3D
	if door == null or door.mesh == null:
		push_warning("DoorEntrance '%s': no se encontró la malla '%s'; se usa %.1f m." % [
			name, DOOR_NODE_NAME, FALLBACK_WALK_DISTANCE
		])
		return FALLBACK_WALK_DISTANCE
	var center := (door.global_transform * door.get_aabb()).get_center()
	return clampf((center - _player.global_position).dot(direction), 0.3, 4.0)


func _finish_entry() -> void:
	if interior_scene_id != &"":
		await SceneLoader.load_map(interior_scene_id, interior_spawn)
		return
	await _temporary_fade_and_quit()


## TEMPORAL — REMOVER cuando exista el mapa del interior.
## Fundido a negro y cierre del juego. Para sustituirlo basta con asignar
## `interior_scene_id` en cada puerta (y borrar esta función y su llamada en
## `_finish_entry`).
func _temporary_fade_and_quit() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 125 # Por encima de la capa de transiciones de SceneLoader (120).
	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 0.0
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(layer)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fade, "modulate:a", 1.0, 0.45)
	await tween.finished
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
