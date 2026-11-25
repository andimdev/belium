extends SceneTree


const REGION_PATH := "res://Maps/map_001_3d_data/terrain3d_00_00.res"
const MESH_ID := 0
const SOURCE_CELL := Vector2i(0, 1)
const OBSOLETE_CELL := Vector2i(0, 0)

const GAP_POSITIONS := [
	Vector2(2.8, 56.0),
	Vector2(8.0, 56.6),
	Vector2(13.1, 55.7),
	Vector2(18.4, 56.4),
	Vector2(4.8, 62.1),
	Vector2(9.8, 61.5),
	Vector2(15.2, 62.4),
	Vector2(19.3, 61.7),
	Vector2(2.5, 68.0),
	Vector2(7.5, 68.7),
	Vector2(12.8, 67.8),
	Vector2(18.0, 68.4),
	Vector2(4.6, 74.3),
	Vector2(9.9, 73.7),
	Vector2(15.1, 74.5),
	Vector2(19.2, 73.8),
	Vector2(2.7, 80.2),
	Vector2(7.8, 80.8),
	Vector2(13.0, 79.9),
	Vector2(18.1, 80.5),
	Vector2(5.0, 86.2),
	Vector2(10.4, 85.6),
	Vector2(16.0, 86.4),
]

const SOURCE_VARIANTS := [
	3, 10, 0, 16, 7, 12, 5, 14, 2, 17, 8, 11,
	1, 15, 6, 9, 4, 13, 0, 7, 16, 5, 12,
]


func _initialize() -> void:
	var region = ResourceLoader.load(REGION_PATH)
	if region == null:
		push_error("Could not load %s" % REGION_PATH)
		quit(1)
		return

	var instances: Dictionary = region.instances.duplicate(true)
	if not instances.has(MESH_ID):
		push_error("Mesh ID %d has no saved instances" % MESH_ID)
		quit(1)
		return

	var mesh_cells: Dictionary = instances[MESH_ID].duplicate(true)
	if not mesh_cells.has(SOURCE_CELL):
		push_error("Source cell %s has no saved tree pattern" % SOURCE_CELL)
		quit(1)
		return

	# This cell was empty before the first placement attempt. It contains only the
	# temporary trees added in the wrong direction, so remove it before correcting.
	mesh_cells.erase(OBSOLETE_CELL)

	var source_data: Array = mesh_cells[SOURCE_CELL]
	var source_transforms: Array = source_data[0].duplicate()
	var source_colors: PackedColorArray = source_data[1].duplicate()
	var added := 0

	for index in GAP_POSITIONS.size():
		var position: Vector2 = GAP_POSITIONS[index]
		var target_cell := Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))
		var target_transforms: Array[Transform3D] = []
		var target_colors := PackedColorArray()

		if mesh_cells.has(target_cell):
			var target_data: Array = mesh_cells[target_cell]
			target_transforms.assign(target_data[0])
			target_colors = target_data[1]

		var already_present := false
		for existing: Transform3D in target_transforms:
			if Vector2(existing.origin.x, existing.origin.z).distance_to(position) < 1.0:
				already_present = true
				break
		if already_present:
			continue

		var source_index: int = SOURCE_VARIANTS[index] % source_transforms.size()
		var tree_transform: Transform3D = source_transforms[source_index]
		tree_transform.origin = Vector3(position.x, 0.0, position.y)
		target_transforms.append(tree_transform)
		target_colors.append(source_colors[source_index])
		mesh_cells[target_cell] = [target_transforms, target_colors, false]
		added += 1

	instances[MESH_ID] = mesh_cells
	region.instances = instances

	var error := ResourceSaver.save(region, REGION_PATH)
	if error != OK:
		push_error("Could not save the region: %s" % error_string(error))
		quit(1)
		return

	print("TREE_GAP_CORRECTED added=", added)
	quit()
