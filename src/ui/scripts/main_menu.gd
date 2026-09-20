extends Control
class_name MainMenu

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
		$ButtonContainer/PostCreditsOneButton,
		$ButtonContainer/PostCreditsTwoButton,
		$ButtonContainer/QuitButton,
	]
	$ButtonContainer/PostCreditsOneButton.visible = QuestManager.endings_seen.get("kill", false)
	$ButtonContainer/PostCreditsTwoButton.visible = QuestManager.endings_seen.get("spare_novius_intervened", false)
	_update_focus_neighbors()

	for button in menu_buttons:
		button.mouse_entered.connect(_on_button_hovered.bind(button))
	for panel in [controls_panel, credits_panel]:
		panel.get_node("BackButton").pressed.connect(_close_subpage)

	var tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, 4)
	AudioController.play_main_menu_music()
	call_deferred("_focus_first_menu_button")

func _unhandled_input(event: InputEvent) -> void:
	# "pause" is included so Escape backs out too — it's bound to Escape/gamepad Start,
	# while "cancel" itself is only bound to F/gamepad B. The global pause overlay never
	# opens on the main menu (see pause_menu.gd's MainMenu guard), so there's no conflict
	# with also treating "pause" as a back button here.
	if active_subpage != null and (event.is_action_pressed("cancel") or event.is_action_pressed("pause")):
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
	subpage.get_node("BackButton").call_deferred("grab_focus")

# Returns from whichever sub-page is open back to the main menu, refocusing the
# button that opened it.
func _close_subpage() -> void:
	if active_subpage:
		active_subpage.hide()
	active_subpage = null
	main_menu_elements.show()
	button_container.show()
	call_deferred("_focus_menu_button", active_subpage_button)

# Chains focus_neighbor_top/bottom across only the currently-visible menu buttons, so
# navigation doesn't land on a hidden PostCredits button when it's not unlocked.
func _update_focus_neighbors() -> void:
	var visible_buttons: Array[Button] = menu_buttons.filter(func(b): return b.visible)
	for i in visible_buttons.size():
		var button: Button = visible_buttons[i]
		button.focus_neighbor_top = button.get_path_to(visible_buttons[i - 1]) if i > 0 else NodePath()
		button.focus_neighbor_bottom = button.get_path_to(visible_buttons[i + 1]) if i < visible_buttons.size() - 1 else NodePath()

# ---- Button Signal Handlers ----

func _on_button_hovered(button: Button) -> void:
	if button.visible:
		button.grab_focus()

func _on_start_button_pressed() -> void:
	print("Switch to Free Roam Scene via Menu")
	QuestManager.reset_progress()
	SignalBus.request_scene_change.emit(free_roam_scene, {})
	AudioController.stop_main_menu_music()

func _on_controls_button_pressed() -> void:
	_open_subpage(controls_panel, $ButtonContainer/ControlsButton)

func _on_credits_button_pressed() -> void:
	_open_subpage(credits_panel, $ButtonContainer/CreditsButton)

func _on_post_credits_one_button_pressed() -> void:
	_replay_ending_epilogue("post_credits_epilogue")

func _on_post_credits_two_button_pressed() -> void:
	_replay_ending_epilogue("post_credits_epilogue_novius_intervened")

# Jumps straight to the post-credits epilogue dialogue for an already-seen ending — same
# scene/title pair BossTurnBasedCombat's ending sequence uses, minus the credits roll.
func _replay_ending_epilogue(epilogue_title: String) -> void:
	AudioController.stop_main_menu_music()
	AudioController.play_credits_music()
	var end_credit_scene: PackedScene = load("res://src/level/scenes/end_credit_scene.tscn")
	SignalBus.request_scene_change.emit(end_credit_scene, {"epilogue_title": epilogue_title})

func _on_quit_button_pressed() -> void:
	get_tree().quit()
