extends Node3D
class_name FreeRoam

signal start_combat()

# Reuses Solider Battle's own configured roster instead of duplicating it here.
@onready var practice_fight_soldier: Enemy = $"Solider Battle"
@onready var player: Character = $Astryn
@onready var practice_soldier_return_spawn: Marker3D = $PracticeSoldierReturnSpawn

func _ready() -> void:
	AudioController.play_background_music()

# Called by main.gd's switch_scene() right after instantiation, mirroring
# TurnBasedCombat.initialize_data() — lets a caller reposition the player instead of
# always landing at this scene's baked-in default spawn transform.
func initialize_data(data: Dictionary) -> void:
	if data.get("return_to_practice_soldier", false):
		player.global_position = practice_soldier_return_spawn.global_position

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("switch scene (for testing)"):
		# Free-roam music keeps playing through the transition and the duel-intro
		# cutscene; TurnBasedCombat._ready() stops it once the intro resolves.
		start_combat.emit()
	if Input.is_action_just_pressed("start practice fight (for testing)") and practice_fight_soldier:
		practice_fight_soldier.start_practice_fight()
