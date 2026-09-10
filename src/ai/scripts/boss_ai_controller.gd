extends Node

# Flattened, AI-friendly snapshot of the current combat state, rebuilt each boss turn.
var game_state: Dictionary = {}
# Boss's CharacterData, cached so scoring can read stage modifiers/stat helpers.
var latest_boss_data: CharacterData = null
# Live party/enemy nodes from the most recent snapshot, so decisions can return real targets.
var last_party_nodes: Array = []
var last_enemy_nodes: Array = []
# Matchup knowledge discovered during combat: target_id -> attack_type -> state.
var learned_type_knowledge: Dictionary = {}
var previous_boss_actor_id: int = -1

# Bucket weights for boss personality tuning; normalized per turn before selection.
const ATTACK_BUCKET_WEIGHT: float = 0.65
const STATUS_BUCKET_WEIGHT: float = 0.35

# String keys used in bucket dictionaries and debug output.
const BUCKET_ATTACK: String = "attack"
const BUCKET_STATUS: String = "status"

# Discrete knowledge states stored in learned_type_knowledge.
const TYPE_KNOWLEDGE_UNKNOWN: String = "unknown"
const TYPE_KNOWLEDGE_WEAK: String = "weak"
const TYPE_KNOWLEDGE_RESIST: String = "resist"
const TYPE_KNOWLEDGE_IMMUNE: String = "immune"
const TYPE_KNOWLEDGE_NEUTRAL: String = "neutral"

# ---- Lifecycle ----

func _ready():
	# Connects to TurnBasedCombat's game-state signal (carries live node refs for
	# current_hp/CharacterData).
	_enter_tree()

func _enter_tree():
	if SignalBus != null and not SignalBus.get_game_state.is_connected(_on_get_game_state):
		SignalBus.get_game_state.connect(_on_get_game_state)
	if SignalBus != null and not SignalBus.boss_attack_observation.is_connected(_on_boss_attack_observation):
		SignalBus.boss_attack_observation.connect(_on_boss_attack_observation)

func _exit_tree():
	if SignalBus != null and SignalBus.get_game_state.is_connected(_on_get_game_state):
		SignalBus.get_game_state.disconnect(_on_get_game_state)
	if SignalBus != null and SignalBus.boss_attack_observation.is_connected(_on_boss_attack_observation):
		SignalBus.boss_attack_observation.disconnect(_on_boss_attack_observation)

# ---- Signal Handler ----

# Entry point called each boss turn: stores live references, builds the snapshot, and
# picks a move.
func _on_get_game_state(party_members: Array, enemy_members: Array, boss_data: CharacterData):
	# Learned matchup memory is battle-scoped, so it resets when the boss actor changes.
	var current_boss_actor_id: int = -1
	for member in enemy_members:
		if member != null and member.get("data") == boss_data:
			current_boss_actor_id = member.get_instance_id()
			break

	if previous_boss_actor_id != -1 and current_boss_actor_id != previous_boss_actor_id:
		learned_type_knowledge.clear()
		print("AI Learn Reset | Reason=BossActorChanged")

	previous_boss_actor_id = current_boss_actor_id
	latest_boss_data = boss_data
	last_party_nodes = party_members
	last_enemy_nodes = enemy_members
	_setup_ai(party_members, enemy_members, boss_data)
	var decision = _make_decision()
	_execute_ai_logic(decision)

# ---- State Setup ----

# Converts live combat nodes into game_state. Only living combatants are passed in
# (already filtered by TurnBasedCombat).
func _setup_ai(party_members: Array, enemy_members: Array, boss_data: CharacterData):
	var party_snapshot: Array[Dictionary] = []
	for member in party_members:
		party_snapshot.append(_build_party_member_snapshot(member))

	var enemy_snapshot: Array[Dictionary] = []
	for index in range(enemy_members.size()):
		# Index doubles as the field slot for future positioning logic (front/back row).
		enemy_snapshot.append(_build_enemy_member_snapshot(enemy_members[index], index))

	var boss_snapshot: Dictionary = _build_boss_snapshot(boss_data, enemy_members)

	game_state = {
		"party_members": party_snapshot,  # Array[Dictionary] — one entry per living party member
		"enemy_members": enemy_snapshot,  # Array[Dictionary] — one entry per living enemy (including boss node)
		"boss": boss_snapshot             # Dictionary        — detailed boss-specific data
	}

# ---- Snapshot Builders ----

# Builds a party member snapshot from live HP (falling back to CharacterData) — typing is
# left unknown, since matchup knowledge is only discovered through real attack observations.
func _build_party_member_snapshot(member: Node) -> Dictionary:
	var snapshot: Dictionary = {
		"name": "",
		"health": {
			"current": 0,
			"max": 0
		},
		"stats": {
			"physical_attack": 0,
			"magic_attack": 0,
			"physical_defense": 0,
			"magic_defense": 0,
			"accuracy": 0,
			"evasion": 0
		},
		"buffs_debuffs": {
			"physical_attack_stage": 0,
			"physical_defense_stage": 0,
			"magic_attack_stage": 0,
			"magic_defense_stage": 0,
			"accuracy_stage": 0,
			"evasion_stage": 0
		},
		"target_id": -1,
		"typing": [],           # Array[TypeData.Type]   — this member's own types
		"resists": [],          # Array[TypeData.Type]   — types that deal < 1x damage to this member
		"weaknesses": [],       # Array[TypeData.Type]   — types that deal > 1x damage to this member
		"moves": [],            # Array[Dictionary]      — see _build_move_snapshots
		"status_conditions": [], # Array[Dictionary]     — see _build_status_snapshots
	}

	var member_data: CharacterData = member.get("data")
	if member_data == null:
		print("Error: Member data is null")
		return snapshot

	snapshot["name"] = member_data.character_name
	snapshot["target_id"] = member.get_instance_id()

	# Prefer the live node HP values; fall back to resource defaults if missing.
	snapshot["health"]["current"] = member.get("current_hp")
	snapshot["health"]["max"] = member.get("max_hp")
	if snapshot["health"]["max"] == null:
		snapshot["health"]["max"] = member_data.base_max_hp
	if snapshot["health"]["current"] == null:
		snapshot["health"]["current"] = snapshot["health"]["max"]

	# Base stats from CharacterData — unmodified by stage, same as the boss's own snapshot.
	snapshot["stats"] = {
		"physical_attack": member_data.base_physical_attack,
		"magic_attack": member_data.base_magic_attack,
		"physical_defense": member_data.base_physical_defense,
		"magic_defense": member_data.base_magic_defense,
		"accuracy": member_data.base_accuracy,
		"evasion": member_data.base_evasion
	}

	# Stage integers, same shape as the boss's own buffs_debuffs — lets scoring see buffs
	# (e.g. for Haze) without a multiplier calc.
	snapshot["buffs_debuffs"] = {
		"physical_attack_stage": member_data.physical_attack_stage,
		"physical_defense_stage": member_data.physical_defense_stage,
		"magic_attack_stage": member_data.magic_attack_stage,
		"magic_defense_stage": member_data.magic_defense_stage,
		"accuracy_stage": member_data.accuracy_stage,
		"evasion_stage": member_data.evasion_stage
	}

	# Typing intentionally left blank — matchup knowledge is discovered only through
	# combat observations.
	snapshot["typing"] = []
	snapshot["resists"] = []
	snapshot["weaknesses"] = []
	snapshot["moves"] = _build_move_snapshots(member_data.moves)
	snapshot["status_conditions"] = _build_status_snapshots(member_data.active_statuses)

	return snapshot

# Lightweight snapshot for a non-boss enemy — the AI treats them as field obstacles, not
# strategic actors, hence less detail than a party snapshot.
func _build_enemy_member_snapshot(member: Node, index: int) -> Dictionary:
	var snapshot: Dictionary = {
		"name": "",
		"health": {
			"current": 0,
			"max": 0
		},
		"positioning": {
			"slot": index,      # 0-based index in the live enemy_nodes array
			"position": "field" # TODO: expand to "front" / "back" when row system is added
		},
		"is_boss": false
	}

	var member_data: CharacterData = member.get("data")
	if member_data == null:
		# Graceful fallback: use node name and whatever HP is available.
		snapshot["name"] = member.name
		snapshot["health"]["current"] = member.get("current_hp")
		snapshot["health"]["max"] = member.get("max_hp")
		return snapshot

	snapshot["name"] = member_data.character_name
	snapshot["health"]["current"] = member.get("current_hp")
	snapshot["health"]["max"] = member.get("max_hp")
	if snapshot["health"]["max"] == null:
		snapshot["health"]["max"] = member_data.base_max_hp
	if snapshot["health"]["current"] == null:
		snapshot["health"]["current"] = snapshot["health"]["max"]

	snapshot["is_boss"] = member_data.is_boss
	return snapshot

# Boss snapshot used for all decision-making. HP comes from the live enemy node (reflects
# actual damage); buffs_debuffs holds stage integers — see CharacterData.get_stat_multiplier().
func _build_boss_snapshot(boss_data: CharacterData, enemy_members: Array) -> Dictionary:
	# Walk the enemy nodes to find the boss node and read its live HP.
	var boss_hp: float = boss_data.base_max_hp
	for member in enemy_members:
		var member_data: CharacterData = member.get("data")
		if member_data == boss_data:
			var node_hp = member.get("current_hp")
			if node_hp != null:
				boss_hp = node_hp
			break

	return {
		"name": boss_data.character_name,
		"health": {
			"current": boss_hp,
			"max": boss_data.base_max_hp
		},
		# Base stats before stage multipliers are applied.
		"stats": {
			"physical_attack": boss_data.base_physical_attack,
			"magic_attack": boss_data.base_magic_attack,
			"physical_defense": boss_data.base_physical_defense,
			"magic_defense": boss_data.base_magic_defense,
			"accuracy": boss_data.base_accuracy,
			"evasion": boss_data.base_evasion
		},
		# Stage integers per stat; multiply by CharacterData.get_stat_multiplier(stage) for
		# effective value.
		"buffs_debuffs": {
			"physical_attack_stage": boss_data.physical_attack_stage,
			"physical_defense_stage": boss_data.physical_defense_stage,
			"magic_attack_stage": boss_data.magic_attack_stage,
			"magic_defense_stage": boss_data.magic_defense_stage,
			"accuracy_stage": boss_data.accuracy_stage,
			"evasion_stage": boss_data.evasion_stage
		},
		"typing": boss_data.typing.duplicate(),              # Array[TypeData.Type]
		"moves": _build_move_snapshots(boss_data.moves),     # Array[Dictionary]
		"status_conditions": _build_status_snapshots(boss_data.active_statuses) # Array[Dictionary]
	}

# ---- Type Effectiveness Helpers ----

# Types that deal < 1x damage against the given type array (resisted/immune); subtypes
# resolve to primary before lookup.
func _get_resistances(types: Array) -> Array[TypeData.Type]:
	var results: Array[TypeData.Type] = []
	for type_value in TypeData.Type.values():
		var effectiveness: float = _get_type_effectiveness(types, type_value)
		if effectiveness < 1.0:
			results.append(type_value as TypeData.Type)
	return results

# Types that deal > 1x damage against the given type array (weaknesses).
func _get_weaknesses(types: Array) -> Array[TypeData.Type]:
	var results: Array[TypeData.Type] = []
	for type_value in TypeData.Type.values():
		var effectiveness: float = _get_type_effectiveness(types, type_value)
		if effectiveness > 1.0:
			results.append(type_value as TypeData.Type)
	return results

# Combined effectiveness of attack_type against a (possibly dual-typed) defender; subtypes
# resolve to primary first.
func _get_type_effectiveness(types: Array, attack_type: int) -> float:
	if types.is_empty():
		return 1.0  # Typeless defenders take neutral damage from everything.

	var effectiveness: float = 1.0
	for defended_type in types:
		var defense_type: int = TypeData.get_primary_type(int(defended_type))
		var attack_primary: int = TypeData.get_primary_type(attack_type)
		var chart_row = TypeData.DEFENDING_CHART.get(defense_type, {})
		if chart_row.has(attack_primary):
			effectiveness *= float(chart_row[attack_primary])
	return effectiveness

# ---- Move / Status Snapshot Builders ----

# Converts MoveData resources into plain dicts; "status" is null or the live StatusEffect
# resource.
func _build_move_snapshots(moves: Array) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for move in moves:
		var move_snapshot: Dictionary = {
			"name": move.move_name,
			"category": move.category as MoveData.MoveCategory, # PHYSICAL / MAGIC / STATUS
			"damage": move.damage,
			"typing": move.typing as TypeData.Type,             # Primary type of the move
			"subtype": move.subtype as TypeData.Type,           # Secondary type (BASIC if unused)
			"accuracy": move.accuracy,
			"crit_chance": move.crit_chance,
			"status": null,  # StatusEffect resource, or null if the move has no status
			"targets_all": move.targets_all,
			"resets_stat_stages": move.resets_stat_stages
		}
		if move.status_to_inflict != null:
			move_snapshot["status"] = move.status_to_inflict
		snapshots.append(move_snapshot)
	return snapshots

# Converts active StatusEffect resources into plain dicts; "ref" is the live resource, so
# it never goes stale.
func _build_status_snapshots(statuses: Array) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for effect in statuses:
		snapshots.append({
			"type": effect.type as StatusEffect.StatusType, # e.g. StatusEffect.StatusType.BURN
			"duration": effect.duration,                    # Turns remaining
			"ref": effect                                   # Live resource reference
		})
	return snapshots

# ---- Bucket Selection Helpers ----

# Only STATUS category moves count as status-bucket actions.
func _is_status_bucket_move(move_snapshot: Dictionary) -> bool:
	return int(move_snapshot.get("category", MoveData.MoveCategory.PHYSICAL)) == MoveData.MoveCategory.STATUS

# Partitions move indices into attack/status buckets; indices are preserved so resources
# and snapshots stay aligned.
func _partition_move_indices_by_bucket(move_snapshots: Array) -> Dictionary:
	var attack_indices: Array[int] = []
	var status_indices: Array[int] = []
	for index in range(move_snapshots.size()):
		if _is_status_bucket_move(move_snapshots[index]):
			status_indices.append(index)
		else:
			attack_indices.append(index)

	return {
		BUCKET_ATTACK: attack_indices,
		BUCKET_STATUS: status_indices
	}

# Normalizes bucket weights to probabilities summing to 1.0; falls back to a 50/50 split
# if both are zero/negative.
func _normalized_bucket_weights() -> Dictionary:
	var attack_weight: float = max(0.0, ATTACK_BUCKET_WEIGHT)
	var status_weight: float = max(0.0, STATUS_BUCKET_WEIGHT)
	var total: float = attack_weight + status_weight
	if total <= 0.0:
		return {
			BUCKET_ATTACK: 0.5,
			BUCKET_STATUS: 0.5
		}

	return {
		BUCKET_ATTACK: attack_weight / total,
		BUCKET_STATUS: status_weight / total
	}

# Performs a weighted random bucket selection using normalized probabilities.
func _select_weighted_bucket(weights: Dictionary) -> String:
	var attack_weight: float = clamp(float(weights.get(BUCKET_ATTACK, 0.5)), 0.0, 1.0)
	var roll: float = randf()
	if roll < attack_weight:
		return BUCKET_ATTACK
	return BUCKET_STATUS

# Updates learned type knowledge from post-attack observations; only successful,
# non-status hits count.
func _on_boss_attack_observation(observation: Dictionary) -> void:
	if observation.is_empty():
		return
	if not bool(observation.get("did_hit", false)):
		return

	var move_category: int = int(observation.get("move_category", MoveData.MoveCategory.STATUS))
	if move_category == MoveData.MoveCategory.STATUS:
		return

	var target_id: int = int(observation.get("target_id", -1))
	if target_id < 0:
		return

	var move_type: int = int(observation.get("move_type", TypeData.Type.BASIC))
	var result_state: String = String(observation.get("type_result", TYPE_KNOWLEDGE_UNKNOWN))
	if result_state == "miss" or result_state == "status" or result_state == TYPE_KNOWLEDGE_UNKNOWN:
		return

	_learn_target_type_result(target_id, move_type, result_state)
	print("AI Learn | Target=%s(%d) | Type=%s | Result=%s" % [
		String(observation.get("target_name", "Unknown")),
		target_id,
		_type_name(move_type),
		result_state
	])

# Stores a discovered matchup state for one target/type pair.
func _learn_target_type_result(target_id: int, attack_type: int, result_state: String) -> void:
	if not learned_type_knowledge.has(target_id):
		learned_type_knowledge[target_id] = {}
	var target_memory: Dictionary = learned_type_knowledge[target_id]
	target_memory[attack_type] = result_state
	learned_type_knowledge[target_id] = target_memory

# Reads learned state for a target/type pair, defaulting to unknown.
func _get_learned_type_state(target_snapshot: Dictionary, attack_type: int) -> String:
	var target_id: int = int(target_snapshot.get("target_id", -1))
	if target_id < 0:
		return TYPE_KNOWLEDGE_UNKNOWN
	if not learned_type_knowledge.has(target_id):
		return TYPE_KNOWLEDGE_UNKNOWN
	var target_memory: Dictionary = learned_type_knowledge[target_id]
	return String(target_memory.get(attack_type, TYPE_KNOWLEDGE_UNKNOWN))

# Converts discrete learned knowledge into a multiplier used by utility scoring.
func _type_state_to_multiplier(state: String) -> float:
	match state:
		TYPE_KNOWLEDGE_WEAK:
			return 2.0
		TYPE_KNOWLEDGE_RESIST:
			return 0.5
		TYPE_KNOWLEDGE_IMMUNE:
			return 0.0
		TYPE_KNOWLEDGE_NEUTRAL:
			return 1.0
		_:
			return 1.0

# ---- Decision Making ----

# Scores each available move against each valid target using several normalized decision
# factors (utility-theory style), then picks among the top candidates.
func _make_decision() -> Dictionary:
	if game_state.is_empty():
		return {}

	var boss_snapshot: Dictionary = game_state.get("boss", {})
	var party_snapshots: Array = game_state.get("party_members", [])
	if boss_snapshot.is_empty() or party_snapshots.is_empty():
		return {}

	var boss_moves: Array = []
	if latest_boss_data != null:
		boss_moves = latest_boss_data.moves

	# Clamp to the smaller of the resource/snapshot arrays so indexing always stays valid.
	var boss_move_snapshots: Array = boss_snapshot.get("moves", [])
	var move_count: int = min(boss_moves.size(), boss_move_snapshots.size())
	if move_count <= 0:
		return {}

	var bucket_source_snapshots: Array = []
	for move_index in range(move_count):
		bucket_source_snapshots.append(boss_move_snapshots[move_index])

	var bucket_indices: Dictionary = _partition_move_indices_by_bucket(bucket_source_snapshots)
	var weights: Dictionary = _normalized_bucket_weights()
	var selected_bucket: String = _select_weighted_bucket(weights)
	var selected_move_indices: Array = bucket_indices.get(selected_bucket, [])

	# Fall back to the opposite bucket if the selected one has no valid moves, so the boss
	# still acts.
	if selected_move_indices.is_empty():
		var fallback_bucket: String = BUCKET_STATUS if selected_bucket == BUCKET_ATTACK else BUCKET_ATTACK
		selected_move_indices = bucket_indices.get(fallback_bucket, [])
		print("AI Bucket Fallback | Requested=%s | Fallback=%s" % [selected_bucket, fallback_bucket])
		selected_bucket = fallback_bucket

	if selected_move_indices.is_empty():
		return {}

	print("AI Bucket Selected | Bucket=%s | AttackWeight=%.2f | StatusWeight=%.2f | MoveCount=%d" % [
		selected_bucket,
		float(weights.get(BUCKET_ATTACK, 0.5)),
		float(weights.get(BUCKET_STATUS, 0.5)),
		selected_move_indices.size()
	])

	var debug_lines: Array[String] = []
	var candidate_entries: Array[Dictionary] = []

	# Taunt Override: mirrors _select_random_party_target()'s hard filter — a taunting
	# party member restricts scoring to that target only.
	var taunted_indices: Array[int] = []
	for index in range(party_snapshots.size()):
		for status in party_snapshots[index].get("status_conditions", []):
			if int(status.get("type", StatusEffect.StatusType.NONE)) == StatusEffect.StatusType.TAUNT:
				taunted_indices.append(index)
				break
	var candidate_target_indices: Array = taunted_indices if not taunted_indices.is_empty() else range(party_snapshots.size())

	for index in candidate_target_indices:
		if index >= last_party_nodes.size():
			continue
		var target_snapshot: Dictionary = party_snapshots[index]
		var target_node: Node = last_party_nodes[index]
		if target_snapshot.is_empty() or target_node == null:
			continue

		for move_index in selected_move_indices:
			var resolved_move_index: int = int(move_index)
			var move_snapshot: Dictionary = boss_move_snapshots[resolved_move_index]
			var move_resource: MoveData = boss_moves[resolved_move_index]
			var score: float = _score_move_against_target(move_snapshot, boss_snapshot, target_snapshot)
			var breakdown: Dictionary = _get_move_breakdown(move_snapshot, boss_snapshot, target_snapshot)
			var move_name: String = move_resource.move_name if move_resource != null else move_snapshot.get("name", "Unnamed")
			var target_name: String = target_snapshot.get("name", target_node.name)
			var move_type_name: String = _type_name(move_snapshot.get("typing", TypeData.Type.BASIC))
			# Logs now reflect what the AI has learned so far rather than true typing.
			var learned_state: String = _get_learned_type_state(target_snapshot, int(move_snapshot.get("typing", TypeData.Type.BASIC)))
			var learned_multiplier: float = _type_state_to_multiplier(learned_state)
			var log_text: String = "AI Eval | Bucket=%s | Move=%s | Type=%s | Target=%s | LearnedTypeState=%s | LearnedTypeMult=%.2f | Score=%.3f | Attack=%.3f | Threat=%.3f | Health=%.3f | Defense=%.3f | Accuracy=%.3f" % [
				selected_bucket,
				move_name,
				move_type_name,
				target_name,
				learned_state,
				learned_multiplier,
				score,
				breakdown.get("attack_desire", 0.0),
				breakdown.get("threat", 0.0),
				breakdown.get("health_desire", 0.0),
				breakdown.get("defensive_desire", 0.0),
				breakdown.get("accuracy_factor", 0.0)
			]
			debug_lines.append(log_text)
			print(log_text)

			candidate_entries.append({
				"score": score,
				"move": move_resource,
				"target": target_node,
				"move_snapshot": move_snapshot,
				"target_snapshot": target_snapshot,
				"bucket": selected_bucket
			})

	if candidate_entries.is_empty():
		return {}

	var top_candidates: Array[Dictionary] = []
	for candidate in candidate_entries:
		var candidate_score: float = float(candidate.get("score", -INF))
		var inserted: bool = false
		for index in range(top_candidates.size()):
			if candidate_score > float(top_candidates[index].get("score", -INF)):
				top_candidates.insert(index, candidate)
				inserted = true
				if top_candidates.size() > 3:
					top_candidates.pop_back()
				break
		if inserted:
			continue
		if top_candidates.size() < 3:
			top_candidates.append(candidate)

	var top_candidates_log: String = "AI Top Candidates | Bucket=%s | " % selected_bucket
	for candidate in top_candidates:
		var candidate_move: MoveData = candidate.get("move")
		var candidate_target: Node = candidate.get("target")
		var candidate_score: float = float(candidate.get("score", 0.0))
		var candidate_name: String = candidate_move.move_name if candidate_move != null else "Unnamed"
		var target_name: String = String(candidate_target.name) if candidate_target != null else "None"
		top_candidates_log += "%s -> %s (%.3f) | " % [candidate_name, target_name, candidate_score]
	print(top_candidates_log)

	var selected_candidate: Dictionary = _weighted_random_candidate(top_candidates)
	var best_move: MoveData = selected_candidate.get("move")
	var best_target: Node = selected_candidate.get("target")
	var best_move_snapshot: Dictionary = selected_candidate.get("move_snapshot")
	var best_score: float = float(selected_candidate.get("score", 0.0))

	if best_move == null or best_target == null:
		return {}

	var final_log: String = "AI Final Decision | Bucket=%s | Move=%s | Target=%s | Score=%.3f | SelectedFromTop3=true" % [
		selected_bucket,
		String(best_move.move_name) if best_move != null else "None",
		String(best_target.name) if best_target != null else "None",
		best_score
	]
	print(final_log)

	# best_target is just whichever single target scored highest; a targets_all move (e.g.
	# Haze) needs to hit everyone standing on the party side instead. This AI only evaluates
	# party targets, so it can't also reset the boss's own stages the way the forced
	# phase-2 opener does.
	var final_targets: Array = [best_target]
	if best_move.targets_all:
		var all_living_targets: Array = []
		for i in range(last_party_nodes.size()):
			var node: Node = last_party_nodes[i]
			if node != null and is_instance_valid(node) and node.current_hp > 0:
				all_living_targets.append(node)
		if not all_living_targets.is_empty():
			final_targets = all_living_targets

	return {
		"move": best_move,
		"targets": final_targets,
		"move_snapshot": best_move_snapshot,
		"target_snapshot": selected_candidate.get("target_snapshot", {})
	}

# Weighted pick among the top 3 (favoring the highest scorer, but not fully deterministic).
# A small floor keeps a near-zero score from having zero chance or breaking the weighting.
func _weighted_random_candidate(candidates: Array[Dictionary]) -> Dictionary:
	if candidates.size() == 1:
		return candidates[0]

	var total_weight: float = 0.0
	for candidate in candidates:
		total_weight += max(float(candidate.get("score", 0.0)), 0.01)

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for candidate in candidates:
		cumulative += max(float(candidate.get("score", 0.0)), 0.01)
		if roll <= cumulative:
			return candidate
	return candidates.back()

# Emits the decision through the signal bus, keeping AI logic separate from turn management.
func _execute_ai_logic(decision: Dictionary = {}):
	if decision.is_empty():
		decision = _make_decision()

	if decision.is_empty():
		return

	SignalBus.boss_action_selected.emit(decision)

# ---- Utility Scoring ----

# Scores one move against one target by combining aggression, threat, health pressure, and
# defensive intent into a single expected-utility-style result.
func _score_move_against_target(move_snapshot: Dictionary, boss_snapshot: Dictionary, target_snapshot: Dictionary) -> float:
	if move_snapshot.is_empty() or target_snapshot.is_empty():
		return 0.0

	var accuracy_factor: float = clamp(float(move_snapshot.get("accuracy", 100)) / 100.0, 0.0, 1.0)

	# Status moves use a lighter, more tactical model — no direct damage, but
	# pressure/control/defensive value.
	if move_snapshot["category"] == MoveData.MoveCategory.STATUS:
		return _score_status_move(move_snapshot, boss_snapshot, target_snapshot) * accuracy_factor

	var attack_desire: float = _calculate_attack_desire(move_snapshot, boss_snapshot, target_snapshot)
	var threat: float = _calculate_threat(move_snapshot, boss_snapshot, target_snapshot)
	var health_desire: float = _calculate_health_desire(boss_snapshot)
	var defensive_desire: float = _calculate_defensive_desire(boss_snapshot, move_snapshot)

	# Weights can be tuned to make the boss more aggressive, defensive, or control-focused.
	var combined_utility: float = (
		attack_desire * 0.55 +
		threat * 0.20 +
		health_desire * 0.15 +
		defensive_desire * 0.10
	)

	return combined_utility * accuracy_factor

func _get_move_breakdown(move_snapshot: Dictionary, boss_snapshot: Dictionary, target_snapshot: Dictionary) -> Dictionary:
	var accuracy_factor: float = clamp(float(move_snapshot.get("accuracy", 100)) / 100.0, 0.0, 1.0)
	var attack_desire: float = _calculate_attack_desire(move_snapshot, boss_snapshot, target_snapshot)
	var threat: float = _calculate_threat(move_snapshot, boss_snapshot, target_snapshot)
	var health_desire: float = _calculate_health_desire(boss_snapshot)
	var defensive_desire: float = _calculate_defensive_desire(boss_snapshot, move_snapshot)
	return {
		"attack_desire": attack_desire,
		"threat": threat,
		"health_desire": health_desire,
		"defensive_desire": defensive_desire,
		"accuracy_factor": accuracy_factor
	}

func _score_status_move(move_snapshot: Dictionary, _boss_snapshot: Dictionary, target_snapshot: Dictionary) -> float:
	var score: float = 0.25
	if move_snapshot.get("status") != null:
		score += 0.35
	# Field-wide moves (e.g. Haze) don't inflict a status themselves, so without this they'd
	# never compete with a single-target status move's +0.35 bonus above.
	if move_snapshot.get("targets_all", false):
		score += 0.35
	if target_snapshot.get("status_conditions", []).is_empty():
		score += 0.15
	if move_snapshot.get("accuracy", 100) < 90:
		score -= 0.10
	if target_snapshot["health"]["current"] <= target_snapshot["health"]["max"] * 0.35:
		score += 0.10
	# A field-reset move (Haze) is worth prioritizing hard once any party member is buffed —
	# big enough to reliably take the #1 slot over Poison Spit.
	if move_snapshot.get("resets_stat_stages", false) and _target_has_any_buff(target_snapshot):
		score += 0.9

	return clamp(score, 0.0, 1.0)

# True if any of the target's stat stages is positive (i.e. currently buffed).
func _target_has_any_buff(target_snapshot: Dictionary) -> bool:
	var stages: Dictionary = target_snapshot.get("buffs_debuffs", {})
	for stage_value in stages.values():
		if int(stage_value) > 0:
			return true
	return false

func _calculate_attack_desire(move_snapshot: Dictionary, boss_snapshot: Dictionary, target_snapshot: Dictionary) -> float:
	# Linear curve: more damage relative to the target's current HP scores more aggressive.
	var estimated_damage: float = _estimate_damage(move_snapshot, boss_snapshot, target_snapshot)
	var target_hp: float = max(float(target_snapshot["health"].get("current", 1)), 1.0)
	var max_hp: float = max(float(target_snapshot["health"].get("max", target_hp)), 1.0)
	return _linear_curve(estimated_damage, max_hp)

func _calculate_threat(_move_snapshot: Dictionary, boss_snapshot: Dictionary, target_snapshot: Dictionary) -> float:
	# Danger the target poses to the boss — a hard hitter should make the boss more cautious.
	var target_attack: float = max(
		float(target_snapshot["stats"].get("physical_attack", 0)),
		float(target_snapshot["stats"].get("magic_attack", 0))
	)
	var boss_hp: float = max(float(boss_snapshot["health"].get("current", 1)), 1.0)
	var threat_ratio: float = clamp(target_attack / max(boss_hp, 1.0), 0.0, 1.0)
	return _quadratic_curve(threat_ratio, 2.0)

func _calculate_health_desire(boss_snapshot: Dictionary) -> float:
	# Sigmoid curve: the boss leans toward defensive/recovery options as it gets badly hurt.
	var hp_ratio: float = clamp(float(boss_snapshot["health"].get("current", 1)) / max(float(boss_snapshot["health"].get("max", 1)), 1.0), 0.0, 1.0)
	var x: float = hp_ratio * 12.0 - 6.0
	var logistic_value: float = 1.0 / (1.0 + exp(-x))
	return clamp(1.0 - logistic_value, 0.0, 1.0)

func _calculate_defensive_desire(boss_snapshot: Dictionary, move_snapshot: Dictionary) -> float:
	# Simple curve: lower boss health makes supportive/defensive actions more attractive.
	var hp_ratio: float = clamp(float(boss_snapshot["health"].get("current", 1)) / max(float(boss_snapshot["health"].get("max", 1)), 1.0), 0.0, 1.0)
	var pressure: float = pow(1.0 - hp_ratio, 2.0)
	if move_snapshot["category"] == MoveData.MoveCategory.STATUS:
		pressure += 0.25
	return clamp(pressure, 0.0, 1.0)

func _linear_curve(value: float, max_value: float) -> float:
	return clamp(value / max(max_value, 1.0), 0.0, 1.0)

func _quadratic_curve(value: float, exponent: float) -> float:
	return clamp(pow(value, exponent), 0.0, 1.0)

func _type_name(type_value: int) -> String:
	match type_value:
		TypeData.Type.BASIC:
			return "BASIC"
		TypeData.Type.FIRE:
			return "FIRE"
		TypeData.Type.WATER:
			return "WATER"
		TypeData.Type.PLANT:
			return "PLANT"
		TypeData.Type.EARTH:
			return "EARTH"
		TypeData.Type.DARK:
			return "DARK"
		TypeData.Type.ICE:
			return "ICE"
		TypeData.Type.ELECTRIC:
			return "ELECTRIC"
		TypeData.Type.LEAF:
			return "LEAF"
		TypeData.Type.WOOD:
			return "WOOD"
		TypeData.Type.ROCK:
			return "ROCK"
		TypeData.Type.GROUND:
			return "GROUND"
		TypeData.Type.POISON:
			return "POISON"
		TypeData.Type.PSYCHIC:
			return "PSYCHIC"
		TypeData.Type.NONE:
			return "NONE"
		_:
			return "UNKNOWN"

# Estimates damage from attack/defense, stage modifiers, STAB, and learned matchup
# knowledge (unknown = neutral).
func _estimate_damage(move_snapshot: Dictionary, boss_snapshot: Dictionary, target_snapshot: Dictionary) -> float:
	var attack_stat: float = 0.0
	var defense_stat: float = 0.0
	if move_snapshot["category"] == MoveData.MoveCategory.PHYSICAL:
		attack_stat = float(boss_snapshot["stats"]["physical_attack"])
		defense_stat = float(target_snapshot["stats"]["physical_defense"])
	else:
		attack_stat = float(boss_snapshot["stats"]["magic_attack"])
		defense_stat = float(target_snapshot["stats"]["magic_defense"])

	var attack_stage: int = 0
	var attack_multiplier: float = 1.0
	if latest_boss_data != null:
		attack_stage = boss_snapshot["buffs_debuffs"]["physical_attack_stage"] if move_snapshot["category"] == MoveData.MoveCategory.PHYSICAL else boss_snapshot["buffs_debuffs"]["magic_attack_stage"]
		attack_multiplier = latest_boss_data.get_stat_multiplier(attack_stage)

	var damage_ratio: float = (attack_stat * attack_multiplier) / max(defense_stat, 1.0)
	var attack_type: int = int(move_snapshot.get("typing", TypeData.Type.BASIC))
	var learned_type_state: String = _get_learned_type_state(target_snapshot, attack_type)
	var type_multiplier: float = _type_state_to_multiplier(learned_type_state)
	var stab_multiplier: float = 1.5 if move_snapshot.get("typing", TypeData.Type.BASIC) in boss_snapshot.get("typing", []) else 1.0
	var accuracy_factor: float = clamp(float(move_snapshot.get("accuracy", 100)) / 100.0, 0.0, 1.0)

	return max(1.0, float(move_snapshot.get("damage", 0)) * damage_ratio * type_multiplier * stab_multiplier * accuracy_factor)
