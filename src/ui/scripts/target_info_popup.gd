extends CanvasLayer
class_name TargetInfoPopup

@onready var name_label: Label = $PopupRoot/InfoPanel/VBoxContainer/NameLabel
@onready var buffs_label: Label = $PopupRoot/InfoPanel/VBoxContainer/BuffsLabel
@onready var status_label: Label = $PopupRoot/InfoPanel/VBoxContainer/StatusLabel


func _ready() -> void:
	visible = false


## Populates the popup with a target's current stat stages and status effects.
func show_target(target: Node3D) -> void:
	if target == null or target.data == null:
		return

	var display_name = target.get("character_name")
	name_label.text = str(display_name) if display_name else str(target.name)

	var buffs_text: String = _build_buffs_line(target.data)
	buffs_label.text = buffs_text if not buffs_text.is_empty() else "No active buffs or debuffs."

	var status_text: String = _build_status_line(target.data)
	status_label.text = status_text if not status_text.is_empty() else "No active status effects."

	visible = true


func hide_popup() -> void:
	visible = false


func _build_buffs_line(data: CharacterData) -> String:
	var lines: Array[String] = []
	var stat_types: Array = [
		CharacterData.StatType.PHYSICALATTACK, CharacterData.StatType.PHYSICALDEFENSE,
		CharacterData.StatType.MAGICATTACK, CharacterData.StatType.MAGICDEFENSE,
		CharacterData.StatType.ACCURACY, CharacterData.StatType.EVASION, CharacterData.StatType.SPEED,
	]
	for stat_type in stat_types:
		var stage: int = data.get_stat_stage(stat_type)
		if stage != 0:
			var sign_str: String = "+" if stage > 0 else ""
			lines.append("%s %s%d" % [CombatMath.get_stat_label(stat_type), sign_str, stage])
	return "\n".join(lines)


func _build_status_line(data: CharacterData) -> String:
	var lines: Array[String] = []
	for effect in data.active_statuses:
		var turn_word: String = "turn" if effect.duration == 1 else "turns"
		lines.append("%s - %d %s left" % [effect.effect_name.capitalize(), effect.duration, turn_word])
	return "\n".join(lines)
