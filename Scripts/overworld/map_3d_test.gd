class_name Map3DTest
extends Node3D

## Adaptador del GLB de prueba. Conserva el archivo fuente intacto, descarta las
## mallas auxiliares sobredimensionadas del export y crea colisiones simples.

@export var hide_oversized_import_meshes := true
@export_range(10.0, 500.0, 1.0, "or_greater") var maximum_mesh_extent := 30.0
@export var generate_environment_collisions := true
@export_range(0.1, 2.0, 0.05, "or_greater") var tree_collision_radius := 0.45

@onready var map_geometry: Node3D = $MapGeometry
@onready var static_obstacles: StaticBody3D = $StaticObstacles


func _ready() -> void:
	if hide_oversized_import_meshes:
		_hide_oversized_meshes(map_geometry)
	if generate_environment_collisions:
		_build_environment_collisions()
func _hide_oversized_meshes(root_node: Node) -> void:
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var current: Node = pending.pop_back() as Node
		for child: Node in current.get_children():
			pending.append(child)
		if current is not MeshInstance3D:
			continue
		var mesh_instance := current as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		if (
			world_bounds.size.x > maximum_mesh_extent
			or world_bounds.size.y > maximum_mesh_extent
			or world_bounds.size.z > maximum_mesh_extent
		):
			mesh_instance.visible = false


func _build_environment_collisions() -> void:
	var cabins := map_geometry.get_node_or_null("Cabins")
	if cabins != null:
		for cabin: Node in cabins.get_children():
			var bounds := _get_practical_descendant_bounds(cabin)
			if bounds.size != Vector3.ZERO:
				_add_box_collision(bounds, Vector3(0.25, 0.0, 0.25))

	var mailboxes := map_geometry.get_node_or_null("Mailboxes")
	if mailboxes != null:
		for mailbox: Node in mailboxes.get_children():
			var bounds := _get_practical_descendant_bounds(mailbox)
			if bounds.size != Vector3.ZERO:
				_add_box_collision(bounds, Vector3(0.05, 0.0, 0.05))

	var rocks := map_geometry.get_node_or_null("Rocks")
	if rocks != null:
		for rock: Node in rocks.get_children():
			if rock is not Node3D:
				continue
			var rock_shape := CylinderShape3D.new()
			rock_shape.radius = 0.55
			rock_shape.height = 1.0
			var rock_collision := CollisionShape3D.new()
			rock_collision.shape = rock_shape
			var rock_position := (rock as Node3D).global_position
			rock_collision.position = Vector3(rock_position.x, 0.5, rock_position.z)
			static_obstacles.add_child(rock_collision)

	var trees := map_geometry.get_node_or_null("Trees")
	if trees != null:
		for tree: Node in trees.get_children():
			if tree is not Node3D:
				continue
			var tree_shape := CylinderShape3D.new()
			tree_shape.radius = tree_collision_radius
			tree_shape.height = 1.4
			var tree_collision := CollisionShape3D.new()
			tree_collision.shape = tree_shape
			var tree_position := (tree as Node3D).global_position
			tree_collision.position = Vector3(tree_position.x, 0.7, tree_position.z)
			static_obstacles.add_child(tree_collision)


func _get_practical_descendant_bounds(root_node: Node) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var current: Node = pending.pop_back() as Node
		for child: Node in current.get_children():
			pending.append(child)
		if current is not MeshInstance3D:
			continue
		var mesh_instance := current as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_bounds: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		if (
			world_bounds.size.x > maximum_mesh_extent
			or world_bounds.size.y > maximum_mesh_extent
			or world_bounds.size.z > maximum_mesh_extent
		):
			continue
		if has_bounds:
			bounds = bounds.merge(world_bounds)
		else:
			bounds = world_bounds
			has_bounds = true
	return bounds


func _add_box_collision(bounds: AABB, padding: Vector3) -> void:
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(
		maxf(bounds.size.x - padding.x, 0.25),
		maxf(bounds.size.y - padding.y, 0.5),
		maxf(bounds.size.z - padding.z, 0.25)
	)
	var collision := CollisionShape3D.new()
	collision.shape = box_shape
	collision.position = bounds.get_center()
	static_obstacles.add_child(collision)

