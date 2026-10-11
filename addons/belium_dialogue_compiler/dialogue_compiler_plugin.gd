@tool
extends EditorPlugin

const COMPILER_SCRIPT := "res://Tools/Dialogue/compile_dialogue_sources.gd"


## Godot llama a _build antes de ejecutar el proyecto desde el editor. De este
## modo los JSON editables nunca quedan desfasados respecto de sus .res.
func _build() -> bool:
	var project_directory := ProjectSettings.globalize_path("res://")
	var compiler_log := ProjectSettings.globalize_path(
		"res://.godot/dialogue_compiler.log"
	)
	var arguments := PackedStringArray([
		"--headless",
		"--path",
		project_directory,
		"--script",
		COMPILER_SCRIPT,
		"--log-file",
		compiler_log,
	])
	var output: Array = []
	var exit_code := OS.execute(
		OS.get_executable_path(),
		arguments,
		output,
		true
	)
	if exit_code == 0:
		return true
	var details := "\n".join(PackedStringArray(output))
	push_error(
		"No se pudieron compilar los diálogos antes de ejecutar el juego.\n%s"
		% details
	)
	return false
