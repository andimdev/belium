@tool
extends Marker2D

## Punto de lectura de un cartel, estatua u otro objeto del mapa.
## Colocarlo en el centro del borde inferior de la celda ocupada por el objeto.

## Clave exterior del JSON; por ejemplo: welcome_leaftown.
@export var object_id: StringName:
	set(value):
		object_id = value
		update_configuration_warnings()
## Sufijo del archivo JSON, respetando mayúsculas. Vacío = región actual.
@export var dialogue_place_id: StringName
## Dirección hacia la que debe mirar el jugador. (0, -1) = leer desde abajo;
## (0, 0) permite leer el objeto desde cualquier lado.
@export var required_facing := Vector2.UP
@export var interaction_enabled := true


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"dialogue_interactable")


func get_object_id() -> StringName:
	return object_id


func get_dialogue_place_id() -> StringName:
	return dialogue_place_id


func can_interact_from(player: Node2D) -> bool:
	if not interaction_enabled or not is_visible_in_tree():
		return false
	if required_facing.is_zero_approx():
		return true
	var facing: Variant = player.get("last_cardinal_direction")
	return facing is Vector2 and (facing as Vector2).normalized().dot(
		required_facing.normalized()
	) > 0.99


func _get_configuration_warnings() -> PackedStringArray:
	if object_id.is_empty():
		return ["Asigna Object Id con la clave exterior de la entrada del JSON."]
	return []
