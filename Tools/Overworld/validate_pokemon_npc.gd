extends SceneTree

const MAP_SCENE := preload("res://Maps/map_001_leaftown_201_sandtown_202.tscn")
const POKEMON_SCRIPT := preload("res://Scripts/NPC/pokemon_walking_npc.gd")

var _failures: Array[String] = []
var _test_paths: Array[String] = []


func _init() -> void:
	call_deferred(&"_run_validation")


func _run_validation() -> void:
	# Nunca cargar, borrar ni modificar el save/pre-save real durante la prueba.
	var saves := root.get_node("SaveManager")
	var prefix := "res://.godot/pokemon_validation_%s" % Time.get_ticks_usec()
	for property in ["_save_path", "_pre_save_path", "_identity_path"]:
		var path: String = prefix + property + ".json"
		saves.set(property, path)
		_test_paths.append(path)

	var map := MAP_SCENE.instantiate() as Node2D
	map.get_node("MovementGridGuide").set("show_grid", false)
	root.add_child(map)
	var pokemon = map.get_node("Mapa/Casas/NPCs/Starly")
	var harry = map.get_node("Mapa/Casas/NPCs/OldMan")
	var player = map.get_node("Mapa/Casas/CynthiaPlayer")
	var ui = map.get_node("UIRoot")
	# Revisar la instancia efectiva: el mapa puede sobrescribir el script de
	# la escena original aunque esa escena, aislada, esté bien configurada.
	if pokemon.get_script() != POKEMON_SCRIPT:
		_check(false, "La instancia Starly del mapa sobrescribe el script Pokémon.")
		await _finish_validation(map)
		return
	var initial_position: Vector2 = pokemon.global_position
	for actor in [pokemon, harry, player]:
		actor.set_physics_process(false)
	player.set_movement_locked(true)
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

	_check(pokemon.get_script() == POKEMON_SCRIPT, "Starly usa el script especializado.")
	_check(pokemon.is_in_group(&"grid_movement_actor"), "Conserva la cuadrícula compartida.")
	_check(pokemon.is_in_group(&"dialogue_interactable"), "Es detectable al interactuar.")
	_check(pokemon.is_in_group(&"pokemon_npc"), "Está identificado como Pokémon.")
	_check(pokemon.has_method("interact_in_overworld"), "Interacción Pokémon independiente del npc_id.")
	_check(is_equal_approx(pokemon.movement_probability, 0.70), "Probabilidad Pokémon: 70%.")
	_check(is_equal_approx(harry.movement_probability, 0.10), "Harry conserva su 10%.")
	_check(is_equal_approx(harry.minimum_decision_delay, 2.5), "Pausa humana intacta.")
	_check(is_equal_approx(pokemon.minimum_decision_delay, 0.8), "Pausa mínima Pokémon.")
	_check(is_equal_approx(pokemon.maximum_decision_delay, 1.8), "Pausa máxima Pokémon.")
	_check(is_equal_approx(pokemon.grid_cell_size, 20.0), "Celda de 20 px.")
	_check(pokemon.global_position.is_equal_approx(initial_position), "Sin teletransporte al cargar.")
	for facing in ["down", "up", "left", "right"]:
		for state in ["idle", "walk"]:
			_check(pokemon._sprite.sprite_frames.has_animation(state + "_" + facing),
				"Animación %s_%s disponible." % [state, facing])

	# El primer paso corrige el origen colocado a mano, con segmentos cardinales.
	var started := false
	for direction in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]:
		if pokemon.try_start_grid_step(direction):
			started = true
			break
	_check(started, "Puede empezar a caminar desde su posición real en el mapa.")
	_check(_finish_step(pokemon), "Termina la corrección por ejes sin saltos ni diagonales.")
	var guide = map.get_node("MovementGridGuide")
	var relative: Vector2 = (pokemon.global_position - guide.grid_origin) / 20.0
	_check(relative.is_equal_approx(relative.round()), "Primer paso termina alineado.")
	_check(pokemon.global_position.distance_to(pokemon._home_position) <= 85.0,
		"Conserva el radio de paseo alrededor de su hogar.")

	var audio := pokemon.get_node("CryAudio") as AudioStreamPlayer
	_check(audio.stream != null, "Tiene audio asignado.")
	_check(not (audio.stream as AudioStreamOggVorbis).loop, "El grito no tiene bucle.")
	_check(audio.stream != pokemon.cry_stream, "No modifica el recurso de audio compartido.")
	var sound_bus := AudioServer.get_bus_index(&"Map_Sound")
	var sound_bus_volume := AudioServer.get_bus_volume_db(sound_bus)

	# Teclas por el recorrido real de input, no por una llamada directa al grito.
	player.global_position = pokemon.global_position + Vector2.DOWN * 20.0
	player.last_cardinal_direction = Vector2.UP
	await physics_frame
	await process_frame
	_check(map.get_interactable_in_front() == pokemon, "Detecta a Starly desde la celda vecina.")
	var collision: KinematicCollision2D = player.move_and_collide(Vector2.UP * 20.0, true)
	if collision == null or collision.get_collider() != pokemon:
		print("Collision diagnostic: player=%s pokemon=%s collider=%s" % [
			player.global_position, pokemon.global_position,
			collision.get_collider() if collision != null else null])
		print("Collision setup: player layer=%s mask=%s shape=%s; pokemon layer=%s mask=%s shape=%s" % [
			player.collision_layer, player.collision_mask, player.get_node("CollisionShape2D").shape,
			pokemon.collision_layer, pokemon.collision_mask, pokemon.get_node("CollisionShape2D").shape])
	_check(collision != null and collision.get_collider() == pokemon,
		"Cynthia colisiona con Starly.")
	_press_key(KEY_ENTER)
	_check(pokemon.is_crying() and audio.playing, "Enter reproduce el grito.")
	_check(not ui._menu_open, "Enter frente a Starly no abre el menú.")
	_check(not ui.get_node("DialogueRunner").is_active(), "No abre un diálogo humano.")
	if pokemon._facing != &"down":
		print("Facing diagnostic: direction=%s facing=%s" % [
			player.global_position - pokemon.global_position, pokemon._facing])
	_check(pokemon._facing == &"down", "Starly mira hacia Cynthia.")
	_check(audio.bus == &"Map_Sound", "Usa Map_Sound.")
	var expected_cry_volume: float = float(pokemon.cry_volume_percent) / 100.0
	_check(
		absf(audio.volume_linear - expected_cry_volume) < 0.001,
		"El volumen local respeta su configuración (actual: %.4f; esperado: %.4f)." % [
			audio.volume_linear,
			expected_cry_volume,
		]
	)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(sound_bus), sound_bus_volume),
		"El volumen de otros sonidos del bus no cambia.")
	var standing_position: Vector2 = pokemon.global_position
	pokemon._physics_process(5.0)
	_check(pokemon.global_position.is_equal_approx(standing_position), "Se detiene al emitir el grito.")
	await create_timer(0.12).timeout
	var playback_before := audio.get_playback_position()
	_press_key(KEY_F)
	_check(audio.get_playback_position() >= playback_before - 0.02,
		"Pulsaciones repetidas no reinician ni superponen el grito.")
	_check(await _wait_for_cry(pokemon, audio.stream.get_length() + 1.0),
		"El audio termina y libera el movimiento.")
	_check(not pokemon._interaction_locked, "Starly vuelve a poder caminar.")
	_press_key(KEY_F, true)
	_check(not pokemon.is_crying(), "Mantener pulsada la tecla no repite el audio.")
	var configured_npc_id: StringName = pokemon.npc_id
	pokemon.npc_id = &""
	_press_key(KEY_F)
	_check(pokemon.is_crying(), "F inicia el grito incluso sin npc_id.")
	pokemon.npc_id = configured_npc_id
	_check(await _wait_for_cry(pokemon, audio.stream.get_length() + 1.0), "Segundo grito termina.")

	# Desde todos los lados, pero no mirando en sentido contrario o desde lejos.
	for facing in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		player.global_position = pokemon.global_position - facing * 20.0
		player.last_cardinal_direction = facing
		_check(map.get_interactable_in_front() == pokemon, "Interactuable desde %s." % facing)
		pokemon.face_toward(player.global_position)
		_check(pokemon._facing == _facing_name(-facing), "Mira al jugador desde %s." % facing)
	player.last_cardinal_direction = Vector2.LEFT
	_check(map.get_interactable_in_front() != pokemon, "No interactúa si le da la espalda.")
	player.global_position = pokemon.global_position + Vector2.DOWN * 100.0
	player.last_cardinal_direction = Vector2.UP
	_check(map.get_interactable_in_front() != pokemon, "No interactúa a distancia.")
	player.global_position = pokemon.global_position + Vector2.DOWN * 20.0
	player.last_cardinal_direction = Vector2.DOWN
	_press_key(KEY_ENTER)
	_check(ui._menu_open and not pokemon.is_crying(), "El menú funciona cuando no hay objetivo enfrente.")
	ui._close_menu()
	player.set_movement_locked(true)

	# Interrumpir un paso con el grito no cambia su destino ni teletransporta.
	player.global_position = pokemon.global_position + Vector2(100.0, 100.0)
	started = false
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		if pokemon.try_start_grid_step(direction):
			started = true
			break
	_check(started, "Puede iniciar otro paso.")
	pokemon._physics_process(0.1)
	var step_target: Vector2 = pokemon._step_target
	var step_direction: Vector2 = pokemon._step_direction
	player.global_position = pokemon.global_position + Vector2(-step_direction.y, step_direction.x) * 20.0
	player.last_cardinal_direction = (pokemon.global_position - player.global_position).normalized()
	_press_key(KEY_F)
	_check(pokemon.is_crying(), "Responde también a mitad de un paso.")
	standing_position = pokemon.global_position
	pokemon._physics_process(1.0)
	_check(pokemon.global_position.is_equal_approx(standing_position), "Pausa el paso sin salto.")
	_check(await _wait_for_cry(pokemon, audio.stream.get_length() + 1.0), "Grito intermedio termina.")
	_check(pokemon._step_target.is_equal_approx(step_target), "Conserva el destino del paso.")
	_check(_finish_step(pokemon), "Retoma y termina el paso original.")
	_check(pokemon.global_position.is_equal_approx(step_target), "Llega al destino original.")

	# Sigue funcionando el NPC humano y no se le asigna el reproductor Pokémon.
	_check(not harry.has_node("CryAudio"), "Harry no recibe cambios de audio.")
	player.global_position = harry.global_position + Vector2.DOWN * 20.0
	player.last_cardinal_direction = Vector2.UP
	ui._on_active_camera_zone_changed(&"leaftown", "Pueblo Hojaverde")
	_check(map.get_interactable_in_front() == harry, "Harry continúa siendo interactuable.")
	_check(ui._try_start_dialogue(), "La ruta de diálogo humano sigue disponible.")
	_check(ui.get_node("DialogueRunner").is_active(), "Harry sigue abriendo su panel.")
	await _finish_validation(map)


func _finish_validation(map: Node) -> void:
	map.queue_free()
	await process_frame
	for path in _test_paths:
		for suffix in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	if _failures.is_empty():
		print("POKEMON_NPC_VALIDATED: grid, collision, movement, Enter/F, configured one-shot cry, Map_Sound, human dialogue.")
	quit(0 if _failures.is_empty() else 1)


func _press_key(key: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	var release := InputEventKey.new()
	release.physical_keycode = key
	release.pressed = false
	root.push_input(release)


func _wait_for_cry(pokemon: Node, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while pokemon.is_crying() and Time.get_ticks_msec() < deadline:
		await process_frame
	return not pokemon.is_crying()


func _finish_step(pokemon: Node) -> bool:
	for frame in range(180):
		if not pokemon._is_stepping:
			return true
		var previous: Vector2 = pokemon.global_position
		pokemon._physics_process(1.0 / 60.0)
		var delta: Vector2 = pokemon.global_position - previous
		if absf(delta.x) > 0.001 and absf(delta.y) > 0.001:
			return false
		if delta.length() > pokemon.walking_speed / 60.0 + 0.001:
			return false
		if pokemon._is_stepping and pokemon._facing != _facing_name(pokemon._step_direction):
			return false
	return false


func _facing_name(direction: Vector2) -> StringName:
	if absf(direction.x) > absf(direction.y):
		return &"left" if direction.x < 0.0 else &"right"
	return &"up" if direction.y < 0.0 else &"down"


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("PokemonNPCValidation: " + message)
