extends CanvasLayer
class_name TurnQueueDisplay

@onready var name_container: HBoxContainer = $Root/NameContainer

const CURRENT_ACTOR_COLOR: Color = Color(1.0, 0.85, 0.3)
const UPCOMING_ACTOR_COLOR: Color = Color(1.0, 1.0, 1.0, 0.75)
const CURRENT_ACTOR_FONT_SIZE: int = 22

## Rebuilds the row of name labels to reflect the current turn order.
## ordered_names[0] is treated as the current actor and highlighted; the rest
## are shown as upcoming turns in order.
func update_queue(ordered_names: Array[String]) -> void:
	# free() rather than queue_free(): update_queue() can be called more than once in the
	# same frame (recursive _next_turn() paths), and queue_free()'s deferred removal would
	# leave stale labels in get_children() for the rest of that frame.
	for child in name_container.get_children():
		child.free()

	for index in range(ordered_names.size()):
		if index > 0:
			var separator := Label.new()
			separator.text = "›"
			separator.add_theme_color_override("font_color", UPCOMING_ACTOR_COLOR)
			name_container.add_child(separator)

		var label := Label.new()
		label.text = ordered_names[index]
		if index == 0:
			label.add_theme_color_override("font_color", CURRENT_ACTOR_COLOR)
			label.add_theme_font_size_override("font_size", CURRENT_ACTOR_FONT_SIZE)
		else:
			label.add_theme_color_override("font_color", UPCOMING_ACTOR_COLOR)
		name_container.add_child(label)
