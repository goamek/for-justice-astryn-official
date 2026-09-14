extends Control

@onready var fade_overlay = $FadeOverlay
@onready var button_container = $ButtonContainer
@onready var main_menu_elements = $"Main Menu Elements"
@onready var controls_panel = $ControlsPanel
@onready var credits_panel = $CreditsPanel
@export var free_roam_scene: PackedScene

var menu_buttons: Array[Button] = []
# The currently open full-screen sub-page (Controls/Credits), or null when on the
# main menu itself. Tracked so a single cancel handler can close whichever is open.
var active_subpage: Control = null
# The button that opened active_subpage, so closing it can return focus to that same
# button instead of always snapping back to the first menu button.
var active_subpage_button: Button = null

func _ready():
	fade_overlay.visible = true
	fade_overlay.modulate.a = 1.0

	menu_buttons = [
		$ButtonContainer/StartButton,
		$ButtonContainer/ControlsButton,
		$ButtonContainer/CreditsButton,
		$ButtonContainer/QuitButton,
	]

	var tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, 4)
	AudioController.play_main_menu_music()
	call_deferred("_focus_first_menu_button")

func _unhandled_input(event: InputEvent) -> void:
	if active_subpage != null and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_close_subpage()

func _focus_first_menu_button() -> void:
	for button in menu_buttons:
		if button and button.visible and button.is_visible_in_tree():
			button.grab_focus()
			return

# Focuses the given button if it's still valid and visible, falling back to the first
# visible menu button otherwise.
func _focus_menu_button(button: Button) -> void:
	if button and is_instance_valid(button) and button.visible and button.is_visible_in_tree():
		button.grab_focus()
	else:
		_focus_first_menu_button()

# Hides the main menu and shows a full-screen sub-page (Controls/Credits). source_button
# is remembered so closing the sub-page can return focus to the button that opened it.
func _open_subpage(subpage: Control, source_button: Button) -> void:
	active_subpage = subpage
	active_subpage_button = source_button
	main_menu_elements.hide()
	button_container.hide()
	subpage.show()

# Returns from whichever sub-page is open back to the main menu, refocusing the
# button that opened it.
func _close_subpage() -> void:
	if active_subpage:
		active_subpage.hide()
	active_subpage = null
	main_menu_elements.show()
	button_container.show()
	call_deferred("_focus_menu_button", active_subpage_button)

# ---- Button Signal Handlers ----

func _on_start_button_pressed() -> void:
	print("Switch to Free Roam Scene via Menu")
	QuestManager.reset_progress()
	SignalBus.request_scene_change.emit(free_roam_scene, {})
	AudioController.stop_main_menu_music()

func _on_controls_button_pressed() -> void:
	_open_subpage(controls_panel, $ButtonContainer/ControlsButton)

func _on_credits_button_pressed() -> void:
	_open_subpage(credits_panel, $ButtonContainer/CreditsButton)

func _on_quit_button_pressed() -> void:
	get_tree().quit()
