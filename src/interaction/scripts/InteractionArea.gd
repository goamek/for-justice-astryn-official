extends Area3D
class_name InteractionArea


@export var action_name: String = "interact"

# Set false to make this NPC/object non-interactable (no "[E] to ..." prompt, no
# interact() call) without removing the InteractionArea node itself.
@export var interactable: bool = true

# Called by InteractionManager when this area is interacted with; assigned by the owning
# node (e.g. PartyMember._on_interact).
var interact: Callable = func():
	pass

func _on_body_entered(_body: Node3D) -> void:
	if interactable:
		InteractionManager.register_area(self)

func _on_body_exited(_body: Node3D) -> void:
	InteractionManager.unregister_area(self)
