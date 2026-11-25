class_name MovementGrid3D
extends MeshInstance3D

## Cuadrícula lógica compartida por los personajes del mapa 2.5D.
## La guía visual es opcional: la cuadrícula funciona aunque no se dibuje.

@export_range(0.1, 10.0, 0.1, "or_greater") var cell_size := 1.0
@export var grid_origin := Vector3.ZERO
@export var world_min := Vector2(-84.0, -57.0)
@export var world_max := Vector2(53.0, 64.0)
@export var show_debug_grid := false
@export var debug_color := Color(1.0, 1.0, 1.0, 0.18)


func _ready() -> void:
	add_to_group(&"movement_grid_3d")
	_rebuild_debug_grid()


func snap_world_position(world_position: Vector3) -> Vector3:
	var snapped_position := world_position
	snapped_position.x = (
		snappedf(world_position.x - grid_origin.x, cell_size) + grid_origin.x
	)
	snapped_position.z = (
		snappedf(world_position.z - grid_origin.z, cell_size) + grid_origin.z
	)
	return snapped_position


func contains_world_position(world_position: Vector3) -> bool:
	return (
		world_position.x >= world_min.x
		and world_position.x <= world_max.x
		and world_position.z >= world_min.y
		and world_position.z <= world_max.y
	)


func _rebuild_debug_grid() -> void:
	if not show_debug_grid:
		mesh = null
		return

	var grid_mesh := ImmediateMesh.new()
	var grid_material := StandardMaterial3D.new()
	grid_material.albedo_color = debug_color
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.vertex_color_use_as_albedo = true

	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	var x := world_min.x
	while x <= world_max.x + 0.001:
		grid_mesh.surface_set_color(debug_color)
		grid_mesh.surface_add_vertex(Vector3(x, 0.025, world_min.y))
		grid_mesh.surface_set_color(debug_color)
		grid_mesh.surface_add_vertex(Vector3(x, 0.025, world_max.y))
		x += cell_size

	var z := world_min.y
	while z <= world_max.y + 0.001:
		grid_mesh.surface_set_color(debug_color)
		grid_mesh.surface_add_vertex(Vector3(world_min.x, 0.025, z))
		grid_mesh.surface_set_color(debug_color)
		grid_mesh.surface_add_vertex(Vector3(world_max.x, 0.025, z))
		z += cell_size
	grid_mesh.surface_end()
	mesh = grid_mesh

