class_name PokemonWalkingNPC
extends "res://Scripts/NPC/random_walking_npc.gd"

## Pokémon del mundo: paseo frecuente por la misma cuadrícula que los NPCs.
## El grito se asigna en el Inspector de cada escena o instancia.

@export_category("Grito del Pokémon")
@export var cry_stream: AudioStream
@export var cry_bus: StringName = &"Map_Sound"
@export_range(0.0, 100.0, 1.0, "suffix:%") var cry_volume_percent := 60.0

var _cry_player: AudioStreamPlayer
var _cry_active := false
var _locked_before_cry := false


func _init() -> void:
	# Defaults propios; el Inspector puede sobrescribirlos para cada especie.
	movement_probability = 0.70
	minimum_decision_delay = 0.8
	maximum_decision_delay = 1.8


func _ready() -> void:
	super._ready()
	_cry_player = AudioStreamPlayer.new()
	_cry_player.name = "CryAudio"
	_cry_player.max_polyphony = 1
	add_child(_cry_player)
	_cry_player.finished.connect(_on_cry_finished)
	if cry_stream != null:
		# No cambiar el recurso importado compartido con otros Pokémon.
		_cry_player.stream = cry_stream.duplicate() as AudioStream
		if _cry_player.stream is AudioStreamOggVorbis:
			(_cry_player.stream as AudioStreamOggVorbis).loop = false
		elif _cry_player.stream is AudioStreamWAV:
			(_cry_player.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
		elif _cry_player.stream is AudioStreamMP3:
			(_cry_player.stream as AudioStreamMP3).loop = false


func _register_interaction() -> void:
	add_to_group(&"dialogue_interactable")
	add_to_group(&"pokemon_npc")


## UIRoot llama esta entrada solo para el interactuable frente al jugador.
## Consumir también las pulsaciones repetidas evita abrir el menú o reiniciar
## el audio. No abre diálogos ni registra contactos narrativos de NPCs.
func interact_in_overworld(player: Node2D) -> bool:
	if _cry_active or not is_instance_valid(player):
		return true
	if _cry_player.stream == null:
		push_warning("%s: asigna Cry Stream en el Inspector del Pokémon." % get_path())
		return true
	if AudioServer.get_bus_index(cry_bus) < 0:
		push_warning("%s: no existe el bus de audio %s." % [get_path(), cry_bus])
		return true

	_cry_player.bus = cry_bus
	_cry_player.volume_linear = clampf(cry_volume_percent / 100.0, 0.0, 1.0)
	_locked_before_cry = _interaction_locked
	set_interaction_locked(true)
	face_toward(player.global_position)
	_cry_active = true
	_cry_player.play()
	return true


func is_crying() -> bool:
	return _cry_active


func _on_cry_finished() -> void:
	_cry_active = false
	if not _locked_before_cry:
		# Si fue llamado a mitad de un paso, retoma esa misma trayectoria sin
		# saltar de celda y mirando de nuevo en la dirección del desplazamiento.
		if _is_stepping:
			_update_facing(_step_direction)
		set_interaction_locked(false)
		_schedule_next_decision()
