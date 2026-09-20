extends Control
class_name Credits

# Simple demo timer — no scroll/skip interaction needed.
const CREDITS_DURATION: float = 15.0

var _epilogue_title: String = "post_credits_epilogue"

# Called by main.gd's switch_scene() right after instantiation. data comes from
# BossTurnBasedCombat's SignalBus.request_scene_change.emit(CREDITS_SCENE, {"epilogue_title": ...}).
func initialize_data(data: Dictionary) -> void:
	if data.has("epilogue_title"):
		_epilogue_title = data["epilogue_title"]

func _ready() -> void:
	AudioController.play_credits_music()
	await get_tree().create_timer(CREDITS_DURATION).timeout
	# Loaded here rather than preloaded at the top of the script — see GameOver.gd's
	# _on_continue_button_pressed() for why (an eager preload chain looping back to a scene
	# main.gd already preloads independently, which can hand back a broken PackedScene stub).
	var end_credit_scene: PackedScene = load("res://src/level/scenes/end_credit_scene.tscn")
	SignalBus.request_scene_change.emit(end_credit_scene, {"epilogue_title": _epilogue_title})
