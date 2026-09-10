extends CanvasLayer
## Letterbox-style black bars that slide in from the top and bottom of the
## screen during dialogue, and slide back out when the conversation ends.

@export var bar_height: float = 70.0
@export var animation_duration: float = 0.4

@onready var top_bar: ColorRect = $TopBar
@onready var bottom_bar: ColorRect = $BottomBar


func _ready() -> void:
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started(resource: DialogueResource) -> void:
	# Enemy.gd/PartyMember.gd stamp this per-instance before starting dialogue (see
	# show_cinematic_bars there); anything that doesn't set it keeps the always-on default.
	if resource and resource.has_meta("show_cinematic_bars") and not resource.get_meta("show_cinematic_bars"):
		return
	show_bars()


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	hide_bars()


## Also callable directly from a .dialogue file as a mutation - `do CinematicBars.show_bars()` -
## for turning bars on partway through a conversation, or in just one ~ titled section of a
## multi-section file, rather than for the whole thing via Enemy/PartyMember's Inspector toggle.
func show_bars() -> void:
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(top_bar, "offset_bottom", bar_height, animation_duration)
	tween.tween_property(bottom_bar, "offset_top", -bar_height, animation_duration)


## `do CinematicBars.hide_bars()` - the .dialogue-file counterpart to show_bars() above.
func hide_bars() -> void:
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(top_bar, "offset_bottom", 0.0, animation_duration)
	tween.tween_property(bottom_bar, "offset_top", 0.0, animation_duration)
