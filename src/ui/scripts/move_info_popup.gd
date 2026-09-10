extends CanvasLayer
class_name MoveInfoPopup

@onready var name_label: Label = $PopupRoot/InfoPanel/VBoxContainer/NameLabel
@onready var stats_label: Label = $PopupRoot/InfoPanel/VBoxContainer/StatsLabel
@onready var effect_label: Label = $PopupRoot/InfoPanel/VBoxContainer/EffectLabel
@onready var description_label: Label = $PopupRoot/InfoPanel/VBoxContainer/DescriptionLabel


func _ready() -> void:
	visible = false


## Populates the popup with a move's stats/effect/flavor text and shows it.
func show_move(move: MoveData) -> void:
	if move == null:
		return

	name_label.text = move.move_name
	stats_label.text = _build_stats_line(move)

	var effect_text: String = _build_effect_line(move)
	effect_label.text = effect_text
	effect_label.visible = not effect_text.is_empty()

	description_label.text = move.description
	description_label.visible = not move.description.is_empty()

	visible = true


func hide_popup() -> void:
	visible = false


func _build_stats_line(move: MoveData) -> String:
	var category_names := ["Physical", "Magic", "Status"]
	var parts: Array[String] = ["%s · %s" % [TypeData.type_to_string(move.typing), category_names[move.category]]]

	if move.category != MoveData.MoveCategory.STATUS:
		parts.append("Power %d" % move.damage)
		parts.append("Accuracy %d%%" % move.accuracy)
		parts.append("Crit %d%%" % move.crit_chance)

	if move.category != MoveData.MoveCategory.PHYSICAL:
		parts.append("MP %d" % move.mana_cost)

	return " · ".join(parts)


func _build_effect_line(move: MoveData) -> String:
	var lines: Array[String] = []

	if move.status_to_inflict != null:
		lines.append("%d%% chance to inflict %s" % [move.status_chance, move.status_to_inflict.effect_name.capitalize()])

	if move.heal_fraction_of_max_hp > 0.0:
		lines.append("Heals %d%% max HP" % int(round(move.heal_fraction_of_max_hp * 100)))

	if move.stat_to_change != MoveData.StatType.NONE:
		lines.append(_stat_change_text(move.stat_to_change, move.stat_change_amount, move.self_target_only))
	if move.stat_to_change_2 != MoveData.StatType.NONE:
		lines.append(_stat_change_text(move.stat_to_change_2, move.stat_change_amount_2, move.self_target_only))

	if not move.cures_statuses.is_empty():
		var cure_names: Array[String] = []
		for status_type in move.cures_statuses:
			cure_names.append(StatusEffect.StatusType.keys()[status_type].capitalize())
		lines.append("Cures: %s" % ", ".join(cure_names))

	if move.targets_all:
		lines.append("Hits all combatants")

	return "\n".join(lines)


func _stat_change_text(stat: MoveData.StatType, amount: int, self_target_only: bool) -> String:
	var stat_name: String = MoveData.StatType.keys()[stat].capitalize()
	var who: String = "Self" if self_target_only else "Target"
	var sign_str: String = "+" if amount >= 0 else ""
	return "%s: %s%d %s" % [who, sign_str, amount, stat_name]
