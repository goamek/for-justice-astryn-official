# Owns the single scene container and swaps its child between top-level scenes (main menu,
# free roam, TBC), always through SceneTransition's fade.

extends Node

const MAIN_MENU_SCENE = preload("res://src/level/scenes/main_menu.tscn")
const FREE_ROAM_SCENE = preload("res://src/level/scenes/free_roam.tscn")
const TBC_SCENE = preload("res://src/level/scenes/boss_fight_tbc.tscn")

@onready var current_scene_container = $Current_Scene_Container
@onready var pause_menu = $UI/CanvasLayer/PauseMenu
var current_scene = null

func _ready():
	SignalBus.request_scene_change.connect(switch_scene)
	current_scene = MAIN_MENU_SCENE.instantiate()
	current_scene_container.add_child(current_scene)
	pause_menu.current_gameplay_scene = current_scene

func switch_scene(new_scene_packed: PackedScene, data = {}):
	# Guards against a button mashed while its own press is already fading the scene out —
	# each extra call would free/instantiate on top of the transition already in flight
	# (e.g. spamming the main menu's Start button could free the opening cutscene mid-setup
	# while its own dialogue was still starting, crashing on the now-freed node).
	if SceneTransition.is_transitioning:
		return

	SceneTransition.transition()
	await SceneTransition.on_transition_finished

	if current_scene != null:
		current_scene.queue_free()
		current_scene = null

	current_scene = new_scene_packed.instantiate()
	current_scene_container.add_child(current_scene)
	pause_menu.current_gameplay_scene = current_scene

	if current_scene.has_method("initialize_data"):
		current_scene.initialize_data(data)

	if current_scene is FreeRoam:
		current_scene.start_combat.connect(_on_start_combat)
	elif current_scene is TurnBasedCombat:
		current_scene.combat_ended.connect(_on_combat_ended)

	SceneTransition.fade_in()

func _on_start_combat():
	switch_scene(TBC_SCENE)

func _on_combat_ended(_was_quit: bool):
	# Any practice-fight ending (win, loss, or quit) returns to the soldier who started it,
	# not just a quit — only the real boss fight falls back to the default free-roam spawn.
	var was_practice_fight: bool = current_scene is TurnBasedCombat and not current_scene is BossTurnBasedCombat
	switch_scene(FREE_ROAM_SCENE, {"return_to_practice_soldier": was_practice_fight})
