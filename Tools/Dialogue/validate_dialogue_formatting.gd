extends SceneTree

const TextFormat := preload("res://Scripts/Dialogue/dialogue_text_format.gd")
const PANEL_SCENE := preload("res://Scenes/GUI/dialogue_panel.tscn")
var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var source := "*Cynthia* visitó _Pueblo Hojaverde_. 'La luz guía a *Harry* hacia _Ruta 201_.'"
	var runs := TextFormat.parse(source)
	var expected := "Cynthia visitó Pueblo Hojaverde. La luz guía a Harry hacia Ruta 201."
	_check(TextFormat.plain_text(runs) == expected, "Las marcas deben desaparecer sin alterar el texto.")
	var combined_styles := false
	for run in runs:
		if run.text == "Harry":
			combined_styles = run.kind == "character" and run.italic
	_check(combined_styles, "Los nombres dentro de citas deben conservar azul y cursiva.")
	var literal := "d'Artagnan y O'Connor: npc_001_harry; _marca abierta; [color=red]literal[/color]"
	_check(TextFormat.plain_text(TextFormat.parse(literal)) == literal, "Apóstrofos, IDs y marcas incompletas deben conservarse.")
	_check(TextFormat.plain_text(TextFormat.parse("\\_literal\\_ \\*literal\\* \\'cita\\'")) == "_literal_ *literal* 'cita'", "Los escapes deben permitir escribir los símbolos literalmente.")

	var panel := PANEL_SCENE.instantiate() as DialoguePanel
	root.add_child(panel)
	await process_frame
	await process_frame
	panel.set_dialogue_text(source, false)
	_check(panel.dialogue_label.get_parsed_text().contains("Cynthia"), "El texto enriquecido no se renderiza como texto legible.")
	_check(panel.dialogue_label.text.contains("[color=#3578b8]"), "Falta el azul de personajes.")
	_check(panel.dialogue_label.text.contains("[color=#c45d67]"), "Falta el rojo suave de lugares.")
	var italic := panel.dialogue_label.get_theme_font("italics_font") as FontVariation
	_check(italic != null and not italic.variation_transform.is_equal_approx(Transform2D.IDENTITY), "La cursiva necesita una variante inclinada de la fuente.")
	panel.set_dialogue_text(literal, false)
	_check(panel.dialogue_label.get_parsed_text().contains("[color=red]"), "El BBCode literal no debe convertirse en formato adicional.")

	# La cita atraviesa varias páginas y dos saltos de párrafo explícitos.
	var long_source := "'En _Pueblo Hojaverde_ *Cynthia* escuchó el poema. " + "La memoria de los viajeros conserva la luz de los antiguos caminos. ".repeat(9) + "\n\n*Harry* recuerda el final.'"
	panel.set_dialogue_text(long_source, true)
	_check(panel.dialogue_label.visible_characters == 0, "El revelado debe empezar vacío.")
	panel.call("_process", 1.0 / panel.characters_per_second)
	_check(panel.dialogue_label.visible_characters == 1, "Las marcas no deben consumir tiempo de escritura.")
	panel.finish_dialogue_reveal()
	_check(panel.is_waiting_for_page_advance(), "Debe detenerse después de dos líneas.")
	var initial_page := panel.get_dialogue_page_index()
	panel.call("_process", 100.0)
	_check(panel.get_dialogue_page_index() == initial_page, "Ni el paso del tiempo debe avanzar una página en pausa.")
	var page_texts: Array[String] = []
	for iteration in range(100):
		if not panel.is_waiting_for_page_advance() and panel.is_revealing_dialogue():
			panel.finish_dialogue_reveal()
		var parsed := panel.dialogue_label.get_parsed_text()
		page_texts.append(parsed)
		_check(panel.dialogue_label.get_line_count() <= 2, "El texto con estilos ocupa más de dos líneas.")
		_check(panel.dialogue_label.text.contains("[i]"), "La cursiva se perdió al partir la cita entre páginas.")
		for line_index in panel.dialogue_label.get_line_count():
			_check(panel.dialogue_label.get_line_width(line_index) <= panel.dialogue_label.size.x + 1.0, "Una línea formateada excede el ancho del panel.")
		if not panel.is_revealing_dialogue():
			break
		panel.finish_dialogue_reveal()
	_check(_without_whitespace("".join(page_texts)) == _without_whitespace(TextFormat.plain_text(TextFormat.parse(long_source))), "La paginación omitió o duplicó texto.")
	_check(not (panel.get_node("MainDialogue/ContentMargin/DialogueContent/MoreIndicator") as Control).visible, "Los puntos deben desaparecer en la última página.")

	panel.set_dialogue_options(["Visitar _Ruta 201_", "Buscar a *Harry*", "'Recordar el mito'"])
	var options: Array = panel.get("_option_labels")
	_check((options[0] as RichTextLabel).get_parsed_text() == "Visitar Ruta 201", "Las elecciones también deben interpretar las marcas.")
	_check((options[1] as RichTextLabel).text.contains("[color=#3578b8]"), "Falta azul en la elección de personaje.")
	_check((options[2] as RichTextLabel).text.contains("[i]"), "Falta cursiva en la elección de cita.")
	panel.set_speaker("*Cynthia*", Color("28839c"), true)
	_check((panel.get_node("MainDialogue/ContentMargin/DialogueContent/SpeakerName") as RichTextLabel).get_parsed_text() == "Cynthia", "El nombre visible del hablante también debe interpretar las marcas.")
	if "--preview" in OS.get_cmdline_user_args():
		panel.set_dialogue_options(["Ir a _Ruta 201_", "Hablar con *Harry*", "'Recordar el mito'"])
		panel.set_dialogue_text("*Cynthia* llegó a _Pueblo Hojaverde_.\n'Hasta la noche más larga termina al amanecer.'", false)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var error := image.save_png("res://.godot/dialogue_format_preview.png")
		_check(error == OK, "No se pudo guardar la vista de comprobación.")
		panel.set_speaker("Harry", Color("65584a"))
		panel.set_dialogue_options([])
		panel.set_dialogue_text("Te doy la bienvenida a _Pueblo Hojaverde_.\nHace mucho tiempo que cuido este jardín.", false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/dialogue_npc_preview.png")
		panel.set_speaker("", Color("20242b"))
		panel.set_dialogue_text("Bienvenido a _Pueblo Hojaverde_.", false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/dialogue_sign_preview.png")
	panel.queue_free()
	if _failures.is_empty():
		print("DIALOGUE_FORMATTING_VALIDATED colors=true italics=true choices=true typewriter=true pagination=true literals=true")
	quit(0 if _failures.is_empty() else 1)


func _without_whitespace(text: String) -> String:
	return text.replace(" ", "").replace("\n", "").replace("\r", "").replace("\t", "")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("DialogueFormattingValidation: " + message)
