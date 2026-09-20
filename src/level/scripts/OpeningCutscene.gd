extends Node3D
class_name OpeningCutscene

## Opened immediately on scene load (during the fade-in, not after it), so the bars/balloon
## are in place as early as possible; the first spoken line waits a beat via the dialogue's
## own opening `do cutscene.wait_before_dialogue()` line, not a wait here in _ready().
@export var dialogue_resource: DialogueResource
## Scene to transition to once the dialogue ends.
@export var next_scene: PackedScene

@onready var vorkoth: BossEnemy = $Platform/Vorkoth

func _ready() -> void:
	# Set here rather than relying on a scene-file override, since Vorkoth starts
	# invisible until his teleport-in reveal and this can't be accidentally lost.
	if vorkoth.animated_sprite:
		vorkoth.animated_sprite.modulate.a = 0.0
	if dialogue_resource:
		# Keeps CinematicBars from auto-hiding the instant dialogue ends — we hide them
		# ourselves below, once the fade-to-black actually covers the screen, so the bars
		# stay in place right up until the scene switches instead of retracting early.
		dialogue_resource.set_meta("keep_cinematic_bars_on_end", true)
	AudioController.play_world_map_music()
	DialogueManager.show_dialogue_balloon(dialogue_resource, "start", [{"vorkoth": vorkoth, "cutscene": self}])
	await DialogueManager.dialogue_ended
	SignalBus.request_scene_change.emit(next_scene, {})
	await SceneTransition.on_transition_finished
	CinematicBars.hide_bars()

## Callable from the dialogue's opening line — delays the first spoken line so the balloon
## doesn't visibly start until well after the fade-in (1s wait + SceneTransition.fade_in()'s
## own ~1s duration, since the balloon now opens immediately rather than after the fade-in).
func wait_before_dialogue() -> void:
	await get_tree().create_timer(2.0).timeout
