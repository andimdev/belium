extends Control

@onready var fade_from_black: ColorRect = $FadeFromBlack
@onready var press_start_label: Label = $PressStartLabel
@onready var music: AudioStreamPlayer = $Press_Start
@onready var houndoom_cry: AudioStreamPlayer = $HoundoomCry

const DEFAULT_MUSIC_FADE_DURATION := 1.0

var _can_start := false
var _opening_menu := false

func _ready() -> void:
	_configure_music_loop()
	press_start_label.modulate = Color(0.72, 0.66, 0.78, 0.0)
	_play_intro_sequence()

func _configure_music_loop() -> void:
	if music.stream is AudioStreamOggVorbis:
		music.stream.loop = true
	if not music.playing:
		music.play()

func _play_intro_sequence() -> void:
	fade_from_black.modulate.a = 1.0
	var fade_tween := create_tween()
	fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(fade_from_black, "modulate:a", 0.0, 2.4)
	await fade_tween.finished
	fade_from_black.hide()

	await get_tree().create_timer(1.0).timeout
	var label_fade := create_tween()
	label_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	label_fade.tween_property(
		press_start_label,
		"modulate",
		Color(0.82, 0.76, 0.88, 1.0),
		0.8
	)
	await label_fade.finished
	_play_label_pulse()
	_can_start = true

func _play_label_pulse() -> void:
	press_start_label.modulate = Color(0.72, 0.66, 0.78, 1.0)
	var pulse_tween := create_tween().set_loops()
	pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(
		press_start_label,
		"modulate",
		Color(1.0, 0.96, 1.0, 1.0),
		1.25
	)
	pulse_tween.tween_property(
		press_start_label,
		"modulate",
		Color(0.72, 0.66, 0.78, 1.0),
		1.25
	)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_start or _opening_menu:
		return
	var mouse_start: bool = (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	)
	if event.is_action_pressed("ui_accept") or mouse_start:
		_opening_menu = true
		var scene_loader := get_node_or_null("/root/SceneLoader")
		if scene_loader != null:
			_play_title_exit_audio(scene_loader)
			scene_loader.call("go_to", &"load_new_play", {
				"transition": &"fade",
				"duration": 0.35,
			})


func _play_title_exit_audio(scene_loader: Node) -> void:
	var music_fade_duration := DEFAULT_MUSIC_FADE_DURATION
	if houndoom_cry.stream != null:
		var cry_duration := houndoom_cry.stream.get_length()
		if cry_duration > 0.0:
			music_fade_duration = cry_duration

	# Ambos reproductores salen de la escena para que el cambio no corte el audio.
	houndoom_cry.reparent(scene_loader)
	houndoom_cry.finished.connect(houndoom_cry.queue_free, CONNECT_ONE_SHOT)
	houndoom_cry.play()

	music.reparent(scene_loader)
	var music_fade := music.create_tween()
	music_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	music_fade.tween_property(music, "volume_db", -80.0, music_fade_duration)
	music_fade.tween_callback(music.stop)
	music_fade.tween_callback(music.queue_free)
