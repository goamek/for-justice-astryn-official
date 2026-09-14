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
	# 1. Fade out
	SceneTransition.transition()

	# 2. Wait for the fade to finish
	await SceneTransition.on_transition_finished

	# 3. Swap the scene content while the screen is black
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null

	current_scene = new_scene_packed.instantiate()
	current_scene_container.add_child(current_scene)
	pause_menu.current_gameplay_scene = current_scene

	if current_scene.has_method("initialize_data"):
		current_scene.initialize_data(data)

	# Connect signals for game logic
	if current_scene is FreeRoam:
		current_scene.start_combat.connect(_on_start_combat)
	elif current_scene is TurnBasedCombat:
		current_scene.combat_ended.connect(_on_combat_ended)

	# 4. Fade back in
	SceneTransition.fade_in()

func _on_start_combat():
	switch_scene(TBC_SCENE)

func _on_combat_ended(was_quit: bool):
	switch_scene(FREE_ROAM_SCENE, {"return_to_practice_soldier": was_quit})
