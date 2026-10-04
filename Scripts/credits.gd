extends Control

const FADE_DURATION := 1.0
const SCREEN_DURATION := 3.0

func _ready() -> void:
	modulate.a = 0.0
	await _fade_to(1.0)
	await get_tree().create_timer(SCREEN_DURATION).timeout
	await _fade_to(0.0)
	var scene_loader := get_node_or_null("/root/SceneLoader")
	if scene_loader != null:
		scene_loader.call("go_to", &"press_start", {
			"transition": &"none",
			"record_history": false,
		})

func _fade_to(target_opacity: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", target_opacity, FADE_DURATION)
	await tween.finished
