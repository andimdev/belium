class_name BattleController
extends Node

const TRIGGER_TALL_GRASS: StringName = &"tall_grass"
const SLOT_0 := 0

@export_range(0.0, 1.0, 0.001) var tall_grass_encounter_chance := 0.05
@export var wild_slot_0: PokemonBattleVisualData
@export_range(1.0, 2.0, 0.01) var encounter_camera_zoom := 1.5
@export_range(0.0, 2.0, 0.01) var camera_zoom_duration := 0.35
@export_range(0.0, 2.0, 0.01) var battle_screen_fade_duration := 0.45
@export_range(0.0, 5.0, 0.05) var entrance_delay := 1.0

@onready var _battle_music: AudioStreamPlayer = $BattleMusic

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		if _player.has_signal(&"grid_step_completed"):
			_player.grid_step_completed.connect(_on_player_grid_step_completed)
	if _ui_root == null:
		push_warning("BattleController: el mapa no contiene UIRoot.")
		return
	_battle_screen = _ui_root.get_battle_screen()
	_transition_overlay = _ui_root.get_battle_transition_overlay()
	_ui_root.battle_command_selected.connect(_on_battle_command_selected)
	_prewarm_default_enemy.call_deferred()


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


func _prewarm_default_enemy() -> void:
	if _battle_screen == null or wild_slot_0 == null:
		return
	await _battle_screen.prepare_enemy(wild_slot_0)


func _on_player_grid_step_completed(
	world_position: Vector2,
	_direction: Vector2
) -> void:
	if _battle_active or _battle_closing:
		return
	if not _environment.has_method("is_tall_grass_at_world_position"):
		return
	if not bool(_environment.call(
		"is_tall_grass_at_world_position", world_position
	)):
		return
	if not should_trigger_tall_grass_encounter(_random.randf()):
		return
	if select_wild_slot(_random.randf()) == SLOT_0:
		request_battle(TRIGGER_TALL_GRASS, wild_slot_0)


func _run_battle_intro(
	_trigger_reason: StringName,
	enemy_data: PokemonBattleVisualData
) -> void:
	if not await _battle_screen.prepare_enemy(enemy_data):
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
	_battle_music.stop()
	_battle_music.volume_db = 0.0
	_ui_root.hide_battle_screen()
	if _player_camera != null:
		_player_camera.zoom = _original_camera_zoom
	_battle_active = false
	_battle_closing = false


func _start_battle_music() -> void:
	if _battle_music.stream == null:
		return
	if _battle_music.stream is AudioStreamOggVorbis:
		var looping_stream := _battle_music.stream.duplicate() as AudioStreamOggVorbis
		looping_stream.loop = true
		_battle_music.stream = looping_stream
	_battle_music.volume_db = 0.0
	_battle_music.play()


func _fade_battle_music(duration: float) -> void:
	if not _battle_music.playing:
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		_battle_music, "volume_db", -60.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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
	_battle_music.stop()
	if _transition_overlay != null:
		_transition_overlay.reset()
	if _player_camera != null:
		_player_camera.zoom = _original_camera_zoom
	_ui_root.hide_battle_screen()
	_battle_active = false
	_battle_closing = false
