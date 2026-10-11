extends RefCounted

## Marcas de autoría comunes a NPC, personajes, objetos y elecciones.
## Se interpretan sólo al mostrar texto: nunca se transforman IDs ni JSON.
const LOCATION_COLOR := Color("c45d67")
const CHARACTER_COLOR := Color("3578b8")


static func parse(source: String, color_kind: String = "", italic: bool = false) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var index := 0
	while index < source.length():
		var character := source[index]
		if character == "\\" and index + 1 < source.length() and source[index + 1] in "\\_*'":
			append_run(runs, source[index + 1], color_kind, italic)
			index += 2
			continue
		if character in "_*'" and _can_open(source, index):
			var closing := _find_closing(source, index, character)
			if closing >= 0:
				var next_kind := color_kind
				if character == "_":
					next_kind = "location"
				elif character == "*":
					next_kind = "character"
				var nested := parse(source.substr(index + 1, closing - index - 1), next_kind, italic or character == "'")
				for run in nested:
					append_run(runs, run.text, run.kind, run.italic)
				index = closing + 1
				continue
		append_run(runs, character, color_kind, italic)
		index += 1
	return runs


static func _can_open(source: String, index: int) -> bool:
	return (
		index + 1 < source.length()
		and not source[index + 1] in " \t\r\n"
		and (index == 0 or not _is_word_character(source[index - 1]))
	)


static func _find_closing(source: String, opening: int, delimiter: String) -> int:
	var index := opening + 1
	while index < source.length():
		if source[index] == "\\":
			index += 2
			continue
		if (
			source[index] == delimiter and index > opening + 1
			and source[index - 1] not in " \t\r\n"
			and (index + 1 == source.length() or not _is_word_character(source[index + 1]))
		):
			return index
		index += 1
	return -1


static func _is_word_character(character: String) -> bool:
	return character.to_lower() != character.to_upper() or character in "0123456789"


static func append_run(runs: Array[Dictionary], text: String, kind: String = "", italic: bool = false) -> void:
	if text.is_empty():
		return
	if not runs.is_empty() and runs.back().kind == kind and runs.back().italic == italic:
		runs.back()["text"] += text
	else:
		runs.append({"text": text, "kind": kind, "italic": italic})


static func plain_text(runs: Array[Dictionary]) -> String:
	var result := ""
	for run in runs:
		result += str(run.text)
	return result


static func slice(runs: Array[Dictionary], start: int, end: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offset := 0
	for run in runs:
		var text := str(run.text)
		var from := maxi(start - offset, 0)
		var to := mini(end - offset, text.length())
		if to > from:
			append_run(result, text.substr(from, to - from), run.kind, run.italic)
		offset += text.length()
		if offset >= end:
			break
	return result


static func to_bbcode(runs: Array[Dictionary], location_color: Color = LOCATION_COLOR, character_color: Color = CHARACTER_COLOR) -> String:
	var result := ""
	for run in runs:
		# El BBCode literal del guion no se interpreta como órdenes del panel.
		var text := str(run.text).replace("[", "[lb]")
		if run.italic:
			text = "[i]%s[/i]" % text
		if run.kind == "location":
			text = "[color=#%s]%s[/color]" % [location_color.to_html(false), text]
		elif run.kind == "character":
			text = "[color=#%s]%s[/color]" % [character_color.to_html(false), text]
		result += text
	return result


static func configure_label(label: RichTextLabel, font: Font, font_size: int) -> void:
	label.bbcode_enabled = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_NONE
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("italics_font_size", font_size)
	var italic_font := FontVariation.new()
	italic_font.base_font = font
	# Orbitron no incluye una variante cursiva en el proyecto: se inclina la
	# misma fuente para conservar su aspecto y métricas en todos los dispositivos.
	italic_font.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)
	label.add_theme_font_override("italics_font", italic_font)
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
