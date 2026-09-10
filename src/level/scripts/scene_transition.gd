extends CanvasLayer

signal on_transition_finished

@onready var color_rect = $ColorRect

func _ready():
	color_rect.visible = false
	color_rect.modulate.a = 0.0

func transition(duration: float = 1.0):
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
