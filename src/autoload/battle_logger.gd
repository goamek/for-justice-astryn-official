extends Node

# Mirrors every on-screen battle message to a plain-text file, cleared at the start
# of each battle, so the current battle's log can be reviewed after the fact without
# having to watch the battle_message_box live. Editor-only — an exported build (what
# players run) must never write anything to disk, so this whole autoload is inert
# outside the editor (see the OS.has_feature("editor") check in _ready()).
const LOG_PATH: String = "res://logs/battle_log.txt"

var _log_file: FileAccess


func _ready() -> void:
	if not OS.has_feature("editor"):
		return

	if SignalBus != null:
		if SignalBus.has_signal("battle_message_requested"):
			SignalBus.battle_message_requested.connect(_on_battle_message_requested)
		if SignalBus.has_signal("battle_started"):
			SignalBus.battle_started.connect(_reset_log)

	_reset_log()


func _exit_tree() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null


## Truncates the log file and writes a fresh header, discarding any previous battle's messages.
func _reset_log() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null

	var log_dir: String = LOG_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(log_dir):
		DirAccess.make_dir_recursive_absolute(log_dir)
	_log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _log_file == null:
		push_error("BattleLogger: could not open %s for writing (error %d)" % [LOG_PATH, FileAccess.get_open_error()])
		return

	_log_file.store_line("=== Battle log started %s ===" % Time.get_datetime_string_from_system())
	_log_file.flush()


func _on_battle_message_requested(message: String, _options: Dictionary = {}) -> void:
	if _log_file == null:
		return
	_log_file.store_line(message)
	_log_file.flush()
