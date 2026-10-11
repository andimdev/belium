class_name OverworldCameraZone
extends Area2D

## Región espacial que define cuándo cambia el encuadre y hasta dónde puede
## mostrar la cámara. Su forma se edita con CollisionShape2D o
## CollisionPolygon2D hijos, sin participar en las colisiones del juego.

## Identificador estable de la región; no es el nombre que ve el jugador.
@export var zone_id: StringName
## Nombre que mostrará el aviso de ubicación del UIRoot.
@export var display_name := "cam"
## Rectángulo que puede mostrar la cámara, en píxeles locales de este Area2D.
## Position es la esquina superior izquierda; Size es ancho y alto (no la esquina final).
## Es independiente del RegionShape hijo, que solo detecta la entrada a la región.
## Debe tener ancho y alto mayores que cero e incluir terreno realmente dibujado.
@export var camera_bounds := Rect2()
## Filas que se excluyen del encuadre: X=izquierda, Y=arriba,
## Z=derecha, W=abajo. Con un borde de 8 filas, usar 5 deja visibles 3.
## Con celdas de 20px, 5 excluye 100px. Usar 0 en conexiones con otra región.
@export var hidden_boundary_rows := Vector4.ZERO
## Segundos del cambio de encuadre al entrar caminando. Al iniciar el mapa es inmediato.
@export_range(0.0, 8.0, 0.1) var transition_duration := 2


func contains_world_point(world_point: Vector2) -> bool:
	for child in get_children():
		if child is CollisionShape2D:
			var collision_shape := child as CollisionShape2D
			if collision_shape.disabled or collision_shape.shape == null:
				continue
			if _shape_contains_point(
				collision_shape.shape,
				collision_shape.to_local(world_point)
			):
				return true
		elif child is CollisionPolygon2D:
			var collision_polygon := child as CollisionPolygon2D
			if collision_polygon.disabled or collision_polygon.polygon.size() < 3:
				continue
			if Geometry2D.is_point_in_polygon(
				collision_polygon.to_local(world_point),
				collision_polygon.polygon
			):
				return true
	return false


func _shape_contains_point(shape: Shape2D, local_point: Vector2) -> bool:
	if shape is RectangleShape2D:
		var rectangle := shape as RectangleShape2D
		return Rect2(-rectangle.size * 0.5, rectangle.size).has_point(local_point)
	if shape is CircleShape2D:
		var circle := shape as CircleShape2D
		return local_point.length_squared() <= circle.radius * circle.radius
	return shape.get_rect().has_point(local_point)


func get_world_camera_bounds(world_cell_size: Vector2 = Vector2.ZERO) -> Rect2:
	var normalized_bounds := camera_bounds.abs()
	var local_corners := PackedVector2Array([
		normalized_bounds.position,
		Vector2(normalized_bounds.end.x, normalized_bounds.position.y),
		normalized_bounds.end,
		Vector2(normalized_bounds.position.x, normalized_bounds.end.y),
	])
	var minimum := to_global(local_corners[0])
	var maximum := minimum
	for corner in local_corners:
		var world_corner := to_global(corner)
		minimum = minimum.min(world_corner)
		maximum = maximum.max(world_corner)

	var world_bounds := Rect2(minimum, maximum - minimum)
	var left_inset := maxf(hidden_boundary_rows.x, 0.0) * world_cell_size.x
	var top_inset := maxf(hidden_boundary_rows.y, 0.0) * world_cell_size.y
	var right_inset := maxf(hidden_boundary_rows.z, 0.0) * world_cell_size.x
	var bottom_inset := maxf(hidden_boundary_rows.w, 0.0) * world_cell_size.y
	world_bounds.position += Vector2(left_inset, top_inset)
	world_bounds.size -= Vector2(
		left_inset + right_inset,
		top_inset + bottom_inset
	)
	return world_bounds
