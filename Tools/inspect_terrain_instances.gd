extends SceneTree


func _initialize() -> void:
	for path in [
		"res://Maps/map_001_3d_data/terrain3d_00_00.res",
		"res://Maps/map_001_3d_data/terrain3d_00-01.res",
		"res://Maps/map_001_3d_data/terrain3d-01_00.res",
		"res://Maps/map_001_3d_data/terrain3d-01-01.res",
	]:
		var region := ResourceLoader.load(path)
		if region == null:
			print("REGION_LOAD_FAILED ", path)
			continue
		print("REGION ", path, " location=", region.location)
		print("INSTANCES ", region.instances)
	quit()
