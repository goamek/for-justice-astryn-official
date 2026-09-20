extends Node3D
class_name EndCreditScene

## dialogue_post_credits_epilogue.dialogue — holds both epilogue nodes; which one plays is
## picked by _epilogue_title, set via initialize_data().
@export var epilogue_dialogue: DialogueResource

var _epilogue_title: String = "post_credits_epilogue"

const IDLE_DIRECTIONS: Array[String] = ["Up Idle", "Down Idle", "Left Idle", "Right Idle"]

# Called by main.gd's switch_scene() right after instantiation. data comes from
# Credits.gd's SignalBus.request_scene_change.emit(END_CREDIT_SCENE, {"epilogue_title": ...}).
func initialize_data(data: Dictionary) -> void:
	if data.has("epilogue_title"):
		_epilogue_title = data["epilogue_title"]

func _ready() -> void:
	_randomize_npc_idle_directions()
	if epilogue_dialogue:
		epilogue_dialogue.set_meta("keep_cinematic_bars_on_end", true)
		AudioController.duck_credits_music()
		DialogueManager.show_dialogue_balloon(epilogue_dialogue, _epilogue_title)
		await DialogueManager.dialogue_ended
		AudioController.unduck_credits_music()
	# Loaded here rather than preloaded at the top of the script — see GameOver.gd's
	# _on_continue_button_pressed() for why (an eager preload chain looping back to a scene
	# main.gd already preloads independently, which can hand back a broken PackedScene stub).
	var main_menu_scene: PackedScene = load("res://src/level/scenes/main_menu.tscn")
	AudioController.stop_credits_music()
	SignalBus.request_scene_change.emit(main_menu_scene, {})
	await SceneTransition.on_transition_finished
	CinematicBars.hide_bars()

## Gives the background crowd (everyone except the four real party members, who keep their
## scripted facing) a random idle direction each time this scene loads, so the same hand-placed
## layout doesn't look identical crowd-to-crowd on repeat playthroughs.
func _randomize_npc_idle_directions() -> void:
	var npcs: Array[Node] = $Crowd.get_children()
	npcs.append($NPCBlack2)
	npcs.append($NPCGreen2)
	for npc in npcs:
		if npc is PartyMember and npc.animated_sprite != null:
			npc.animated_sprite.play(IDLE_DIRECTIONS[randi() % IDLE_DIRECTIONS.size()])
