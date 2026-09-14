extends Control
## Global pause overlay, mounted once under main_node.tscn's UI/CanvasLayer (survives
## every scene swap). Toggleable in any scene except mid scene-transition; freezes
## gameplay via get_tree().paused, which every other script's default
## PROCESS_MODE_INHERIT already respects.

@onready var button_container: VBoxContainer = $ButtonContainer
@onready var controls_panel: Control = $ControlsPanel
@onready var resume_button: Button = $ButtonContainer/ResumeButton
@onready var controls_button: Button = $ButtonContainer/ControlsButton
@onready var quit_battle_button: Button = $ButtonContainer/QuitBattleButton
@onready var quit_game_button: Button = $ButtonContainer/QuitGameButton

# Kept current by main.gd on every scene swap, so this menu knows what it's pausing
# (and, for Quit Battle, whether it's a practice fight) without a fragile absolute path.
var current_gameplay_scene: Node = null

# The sub-page currently open in place of the button list (Controls), or null.
var active_subpage: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if SceneTransition.is_transitioning:
		return

	if active_subpage != null:
		if event.is_action_pressed("cancel"):
			get_viewport().set_input_as_handled()
			_close_subpage()
		return

	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if visible:
			_close_pause()
		else:
			_open_pause()


func _open_pause() -> void:
	visible = true
	get_tree().paused = true
	var is_practice_fight: bool = current_gameplay_scene != null \
		and current_gameplay_scene is TurnBasedCombat \
		and not current_gameplay_scene is BossTurnBasedCombat
	quit_battle_button.visible = is_practice_fight
	call_deferred("_focus_first_button")


func _close_pause() -> void:
	active_subpage = null
	button_container.show()
	controls_panel.hide()
	visible = false
	get_tree().paused = false


func _focus_first_button() -> void:
	for button in [resume_button, controls_button, quit_battle_button, quit_game_button]:
		if button.visible:
			button.grab_focus()
			return


func _open_subpage(subpage: Control) -> void:
	active_subpage = subpage
	button_container.hide()
	subpage.show()


func _close_subpage() -> void:
	if active_subpage:
		active_subpage.hide()
	active_subpage = null
	button_container.show()
	call_deferred("_focus_first_button")


# ---- Button Signal Handlers ----

func _on_resume_button_pressed() -> void:
	_close_pause()


func _on_controls_button_pressed() -> void:
	_open_subpage(controls_panel)


func _on_quit_game_button_pressed() -> void:
	get_tree().quit()


func _on_quit_battle_button_pressed() -> void:
	var battle := current_gameplay_scene as TurnBasedCombat
	if battle == null:
		return
	battle.reset_party_battle_modifiers()
	# Unpause before emitting combat_ended — SceneTransition's fade tween would otherwise
	# be frozen by the same get_tree().paused this menu set.
	_close_pause()
	AudioController.stop_battle_music()
	battle.combat_ended.emit(true)
