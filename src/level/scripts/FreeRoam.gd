extends Node3D
class_name FreeRoam

signal start_combat()

func _ready() -> void:
	AudioController.play_background_music()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("switch scene (for testing)"):
		AudioController.stop_background_music()
		start_combat.emit()
