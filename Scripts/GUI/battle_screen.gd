class_name BattleScreen
extends Control

signal command_selected(command_id: StringName)

const COMMAND_ATTACK: StringName = &"attack"
const COMMAND_POKEMON: StringName = &"pokemon"
const COMMAND_BAG: StringName = &"bag"
const COMMAND_RUN: StringName = &"run"

const PLAYER_SINGLE_RECT := Rect2(0.03, 0.48, 0.42, 0.36)
const ENEMY_SINGLE_RECT := Rect2(0.56, 0.08, 0.41, 0.36)
const PLAYER_DOUBLE_PRIMARY_RECT := Rect2(0.03, 0.52, 0.31, 0.30)
const PLAYER_DOUBLE_SECONDARY_RECT := Rect2(0.27, 0.37, 0.31, 0.30)
const ENEMY_DOUBLE_PRIMARY_RECT := Rect2(0.66, 0.07, 0.31, 0.30)
const ENEMY_DOUBLE_SECONDARY_RECT := Rect2(0.43, 0.22, 0.31, 0.30)

@export var background_texture: Texture2D
@export var fallback_background_color := Color.WHITE
@export_range(1, 2, 1) var player_slot_count := 1
@export_range(1, 2, 1) var enemy_slot_count := 1
@export var show_presentation_guides := false
@export_group("Ground shadows")
@export_range(0.1, 1.0, 0.01) var ground_shadow_width_ratio := 0.74
@export_range(0.1, 1.0, 0.01) var ground_shadow_height_ratio := 0.48

@onready var _background: Control = $Background
@onready var _fallback_background: ColorRect = \
	get_node_or_null("Background/FallbackColor") as ColorRect
@onready var _background_texture: TextureRect = $Background/Texture
@onready var _battle_stage: Control = $BattleStage
@onready var _player_ground_base: TextureRect = $BattleStage/PlayerGroundBase
@onready var _enemy_ground_base: TextureRect = $BattleStage/EnemyGroundBase
@onready var _player_ground_shadow: Polygon2D = $BattleStage/PlayerGroundShadow
@onready var _enemy_ground_shadow: Polygon2D = $BattleStage/EnemyGroundShadow
@onready var _viewport_mount: Control = $BattleStage/BattleViewportMount
@onready var _viewport_container: SubViewportContainer = \
	$BattleStage/BattleViewportMount/BattleViewportContainer
@onready var _battle_viewport: SubViewport = \
	$BattleStage/BattleViewportMount/BattleViewportContainer/BattleViewport
@onready var _player_anchor: Node3D = \
	$BattleStage/BattleViewportMount/BattleViewportContainer/BattleViewport/BattleWorld3D/PlayerPokemonAnchor
@onready var _enemy_anchor: Node3D = \
	$BattleStage/BattleViewportMount/BattleViewportContainer/BattleViewport/BattleWorld3D/EnemyPokemonAnchor
@onready var _battle_camera: Camera3D = \
	$BattleStage/BattleViewportMount/BattleViewportContainer/BattleViewport/BattleWorld3D/BattleCamera
@onready var _presentation_guides: Control = $BattleStage/PresentationGuides
@onready var _player_primary: Control = \
	$BattleStage/PresentationGuides/PlayerPrimary
@onready var _player_secondary: Control = \
	$BattleStage/PresentationGuides/PlayerSecondary
@onready var _enemy_primary: Control = \
	$BattleStage/PresentationGuides/EnemyPrimary
@onready var _enemy_secondary: Control = \
	$BattleStage/PresentationGuides/EnemySecondary
@onready var _attack_button: Button = \
	$CommandPanel/Content/Commands/Attack
@onready var _pokemon_button: Button = \
	$CommandPanel/Content/Commands/Pokemon
@onready var _bag_button: Button = \
	$CommandPanel/Content/Commands/Bag
@onready var _run_button: Button = \
	$CommandPanel/Content/Commands/Run
@onready var _command_panel: PanelContainer = $CommandPanel
@onready var _cry_player: AudioStreamPlayer = $PokemonCry
@onready var _battle_wind: Control = $BattleWind

var _command_buttons: Dictionary = {}
var _player_data: PokemonBattleVisualData
var _player_battler: PokemonBattler3D
var _enemy_data: PokemonBattleVisualData
var _enemy_battler: PokemonBattler3D
var _screen_tween: Tween
var _command_tween: Tween
var _weather_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visibility_changed.connect(_sync_wind_activity)
	_player_ground_base.resized.connect(_sync_ground_shadows)
	_enemy_ground_base.resized.connect(_sync_ground_shadows)
	_configure_battle_camera()
	_command_buttons = {
		COMMAND_ATTACK: _attack_button,
		COMMAND_POKEMON: _pokemon_button,
		COMMAND_BAG: _bag_button,
		COMMAND_RUN: _run_button,
	}
	for command_id: StringName in _command_buttons:
		var button := _command_buttons[command_id] as Button
		button.pressed.connect(_emit_command.bind(command_id))
		button.mouse_entered.connect(Callable(button, "grab_focus"))
	_apply_background()
	_sync_ground_shadows()
	_set_battle_tint(Color.WHITE)
	_sync_wind_activity()
	set_presentation_guides_visible(show_presentation_guides)
	hide_commands()
	if not configure_slot_counts(player_slot_count, enemy_slot_count):
		configure_slot_counts(1, 1)


func set_background_texture(texture: Texture2D) -> void:
	background_texture = texture
	if is_node_ready():
		_apply_background()


func set_fallback_background_color(color: Color) -> void:
	fallback_background_color = color
	if is_node_ready() and _fallback_background != null:
		_fallback_background.color = color


## Hereda la luz y la densidad atmosférica del mapa. La batalla reutiliza sólo
## las estelas de viento: nubes y remolinos permanecen fuera de esta interfaz.
func apply_weather_profile(
	profile: Dictionary,
	transition_duration: float = 0.0
) -> void:
	var target_tint: Color = profile.get("tint", Color.WHITE)
	var target_wind_count := int(profile.get("wind_count", 0))
	if is_instance_valid(_weather_tween):
		_weather_tween.kill()
		_weather_tween = null
	_battle_wind.call(
		"set_weather_profile",
		target_wind_count,
		0.0,
		transition_duration
	)
	if transition_duration <= 0.0:
		_set_battle_tint(target_tint)
		return
	_weather_tween = create_tween()
	_weather_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_weather_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_weather_tween.tween_method(
		_set_battle_tint,
		_background.modulate,
		target_tint,
		transition_duration
	)
	_weather_tween.finished.connect(_on_weather_tween_finished)


## Admite los diseños estándar singles y dobles. Las composiciones 3v1/4v1 se
## definirán cuando sus reglas de batalla estén cerradas; no se simulan aquí.
func configure_slot_counts(player_count: int, enemy_count: int) -> bool:
	if player_count < 1 or player_count > 2 or enemy_count < 1 or enemy_count > 2:
		push_warning(
			"BattleScreen: por ahora sólo se admiten uno o dos Pokémon por lado."
		)
		return false
	player_slot_count = player_count
	enemy_slot_count = enemy_count
	_player_secondary.visible = player_count == 2
	_enemy_secondary.visible = enemy_count == 2
	_apply_slot_layout()
	return true


func set_presentation_guides_visible(should_show: bool) -> void:
	show_presentation_guides = should_show
	if is_node_ready():
		_presentation_guides.visible = should_show


func get_viewport_mount() -> Control:
	return _viewport_mount


func prepare_battlers(
	player_data: PokemonBattleVisualData,
	enemy_data: PokemonBattleVisualData
) -> bool:
	if not await prepare_enemy(enemy_data):
		return false
	return await prepare_player(player_data)


func prepare_enemy(enemy_data: PokemonBattleVisualData) -> bool:
	if enemy_data == null or enemy_data.battler_scene == null:
		_enemy_ground_base.visible = false
		_enemy_ground_shadow.visible = false
		return false
	hide_commands()
	modulate.a = 0.0
	_cry_player.stop()
	_cry_player.stream = enemy_data.cry
	_enemy_anchor.position = enemy_data.enemy_position
	_enemy_anchor.rotation_degrees = enemy_data.enemy_rotation_degrees
	_enemy_ground_base.visible = true
	_enemy_ground_shadow.visible = true
	if (
		_enemy_data != null
		and _enemy_data.asset_id == enemy_data.asset_id
		and is_instance_valid(_enemy_battler)
	):
		_enemy_battler.play_idle()
		return true

	_clear_enemy_battler()
	_enemy_data = enemy_data
	var battler := enemy_data.battler_scene.instantiate() as PokemonBattler3D
	if battler == null:
		push_warning("BattleScreen: la escena rival no es PokemonBattler3D.")
		return false
	_enemy_anchor.add_child(battler)
	_enemy_battler = battler
	_enemy_battler.scale = Vector3.ONE * enemy_data.enemy_scale
	await get_tree().process_frame
	_enemy_battler.play_idle()
	await _fit_enemy_to_height(enemy_data)
	return true


func prepare_player(player_data: PokemonBattleVisualData) -> bool:
	if player_data == null or player_data.battler_scene == null:
		_player_ground_base.visible = false
		_player_ground_shadow.visible = false
		return false
	_player_anchor.position = player_data.player_position
	_player_anchor.rotation_degrees = player_data.player_rotation_degrees
	_player_ground_base.visible = true
	_player_ground_shadow.visible = true
	if (
		_player_data != null
		and _player_data.asset_id == player_data.asset_id
		and is_instance_valid(_player_battler)
	):
		_player_battler.play_idle()
		return true

	_clear_player_battler()
	_player_data = player_data
	var battler := player_data.battler_scene.instantiate() as PokemonBattler3D
	if battler == null:
		push_warning(
			"BattleScreen: la escena del Pokémon entrenador no es PokemonBattler3D."
		)
		return false
	_player_anchor.add_child(battler)
	_player_battler = battler
	_player_battler.scale = Vector3.ONE * player_data.player_scale
	await get_tree().process_frame
	_player_battler.play_idle()
	await _fit_player_to_height(player_data)
	return true


func fade_in(duration: float = 0.45) -> void:
	_kill_screen_tween()
	visible = true
	_battle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	modulate.a = 0.0
	if duration <= 0.0:
		modulate.a = 1.0
		return
	_screen_tween = create_tween()
	_screen_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_screen_tween.tween_property(
		self, "modulate:a", 1.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _screen_tween.finished
	_screen_tween = null


func fade_out(duration: float = 0.45) -> void:
	_kill_screen_tween()
	if duration <= 0.0:
		modulate.a = 0.0
		_battle_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_screen_tween = create_tween()
	_screen_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_screen_tween.tween_property(
		self, "modulate:a", 0.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _screen_tween.finished
	_screen_tween = null
	_battle_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func play_enemy_entrance() -> void:
	if not is_instance_valid(_enemy_battler):
		show_commands()
		return
	if _cry_player.stream != null:
		_cry_player.play()
	if _enemy_battler.play_action(&"battle_enter", false):
		var completed_action: StringName = await _enemy_battler.action_finished
		while completed_action != &"battle_enter":
			completed_action = await _enemy_battler.action_finished
	_enemy_battler.play_idle()
	await show_commands()


func show_commands(duration: float = 0.24) -> void:
	_kill_command_tween()
	_command_panel.visible = true
	_command_panel.modulate.a = 0.0
	if duration <= 0.0:
		_command_panel.modulate.a = 1.0
		focus_default_command()
		return
	_command_tween = create_tween()
	_command_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_command_tween.tween_property(
		_command_panel, "modulate:a", 1.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _command_tween.finished
	_command_tween = null
	focus_default_command()


func hide_commands() -> void:
	_kill_command_tween()
	_command_panel.visible = false
	_command_panel.modulate.a = 0.0


func get_enemy_visual_height_px() -> float:
	return _get_battler_visual_height_px(_enemy_battler)


func get_player_visual_height_px() -> float:
	return _get_battler_visual_height_px(_player_battler)


func _get_battler_visual_height_px(battler: PokemonBattler3D) -> float:
	if not is_instance_valid(battler):
		return 0.0
	var minimum_y := INF
	var maximum_y := -INF
	for world_point in battler.get_visual_world_points():
		if _battle_camera.is_position_behind(world_point):
			continue
		var screen_point := _battle_camera.unproject_position(world_point)
		minimum_y = minf(minimum_y, screen_point.y)
		maximum_y = maxf(maximum_y, screen_point.y)
	if minimum_y == INF:
		return 0.0
	return maximum_y - minimum_y


func set_command_enabled(command_id: StringName, enabled: bool) -> void:
	if not _command_buttons.has(command_id):
		push_warning("BattleScreen: comando desconocido '%s'." % command_id)
		return
	var button := _command_buttons[command_id] as Button
	button.disabled = not enabled


func focus_default_command() -> void:
	if not _command_panel.visible:
		return
	if not _attack_button.disabled:
		_attack_button.grab_focus.call_deferred()
		return
	for button: Button in _command_buttons.values():
		if not button.disabled:
			button.grab_focus.call_deferred()
			return


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var physical_key := key_event.physical_keycode
	if physical_key == 0:
		physical_key = key_event.keycode
	if physical_key != KEY_F:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is Button and _command_buttons.values().has(focus_owner):
		(focus_owner as Button).emit_signal(&"pressed")
		get_viewport().set_input_as_handled()


func _emit_command(command_id: StringName) -> void:
	command_selected.emit(command_id)


func _apply_background() -> void:
	if _fallback_background != null:
		_fallback_background.color = fallback_background_color
	_background_texture.texture = background_texture
	_background_texture.visible = background_texture != null


func _sync_ground_shadows() -> void:
	_sync_ground_shadow(_player_ground_base, _player_ground_shadow)
	_sync_ground_shadow(_enemy_ground_base, _enemy_ground_shadow)


func _sync_ground_shadow(base: Control, shadow: Polygon2D) -> void:
	shadow.rotation = 0.0
	var radius := base.size * Vector2(
		ground_shadow_width_ratio,
		ground_shadow_height_ratio
	) * 0.5
	var points := PackedVector2Array()
	const SEGMENT_COUNT := 32
	points.resize(SEGMENT_COUNT)
	for point_index in range(SEGMENT_COUNT):
		var angle := TAU * float(point_index) / float(SEGMENT_COUNT)
		points[point_index] = Vector2(
			cos(angle) * radius.x,
			sin(angle) * radius.y
		)
	shadow.polygon = points


func _set_battle_tint(color: Color) -> void:
	# El panel de comandos queda fuera de estos dos contenedores para conservar
	# su contraste incluso durante la noche.
	_background.modulate = color
	_battle_stage.modulate = color


func _sync_wind_activity() -> void:
	var active := is_visible_in_tree()
	_battle_wind.visible = active
	_battle_wind.set_process(active)
	if active:
		_battle_wind.call("reset_camera_tracking")


func _on_weather_tween_finished() -> void:
	_weather_tween = null


func _configure_battle_camera() -> void:
	_battle_camera.look_at_from_position(
		Vector3(0.0, 1.35, 7.5),
		Vector3(0.0, 0.85, 0.0),
		Vector3.UP
	)


func _fit_enemy_to_height(enemy_data: PokemonBattleVisualData) -> void:
	await _fit_battler_to_height(
		_enemy_battler,
		enemy_data.enemy_max_height_px,
		enemy_data.enemy_height_fill_ratio
	)


func _fit_player_to_height(player_data: PokemonBattleVisualData) -> void:
	await _fit_battler_to_height(
		_player_battler,
		player_data.player_max_height_px,
		player_data.player_height_fill_ratio
	)


func _fit_battler_to_height(
	battler: PokemonBattler3D,
	maximum_height: float,
	height_fill_ratio: float
) -> void:
	await get_tree().process_frame
	var current_height := _get_battler_visual_height_px(battler)
	if current_height <= 0.0:
		return
	var target_height := maximum_height * height_fill_ratio
	battler.scale *= target_height / current_height
	await get_tree().process_frame
	var fitted_height := _get_battler_visual_height_px(battler)
	if fitted_height > maximum_height:
		battler.scale *= maximum_height / fitted_height


func _clear_player_battler() -> void:
	if is_instance_valid(_player_battler):
		_player_battler.queue_free()
	_player_battler = null
	_player_data = null


func _clear_enemy_battler() -> void:
	if is_instance_valid(_enemy_battler):
		_enemy_battler.queue_free()
	_enemy_battler = null
	_enemy_data = null


func _kill_screen_tween() -> void:
	if is_instance_valid(_screen_tween):
		_screen_tween.kill()
	_screen_tween = null


func _kill_command_tween() -> void:
	if is_instance_valid(_command_tween):
		_command_tween.kill()
	_command_tween = null


func _apply_slot_layout() -> void:
	_set_normalized_rect(
		_player_primary,
		PLAYER_SINGLE_RECT if player_slot_count == 1 else PLAYER_DOUBLE_PRIMARY_RECT
	)
	_set_normalized_rect(_player_secondary, PLAYER_DOUBLE_SECONDARY_RECT)
	_set_normalized_rect(
		_enemy_primary,
		ENEMY_SINGLE_RECT if enemy_slot_count == 1 else ENEMY_DOUBLE_PRIMARY_RECT
	)
	_set_normalized_rect(_enemy_secondary, ENEMY_DOUBLE_SECONDARY_RECT)


func _set_normalized_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.position.x + rect.size.x
	control.anchor_bottom = rect.position.y + rect.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
