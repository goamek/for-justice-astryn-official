extends CanvasLayer

signal on_transition_finished
signal on_fade_in_finished

@onready var color_rect = $ColorRect

# True from the start of a fade-out until the matching fade-in completes; lets other
# systems (e.g. the pause menu) avoid toggling mid scene-transition.
var is_transitioning: bool = false

func _ready():
	color_rect.visible = false
	color_rect.modulate.a = 0.0

func transition(duration: float = 1.0):
	is_transitioning = true
	color_rect.visible = true
	var tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 1.0, duration)

	await tween.finished
	on_transition_finished.emit()

func fade_in(duration: float = 1.0):
	var tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 0.0, duration)

	await tween.finished
	color_rect.visible = false
	is_transitioning = false
	on_fade_in_finished.emit()
