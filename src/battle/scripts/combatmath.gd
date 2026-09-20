extends Node
class_name CombatMath

const DEBUG_DAMAGE_LOGS: bool = true

# Converts a raw type multiplier into a simple categorical label that AI can
# learn from without requiring access to defender typing internals.
static func _classify_type_result(type_multiplier: float) -> String:
	if type_multiplier <= 0.0:
		return "immune"
	if type_multiplier < 1.0:
		return "resist"
	if type_multiplier > 1.0:
		return "weak"
	return "neutral"


static func get_stat_label(stat_type: MoveData.StatType) -> String:
	match stat_type:
		MoveData.StatType.PHYSICALATTACK:
			return "Physical Attack"
		MoveData.StatType.MAGICATTACK:
			return "Magic Attack"
		MoveData.StatType.PHYSICALDEFENSE:
			return "Physical Defense"
		MoveData.StatType.MAGICDEFENSE:
			return "Magic Defense"
		MoveData.StatType.ACCURACY:
			return "Accuracy"
		MoveData.StatType.EVASION:
			return "Evasion"
		MoveData.StatType.SPEED:
			return "Speed"
		_:
			return "Stat"


## Applies one stat-stage change and appends the resulting message. Returns the new
## stage value (or null if the change couldn't apply), matching CharacterData.adjust_stat_stage.
static func _apply_stat_change(defender: Node3D, stat_type: MoveData.StatType, amount: int, messages: Array[String]):
	if stat_type == MoveData.StatType.NONE or amount == 0:
		return null
	var stat_label: String = get_stat_label(stat_type)
	var previous_stage: int = defender.data.get_stat_stage(stat_type)
	var stat_change = defender.data.adjust_stat_stage(stat_type, amount)
	var was_capped: bool = stat_change != null and stat_change == previous_stage
	if stat_change == null:
		messages.append("%s's %s could not change." % [defender.character_name, stat_label])
	elif was_capped:
		if amount > 0:
			messages.append("%s's %s won't go any higher!" % [defender.character_name, stat_label])
		else:
			messages.append("%s's %s won't go any lower!" % [defender.character_name, stat_label])
	else:
		if amount > 0:
			messages.append("%s's %s rose!" % [defender.character_name, stat_label])
		else:
			messages.append("%s's %s fell!" % [defender.character_name, stat_label])
	if DEBUG_DAMAGE_LOGS:
		var sign_prefix: String = "+" if amount >= 0 else ""
		var change_text: String = "%s%d" % [sign_prefix, amount]
		if stat_change == null:
			print("Applied %s %s (no stage change)" % [stat_label, change_text])
		elif was_capped:
			print("Applied %s %s (already at cap, stage %d)" % [stat_label, change_text, stat_change])
		else:
			print("Applied %s %s (new stage %d)" % [stat_label, change_text, stat_change])
	if stat_change != null and not was_capped and defender.has_method("flash_stat_change_tint"):
		defender.flash_stat_change_tint(amount > 0)
	return stat_change


static func _format_status_applied(target_name: String, status: StatusEffect) -> String:
	var normalized: String = status.effect_name.to_lower()
	if normalized == "freeze":
		return "%s was frozen solid!" % [target_name]
	if normalized == "water coating":
		return "%s is now coated with water!" % [target_name]
	if normalized == "oil coating":
		return "%s is now coated in oil!" % [target_name]
	if normalized == "tar coating":
		return "%s is now coated in tar!" % [target_name]
	var past_tense: String = status.effect_name_past if status.effect_name_past != "" else status.effect_name
	return "%s is now %s." % [target_name, past_tense]

static func calculate_damage(attacker: Node3D, defender: Node3D, move: MoveData) -> Dictionary:

	# ---- 1. Early Exit for Status Moves ----
	if move.category == MoveData.MoveCategory.STATUS:
		var status_effect_messages: Array[String] = []
		var status_base_acc: float = attacker.data.base_accuracy
		var status_base_eva: float = defender.data.base_evasion
		var status_acc_stage: int = attacker.data.accuracy_stage
		var status_eva_stage: int = defender.data.evasion_stage
		var status_acc_mult: float = attacker.data.get_stat_multiplier(status_acc_stage)
		var status_eva_mult: float = defender.data.get_stat_multiplier(status_eva_stage)

		var status_final_accuracy: float = status_base_acc * status_acc_mult
		var status_final_evasion: float = status_base_eva * status_eva_mult

		if defender.data.has_status(StatusEffect.StatusType.PARALYZE):
			status_final_evasion *= 0.5
			if DEBUG_DAMAGE_LOGS:
				print("Defender is Paralyzed! Evasion reduced by half.")
		if defender.data.has_status(StatusEffect.StatusType.FREEZE):
			status_final_evasion *= 0.5
			if DEBUG_DAMAGE_LOGS:
				print("Defender is Frozen! Evasion reduced by half.")

		var status_hit_chance: float = clamp(move.accuracy * (status_final_accuracy / max(status_final_evasion, 1.0)), 0.0, 100.0)
		# Evasion represents dodging an opponent's attack — it shouldn't block your own buff
		# or a teammate's heal, so self/ally/revive/never_misses moves bypass it.
		var bypasses_evasion: bool = move.self_target_only or move.ally_target_only or move.revives or move.never_misses
		var status_did_hit: bool = bypasses_evasion or (randi_range(1, 100) <= int(status_hit_chance))

		if DEBUG_DAMAGE_LOGS:
			print("Hit Chance: %.1f%%" % [status_hit_chance])
		if not status_did_hit:
			if DEBUG_DAMAGE_LOGS:
				print("Move missed: Move Accuracy %.1f, Attacker Accuracy %.1f, Target Evasion %.1f" % [move.accuracy, status_final_accuracy, status_final_evasion])
			return {
				"amount": 0,
				"is_crit": false,
				"did_hit": false,
				"effect_messages": status_effect_messages,
				"oil_ignited": false,
				# AI learning metadata:
				"type_multiplier": 1.0,
				"type_result": "miss"
			}

		_apply_stat_change(defender, move.stat_to_change, move.stat_change_amount, status_effect_messages)
		_apply_stat_change(defender, move.stat_to_change_2, move.stat_change_amount_2, status_effect_messages)

		# Field Reset Hook: clears every stat stage (not status conditions). Paired with
		# targets_all, this is how Smoke resets buffs/debuffs battlefield-wide.
		if move.resets_stat_stages:
			defender.data.reset_modifiers()
			status_effect_messages.append("%s's stat changes were reset!" % [defender.character_name])
			if defender.has_method("flash_stat_reset_tint"):
				defender.flash_stat_reset_tint()

		# Healing Hook: restore a fraction of the target's max HP
		if move.heal_fraction_of_max_hp > 0.0 and defender.has_method("heal"):
			var heal_amount: float = defender.max_hp * move.heal_fraction_of_max_hp
			var actual_heal: float = defender.heal(heal_amount)
			if actual_heal > 0:
				status_effect_messages.append("%s recovered %d HP!" % [defender.character_name, int(round(actual_heal))])
			else:
				status_effect_messages.append("%s's HP is already full!" % [defender.character_name])

		# Cure Hook: remove specific status types from the target
		for cured_type in move.cures_statuses:
			var existing_status: StatusEffect = defender.data.get_status(cured_type)
			if existing_status:
				defender.data.active_statuses.erase(existing_status)
				status_effect_messages.append("%s's %s was cured!" % [defender.character_name, existing_status.effect_name])

		# Status Trigger Hook: Check to see if the status move inflicts an explicit condition
		if move.status_to_inflict and randi_range(1, 100) <= move.status_chance:
			if defender.has_method("apply_status_effect"):
				defender.apply_status_effect(move.status_to_inflict, attacker.data.base_magic_attack)
				status_effect_messages.append(_format_status_applied(defender.character_name, move.status_to_inflict))
				if DEBUG_DAMAGE_LOGS:
					print("Successfully applied condition: %s" % [move.status_to_inflict.effect_name])

		if status_effect_messages.is_empty():
			status_effect_messages.append("It dealt no damage.")

		return {
			"amount": 0,
			"is_crit": false,
			"did_hit": true,
			"effect_messages": status_effect_messages,
			"oil_ignited": false,
			# Status moves do not reveal offensive type matchup information.
			"type_multiplier": 1.0,
			"type_result": "status"
		}

	# ---- 2. Stat Retrieval & Modifiers ----
	var base_atk: float = 0.0
	var base_def: float = 0.0

	if move.category == MoveData.MoveCategory.PHYSICAL:
		base_atk = attacker.data.base_physical_attack
		base_def = defender.data.base_physical_defense
	elif move.category == MoveData.MoveCategory.MAGIC:
		base_atk = attacker.data.base_magic_attack
		base_def = defender.data.base_magic_defense

	# Status Trigger Hook: Paralyze (cuts physical attack moves by half)
	if move.category == MoveData.MoveCategory.PHYSICAL and attacker.data.has_status(StatusEffect.StatusType.PARALYZE):
		base_atk *= 0.5
		if DEBUG_DAMAGE_LOGS:
			print("Attacker is Paralyzed! Physical attack power cut in half")

	# ---- 2.5. Accuracy/Evasion ----
	var base_acc: float = attacker.data.base_accuracy
	var base_eva: float = defender.data.base_evasion
	var acc_stage: int = attacker.data.accuracy_stage
	var eva_stage: int = defender.data.evasion_stage
	var acc_mult: float = attacker.data.get_stat_multiplier(acc_stage)
	var eva_mult: float = defender.data.get_stat_multiplier(eva_stage)

	var final_accuracy: float = base_acc * acc_mult
	var final_evasion: float = base_eva * eva_mult

	if defender.data.has_status(StatusEffect.StatusType.PARALYZE):
		final_evasion *= 0.5
		if DEBUG_DAMAGE_LOGS:
			print("Defender is Paralyzed! Evasion reduced by half.")
	if defender.data.has_status(StatusEffect.StatusType.FREEZE):
		final_evasion *= 0.5
		if DEBUG_DAMAGE_LOGS:
			print("Defender is Frozen! Evasion reduced by half.")

	var hit_chance: float = clamp(move.accuracy * (final_accuracy / max(final_evasion, 1.0)), 0.0, 100.0)
	var did_hit: bool = randi_range(1, 100) <= int(hit_chance)

	if DEBUG_DAMAGE_LOGS:
		print("Hit Chance: %.1f%%" % [hit_chance])
	if not did_hit:
		if DEBUG_DAMAGE_LOGS:
			print("Move missed: Move Accuracy %.1f, Attacker Accuracy %.1f, Target Evasion %.1f" % [move.accuracy, final_accuracy, final_evasion])
		return {
			"amount": 0,
			"is_crit": false,
			"did_hit": false,
			"effect_messages": [] as Array[String],
			"oil_ignited": false,
			# AI learning metadata:
			"type_multiplier": 1.0,
			"type_result": "miss"
		}

	# ---- 3. Critical Hit Determination ----
	var is_crit: bool = randi_range(1, 100) <= move.crit_chance

	var atk_stage: int = attacker.data.physical_attack_stage if move.category == MoveData.MoveCategory.PHYSICAL else attacker.data.magic_attack_stage
	var def_stage: int = defender.data.physical_defense_stage if move.category == MoveData.MoveCategory.PHYSICAL else defender.data.magic_defense_stage

	var atk_mult: float = attacker.data.get_stat_multiplier(atk_stage)
	var def_mult: float = defender.data.get_stat_multiplier(def_stage)

	# CRIT RULE: Ignore attacker negative buffs & defender positive buffs
	var crit_ignored_atk_debuff: bool = false
	var crit_ignored_def_buff: bool = false

	if is_crit:
		if atk_stage < 0:
			atk_mult = 1.0
			crit_ignored_atk_debuff = true
		if def_stage > 0:
			def_mult = 1.0
			crit_ignored_def_buff = true

	var final_atk = base_atk * atk_mult
	var final_def = base_def * def_mult

	# ---- 4. Core Damage Ratio ----
	var damage_ratio: float = final_atk / max(final_def, 1.0)
	var base_damage: float = move.damage * damage_ratio

	# ---- 5. Multipliers (Type, STAB, Crit, Variance) ----
	var type_multiplier: float = 1.0
	var move_typing: TypeData.Type = move.typing
	var move_primary_type: TypeData.Type = TypeData.get_primary_type(move_typing)
	var move_subtype: TypeData.Type = move.subtype
	var attacker_typing: Array[TypeData.Type] = attacker.data.typing
	var defender_typing: Array[TypeData.Type] = defender.data.typing

	var attacker_primary_types: Array[TypeData.Type] = []
	for atk_type in attacker_typing:
		attacker_primary_types.append(TypeData.get_primary_type(atk_type))

	for def_type in defender_typing:
		var defender_primary_type: TypeData.Type = TypeData.get_primary_type(def_type)
		if TypeData.DEFENDING_CHART[defender_primary_type].has(move_primary_type):
			type_multiplier *= TypeData.DEFENDING_CHART[defender_primary_type][move_primary_type]

	var stab_multiplier: float = 1.0
	if move_primary_type in attacker_primary_types:
		stab_multiplier = 1.5

	var final_damage: float = base_damage * type_multiplier * stab_multiplier
	var hit_effect_messages: Array[String] = []
	var oil_ignited: bool = false

	# Coating Hook: Oil ignites on a Fire hit for bonus damage, consuming the coating —
	# mirrors the Water+Ice/Freeze interaction below with a player-facing message instead
	# of a silent damage bump.
	if move_primary_type == TypeData.Type.FIRE and defender.data.has_status(StatusEffect.StatusType.COATING_OIL):
		oil_ignited = true
		var oil_ignite_multiplier: float = 1.5
		final_damage *= oil_ignite_multiplier
		var oil_coating: StatusEffect = defender.data.get_status(StatusEffect.StatusType.COATING_OIL)
		if oil_coating:
			defender.data.active_statuses.erase(oil_coating)
		hit_effect_messages.append("%s's oil coating ignited into a blaze, dealing bonus damage!" % [defender.character_name])
		if DEBUG_DAMAGE_LOGS:
			print("Target's oil coating ignited! Fire attack dealt %sx damage." % [oil_ignite_multiplier])

	# Status Control Hook: Provoke
	if attacker.data.has_status(StatusEffect.StatusType.PROVOKE):
		final_damage *= 1.5
		if DEBUG_DAMAGE_LOGS:
			print("Attacker is Provoked! Dealing 1.5x damage.")
	if defender.data.has_status(StatusEffect.StatusType.PROVOKE):
		final_damage *= 1.5
		if DEBUG_DAMAGE_LOGS:
			print("Defender is Provoked! Taking 1.5x damage.")

	if is_crit:
		final_damage *= 1.5

	var variance: float = randf_range(0.85, 1.0)
	final_damage *= variance

	# ---- 6. Output, Coating Application, & Logs ----
	var rounded_damage: int = int(max(1, ceil(final_damage)))

	# Attack Hit Hook: bundled status/coating application. Skips re-freezing an
	# already-frozen target even if re-coated with water — freeze can't refresh until it
	# wears off on its own.
	var freeze_triggered: bool = (move_subtype == TypeData.Type.ICE
		and defender.data.has_status(StatusEffect.StatusType.COATING_WATER)
		and not defender.data.has_status(StatusEffect.StatusType.FREEZE))
	var freeze_applied_message: String = ""
	if (move.status_to_inflict and randi_range(1, 100) <= move.status_chance) or freeze_triggered:
		if freeze_triggered:
			var coating_effect = defender.data.get_status(StatusEffect.StatusType.COATING_WATER)
			if coating_effect:
				defender.data.active_statuses.erase(coating_effect)
				freeze_applied_message = "Water coating consumed by freezing!"
				hit_effect_messages.append("The water coating was consumed!")

			if defender.has_method("apply_status_effect"):
				if move.status_to_inflict:
					defender.apply_status_effect(move.status_to_inflict, attacker.data.base_magic_attack)
					freeze_applied_message += "\nWater coating froze solid! Applied status condition from attack: " + move.status_to_inflict.effect_name
					hit_effect_messages.append("The water coating froze solid!")
					hit_effect_messages.append(_format_status_applied(defender.character_name, move.status_to_inflict))
				else:
					var freeze_effect: StatusEffect = StatusEffect.new()
					freeze_effect.effect_name = "Freeze"
					freeze_effect.effect_name_past = "Frozen"
					freeze_effect.type = StatusEffect.StatusType.FREEZE
					defender.apply_status_effect(freeze_effect)
					freeze_applied_message += "\nWater coating froze solid! Applied default FREEZE status."
					hit_effect_messages.append("The water coating froze solid!")
					hit_effect_messages.append(_format_status_applied(defender.character_name, freeze_effect))
		elif defender.has_method("apply_status_effect"):
			defender.apply_status_effect(move.status_to_inflict, attacker.data.base_magic_attack)
			hit_effect_messages.append(_format_status_applied(defender.character_name, move.status_to_inflict))

	if DEBUG_DAMAGE_LOGS:
		print("\n## --- DAMAGE LOGS ---")
		print("Move Name: %s" % [move.move_name])
		print("Move Category: %s" % [MoveData.MoveCategory.keys()[move.category]])

		var atk_label = "Physical Attack" if move.category == MoveData.MoveCategory.PHYSICAL else "Magic Attack"
		var def_label = "Physical Defense" if move.category == MoveData.MoveCategory.PHYSICAL else "Magic Defense"

		if is_crit and crit_ignored_atk_debuff:
			print("Attacker %s Stage: %d (Crit ignored debuff, treated as Stage 0)" % [atk_label, atk_stage])
			print("Attacker Multiplier: 1.0 (Base Atk: %d -> Final Atk: %d)" % [base_atk, base_atk])
		else:
			print("Attacker %s Stage: %+d" % [atk_label, atk_stage])
			print("Attacker Multiplier: %.2fx (Base Atk: %d -> Final Atk: %d)" % [atk_mult, base_atk, final_atk])

		if is_crit and crit_ignored_def_buff:
			print("Defender %s Stage: %d (Crit ignored buff, treated as Stage 0)" % [def_label, def_stage])
			print("Defender Multiplier: 1.0 (Base Def: %d -> Final Def: %d)" % [base_def, base_def])
		else:
			print("Defender %s Stage: %+d" % [def_label, def_stage])
			print("Defender Multiplier: %.2fx (Base Def: %d -> Final Def: %d)" % [def_mult, base_def, final_def])

		print("Attacker Accuracy Stage: %+d" % [acc_stage])
		print("Attacker Accuracy Multiplier: %.2fx (Base Acc: %.1f -> Final Acc: %.1f)" % [acc_mult, base_acc, final_accuracy])

		print("Defender Evasion Stage: %+d" % [eva_stage])
		print("Defender Evasion Multiplier: %.2fx (Base Eva: %.1f -> Final Eva: %.1f)" % [eva_mult, base_eva, final_evasion])

		print("Hit Chance: %.1f%%" % [hit_chance])
		print("Att/Def Ratio: %.2f" % [damage_ratio])
		print("Type Matchup Multiplier: %.2f" % [type_multiplier])
		print("STAB Multiplier: %.2f" % [stab_multiplier])
		if is_crit:
			print("Critical Hit! (1.5x)")
		print("Variance: %.3f" % [variance])
		print("Final Damage: %d" % [rounded_damage])
		if freeze_applied_message:
			print(freeze_applied_message)
		print("-------------------\n")

	return {
		"amount": rounded_damage,
		"is_crit": is_crit,
		"did_hit": true,
		"effect_messages": hit_effect_messages,
		"oil_ignited": oil_ignited,
		"type_multiplier": type_multiplier,
		"type_result": _classify_type_result(type_multiplier)
	}
