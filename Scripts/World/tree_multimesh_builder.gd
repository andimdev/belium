@tool
class_name TreeMultiMeshBuilder
extends Node3D

## Dibuja muchos árboles iguales con MultiMeshInstance3D: una por capa del GLB
## (tronco, ramas, otoño, primavera, nieve) y por bloque del mapa.
##
## Sustituye a cientos de instancias del GLB con esqueleto y AnimationPlayer.
## Las posiciones se guardan en `positions`, en el espacio local de este nodo,
## y no se modifican: cada instancia usa exactamente ese origen.
## La animación con huesos no existe aquí; el balanceo lo hace el shader
## `tree_wind.gdshader` (opcional, `use_wind`).
##
## Las MultiMesh se generan al cargar (también en el editor) y no se guardan en
## la escena. En el juego se añade un GlbLayerController para controlar la nieve
## y la estación igual que con los GLB:
##     GlbLayerController.set_layer_everywhere(get_tree(), "snow", true)
##     GlbLayerController.set_variant_everywhere(get_tree(), "season", "autumn")

const GENERATED_META := &"tree_multimesh_generated"
const WIND_SHADER_PATH := "res://Shaders/tree_wind.gdshader"

## Escena del árbol (el GLB importado).
@export var tree_scene: PackedScene:
	set(value):
		tree_scene = value
		_queue_rebuild()
## Origen de cada árbol, relativo a este nodo. Sin rotación ni escala.
@export var positions: PackedVector3Array = PackedVector3Array():
	set(value):
		positions = value
		_queue_rebuild()
## Lado de cada bloque, en unidades locales. Bloques más pequeños = mejor culling
## pero más llamadas de dibujo.
@export_range(4.0, 256.0, 1.0) var chunk_size := 32.0:
	set(value):
		chunk_size = value
		_queue_rebuild()
## Nombres de los MeshInstance3D del GLB que se convierten en capas.
@export var mesh_layers: PackedStringArray = PackedStringArray([
	"Trunk", "Branches", "Branches Autumn", "Branches Spring", "Snow",
])
## Capas visibles mientras no haya GlbLayerController (editor y arranque).
@export var initially_visible: PackedStringArray = PackedStringArray(["Trunk", "Branches"])
@export var cast_shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON

@export_group("Viento")
## Balanceo por shader. Desactívalo para ver los materiales originales del GLB.
@export var use_wind := true:
	set(value):
		use_wind = value
		_queue_rebuild()
@export_range(0.0, 0.2, 0.001) var wind_strength := 0.03:
	set(value):
		wind_strength = value
		_update_wind_params()
@export_range(0.0, 5.0, 0.01) var wind_speed := 1.2:
	set(value):
		wind_speed = value
		_update_wind_params()
## Altura (local del GLB) desde la que el árbol empieza a moverse.
@export_range(0.0, 3.0, 0.01) var wind_min_height := 0.6:
	set(value):
		wind_min_height = value
		_update_wind_params()
## Dirección del viento en el plano XZ.
@export var wind_direction := Vector2(0.7071, 0.7071):
	set(value):
		wind_direction = value
		_update_wind_params()

var _wind_materials: Array[ShaderMaterial] = []
var _rebuild_queued := false


func _ready() -> void:
	rebuild()
	if not Engine.is_editor_hint():
		GlbLayerController.attach(self)


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_deferred_rebuild.call_deferred()


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild()


## Vuelve a generar todas las MultiMesh a partir de `positions`.
func rebuild() -> void:
	_clear_generated()
	if tree_scene == null or positions.is_empty():
		return
	var source := tree_scene.instantiate() as Node3D
	if source == null:
		push_warning("TreeMultiMeshBuilder: tree_scene no es una escena 3D.")
		return
	var chunks := _group_by_chunk()
	var keys := chunks.keys()
	keys.sort()
	var wind_shader: Shader = null
	if use_wind:
		wind_shader = load(WIND_SHADER_PATH) as Shader
	for layer_name: String in mesh_layers:
		var mesh_instance := source.find_child(layer_name, true, false) as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			push_warning("TreeMultiMeshBuilder: el GLB no tiene la malla '%s'." % layer_name)
			continue
		var offset := _transform_to_root(mesh_instance, source)
		var wind_material := _make_wind_material(mesh_instance.mesh, wind_shader)
		var index := 0
		for key: Vector2i in keys:
			var chunk_positions: PackedVector3Array = chunks[key]
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = mesh_instance.mesh
			multimesh.instance_count = chunk_positions.size()
			for i in chunk_positions.size():
				multimesh.set_instance_transform(
					i, Transform3D(Basis.IDENTITY, chunk_positions[i]) * offset
				)
			var node := MultiMeshInstance3D.new()
			# El sufijo numérico permite que GlbLayerController reconozca la capa.
			node.name = "%s_%d" % [layer_name, index]
			node.multimesh = multimesh
			node.cast_shadow = cast_shadows
			if wind_material != null:
				node.material_override = wind_material
			node.visible = initially_visible.has(layer_name)
			node.set_meta(GENERATED_META, true)
			add_child(node)
			index += 1
	source.free()


func get_tree_count() -> int:
	return positions.size()


func _group_by_chunk() -> Dictionary:
	var chunks := {}
	var size := maxf(chunk_size, 0.001)
	for tree_origin: Vector3 in positions:
		var key := Vector2i(floori(tree_origin.x / size), floori(tree_origin.z / size))
		if not chunks.has(key):
			chunks[key] = PackedVector3Array()
		var list: PackedVector3Array = chunks[key]
		list.append(tree_origin)
		chunks[key] = list
	return chunks


func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _make_wind_material(mesh: Mesh, shader: Shader) -> ShaderMaterial:
	if shader == null or mesh.get_surface_count() == 0:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	var original := mesh.surface_get_material(0) as BaseMaterial3D
	if original != null:
		material.set_shader_parameter(&"albedo_tex", original.albedo_texture)
		material.set_shader_parameter(&"use_albedo_tex", original.albedo_texture != null)
		material.set_shader_parameter(&"albedo_color", original.albedo_color)
		material.set_shader_parameter(&"roughness", original.roughness)
		material.set_shader_parameter(&"metallic", original.metallic)
	_wind_materials.append(material)
	_apply_wind_params(material)
	return material


func _update_wind_params() -> void:
	for material: ShaderMaterial in _wind_materials:
		_apply_wind_params(material)


func _apply_wind_params(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"wind_strength", wind_strength)
	material.set_shader_parameter(&"wind_speed", wind_speed)
	material.set_shader_parameter(&"wind_min_height", wind_min_height)
	material.set_shader_parameter(&"wind_direction", wind_direction.normalized())


func _clear_generated() -> void:
	_wind_materials.clear()
	for child: Node in get_children():
		if child.has_meta(GENERATED_META):
			remove_child(child)
			child.queue_free()
