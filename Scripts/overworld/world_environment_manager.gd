class_name WorldEnvironmentManager
extends Node

## Ambiente global de mapas basado en la hora local del dispositivo.
## Las anulaciones regionales permiten sumar lluvia, nieve, arena u otros
## estados sin acoplarlos a una escena concreta.

signal time_period_changed(period_id: StringName, profile: Dictionary)
signal weather_changed(weather_id: StringName, profile: Dictionary)

const PERIOD_DAWN: StringName = &"dawn"
const PERIOD_AFTERNOON: StringName = &"afternoon"
const PERIOD_SUNSET: StringName = &"sunset"
const PERIOD_NIGHT: StringName = &"night"
const DEFAULT_WEATHER: StringName = &"clear"
const MAP_CATEGORY := 1
const CLOCK_REFRESH_INTERVAL := 1.0
const SCENE_SYNC_INTERVAL := 0.25
const FILTER_TRANSITION_DURATION := 5.0

@onready var _world_tint: CanvasModulate = $WorldTint
@onready var _atmosphere: CanvasLayer = $Atmosphere
@onready var _clouds: Control = $Atmosphere/Clouds
@onready var _wind: Control = $Atmosphere/Wind

var _scene_loader: Node
var _current_map: Node
var _current_map_id: StringName
var _current_zone_id: StringName
var _current_period: StringName
var _current_weather_id: StringName = DEFAULT_WEATHER
var _current_profile: Dictionary = {}
var _regional_overrides: Dictionary = {}
var _clock_elapsed := 0.0
var _scene_sync_elapsed := 0.0
var _filter_tween: Tween
var _environment_enabled := false
var _overworld_suspended := false
var _observed_scene: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scene_loader = get_node_or_null("/root/SceneLoader")
	if _scene_loader != null and _scene_loader.has_signal(&"scene_changed"):
		_scene_loader.scene_changed.connect(_on_scene_changed)
	_set_environment_enabled(false)
	_sync_current_scene.call_deferred()


func _process(delta: float) -> void:
	_scene_sync_elapsed += delta
	if _scene_sync_elapsed >= SCENE_SYNC_INTERVAL:
		_scene_sync_elapsed = 0.0
		_sync_current_scene()
	if not _environment_enabled or _overworld_suspended:
		return
	_clock_elapsed += delta
	if _clock_elapsed < CLOCK_REFRESH_INTERVAL:
		return
	_clock_elapsed = 0.0
	refresh_from_system_time()


func refresh_from_system_time(
	force: bool = false,
	apply_immediately: bool = false
) -> void:
	var time := Time.get_time_dict_from_system()
	var seconds_of_day := (
		int(time.get("hour", 0)) * 3600
		+ int(time.get("minute", 0)) * 60
		+ int(time.get("second", 0))
	)
	var period := _get_period_for_second_of_day(seconds_of_day)
	if not force and period == _current_period:
		return
	var previous_period := _current_period
	_current_period = period
	_apply_active_profile(
		previous_period != period,
		0.0 if apply_immediately else FILTER_TRANSITION_DURATION
	)


func get_current_time_period() -> StringName:
	return _current_period


func get_current_weather_profile() -> Dictionary:
	return _current_profile.duplicate(true)


## Suspende únicamente la presentación ambiental del mapa mientras una interfaz
## modal de pantalla completa (por ejemplo, una batalla) conserva el mapa vivo.
## El perfil actual se mantiene y se vuelve a aplicar al reanudar.
func set_overworld_suspended(suspended: bool) -> void:
	if _overworld_suspended == suspended:
		return
	_overworld_suspended = suspended
	_refresh_environment_activity()
	if not suspended and _environment_enabled:
		refresh_from_system_time(true, true)


func is_overworld_suspended() -> bool:
	return _overworld_suspended


## Registra una variación para una zona concreta. `overrides` puede contener
## tint, wind_count, whirlwind_probability, cloud_count, cloud_opacity y
## cloud_size. Los futuros renderizadores de lluvia/nieve/arena pueden usar
## weather_id sin cambiar el reloj global.
func register_region_weather(
	map_id: StringName,
	zone_id: StringName,
	weather_id: StringName,
	overrides: Dictionary = {}
) -> void:
	_regional_overrides[_make_region_key(map_id, zone_id)] = {
		"weather_id": weather_id,
		"overrides": overrides.duplicate(true),
	}
	if map_id == _current_map_id and zone_id == _current_zone_id:
		_apply_active_profile(false, FILTER_TRANSITION_DURATION)


func unregister_region_weather(
	map_id: StringName,
	zone_id: StringName
) -> void:
	_regional_overrides.erase(_make_region_key(map_id, zone_id))
	if map_id == _current_map_id and zone_id == _current_zone_id:
		_apply_active_profile(false, FILTER_TRANSITION_DURATION)


func _get_period_for_second_of_day(seconds_of_day: int) -> StringName:
	# Amanecer incluye exactamente las 11:00:00; Tarde comienza a las 11:00:01.
	if seconds_of_day >= 6 * 3600 and seconds_of_day <= 11 * 3600:
		return PERIOD_DAWN
	if seconds_of_day >= 11 * 3600 + 1 and seconds_of_day < 18 * 3600:
		return PERIOD_AFTERNOON
	if seconds_of_day >= 18 * 3600 and seconds_of_day < 21 * 3600:
		return PERIOD_SUNSET
	return PERIOD_NIGHT


func _build_time_profile(period: StringName) -> Dictionary:
	var weather_day_key := _get_weather_day_key()
	var random := _make_seeded_random("%s:%s" % [weather_day_key, period])
	var night_random := _make_seeded_random("%s:night-condition" % weather_day_key)
	var night_cloudiness := night_random.randf()

	match period:
		PERIOD_DAWN:
			return {
				"period_name": "Amanecer",
				"tint": Color(1.0, 0.91, 0.78, 1.0),
				"wind_count": random.randi_range(140, 150),
				"whirlwind_probability": 0.01,
				"cloud_count": random.randi_range(3, 5),
				"cloud_opacity": 0.035,
				"cloud_size": 0.52,
			}
		PERIOD_AFTERNOON:
			return {
				"period_name": "Tarde",
				"tint": Color(1.0, 0.985, 0.95, 1.0),
				"wind_count": random.randi_range(50, 100),
				"whirlwind_probability": 0.01,
				"cloud_count": 0,
				"cloud_opacity": 0.0,
				"cloud_size": 0.6,
			}
		PERIOD_SUNSET:
			return {
				"period_name": "Atardecer",
				"tint": Color(1.0, 0.70, 0.48, 1.0),
				"wind_count": random.randi_range(5, 10),
				"whirlwind_probability": 0.005,
				"cloud_count": roundi(lerpf(4.0, 11.0, night_cloudiness)),
				"cloud_opacity": 0.055,
				"cloud_size": 0.78,
			}
		_:
			return _build_night_profile(night_cloudiness, night_random)


func _build_night_profile(
	cloudiness: float,
	random: RandomNumberGenerator
) -> Dictionary:
	if cloudiness < 0.20:
		return {
			"period_name": "Noche",
			"tint": Color(0.42, 0.52, 0.73, 1.0),
			"wind_count": random.randi_range(1, 5),
			"whirlwind_probability": 0.0,
			"cloud_count": 0,
			"cloud_opacity": 0.0,
			"cloud_size": 0.9,
		}
	var intensity := inverse_lerp(0.20, 1.0, cloudiness)
	return {
		"period_name": "Noche",
		"tint": Color(0.39, 0.48, 0.69, 1.0).lerp(
			Color(0.32, 0.39, 0.58, 1.0),
			intensity
		),
		"wind_count": roundi(lerpf(12.0, 200.0, intensity)),
		"whirlwind_probability": lerpf(0.005, 0.10, intensity),
		"cloud_count": roundi(lerpf(3.0, 18.0, intensity)),
		"cloud_opacity": lerpf(0.035, 0.095, intensity),
		"cloud_size": lerpf(0.82, 1.18, intensity),
	}


func _apply_active_profile(
	period_changed: bool,
	transition_duration: float
) -> void:
	if (
		not _environment_enabled
		or _overworld_suspended
		or _current_period.is_empty()
	):
		return
	var profile := _build_time_profile(_current_period)
	var weather_id := DEFAULT_WEATHER
	var region_key := _make_region_key(_current_map_id, _current_zone_id)
	if _regional_overrides.has(region_key):
		var region: Dictionary = _regional_overrides[region_key]
		weather_id = region.get("weather_id", DEFAULT_WEATHER)
		profile.merge(region.get("overrides", {}), true)

	var visual_profile_changed := (
		weather_id != _current_weather_id
		or profile != _current_profile
	)
	_current_profile = profile.duplicate(true)
	_current_weather_id = weather_id
	# Un cambio de zona sin clima regional no debe reiniciar tweens ni tocar la
	# población atmosférica. Esto conserva la continuidad visual entre áreas.
	if visual_profile_changed:
		_transition_world_tint(
			profile.get("tint", Color.WHITE),
			transition_duration
		)
		_wind.call(
			"set_weather_profile",
			int(profile.get("wind_count", 0)),
			float(profile.get("whirlwind_probability", 0.0)),
			transition_duration
		)
		_clouds.call(
			"set_weather_profile",
			int(profile.get("cloud_count", 0)),
			float(profile.get("cloud_opacity", 0.0)),
			float(profile.get("cloud_size", 0.7)),
			transition_duration
		)
	if period_changed:
		time_period_changed.emit(_current_period, profile.duplicate(true))
	weather_changed.emit(weather_id, profile.duplicate(true))


func _transition_world_tint(target: Color, transition_duration: float) -> void:
	if is_instance_valid(_filter_tween):
		_filter_tween.kill()
	if transition_duration <= 0.0:
		_world_tint.color = target
		return
	_filter_tween = create_tween()
	_filter_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_filter_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_filter_tween.tween_property(
		_world_tint,
		"color",
		target,
		transition_duration
	)


func _on_scene_changed(
	scene_id: StringName,
	scene: Node,
	_payload: Dictionary
) -> void:
	var is_map := false
	if _scene_loader != null and _scene_loader.has_method("get_scene_info"):
		var info: Dictionary = _scene_loader.call("get_scene_info", scene_id)
		is_map = int(info.get("category", -1)) == MAP_CATEGORY
	_bind_map(scene_id, scene if is_map else null)


func _sync_current_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or scene == _observed_scene:
		return

	var scene_id: StringName = &""
	if _scene_loader != null:
		scene_id = _scene_loader.get("current_scene_id")
		if not scene_id.is_empty():
			_on_scene_changed(scene_id, scene, {})
			return

	# Al ejecutar una escena de mapa directamente desde el editor no existe un
	# identificador activo en SceneLoader. En ese caso se detecta por contrato.
	if _is_overworld_map(scene):
		_bind_map(_get_direct_map_id(scene), scene)
	else:
		_bind_map(&"", null)


func _bind_map(scene_id: StringName, map: Node) -> void:
	if is_instance_valid(_current_map) and _current_map.has_signal(
		&"active_camera_zone_changed"
	):
		var callback := Callable(self, "_on_active_camera_zone_changed")
		if _current_map.is_connected(&"active_camera_zone_changed", callback):
			_current_map.disconnect(&"active_camera_zone_changed", callback)

	_current_map = map
	_observed_scene = get_tree().current_scene
	_current_map_id = scene_id if map != null else &""
	_current_zone_id = &""
	_set_environment_enabled(map != null)
	if map == null:
		return
	if map.has_signal(&"active_camera_zone_changed"):
		map.connect(
			&"active_camera_zone_changed",
			Callable(self, "_on_active_camera_zone_changed")
		)
	if map.has_method("get_active_camera_zone_id"):
		_current_zone_id = map.call("get_active_camera_zone_id")
	# En la primera carga se aplica antes de que termine el fade del mapa. Sólo
	# los cambios posteriores entre franjas o regiones duran cinco segundos.
	refresh_from_system_time(true, true)


func _on_active_camera_zone_changed(
	zone_id: StringName,
	_display_name: String
) -> void:
	if zone_id == _current_zone_id:
		return
	_current_zone_id = zone_id
	_apply_active_profile(false, FILTER_TRANSITION_DURATION)


func _set_environment_enabled(enabled: bool) -> void:
	_environment_enabled = enabled
	_refresh_environment_activity()
	if not enabled:
		_world_tint.color = Color.WHITE


func _refresh_environment_activity() -> void:
	var active := _environment_enabled and not _overworld_suspended
	_atmosphere.visible = active
	_clouds.set_process(active)
	_wind.set_process(active)
	if active:
		_clouds.call("reset_camera_tracking")
		_wind.call("reset_camera_tracking")
	elif is_instance_valid(_filter_tween):
		_filter_tween.kill()
		_filter_tween = null


func _get_weather_day_key() -> String:
	var datetime := Time.get_datetime_dict_from_system()
	if int(datetime.get("hour", 0)) < 6:
		var previous_day: int = int(
			Time.get_unix_time_from_datetime_dict(datetime)
		) - 86400
		datetime = Time.get_datetime_dict_from_unix_time(int(previous_day))
	return "%04d-%02d-%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0)),
	]


func _make_seeded_random(seed_text: String) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = int(seed_text.hash()) & 0x7fffffff
	return random


func _is_overworld_map(scene: Node) -> bool:
	return (
		scene.is_in_group(&"overworld_maps")
		or (
			scene.has_signal(&"active_camera_zone_changed")
			and scene.has_method("get_active_camera_zone_id")
		)
	)


func _get_direct_map_id(scene: Node) -> StringName:
	for property: Dictionary in scene.get_property_list():
		if property.get("name", &"") == &"map_id":
			var configured_id := StringName(str(scene.get("map_id")))
			if not configured_id.is_empty():
				return configured_id
	if not scene.scene_file_path.is_empty():
		return StringName(scene.scene_file_path.get_file().get_basename())
	return StringName(scene.name)


func _make_region_key(map_id: StringName, zone_id: StringName) -> String:
	return "%s::%s" % [map_id, zone_id]
