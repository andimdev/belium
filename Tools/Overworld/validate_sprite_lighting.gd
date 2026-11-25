extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	var map := load("res://Maps/map_001_3d.tscn").instantiate() as Node3D
	var clock_node := map.get_node("Sky/TimeOfDay") as TimeOfDay
	clock_node.game_time_enabled = false
	clock_node.system_sync = false
	clock_node.current_time = 21.0
	root.add_child(map)
	var actor := map.get_node("World/CynthiaPlayer3D") as Node3D
	actor.global_position = Vector3(-1, 0.025, 19)
	actor.set_physics_process(false)
	var sprite := actor.get_node("AnimatedSprite3D") as AnimatedSprite3D
	var material := sprite.material_override as StandardMaterial3D
	_check(material != null, "Cynthia tiene un material de iluminación explícito.")
	if material == null:
		map.free()
		quit(1)
		return
	_check(material.backlight_enabled, "Recibe luz también desde detrás del billboard.")
	_check(not material.disable_receive_shadows, "Conserva la recepción de sombras.")
	_check(sprite.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Conserva la proyección de sombras.")
	_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Conserva el recorte transparente del sprite.")
	# AnimatedSprite3D genera los UV de cada fotograma; el material usa el atlas completo.
	for animation: StringName in sprite.sprite_frames.get_animation_names():
		for frame in sprite.sprite_frames.get_frame_count(animation):
			var texture := sprite.sprite_frames.get_frame_texture(animation, frame)
			while texture is AtlasTexture:
				texture = (texture as AtlasTexture).atlas
			_check(texture == material.albedo_texture, "Atlas correcto: %s, frame %d" % [animation, frame])

	if DisplayServer.get_name() != "headless":
		await _frames(60)
		var camera := map.get_node("CameraRig/Camera3D") as Camera3D
		var sample_center := camera.unproject_position(sprite.global_position + Vector3(0, 0.2, 0))
		var region := Rect2i(Vector2i(sample_center) - Vector2i(10, 7), Vector2i(20, 14))
		material.backlight_enabled = false
		var original := await _capture("cynthia_light_front_only")
		material.backlight_enabled = true
		var illuminated := await _capture("cynthia_spotlights_fixed")
		var controller := map.get_node("World/Leaftown/Buildings/lucas_dawn_house") as GlbLayerController
		controller.call("_apply_window_lighting", 7.0)
		var fade: Tween = controller.get("_window_light_tween")
		fade.pause()
		fade.custom_step(0.5)
		await _capture("window_lighting_half_fade")
		fade.custom_step(0.51)
		var unlit := await _capture("cynthia_spotlights_off")
		var original_luma := _luminance(original, region)
		var illuminated_luma := _luminance(illuminated, region)
		var unlit_luma := _luminance(unlit, region)
		print("SPRITE luminance front_only=", original_luma, " two_sided=", illuminated_luma, " spots_off=", unlit_luma)
		_check(illuminated_luma > original_luma * 1.3, "El material responde a los focos posteriores.")
		_check(illuminated_luma > unlit_luma * 1.3, "Cynthia vuelve a oscurecerse cuando se apagan los focos.")
	map.free()
	for failure: String in _failures:
		push_error(failure)
	print("PASS: sprite atlas, lighting from behind, alpha cutout, shadows, light on/off." if _failures.is_empty() else "FAIL")
	quit(0 if _failures.is_empty() else 1)


func _capture(label: String) -> Image:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png("res://.godot/%s.png" % label)
	print("CAPTURE ", label)
	return picture


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _luminance(picture: Image, area: Rect2i) -> float:
	var region := area.intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
	var result := 0.0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var color := picture.get_pixel(x, y)
			result += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return result / maxi(1, region.get_area())


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
