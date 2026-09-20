extends Control
class_name GameOver

@onready var continue_button: Button = $ContinueButton

func _ready() -> void:
	continue_button.grab_focus()

func _on_continue_button_pressed() -> void:
	# Loaded here rather than preloaded — preloading would force a deep eager compile chain
	# (GameOver -> free_roam.tscn -> ... -> boss_fight_tbc.tscn, which main.gd already
	# preloads independently) that can hand back a broken/stub PackedScene; load() avoids it.
	# No QuestManager.reset_progress() here — losing the boss fight shouldn't wipe quest
	# progress, same as quitting a practice battle from the pause menu.
	var free_roam_scene: PackedScene = load("res://src/level/scenes/free_roam.tscn")
	SignalBus.request_scene_change.emit(free_roam_scene, {})
