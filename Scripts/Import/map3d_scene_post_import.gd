@tool
extends EditorScenePostImport

## Limpia el GLB del mapa antes de que Godot genere su PackedScene importada.
## El archivo fuente permanece intacto; solamente cambia el recurso generado.

const MAXIMUM_VALID_MESH_EXTENT := 30.0
const MATERIAL_TEXTURES: Dictionary[String, Texture2D] = {
	"Tree Trunk Mat": preload("res://Resources/Materials/3D/Map/Textures/Tree Trunk Texture.png"),
	"Tree Top Mat": preload("res://Resources/Materials/3D/Map/Textures/Tree Top Texture.png"),
	"Rock Mat": preload("res://Resources/Materials/3D/Map/Textures/Rock Texture.png"),
	"Plank Mat": preload("res://Resources/Materials/3D/Map/Textures/Plank Texture.png"),
	"Mailbox Mat": preload("res://Resources/Materials/3D/Map/Textures/Mailbox Texture.png"),
	"Log Wall Mat": preload("res://Resources/Materials/3D/Map/Textures/Log Walls Texture.png"),
	"Top House Mat": preload("res://Resources/Materials/3D/Map/Textures/Top House Texture.png"),
	"Inside Floor Mat": preload("res://Resources/Materials/3D/Map/Textures/Inside Floor Texture.png"),
	"Door Mat": preload("res://Resources/Materials/3D/Map/Textures/Door Texture.png"),
	"House Base Mat": preload("res://Resources/Materials/3D/Map/Textures/House Base Texture.png"),
	"Window Mat": preload("res://Resources/Materials/3D/Map/Textures/Window Texture.png"),
	"Roof Mat": preload("res://Resources/Materials/3D/Map/Textures/Roof Texture.png"),
}


func _post_import(scene: Node) -> Object:
	var invalid_meshes: Array[MeshInstance3D] = []
	var configured_materials: Dictionary[int, bool] = {}
	var pending: Array[Node] = [scene]

	while not pending.is_empty():
		var current: Node = pending.pop_back() as Node
		for child: Node in current.get_children():
			pending.append(child)
		if current is not MeshInstance3D:
			continue
		var mesh_instance := current as MeshInstance3D
		if mesh_instance.mesh == null:
			continue

		var imported_transform := _get_imported_transform(mesh_instance, scene)
		var imported_bounds: AABB = imported_transform * mesh_instance.get_aabb()
		if _is_oversized(imported_bounds):
			invalid_meshes.append(mesh_instance)
			continue
		_apply_material_textures(mesh_instance, configured_materials)

	for mesh_instance: MeshInstance3D in invalid_meshes:
		var parent: Node = mesh_instance.get_parent()
		if parent != null:
			parent.remove_child(mesh_instance)
		mesh_instance.free()

	return scene


func _get_imported_transform(node: Node3D, scene_root: Node) -> Transform3D:
	var accumulated_transform := node.transform
	var ancestor: Node = node.get_parent()
	while ancestor is Node3D:
		accumulated_transform = (ancestor as Node3D).transform * accumulated_transform
		if ancestor == scene_root:
			break
		ancestor = ancestor.get_parent()
	return accumulated_transform


func _is_oversized(bounds: AABB) -> bool:
	return (
		bounds.size.x > MAXIMUM_VALID_MESH_EXTENT
		or bounds.size.y > MAXIMUM_VALID_MESH_EXTENT
		or bounds.size.z > MAXIMUM_VALID_MESH_EXTENT
	)


func _apply_material_textures(
	mesh_instance: MeshInstance3D,
	configured_materials: Dictionary[int, bool]
) -> void:
	for surface_index in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_active_material(surface_index)
		if material is not BaseMaterial3D:
			continue
		var material_id := material.get_instance_id()
		if configured_materials.has(material_id):
			continue
		configured_materials[material_id] = true
		var material_3d := material as BaseMaterial3D
		var base_name := _get_base_material_name(material_3d.resource_name)
		var texture := MATERIAL_TEXTURES.get(base_name) as Texture2D
		if texture != null:
			material_3d.albedo_texture = texture


func _get_base_material_name(material_name: String) -> String:
	var suffix_start := material_name.rfind(".")
	if suffix_start < 0:
		return material_name
	var suffix := material_name.substr(suffix_start + 1)
	if suffix.is_valid_int():
		return material_name.left(suffix_start)
	return material_name
