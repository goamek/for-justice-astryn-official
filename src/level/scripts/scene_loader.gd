extends Sprite3D

@onready var interaction_area: InteractionArea = $SceneLoader/CollisionShape3D/InteractionArea

@export var scene_to_load: PackedScene

func _ready() -> void:
	if interaction_area:
		interaction_area.interact = Callable(self, "_on_interact")

func _on_interact():
	if QuestManager.can_enter_boss_fight():
		print("Completed the Quest, now entering the boss fight.")
		# Free-roam music keeps playing through the transition and the duel-intro cutscene;
		# TurnBasedCombat._ready() stops it once the intro resolves, right before battle
		# music starts.
		SignalBus.request_scene_change.emit(scene_to_load, {})
	else:
		print("Have not completed the quest.")
