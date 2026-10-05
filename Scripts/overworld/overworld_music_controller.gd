class_name OverworldMusicController
extends Node

@export var twinleaf_town_track: AudioStream
@export var route_201_track: AudioStream
@export_range(0.1, 5.0, 0.1) var transition_duration := 1.0

@onready var _track_a: AudioStreamPlayer = $TrackA
@onready var _track_b: AudioStreamPlayer = $TrackB

var _environment: Node
var _active_player: AudioStreamPlayer
var _active_zone_id: StringName
var _transition_tween: Tween


func _ready() -> void:
	_environment = get_parent()
	_active_player = _track_a
	if _environment != null and _environment.has_signal(
		&"active_camera_zone_changed"
	):
		_environment.active_camera_zone_changed.connect(
			_on_active_camera_zone_changed
		)
	_sync_initial_zone.call_deferred()


func play_zone(zone_id: StringName) -> void:
	if zone_id == _active_zone_id and _active_player.playing:
		return
	var next_stream := _get_track_for_zone(zone_id)
	_active_zone_id = zone_id
	if next_stream == null:
		_fade_out_active_track()
		return

	var prepared_stream := _prepare_looping_stream(next_stream)
	if not _active_player.playing:
		_active_player.stream = prepared_stream
		_active_player.volume_db = 0.0
		_active_player.play()
		return

	if is_instance_valid(_transition_tween):
		_transition_tween.kill()

	var previous_player := _active_player
	var next_player := _track_b if previous_player == _track_a else _track_a
	next_player.stop()
	next_player.stream = prepared_stream
	next_player.volume_db = -30.0
	next_player.play()
	_active_player = next_player

	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_LINEAR)
	_transition_tween.tween_property(
		previous_player,
		"volume_db",
		-60.0,
		transition_duration
	)
	_transition_tween.parallel().tween_property(
		next_player,
		"volume_db",
		0.0,
		transition_duration
	)
	_transition_tween.finished.connect(
		_finish_crossfade.bind(previous_player)
	)


func _sync_initial_zone() -> void:
	if not is_instance_valid(_environment):
		return
	if _environment.has_method("get_active_camera_zone_id"):
		play_zone(_environment.call("get_active_camera_zone_id"))


func _on_active_camera_zone_changed(
	zone_id: StringName,
	_display_name: String
) -> void:
	play_zone(zone_id)


func _get_track_for_zone(zone_id: StringName) -> AudioStream:
	match zone_id:
		&"leaftown":
			return twinleaf_town_track
		&"route_201":
			return route_201_track
		_:
			return null


func _prepare_looping_stream(source: AudioStream) -> AudioStream:
	var prepared := source.duplicate() as AudioStream
	if prepared is AudioStreamOggVorbis:
		(prepared as AudioStreamOggVorbis).loop = true
	return prepared


func _fade_out_active_track() -> void:
	if not _active_player.playing:
		return
	if is_instance_valid(_transition_tween):
		_transition_tween.kill()
	var player_to_stop := _active_player
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_LINEAR)
	_transition_tween.tween_property(
		player_to_stop,
		"volume_db",
		-60.0,
		transition_duration
	)
	_transition_tween.finished.connect(
		_finish_fade_out.bind(player_to_stop)
	)


func _finish_crossfade(previous_player: AudioStreamPlayer) -> void:
	previous_player.stop()
	previous_player.volume_db = 0.0
	_transition_tween = null


func _finish_fade_out(player_to_stop: AudioStreamPlayer) -> void:
	player_to_stop.stop()
	player_to_stop.volume_db = 0.0
	_transition_tween = null
