extends CanvasLayer
class_name TurnQueueDisplay

@onready var name_container: HBoxContainer = $Root/Backer/NameContainer

const CURRENT_ACTOR_COLOR: Color = Color(1.0, 0.85, 0.3)
const UPCOMING_ACTOR_COLOR: Color = Color(1.0, 1.0, 1.0, 0.75)
const CURRENT_ACTOR_FONT_SIZE: int = 18

# actor node -> its Label, so a specific combatant can be found again for highlighting even
# when multiple entries share a display name (e.g. the boss fight's trio of "Solider").
var _actor_labels: Dictionary = {}
var _highlighted_actor: Node3D = null
var _highlight_tween: Tween

## Rebuilds the row of name labels to reflect the current turn order.
## ordered_actors[0] is treated as the current actor and highlighted; the rest
## are shown as upcoming turns in order.
func update_queue(ordered_actors: Array[Node3D]) -> void:
	# free() rather than queue_free(): update_queue() can be called more than once in the
	# same frame (recursive _next_turn() paths), and queue_free()'s deferred removal would
	# leave stale labels in get_children() for the rest of that frame.
	for child in name_container.get_children():
		child.free()
	_actor_labels.clear()

	var index := 0
	for actor in ordered_actors:
		if not is_instance_valid(actor):
			continue

		if index > 0:
			var separator := Label.new()
			separator.text = "›"
			separator.add_theme_color_override("font_color", UPCOMING_ACTOR_COLOR)
			name_container.add_child(separator)

		var label := Label.new()
		label.text = actor.character_name if actor.character_name else str(actor.name)
		if index == 0:
			label.add_theme_color_override("font_color", CURRENT_ACTOR_COLOR)
			label.add_theme_font_size_override("font_size", CURRENT_ACTOR_FONT_SIZE)
		else:
			label.add_theme_color_override("font_color", UPCOMING_ACTOR_COLOR)
		name_container.add_child(label)
		_actor_labels[actor] = label
		index += 1

	_reapply_highlight()


## Blinks the given actor's name in the queue, in sync with that combatant's own sprite flash
## (see set_turn_highlight() on Enemy/Character/PartyMember). Re-applied after every
## update_queue() rebuild, so the highlight survives a new round reshuffling the list.
func set_highlighted_actor(actor: Node3D) -> void:
	_highlighted_actor = actor
	_reapply_highlight()


func clear_highlight() -> void:
	set_highlighted_actor(null)


func _reapply_highlight() -> void:
	if _highlight_tween and _highlight_tween.is_valid():
		_highlight_tween.kill()
		_highlight_tween = null

	# Killing the tween above stops it wherever it was mid-blink (anywhere between 0.3 and
	# 1.0 alpha) rather than settling back to fully opaque — reset every label here so a
	# highlight moving to a new actor (e.g. cycling targets) never leaves the old one dimmed.
	for label in _actor_labels.values():
		label.modulate.a = 1.0

	if _highlighted_actor == null or not _actor_labels.has(_highlighted_actor):
		return

	var label: Label = _actor_labels[_highlighted_actor]
	_highlight_tween = create_tween().set_loops()
	_highlight_tween.tween_property(label, "modulate:a", 0.3, 0.4)
	_highlight_tween.tween_property(label, "modulate:a", 1.0, 0.4)
