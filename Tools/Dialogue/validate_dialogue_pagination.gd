extends SceneTree

const PANEL_SCENE := preload("res://Scenes/GUI/dialogue_panel.tscn")


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var panel := PANEL_SCENE.instantiate() as DialoguePanel
	root.add_child(panel)
	await process_frame
	await process_frame
	var long_text := (
		"En el lago Veraz, donde el agua es clara y la luna brilla, un guardián "
		+ "duerme desde hace incontables generaciones. Los habitantes más antiguos "
		+ "dicen que enseñó a los humanos a sentir alegría, dolor y tristeza. "
		+ "También cuentan que sus lágrimas dieron al mundo la empatía y la "
		+ "compasión, aunque nadie puede asegurar cuánto queda de verdad en el poema."
	)
	panel.set_dialogue_text(long_text, false)
	if panel.get_dialogue_page_count() < 2:
		_fail(panel, "El texto de prueba no se dividió en varias páginas.")
		return
	if not panel.is_waiting_for_page_advance():
		_fail(panel, "La primera página no quedó esperando confirmación.")
		return
	if _visible_line_count(panel.dialogue_label.text) > 2:
		_fail(panel, "La primera página muestra más de dos líneas.")
		return
	var first_page_text := panel.dialogue_label.text
	await create_timer(0.15).timeout
	if panel.dialogue_label.text != first_page_text:
		_fail(panel, "El texto avanzó automáticamente durante la pausa.")
		return
	while panel.is_revealing_dialogue():
		var previous_page := panel.get_dialogue_page_index()
		panel.finish_dialogue_reveal()
		if panel.get_dialogue_page_index() == previous_page:
			_fail(panel, "Enter/F no avanzaría a la página siguiente.")
			return
		# La primera confirmación inicia la nueva página; la segunda completa su
		# escritura para poder validar inmediatamente sus dos líneas.
		panel.finish_dialogue_reveal()
		if _visible_line_count(panel.dialogue_label.text) > 2:
			_fail(panel, "Una página posterior muestra más de dos líneas.")
			return
	if panel.get_dialogue_page_index() != panel.get_dialogue_page_count() - 1:
		_fail(panel, "El diálogo terminó antes de mostrar la última página.")
		return
	panel.queue_free()
	print("DIALOGUE_PAGINATION_VALIDATED")
	quit()


func _visible_line_count(text: String) -> int:
	return text.split("\n", true).size()


func _fail(panel: DialoguePanel, reason: String) -> void:
	panel.queue_free()
	push_error("DialoguePaginationValidation: %s" % reason)
	quit(1)
