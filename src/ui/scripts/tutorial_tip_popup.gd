# One-shot onboarding popup shown the first time a combat concept (HP/MP, type matchups,
# status moves) becomes relevant. Unlike MoveInfoPopup/TargetInfoPopup it's self-dismissing
# rather than toggled by the input that opened it, since nothing opens it but TurnBasedCombat.

extends CanvasLayer
class_name TutorialTipPopup

signal dismissed

@onready var title_label: Label = $PopupRoot/InfoPanel/VBoxContainer/TitleLabel
@onready var body_label: Label = $PopupRoot/InfoPanel/VBoxContainer/BodyLabel

func _ready() -> void:
	visible = false

func show_tip(title: String, body: String) -> void:
	title_label.text = title
	body_label.text = body
	visible = true
	# Deferred (not the immediate get_viewport().gui_release_focus() _open_move_info_popup()
	# uses) because show_tip() can be called mid-change_state(), the same frame
	# PlayerActionUI.show_action_canvas_layer() queues its own call_deferred to focus a move
	# button — an immediate release here would just lose that race and get overwritten.
	# Queuing ours after guarantees it wins regardless of who else deferred a focus grab.
	call_deferred("_release_focus")

func _release_focus() -> void:
	get_viewport().gui_release_focus()

func hide_popup() -> void:
	visible = false

func wait_for_dismissal() -> void:
	if visible:
		await dismissed

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("confirm"):
		hide_popup()
		dismissed.emit()
		get_viewport().set_input_as_handled()
