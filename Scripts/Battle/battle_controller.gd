class_name BattleController
extends Node

const TRIGGER_TALL_GRASS: StringName = &"tall_grass"
const SLOT_0 := 0

@export_range(0.0, 1.0, 0.001) var tall_grass_encounter_chance := 0.05
@export var wild_slot_0: PokemonBattleVisualData
@export var trainer_slot_0: PokemonBattleVisualData
@export_range(1.0, 2.0, 0.01) var encounter_camera_zoom := 1.5
@export_range(0.0, 2.0, 0.01) var camera_zoom_duration := 0.35
@export_range(0.0, 2.0, 0.01) var battle_screen_fade_duration := 0.45
@export_range(0.0, 5.0, 0.05) var entrance_delay := 1.0
@export_group("Battle music loop")
@export_range(0.0, 600.0, 0.001) var battle_music_loop_start_seconds := 0.0
@export_range(0.0, 600.0, 0.001) var battle_music_loop_end_seconds := 0.0
@export_range(0.01, 0.5, 0.005) var battle_music_crossfade_seconds := 0.08

@onready var _battle_music: AudioStreamPlayer = $BattleMusic
@onready var _battle_music_loop: AudioStreamPlayer = $BattleMusicLoop

var _environment: Node
var _ui_root: OverworldUIRoot
var _battle_screen: BattleScreen
var _transition_overlay: BattleTransitionOverlay
var _player: Node2D
var _player_camera: Camera2D
var _random := RandomNumberGenerator.new()
var _battle_active := false
var _battle_closing := false
var _original_camera_zoom := Vector2.ONE
var _active_battle_music: AudioStreamPlayer
var _battle_music_crossfade_tween: Tween
var _battle_music_fade_tween: Tween
var _battle_music_crossfading := false
var _pending_tall_grass_encounter := false
var _pending_tall_grass_target := Vector2.ZERO
var _pending_tall_grass_enemy: PokemonBattleVisualData


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_active_battle_music = _battle_music
	add_to_group(&"battle_controller")
	_random.randomize()
	_initialize.call_deferred()


func _initialize() -> void:
	_environment = get_parent()
	_ui_root = _environment.get_node_or_null("UIRoot") as OverworldUIRoot
	if _environment.has_method("get_player"):
		_player = _environment.call("get_player") as Node2D
	if _player != null:
		_player_camera = _player.get_node_or_null("Camera2D") as Camera2D
		if _player.has_signal(&"grid_step_started"):
			_player.grid_step_started.connect(_on_player_grid_step_started)
		if _player.has_signal(&"grid_step_completed"):
			_player.grid_step_completed.connect(_on_player_grid_step_completed)
	if _ui_root == null:
		push_warning("BattleController: el mapa no contiene UIRoot.")
		return
	_battle_screen = _ui_root.get_battle_screen()
	_transition_overlay = _ui_root.get_battle_transition_overlay()
	_ui_root.battle_command_selected.connect(_on_battle_command_selected)
	_prewarm_default_battlers.call_deferred()


func _process(_delta: float) -> void:
	_update_battle_music_loop()


## Punto de entrada general para combates. Hoy se usa desde hierba alta; los
## futuros NPC, líderes y eventos podrán invocarlo con otro trigger_reason.
func request_battle(
	trigger_reason: StringName,
	enemy_data: PokemonBattleVisualData = null
) -> bool:
	if _battle_active or _battle_closing or _ui_root == null:
		return false
	var selected_enemy := enemy_data
	if selected_enemy == null:
		selected_enemy = wild_slot_0
	if selected_enemy == null or selected_enemy.battler_scene == null:
		push_warning("BattleController: falta la presentación del Pokémon rival.")
		return false
	if not _ui_root.enter_battle_mode():
		return false
	_battle_active = true
	_original_camera_zoom = (
		_player_camera.zoom if _player_camera != null else Vector2.ONE
	)
	_run_battle_intro.call_deferred(trigger_reason, selected_enemy)
	return true


func is_battle_active() -> bool:
	return _battle_active


## El intervalo [0.0, 0.05) representa exactamente el 5 % del dominio [0, 1).
## No usa contador de compasión ni modifica tiradas posteriores.
func should_trigger_tall_grass_encounter(chance_roll: float) -> bool:
	return chance_roll >= 0.0 and chance_roll < tall_grass_encounter_chance


## La tabla inicial sólo tiene slot_0, por lo que su selección es del 100 %.
func select_wild_slot(_slot_roll: float) -> int:
	return SLOT_0


func _prewarm_default_battlers() -> void:
	if (
		_battle_screen == null
		or wild_slot_0 == null
		or trainer_slot_0 == null
	):
		return
	await _battle_screen.prepare_battlers(trainer_slot_0, wild_slot_0)


func _on_player_grid_step_started(
	_start_position: Vector2,
	target_position: Vector2,
	_direction: Vector2
) -> void:
	_clear_pending_tall_grass_encounter()
	if _battle_active or _battle_closing:
		return
	if not _environment.has_method("is_tall_grass_at_world_position"):
		return
	if not bool(_environment.call(
		"is_tall_grass_at_world_position", target_position
	)):
		return
	if not should_trigger_tall_grass_encounter(_random.randf()):
		return
	if select_wild_slot(_random.randf()) == SLOT_0:
		_pending_tall_grass_encounter = true
		_pending_tall_grass_target = target_position
		_pending_tall_grass_enemy = wild_slot_0


func _on_player_grid_step_completed(
	world_position: Vector2,
	_direction: Vector2
) -> void:
	if not _pending_tall_grass_encounter:
		return
	var reached_pending_target := world_position.is_equal_approx(
		_pending_tall_grass_target
	)
	var selected_enemy := _pending_tall_grass_enemy
	_clear_pending_tall_grass_encounter()
	if not reached_pending_target:
		return
	request_battle(TRIGGER_TALL_GRASS, selected_enemy)


func _clear_pending_tall_grass_encounter() -> void:
	_pending_tall_grass_encounter = false
	_pending_tall_grass_target = Vector2.ZERO
	_pending_tall_grass_enemy = null


func _run_battle_intro(
	_trigger_reason: StringName,
	enemy_data: PokemonBattleVisualData
) -> void:
	if not await _battle_screen.prepare_battlers(trainer_slot_0, enemy_data):
		_abort_battle_start()
		return
	_start_battle_music()
	await _transition_overlay.play_three_black_flashes()
	await _tween_camera_zoom(
		_original_camera_zoom * encounter_camera_zoom,
		camera_zoom_duration
	)
	if not _ui_root.show_battle_screen(1, 1):
		_abort_battle_start()
		return
	await _battle_screen.fade_in(battle_screen_fade_duration)
	await get_tree().create_timer(entrance_delay, true, false, true).timeout
	if not _battle_active or _battle_closing:
		return
	await _battle_screen.play_enemy_entrance()


func _on_battle_command_selected(command_id: StringName) -> void:
	if command_id != BattleScreen.COMMAND_RUN:
		return
	if not _battle_active or _battle_closing:
		return
	_close_battle.call_deferred()


func _close_battle() -> void:
	_battle_closing = true
	_battle_screen.hide_commands()
	_fade_battle_music(battle_screen_fade_duration)
	_tween_camera_zoom(_original_camera_zoom, battle_screen_fade_duration)
	await _battle_screen.fade_out(battle_screen_fade_duration)
	_stop_battle_music()
	_ui_root.hide_battle_screen()
	if _player_camera != null:
		_player_camera.zoom = _original_camera_zoom
	_battle_active = false
	_battle_closing = false


func _start_battle_music() -> void:
	if _battle_music.stream == null:
		return
	_stop_battle_music()
	var playback_stream := _battle_music.stream.duplicate()
	if playback_stream is AudioStreamOggVorbis:
		(playback_stream as AudioStreamOggVorbis).loop = false
	_battle_music.stream = playback_stream
	_battle_music_loop.stream = playback_stream
	_active_battle_music = _battle_music
	_battle_music.volume_linear = 1.0
	_battle_music.play()


func _fade_battle_music(duration: float) -> void:
	_kill_battle_music_tweens()
	var playing_players := _get_playing_battle_music_players()
	if playing_players.is_empty():
		return
	_battle_music_fade_tween = create_tween()
	_battle_music_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_battle_music_fade_tween.set_parallel(true)
	for player: AudioStreamPlayer in playing_players:
		_battle_music_fade_tween.tween_property(
			player, "volume_linear", 0.0, duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _update_battle_music_loop() -> void:
	if (
		_battle_music_crossfading
		or _battle_closing
		or _active_battle_music == null
		or not _active_battle_music.playing
		or battle_music_loop_end_seconds <= battle_music_loop_start_seconds
	):
		return
	var crossfade_start := (
		battle_music_loop_end_seconds - battle_music_crossfade_seconds
	)
	var playback_position := _active_battle_music.get_playback_position()
	if playback_position < crossfade_start:
		return
	var remaining_time := maxf(
		battle_music_loop_end_seconds - playback_position,
		0.01
	)
	var elapsed_crossfade := maxf(playback_position - crossfade_start, 0.0)
	_begin_battle_music_crossfade(
		maxf(
			battle_music_loop_start_seconds
			- battle_music_crossfade_seconds
			+ elapsed_crossfade,
			0.0
		),
		minf(remaining_time, battle_music_crossfade_seconds)
	)


func _begin_battle_music_crossfade(
	loop_position: float,
	duration: float
) -> void:
	_battle_music_crossfading = true
	var outgoing := _active_battle_music
	var incoming := (
		_battle_music_loop if outgoing == _battle_music else _battle_music
	)
	incoming.stop()
	incoming.volume_linear = 0.0
	incoming.play(loop_position)
	_battle_music_crossfade_tween = create_tween()
	_battle_music_crossfade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_battle_music_crossfade_tween.tween_method(
		_set_battle_music_crossfade.bind(outgoing, incoming),
		0.0,
		1.0,
		duration
	)
	_battle_music_crossfade_tween.finished.connect(
		_finish_battle_music_crossfade.bind(outgoing, incoming),
		CONNECT_ONE_SHOT
	)


func _finish_battle_music_crossfade(
	outgoing: AudioStreamPlayer,
	incoming: AudioStreamPlayer
) -> void:
	if not is_instance_valid(outgoing) or not is_instance_valid(incoming):
		return
	outgoing.stop()
	outgoing.volume_linear = 1.0
	incoming.volume_linear = 1.0
	_active_battle_music = incoming
	_battle_music_crossfade_tween = null
	_battle_music_crossfading = false


func _set_battle_music_crossfade(
	weight: float,
	outgoing: AudioStreamPlayer,
	incoming: AudioStreamPlayer
) -> void:
	if not is_instance_valid(outgoing) or not is_instance_valid(incoming):
		return
	var angle := clampf(weight, 0.0, 1.0) * PI * 0.5
	outgoing.volume_linear = cos(angle)
	incoming.volume_linear = sin(angle)


func _get_playing_battle_music_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	if _battle_music.playing:
		players.append(_battle_music)
	if _battle_music_loop.playing:
		players.append(_battle_music_loop)
	return players


func _kill_battle_music_tweens() -> void:
	if is_instance_valid(_battle_music_crossfade_tween):
		_battle_music_crossfade_tween.kill()
	_battle_music_crossfade_tween = null
	if is_instance_valid(_battle_music_fade_tween):
		_battle_music_fade_tween.kill()
	_battle_music_fade_tween = null
	_battle_music_crossfading = false


func _stop_battle_music() -> void:
	_kill_battle_music_tweens()
	_battle_music.stop()
	_battle_music_loop.stop()
	_battle_music.volume_linear = 1.0
	_battle_music_loop.volume_linear = 1.0
	_active_battle_music = _battle_music


func _tween_camera_zoom(target_zoom: Vector2, duration: float) -> void:
	if _player_camera == null:
		return
	if duration <= 0.0:
		_player_camera.zoom = target_zoom
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		_player_camera, "zoom", target_zoom, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _abort_battle_start() -> void:
	_stop_battle_music()
	if _transition_overlay != null:
		_transition_overlay.reset()
	if _player_camera != null:
		_player_camera.zoom = _original_camera_zoom
	_ui_root.hide_battle_screen()
	_battle_active = false
	_battle_closing = false
