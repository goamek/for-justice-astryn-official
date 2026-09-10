# Shows/hides the TBC action UI; targeting is handled separately by TurnBasedCombat's
# cycle-and-confirm target pointer rather than a button grid.

extends CanvasLayer
class_name PlayerActionUI

@onready var action_canvas_layer = $"Player Action CL"
@onready var target_canvas_layer = $"Select Target CL"
@onready var button_one = $"Player Action CL/VBoxContainer/HBoxContainer/Button1"
@onready var button_two = $"Player Action CL/VBoxContainer/HBoxContainer/Button2"
@onready var button_three = $"Player Action CL/VBoxContainer/HBoxContainer/Button3"
@onready var button_four = $"Player Action CL/VBoxContainer/HBoxContainer/Button4"

var action_buttons: Array[Button] = []

func _ready() -> void:
	action_buttons = [button_one, button_two, button_three, button_four]
	for button in action_buttons:
		if button:
			button.focus_mode = Control.FOCUS_ALL


func show_action_canvas_layer():
	target_canvas_layer.visible = false
	action_canvas_layer.visible = true
	call_deferred("set_focus_on_attack_button")

func hide_action_canvas_layer():
	action_canvas_layer.visible = false

func show_target_canvas_layer():
	action_canvas_layer.visible = false
	target_canvas_layer.visible = true

func hide_target_canvas_layer():
	target_canvas_layer.visible = false

func _focus_first_visible_button(buttons: Array[Button]) -> void:
	for button in buttons:
		if button and button.visible and button.is_visible_in_tree():
			call_deferred("_grab_focus", button)
			return

func _grab_focus(button: Button) -> void:
	if is_instance_valid(button) and button.visible and button.is_visible_in_tree():
		button.grab_focus()

func set_focus_on_attack_button():
	_focus_first_visible_button(action_buttons)

## Returns the index of whichever action button currently has focus, or -1 if none does.
func get_focused_move_index() -> int:
	for i in range(action_buttons.size()):
		if action_buttons[i] and action_buttons[i].has_focus():
			return i
	return -1
