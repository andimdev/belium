extends SceneTree

const MENU_SCENE := preload("res://Scenes/GUI/menu.tscn")
const EXPECTED_ICONS := {
	&"pokemon": "res://Resources/Materials/Icons/pokeball.png",
	&"pokedex": "res://Resources/Materials/Icons/pokedex.png",
	&"bag": "res://Resources/Materials/Icons/bag.png",
	&"trainer": "res://Resources/Materials/Icons/trainer_card.png",
	&"save": "res://Resources/Materials/Icons/save.png",
	&"options": "res://Resources/Materials/Icons/settings.png",
}
const ROTATED := deg_to_rad(45.0)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_validate")


func _validate() -> void:
	var menu := MENU_SCENE.instantiate() as OverworldMenu
	root.add_child(menu)
	await process_frame
	await process_frame

	var grid := menu.get_node("MenuCenter/MenuGrid") as GridContainer
	var description_icon := menu.get_node(
		"DescriptionPanel/DescriptionContent/DescriptionIcon"
	) as TextureRect
	var close_hint := menu.get_node("Footer/CloseHintMargin/CloseHint") as HBoxContainer
	var close_label := close_hint.get_node("CloseLabel") as Label
	var options: Array[MainMenuOption] = []
	for child in grid.get_children():
		if child is MainMenuOption:
			options.append(child as MainMenuOption)
	_check(options.size() == EXPECTED_ICONS.size(), "Deben existir seis opciones con icono.")
	_check(is_equal_approx(description_icon.rotation, ROTATED),
		"El icono descriptivo permanece rotado 45 grados.")
	_check(close_hint.get_node("KeyZ/Label").text == "Z", "El pie muestra la tecla Z.")
	_check(close_hint.get_node("KeyEscape/Label").text == "ESC", "El pie muestra ESC.")
	_check(close_label.text == "CERRAR MENÚ",
		"El pie explica la acción de ambas teclas.")
	_check(close_label.global_position.x > root.size.x * 0.5,
		"El mensaje de cierre está alineado a la derecha.")
	options[0].icon_button.grab_focus()
	await create_timer(0.34).timeout
	_press_action(&"ui_right")
	await create_timer(0.34).timeout
	_check(options[1].icon_button.has_focus(),
		"La navegación de teclado cambia a la siguiente opción.")
	_check(is_equal_approx(options[1]._icon.rotation, ROTATED),
		"El teclado aplica la misma rotación que el mouse.")
	_check(description_icon.texture == options[1].icon_texture,
		"El teclado también actualiza el icono descriptivo.")

	for option in options:
		var expected_path := str(EXPECTED_ICONS.get(option.option_id, ""))
		_check(not expected_path.is_empty(), "Opción conocida: %s." % option.option_id)
		_check(option.icon_texture != null, "%s tiene icono." % option.option_id)
		if option.icon_texture != null:
			_check(option.icon_texture.resource_path == expected_path,
				"%s usa el recurso correcto." % option.option_id)

		# La entrada por mouse se traduce en el mismo foco utilizado por teclado.
		option.icon_button.mouse_entered.emit()
		await create_timer(0.34).timeout
		_check(option.icon_button.has_focus(), "%s recibe foco con el mouse." % option.option_id)
		_check(is_equal_approx(option._icon.rotation, ROTATED),
			"%s rota suavemente hasta 45 grados." % option.option_id)
		_check(option.icon_button.scale.is_equal_approx(Vector2.ONE),
			"%s no transforma el botón completo." % option.option_id)
		_check(description_icon.texture == option.icon_texture,
			"La descripción refleja el icono de %s." % option.option_id)
		_check(is_equal_approx(description_icon.rotation, ROTATED),
			"La marca de agua no cambia su rotación.")

		var option_index := options.find(option)
		if option_index > 0:
			var previous := options[option_index - 1]
			_check(is_zero_approx(previous._icon.rotation),
				"El icono anterior vuelve suavemente a 0 grados.")

	# Un icono asimétrico permite comprobar visualmente los 45 grados.
	var trainer_option := options.filter(
		func(option: MainMenuOption) -> bool: return option.option_id == &"trainer"
	).front() as MainMenuOption
	trainer_option.icon_button.grab_focus()
	await create_timer(0.34).timeout

	# Una captura sirve para revisar el resultado compuesto, además de los datos.
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		var preview := root.get_texture().get_image()
		var preview_error := preview.save_png("res://.godot/menu_icons_preview.png")
		_check(preview_error == OK, "Se pudo generar la vista previa del menú.")

	menu.queue_free()
	await process_frame
	if _failures.is_empty():
		print("MENU_ICONS_VALIDATED: six icons, mouse/keyboard focus, smooth 45-degree rotation, fixed description icon.")
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("MenuIconsValidation: " + message)


func _press_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	root.push_input(pressed)
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	root.push_input(released)
