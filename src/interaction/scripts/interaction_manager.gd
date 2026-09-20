extends Node2D


var player = null
@onready var label = $Label

const base_text = "[E / Gamepad A] to "
const TBC_SCENE = "res://src/level/scenes/tbc.tscn"
const BOSS_FIGHT_SCENE = "res://src/level/scenes/boss_fight_tbc.tscn"

var is_dialogue_playing: bool = false

func _ready() -> void:
	DialogueManager.dialogue_started.connect(func(_res): is_dialogue_playing = true)
	DialogueManager.dialogue_ended.connect(func(_res): is_dialogue_playing = false)

	# InteractionArea only unregisters on body_exited — a scene swap while still standing
	# inside one (e.g. the boss-fight trigger) tears down free-roam without firing that
	# signal, leaving a stale area and the prompt showing into the next scene.
	SignalBus.request_scene_change.connect(func(_scene, _data): _clear_interaction_state())

func _clear_interaction_state() -> void:
	active_areas.clear()
	can_interact = true
	label.hide()

# ---- Active Interaction Areas ----
var active_areas = []
var can_interact = true

func register_area(area: InteractionArea):
	active_areas.push_back(area)
	
func unregister_area(area: InteractionArea):
	var index = active_areas.find(area)
	if index != -1:
		active_areas.remove_at(index)

func _sort_by_distance_to_player(area1, area2):
	var area1_to_player = player.global_position.distance_to(area1.global_position)
	var area2_to_player = player.global_position.distance_to(area2.global_position)
	return area1_to_player < area2_to_player

# Interaction is free-roam-only — party members/NPCs in a TBC/boss-fight scene still carry
# an InteractionArea (same PartyMember.gd script), so this check stops the prompt from
# popping up mid-battle if the player's body ends up inside one.
func _in_combat_scene() -> bool:
	var current_scene = get_tree().current_scene
	if current_scene == null or not current_scene.has_node("Current_Scene_Container"):
		return false
	var container = current_scene.get_node("Current_Scene_Container")
	if container.get_child_count() == 0:
		return false
	var path = container.get_child(0).get_scene_file_path()
	return path == TBC_SCENE or path == BOSS_FIGHT_SCENE

func _process(_delta: float) -> void:
	if _in_combat_scene():
		label.hide()
		return
	if active_areas.size() > 0 && can_interact:
		active_areas.sort_custom(_sort_by_distance_to_player)
		label.text = base_text + active_areas[0].action_name
		
		var camera = get_viewport().get_camera_3d()
		if camera:
			var screen_pos = camera.unproject_position(active_areas[0].global_position)
			label.global_position = screen_pos
			label.global_position.y -= 100
			label.global_position.x -= label.size.x / 2
			label.show()
	else:
		label.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") && can_interact && not is_dialogue_playing && not _in_combat_scene():
		if active_areas.size() > 0:
			can_interact = false
			label.hide()
			
			await active_areas[0].interact.call()
			
			if not is_dialogue_playing:
				can_interact = true
