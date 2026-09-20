extends CanvasLayer
## A basic dialogue balloon for use with Dialogue Manager.


## The dialogue resource
@export var dialogue_resource: DialogueResource

## Start from a given title when using balloon as a [Node] in a scene.
@export var start_from_title: String = ""

## If running as a [Node] in a scene then auto start the dialogue.
@export var auto_start: bool = false

## If all other input is blocked as long as dialogue is shown.
@export var will_block_other_input: bool = true

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"
## CUSTOM: custom input for skipping text specifically
@export var skip_text_action: StringName = &"skip_text_action"

## A sound player for voice lines (if they exist).
@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

@onready var portrait: TextureRect = $Balloon/MarginContainer/MarginContainer/HBoxContainer/Portrait

# CUSTOM: central speaker roster (dialogue_cast.tres), keyed by speaker_key; populated in _ready().
const CAST_PATH := "res://src/dialogue/resources/dialogue_cast.tres"
var _cast_by_key: Dictionary = {}

## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			if owner == null:
				queue_free()
			else:
				hide()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

## The base balloon anchor
@onready var balloon: Control = %Balloon

# CUSTOM: balloon's visible-height panel; see _ready() for the cinematic-bar offset.
@onready var balloon_panel: MarginContainer = $Balloon/MarginContainer
const BALLOON_PANEL_HEIGHT: float = 219.0

## The label showing the name of the currently speaking character
@onready var character_label: RichTextLabel = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

## Indicator to show that player can progress dialogue.
@onready var progress: Polygon2D = %Progress


func _ready() -> void:
	balloon.hide()
	# CUSTOM: Balloon fills the full screen and is scaled down (see balloon.tscn),
	# so its pivot must be its own center or it scales toward the top-left corner instead.
	balloon.pivot_offset = balloon.size / 2
	balloon.position.y += 50
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	var cast: DialogueCast = load(CAST_PATH)
	if cast:
		for entry in cast.speakers:
			if entry and entry.speaker_key != "":
				_cast_by_key[entry.speaker_key] = entry

	# CUSTOM: shift the balloon panel up so it clears the bottom cinematic bar
	# instead of sitting behind it.
	var bottom_bar_height: float = CinematicBars.bar_height if CinematicBars else 0.0
	balloon_panel.offset_bottom = -bottom_bar_height
	balloon_panel.offset_top = -(BALLOON_PANEL_HEIGHT + bottom_bar_height)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)

	if auto_start:
		if not is_instance_valid(dialogue_resource):
			assert(false, DMConstants.get_error_message(DMConstants.ERR_MISSING_RESOURCE_FOR_AUTOSTART))
		start()


func _process(_delta: float) -> void:
	if is_instance_valid(dialogue_line):
		progress.visible = not dialogue_label.is_typing and dialogue_line.responses.size() == 0 and not dialogue_line.has_tag("voice")


func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	if will_block_other_input:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio: float = dialogue_label.visible_ratio
		dialogue_line = await dialogue_resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## Start some dialogue
func start(with_dialogue_resource: DialogueResource = null, title: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not title.is_empty():
		start_from_title = title
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_title, temporary_game_states)
	show()


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	progress.hide()
	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()

	# ---- CUSTOM: Speaker/Portrait Lookup ----
	var cast_entry: DialogueSpeaker = _cast_by_key.get(dialogue_line.character)
	if cast_entry:
		character_label.text = tr(cast_entry.display_name, "dialogue")
		portrait.texture = cast_entry.portrait
	else:
		character_label.text = tr(dialogue_line.character, "dialogue")
		# A phase-numbered portrait (e.g. portrait2.png) takes priority, so a character like
		# the boss can have a per-phase portrait (SignalBus.current_boss_phase); everyone else
		# only ever has portrait.png and falls through to it unchanged.
		var character_folder: String = dialogue_line.character.to_lower()
		var phased_portrait_path: String = "res://assets/Sprites/%s/portrait%d.png" % [character_folder, SignalBus.current_boss_phase]
		var default_portrait_path: String = "res://assets/Sprites/%s/portrait.png" % character_folder
		if ResourceLoader.exists(phased_portrait_path):
			portrait.texture = load(phased_portrait_path)
		elif ResourceLoader.exists(default_portrait_path):
			portrait.texture = load(default_portrait_path)
		else:
			portrait.texture = null


	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# Show our balloon
	balloon.show()
	will_hide_balloon = false

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		# CUSTOM: slower than the addon's default 0.02s/step — reads better at this pace.
		dialogue_label.seconds_per_step = 0.04
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.has_tag("voice"):
		audio_stream_player.stream = load(dialogue_line.get_tag_value("voice"))
		audio_stream_player.play()
		await audio_stream_player.finished
		next(dialogue_line.next_id)
	elif dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time: float = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()


func _on_mutated(mutation: Dictionary) -> void:
	if not mutation.is_inline:
		is_waiting_for_input = false
		will_hide_balloon = true
		mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		var skip_text_button_was_pressed: bool = event.is_action_pressed(skip_text_action)
		if skip_button_was_pressed or skip_text_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# When there are no response options the balloon itself is the thing advancing
	get_viewport().set_input_as_handled()

	if event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
