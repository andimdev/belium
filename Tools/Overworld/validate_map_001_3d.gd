extends SceneTree

var _failures: Array[String] = []
var _completed_steps := 0
var _actor: CharacterBody3D
var _camera: Camera3D
var _rig: Node3D


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	var map := load("res://Maps/map_001_3d.tscn").instantiate() as Node3D
	root.add_child(map)
	_actor = map.get_node("World/CynthiaPlayer3D")
	_camera = map.get_node("CameraRig/Camera3D")
	_rig = map.get_node("CameraRig")
	_actor.grid_step_completed.connect(func(_position: Vector3, _direction: Vector3): _completed_steps += 1)
	await _frames(5)
	var terrain := map.get_node("Terrain") as Terrain3D
	var south: Vector3 = _rig.get_meta(&"map_south")
	for house: Node3D in map.get_node("World/Leaftown/Buildings").get_children():
		var door: MeshInstance3D = house.find_child("Door", true, false)
		var floor_mesh: MeshInstance3D = house.find_child("Inside Floor*", true, false)
		_check(door != null and floor_mesh != null, "Puerta y suelo identificables: %s" % house.name)
		if door != null and floor_mesh != null:
			var front := (door.global_transform * door.get_aabb()).get_center()
			var center := (floor_mesh.global_transform * floor_mesh.get_aabb()).get_center()
			_check((front - center).dot(south) > 0.5, "La puerta mira al sur: %s" % house.name)
	_check(_rig.get_node(_rig.target_path) == _actor, "La cámara tiene asignada a Cynthia.")
	_check(_camera.current, "La cámara de seguimiento está activa.")
	_check(absf(_camera.global_basis.x.y) < 0.0001, "La cámara no tiene inclinación lateral.")
	_check((_camera.global_position - _rig.global_position).dot(south) > 0.0, "La cámara mira las fachadas desde el sur.")
	_check(is_equal_approx(_actor.global_position.y, terrain.data.get_surface_height(_actor.global_position) + _actor.ground_clearance), "Cynthia comienza encima del terreno.")
	var initial_position := _actor.global_position
	var camera_basis := _camera.global_basis
	await _tap(&"move_up", Vector3.RIGHT, &"up")
	await _tap(&"move_right", Vector3.BACK, &"right")
	await _tap(&"move_down", Vector3.LEFT, &"down")
	await _tap(&"move_left", Vector3.FORWARD, &"left")
	_check(_actor.global_position.is_equal_approx(initial_position), "Cuatro pasos opuestos regresan a la celda inicial.")
	Input.action_press(&"run")
	await _tap(&"move_down", Vector3.LEFT, &"down", true)
	Input.action_release(&"run")
	var held_start := _actor.global_position
	var steps_before := _completed_steps
	Input.action_press(&"move_down")
	await _frames(65)
	Input.action_release(&"move_down")
	await _wait_for_step()
	_check(_completed_steps - steps_before >= 3, "Mantener una tecla encadena pasos completos.")
	_check(_actor.global_position.x < held_start.x - 2.0, "El movimiento sostenido avanza hacia el sur.")
	await _frames(45)
	_check(_rig.global_position.distance_to(_actor.global_position + _rig.focus_offset) < 0.02, "La cámara alcanza suavemente la posición de Cynthia.")
	_check(_camera.global_basis.is_equal_approx(camera_basis), "Seguir a Cynthia no gira la cámara.")
	_check(not _actor.call("_can_traverse_step", _actor.global_position, Vector3(10000, 0, 10000)), "No permite caminar fuera del terreno.")
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 2.0, 2.0)
	shape.shape = box
	blocker.add_child(shape)
	map.add_child(blocker)
	blocker.global_position = _actor.global_position + Vector3(-0.75, 1.0, 0.0)
	await _frames(3)
	var blocked_start := _actor.global_position
	steps_before = _completed_steps
	Input.action_press(&"move_down")
	await _frames(25)
	Input.action_release(&"move_down")
	_check(_actor.global_position.is_equal_approx(blocked_start), "Un obstáculo impide entrar en la siguiente celda.")
	_check(_completed_steps == steps_before, "Un paso bloqueado no emite paso completado.")
	blocker.queue_free()
	_actor.global_position = initial_position
	await _frames(50)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/map_001_3d_preview.png")
		print("CAPTURE res://.godot/map_001_3d_preview.png")
	map.free()
	if _failures.is_empty():
		print("PASS: fachadas sur, cámara fija y seguimiento, cuatro direcciones, pasos cortos, correr, movimiento sostenido, apoyo y colisiones.")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _tap(action: StringName, expected: Vector3, facing: StringName, running: bool = false) -> void:
	var start := _actor.global_position
	var previous_steps := _completed_steps
	Input.action_press(action)
	await _frames(1)
	Input.action_release(action)
	var sprite := _actor.get_node("AnimatedSprite3D") as AnimatedSprite3D
	_check(sprite.is_playing() and sprite.animation == StringName(("run_" if running else "walk_") + String(facing)), "Un toque inicia la animación: %s" % action)
	await _wait_for_step()
	_check((_actor.global_position - start).is_equal_approx(expected * _actor.fallback_cell_size), "Un toque mueve exactamente una celda: %s" % action)
	_check(_completed_steps == previous_steps + 1, "Un toque completa un único paso: %s" % action)
	_check(_actor.facing_direction == facing, "El sprite mira en la dirección visible: %s" % action)


func _wait_for_step() -> void:
	for _index in range(120):
		await _frames(1)
		if not _actor.get("_is_stepping"):
			return
	_check(false, "El paso debe terminar sin quedar bloqueado.")


func _frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
