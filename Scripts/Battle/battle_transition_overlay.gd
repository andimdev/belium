class_name BattleTransitionOverlay
extends ColorRect

signal flash_started(flash_index: int)
signal flash_sequence_finished

const FLASH_COUNT := 3
const FLASH_SEQUENCE_DURATION := 2.0
const FLASH_IN_DURATION := 0.16
const BLACK_HOLD_DURATION := 0.10
const FLASH_OUT_DURATION := 0.16
const FLASH_CYCLE_DURATION := FLASH_SEQUENCE_DURATION / FLASH_COUNT
const CLEAR_HOLD_DURATION := (
	FLASH_CYCLE_DURATION
	- FLASH_IN_DURATION
	- BLACK_HOLD_DURATION
	- FLASH_OUT_DURATION
)

var _active_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


func play_three_black_flashes() -> void:
	_cancel_tween()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for flash_index in range(FLASH_COUNT):
		_active_tween.tween_callback(flash_started.emit.bind(flash_index))
		_active_tween.tween_property(
			self, "modulate:a", 1.0, FLASH_IN_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_active_tween.tween_interval(BLACK_HOLD_DURATION)
		_active_tween.tween_property(
			self, "modulate:a", 0.0, FLASH_OUT_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_active_tween.tween_interval(CLEAR_HOLD_DURATION)
	await _active_tween.finished
	_active_tween = null
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_sequence_finished.emit()


func reset() -> void:
	_cancel_tween()
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _cancel_tween() -> void:
	if is_instance_valid(_active_tween):
		_active_tween.kill()
	_active_tween = null
