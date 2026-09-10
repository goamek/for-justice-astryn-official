extends CanvasLayer
class_name BattleMessageBox

signal queue_started
signal queue_finished

@export var advance_action: StringName = &"ui_accept"
@export var skip_action: StringName = &"ui_cancel"
@export var will_block_other_input: bool = true

@onready var panel: PanelContainer = $MessageRoot/MessagePanel
@onready var message_label: Label = $MessageRoot/MessagePanel/VBoxContainer/MessageLabel
@onready var prompt_label: Label = $MessageRoot/MessagePanel/VBoxContainer/PromptLabel

# FIFO queue of messages waiting to be shown.
var _queue: Array[String] = []
# True while the message box owns focus and is processing the queue.
var _is_active: bool = false
# True only while waiting for player input to show the next queued message.
var _is_waiting_for_advance: bool = false
# Timer used to blink the advance prompt.
var _blink_time: float = 0.0


## Initializes the message box as hidden and subscribes to battle message requests.
func _ready() -> void:
	visible = false
	if SignalBus != null and SignalBus.has_signal("battle_message_requested"):
		SignalBus.battle_message_requested.connect(_on_battle_message_requested)


## Unsubscribes from SignalBus when this node leaves the scene tree.
func _exit_tree() -> void:
	if SignalBus != null and SignalBus.has_signal("battle_message_requested") and SignalBus.battle_message_requested.is_connected(_on_battle_message_requested):
		SignalBus.battle_message_requested.disconnect(_on_battle_message_requested)


## Updates the blinking advance prompt while waiting for player input.
func _process(delta: float) -> void:
	if not _is_active:
		return

	if _is_waiting_for_advance:
		# Blink the prompt at a 1-second cycle (visible for half the cycle).
		_blink_time += delta
		prompt_label.visible = fmod(_blink_time, 1.0) < 0.5
	else:
		prompt_label.visible = false


## Handles advance/skip actions and optionally blocks other input while active.
func _unhandled_input(event: InputEvent) -> void:
	if not _is_active:
		return

	# Advance or skip both move to the next message immediately.
	if event.is_action_pressed(advance_action) or event.is_action_pressed(skip_action):
		get_viewport().set_input_as_handled()
		if _is_waiting_for_advance:
			_advance_message()
		return

	# Optionally consume all other input while the message box is active.
	if will_block_other_input:
		get_viewport().set_input_as_handled()


## Enqueues a single non-empty message and starts the queue if idle.
func queue_message(message: String) -> void:
	if message.strip_edges().is_empty():
		return

	_queue.append(message)
	# Starting from idle: show this message right away.
	if not _is_active:
		_start_queue()


## Enqueues multiple non-empty messages and starts the queue if idle.
func queue_messages(messages: Array[String]) -> void:
	for message in messages:
		if not message.strip_edges().is_empty():
			_queue.append(message)

	# Batch enqueue should also auto-start when currently idle.
	if not _is_active and not _queue.is_empty():
		_start_queue()


## Waits until the current queue finishes processing.
func wait_until_idle() -> void:
	if not _is_active:
		return
	# Allows callers to await the full queue lifecycle.
	await queue_finished


## Clears pending messages and immediately hides/deactivates the message box.
func clear_queue() -> void:
	_queue.clear()
	_is_waiting_for_advance = false
	_is_active = false
	visible = false


## Receives battle message requests from SignalBus and queues the message.
func _on_battle_message_requested(message: String, _options: Dictionary = {}) -> void:
	queue_message(message)


## Activates the message box and begins displaying queued messages.
func _start_queue() -> void:
	if _queue.is_empty():
		return

	_is_active = true
	visible = true
	panel.show()
	queue_started.emit()
	_show_next_message()


## Displays the next queued message or finishes if the queue is empty.
func _show_next_message() -> void:
	if _queue.is_empty():
		_finish_queue()
		return

	message_label.text = _queue.pop_front()
	# Display one line at a time and wait for explicit player confirmation.
	_is_waiting_for_advance = true
	_blink_time = 0.0
	prompt_label.visible = true


## Moves from the current message to the next queued message.
func _advance_message() -> void:
	_is_waiting_for_advance = false
	_show_next_message()


## Deactivates the message box and emits queue completion.
func _finish_queue() -> void:
	_is_active = false
	_is_waiting_for_advance = false
	visible = false
	queue_finished.emit()
