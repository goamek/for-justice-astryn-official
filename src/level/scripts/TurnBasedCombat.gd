# State machine driving the TBC scene through spawn -> turn order -> move execution -> win/loss.


extends Node3D
class_name TurnBasedCombat

signal combat_ended(was_quit: bool)

@export var tbc_ui: PlayerActionUI

@export var player_node: CharacterBody3D
@export var party_member2: PackedScene
@export var party_member3: PackedScene
@export var party_member4: PackedScene

@export var partyspawn1: Marker3D
@export var partyspawn2: Marker3D
@export var partyspawn3: Marker3D
@export var partyspawn4: Marker3D

@export var spawn1: Marker3D
@export var spawn2: Marker3D
@export var spawn3: Marker3D
@export var spawn4: Marker3D

var spawn_map: Dictionary = {}

@export var enemy1: PackedScene
@export var enemy2: PackedScene
@export var enemy3: PackedScene
@export var enemy4: PackedScene

# Runtime instances of the party/enemy scenes above (player_node is authored in-scene instead).
var party2_in = null
var party3_in = null
var party4_in = null
var enemy1_in = null
var enemy2_in = null
var enemy3_in = null
var enemy4_in = null

@export var damage_text_scene: PackedScene

@export var health_bar_prefab: PackedScene
@export var boss_ai_controller_scene: PackedScene
@export var battle_message_box: CanvasLayer
@export var turn_queue_display: TurnQueueDisplay
@export var move_info_popup: MoveInfoPopup
@export var target_info_popup: TargetInfoPopup
@onready var health_bar_canvas = $HealthBarCanvasLayer
@onready var battle_camera: Camera3D = $BattleCamera

enum CombatState {
	PRE_BATTLE_CUTSCENE,
	START_BATTLE,
	PLAYER_TURN_SELECT,
	PLAYER_TURN_TARGET,
	EXECUTE_ACTIONS,
	ANIMATING,
	ENEMY_TURN,
	END_BATTLE
}
# _process() is off (see _ready()) for the entire PRE_BATTLE_CUTSCENE state, so this is
# never actually matched in _process()'s state machine — it just documents what's
# happening while _play_pre_battle_cutscene() is awaited.
var current_state: CombatState = CombatState.PRE_BATTLE_CUTSCENE

var player_data: CharacterData = null
var party_nodes: Array[Node3D] = []
var enemy_nodes: Array[Node3D] = []
var battle_nodes: Array[Node3D] = []
var turn_queue: Array = []
var current_turn_actor = null
var target_cycle_list: Array[Node3D] = []
var target_cycle_index: int = 0

# Fixed offset added to any target's position to center them in frame; see _focus_camera_on().
const CAMERA_FOCUS_OFFSET: Vector3 = Vector3(0, 1.6, 4.0)
const CAMERA_FOCUS_DURATION: float = 0.5
const CAMERA_OVERVIEW_DURATION: float = 0.4
var _camera_tween: Tween = null
# Captured from the scene's own camera position, not hardcoded, so each TBC scene's
# authored placement is preserved.
var _camera_overview_position: Vector3
var selected_action = {
	"actor": null,
	"move": null,
	"targets": []
}
var boss_ai_controller = null

# Set before a forced backstop move so _execute_action_logic() skips the mana cost for
# that one action; always cleared after.
var _mana_waived_this_action: bool = false

# Set by BossTurnBasedCombat to force a specific opening move (e.g. Haze) on the boss's
# next turn; cleared after that turn.
var forced_enemy_move: MoveData = null

# Index of the move button focused when the info popup opened, so focus can be restored on close.
var _info_popup_move_index: int = -1

const DEBUG_BATTLE_LOGS: bool = true

# Damage fraction dealt to Ignite Slash-style splash targets (everyone on the
# primary target's side who wasn't the one directly hit).
const SPLASH_DAMAGE_MULTIPLIER: float = 0.33

# ---- TBC Setup Functions ----

func _ready() -> void:
	# Off until the pre-battle cutscene resolves below — Godot would otherwise start
	# calling _process() the moment this node enters the tree, racing START_BATTLE's
	# spawn/turn logic underneath the cutscene.
	set_process(false)

	if is_instance_valid(battle_camera):
		_camera_overview_position = battle_camera.position
	_hide_player_action_ui()
	_hide_target_action_ui()
	SignalBus.boss_action_selected.connect(_on_boss_action_selected)
	if boss_ai_controller_scene != null:
		boss_ai_controller = boss_ai_controller_scene.instantiate()
		add_child(boss_ai_controller)

	player_data = player_node.data
	if !player_node:
		push_error("Couldn't get the players characterbody3d")

	SignalBus.battle_started.emit()

	print(player_node.global_position)

	# Spawned before the cutscene below, not after — the duel intro's dialogue has these
	# actors talking to each other, so they need to already be standing in the arena.
	_spawn_party()
	_spawn_enemy()

	# The HP/mana HUD is created by _spawn_party() above, but shouldn't be visible until
	# combat actually starts — hidden here, shown again once the cutscene ends below.
	health_bar_canvas.visible = false

	# Base is a no-op (practice fights start immediately, same as always); overridden in
	# BossTurnBasedCombat to play a pre-fight cutscene before any of this actually starts.
	@warning_ignore("redundant_await")
	await _play_pre_battle_cutscene()
	health_bar_canvas.visible = true
	AudioController.stop_background_music()
	AudioController.play_battle_music()
	change_state(CombatState.START_BATTLE)
	set_process(true)

func _play_pre_battle_cutscene() -> void:
	pass


## Overrides the editor-assigned enemy/party rosters at runtime. Called by main.gd's
## switch_scene() right after instantiation, before the first _process() tick spawns them
## (see CombatState.START_BATTLE) — so this always lands in time. Missing/empty keys leave
## this scene's own editor-assigned defaults in place, so it can still run standalone.
func initialize_data(data: Dictionary) -> void:
	var enemies: Array = data.get("enemies", [])
	if not enemies.is_empty():
		enemy1 = enemies[0] if enemies.size() > 0 else null
		enemy2 = enemies[1] if enemies.size() > 1 else null
		enemy3 = enemies[2] if enemies.size() > 2 else null
		enemy4 = enemies[3] if enemies.size() > 3 else null
	var party: Array = data.get("party", [])
	if not party.is_empty():
		party_member2 = party[0] if party.size() > 0 else null
		party_member3 = party[1] if party.size() > 1 else null
		party_member4 = party[2] if party.size() > 2 else null


func _queue_battle_message(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	SignalBus.battle_message_requested.emit(message, {})


func _queue_battle_messages(messages: Array[String]) -> void:
	for message in messages:
		_queue_battle_message(message)


func _wait_for_battle_messages() -> void:
	if battle_message_box != null and battle_message_box.has_method("wait_until_idle"):
		await battle_message_box.wait_until_idle()


# Pauses battle to play a dialogue cutscene; a null resource is a no-op so trigger points
# can be wired before dialogue exists. show_bars matches Enemy.gd/PartyMember.gd's own
# opt-out (CinematicBars honors a "show_cinematic_bars" meta on the resource) so a caller
# like a mid-battle taunt can skip the letterbox bars without touching CinematicBars itself.
func play_cutscene(dialogue_resource: DialogueResource, title: String = "start", show_bars: bool = true) -> void:
	if dialogue_resource == null:
		return
	if battle_message_box != null and battle_message_box.has_method("clear_queue"):
		battle_message_box.clear_queue()
	_hide_player_action_ui()
	_hide_target_action_ui()
	dialogue_resource.set_meta("show_cinematic_bars", show_bars)
	DialogueManager.show_dialogue_balloon(dialogue_resource, title)
	await DialogueManager.dialogue_ended


func _play_move_animation(attacker: Node3D, target: Node3D, _move: MoveData) -> void:
	# Fallback animation path. Move-specific handlers can be dispatched here later.
	await _lunge_animation(attacker, target)

# "This target was hit" cue — reuses the same opacity flash Haze's stat-reset uses.
func _play_hit_flash(target: Node3D) -> void:
	if target.has_method("flash_stat_reset_tint"):
		target.flash_stat_reset_tint()

func _spawn_party():
	if player_node:
		party_nodes.append(player_node)
		spawn_map[player_node] = partyspawn1
		battle_nodes.append(player_node)
		var bar = health_bar_prefab.instantiate()
		health_bar_canvas.add_child(bar)
		bar.setup(player_node, 0)
		if partyspawn1:
			player_node.global_position = partyspawn1.global_position
			# Character._physics_process() applies a one-time "park in battle position" nudge
			# the first physics frame it sees a TBC scene, meant for whatever stale free-roam
			# position it's still sitting at. Since we've already placed it exactly, mark that
			# nudge as already done so it doesn't fire on top of this and shove it off-mark.
			player_node.did_move_character = true
	if party_member2:
		party2_in = party_member2.instantiate()
		party2_in.scale = Vector3(0.1, 0.1, 0.1)
		partyspawn2.add_child(party2_in)
		spawn_map[party2_in] = partyspawn2
		party_nodes.append(party2_in)
		battle_nodes.append(party2_in)
		var bar = health_bar_prefab.instantiate()
		health_bar_canvas.add_child(bar)
		bar.setup(party2_in, 1)
		party2_in.animated_sprite.play("Battle Idle")
	if party_member3:
		party3_in = party_member3.instantiate()
		party3_in.scale = Vector3(0.1, 0.1, 0.1)
		partyspawn3.add_child(party3_in)
		spawn_map[party3_in] = partyspawn3
		party_nodes.append(party3_in)
		battle_nodes.append(party3_in)
		var bar = health_bar_prefab.instantiate()
		health_bar_canvas.add_child(bar)
		bar.setup(party3_in, 2)
		party3_in.animated_sprite.play("Battle Idle")
	if party_member4:
		party4_in = party_member4.instantiate()
		party4_in.scale = Vector3(0.1, 0.1, 0.1)
		partyspawn4.add_child(party4_in)
		spawn_map[party4_in] = partyspawn4
		party_nodes.append(party4_in)
		battle_nodes.append(party4_in)
		var bar = health_bar_prefab.instantiate()
		health_bar_canvas.add_child(bar)
		bar.setup(party4_in, 3)
		party4_in.animated_sprite.play("Battle Idle")


func _spawn_enemy():
	if enemy1:
		enemy1_in = enemy1.instantiate()
		spawn1.add_child(enemy1_in)
		spawn_map[enemy1_in] = spawn1
		enemy_nodes.append(enemy1_in)
		battle_nodes.append(enemy1_in)
	if enemy2:
		enemy2_in = enemy2.instantiate()
		spawn2.add_child(enemy2_in)
		spawn_map[enemy2_in] = spawn2
		enemy_nodes.append(enemy2_in)
		battle_nodes.append(enemy2_in)
	if enemy3:
		enemy3_in = enemy3.instantiate()
		spawn3.add_child(enemy3_in)
		spawn_map[enemy3_in] = spawn3
		enemy_nodes.append(enemy3_in)
		battle_nodes.append(enemy3_in)
	if enemy4:
		enemy4_in = enemy4.instantiate()
		spawn4.add_child(enemy4_in)
		spawn_map[enemy4_in] = spawn4
		enemy_nodes.append(enemy4_in)
		battle_nodes.append(enemy4_in)


func _calculate_turn_queue():
	turn_queue.clear()

	# current_hp > 0 excludes downed party members; Enemy/Boss are removed from
	# battle_nodes entirely on defeat.
	var current_participants = battle_nodes.filter(func(node): return is_instance_valid(node) and node.current_hp > 0)

	# Rolling once per node (not inside the comparator) keeps each pair's result fixed for
	# one sort, re-randomizing each round. sort_custom requires a stable comparator;
	# re-rolling per comparison corrupts the sort.
	var tiebreak: Dictionary = {}
	for node in current_participants:
		tiebreak[node] = randf()

	# Sort by speed; equal speeds are broken by the stable random tiebreaker above.
	current_participants.sort_custom(func(a, b):
		var speed_a = a.data.base_speed * a.data.get_stat_multiplier(a.data.speed_stage)
		var speed_b = b.data.base_speed * b.data.get_stat_multiplier(b.data.speed_stage)

		if a.data.has_status(StatusEffect.StatusType.COATING_TAR) or a.data.has_status(StatusEffect.StatusType.COATING_ROOTED):
			speed_a *= 0.5
		if b.data.has_status(StatusEffect.StatusType.COATING_TAR) or b.data.has_status(StatusEffect.StatusType.COATING_ROOTED):
			speed_b *= 0.5

		if speed_a != speed_b:
			return speed_a > speed_b
		return tiebreak[a] > tiebreak[b]
	)

	turn_queue.append_array(current_participants)
	print("Turn queue order:", _debug_turn_queue())

func _debug_turn_queue() -> String:
	var queue_names: Array = []
	for actor in turn_queue:
		if actor and is_instance_valid(actor):
			queue_names.append(actor.character_name)
	return "[" + ", ".join(queue_names) + "]"

# Pushes turn order to the optional turn_queue_display, if one is wired up.
func _refresh_turn_queue_display() -> void:
	if turn_queue_display == null:
		return
	var ordered_names: Array[String] = []
	if is_instance_valid(current_turn_actor):
		ordered_names.append(current_turn_actor.character_name)
	for actor in turn_queue:
		if is_instance_valid(actor):
			ordered_names.append(actor.character_name)
	turn_queue_display.update_queue(ordered_names)

func _debug_turn_start(actor: Node3D) -> void:
	if not actor:
		print("==================================================")
		print("TURN START: None")
		print("==================================================")
		return

	print("==================================================")
	print("TURN START: %s" % [actor.character_name])
	print(" State: %s" % [CombatState.keys()[current_state]])
	print(" Actor: %s HP: %.1f/%.1f" % [actor.character_name, actor.current_hp, actor.max_hp])
	print(" Queue: %s" % [_debug_turn_queue()])
	print("==================================================")

func _debug_turn_end(actor: Node3D) -> void:
	if not actor:
		print("--------------------------------------------------")
		print("TURN END: None")
		print("--------------------------------------------------")
		return

	print("--------------------------------------------------")
	print("TURN END: %s" % [actor.character_name])
	print("--------------------------------------------------")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("switch scene (for testing)"):
		AudioController.stop_battle_music()
		combat_ended.emit(false)

	match current_state:
		CombatState.START_BATTLE:
			_calculate_turn_queue()
			current_turn_actor = turn_queue.pop_front()
			_refresh_turn_queue_display()
			_debug_turn_start(current_turn_actor)
			if current_turn_actor is Character:
				change_state(CombatState.PLAYER_TURN_SELECT)
			if current_turn_actor is PartyMember:
				change_state(CombatState.PLAYER_TURN_SELECT)
			if current_turn_actor is Enemy:
				change_state(CombatState.ENEMY_TURN)

		CombatState.PLAYER_TURN_SELECT:
			# Skip re-showing the menu every frame — that would snap focus back and trap the player.
			if Input.is_action_just_pressed("info"):
				if move_info_popup and move_info_popup.visible:
					_close_move_info_popup()
				else:
					_open_move_info_popup()
			elif move_info_popup and move_info_popup.visible and Input.is_action_just_pressed("cancel"):
				_close_move_info_popup()

			# A mouse click on empty space clears GUI focus entirely (buttons are
			# keyboard/gamepad-only, mouse_filter=IGNORE). Only re-grab when focus is truly
			# empty, so this never fights player navigation.
			if tbc_ui and (not move_info_popup or not move_info_popup.visible) and tbc_ui.get_focused_move_index() == -1:
				tbc_ui.set_focus_on_attack_button()

		CombatState.PLAYER_TURN_TARGET:
			if Input.is_action_just_pressed("info"):
				if target_info_popup and target_info_popup.visible:
					_close_target_info_popup()
				else:
					_open_target_info_popup()
			elif target_info_popup and target_info_popup.visible:
				if Input.is_action_just_pressed("cancel"):
					_close_target_info_popup()
			elif Input.is_action_just_pressed("menu_left"):
				_cycle_target(-1)
			elif Input.is_action_just_pressed("menu_right"):
				_cycle_target(1)
			elif Input.is_action_just_pressed("confirm"):
				_confirm_target_selection()
			elif Input.is_action_just_pressed("cancel"):
				_cancel_target_selection()

		CombatState.EXECUTE_ACTIONS:
			change_state(CombatState.ANIMATING)
			_execute_action_logic()

		CombatState.ANIMATING:
			pass # waiting for _execute_action_logic to change the state

		CombatState.ENEMY_TURN:
			change_state(CombatState.ANIMATING)
			selected_action.actor = current_turn_actor
			if forced_enemy_move != null and _is_boss_actor(current_turn_actor):
				selected_action.move = forced_enemy_move
				selected_action.targets = (enemy_nodes + party_nodes).filter(func(n): return is_instance_valid(n) and n.current_hp > 0)
				forced_enemy_move = null
				_execute_action_logic()
			elif _is_boss_actor(current_turn_actor):
				_setup_ai_controller()
				_execute_ai_logic()
			else:
				_select_random_party_target()
				_select_random_enemy_move()
				_execute_action_logic()

		CombatState.END_BATTLE:
			reset_party_battle_modifiers()
			AudioController.stop_battle_music()
			combat_ended.emit(false)

# ---- Target Select Functions ----

func _select_random_enemy_move():
	var moves = current_turn_actor.data.moves
	if moves.is_empty():
		print("Enemy has no moves.")
		return null
	selected_action.move = moves.pick_random()

# Mirrors _select_random_party_target()'s taunt override: a taunting enemy restricts the
# player to that target too.
func _build_target_cycle_list() -> void:
	# Revive targets a downed ally — the only move type that can target someone not standing.
	if selected_action.move != null and selected_action.move.revives:
		target_cycle_list = party_nodes.filter(func(p): return is_instance_valid(p) and p.current_hp <= 0)
		target_cycle_index = 0
		return

	# Ally-only moves never offer an enemy target, regardless of taunt state.
	if selected_action.move != null and selected_action.move.ally_target_only:
		target_cycle_list = party_nodes.filter(func(p): return is_instance_valid(p) and p.current_hp > 0)
		target_cycle_index = 0
		return

	# Only STATUS moves can target the player's own side; PHYSICAL/MAGIC can only hit enemies.
	var move_is_damaging: bool = selected_action.move != null and selected_action.move.category != MoveData.MoveCategory.STATUS
	var all_active_nodes = enemy_nodes if move_is_damaging else enemy_nodes + party_nodes
	var valid_targets = all_active_nodes.filter(func(p): return is_instance_valid(p) and p.current_hp > 0)

	# Taunt only forces offensive moves onto the taunting enemy — heals still reach their intended ally.
	var move_is_healing: bool = selected_action.move != null and selected_action.move.heal_fraction_of_max_hp > 0.0
	var taunting_enemies = enemy_nodes.filter(func(e): return is_instance_valid(e) and e.current_hp > 0 and e.data.has_status(StatusEffect.StatusType.TAUNT))
	if taunting_enemies.size() > 0 and not move_is_healing:
		target_cycle_list = [taunting_enemies[0]]
	else:
		target_cycle_list = valid_targets

	target_cycle_index = 0

# Moves the cycle index by delta (wrapping) and repositions the pointer over the new target.
func _cycle_target(delta: int) -> void:
	if target_cycle_list.is_empty():
		return
	target_cycle_index = wrapi(target_cycle_index + delta, 0, target_cycle_list.size())
	_update_target_pointer()

# Pans the camera onto the currently cycled target as the player cycles.
func _update_target_pointer() -> void:
	if target_cycle_list.is_empty():
		return
	var target = target_cycle_list[target_cycle_index]
	_focus_camera_on(target)

# Locks in the currently cycled target and executes the selected move.
func _confirm_target_selection() -> void:
	if current_state != CombatState.PLAYER_TURN_TARGET or target_cycle_list.is_empty():
		return
	selected_action.targets.append(target_cycle_list[target_cycle_index])
	_hide_target_action_ui()
	change_state(CombatState.EXECUTE_ACTIONS)

# Backs out of target selection to move selection, in case the wrong move was chosen.
func _cancel_target_selection() -> void:
	if current_state != CombatState.PLAYER_TURN_TARGET:
		return
	selected_action.move = null
	selected_action.targets.clear()
	_hide_target_action_ui()
	change_state(CombatState.PLAYER_TURN_SELECT)

# Picks a random living party member as the enemy's target (non-boss enemies only).
func _select_random_party_target():
	var valid_targets = party_nodes.filter(func(p): return p.current_hp > 0)

	if valid_targets.size() > 0:
		# Taunt Override Check
		var taunted_targets = valid_targets.filter(func(p): return p.data.has_status(StatusEffect.StatusType.TAUNT))
		if taunted_targets.size() > 0:
			var taunted_node = taunted_targets.pick_random()
			selected_action.targets.append(taunted_node)
			print("Forced to target taunted combatant: ", taunted_node.character_name)
			return

		var random_index = randi_range(0, valid_targets.size() - 1)
		var random_node = valid_targets[random_index]
		selected_action.targets.append(random_node)
	else:
		print("no valid targets for attack")

# ---- Boss AI Controller ----

func _setup_ai_controller():
	# Emits the current battle snapshot so the AI can evaluate state before choosing a move.
	if boss_ai_controller == null and boss_ai_controller_scene != null:
		boss_ai_controller = boss_ai_controller_scene.instantiate()
		add_child(boss_ai_controller)

	var party_snapshot = party_nodes.filter(func(p): return p.current_hp > 0)
	var enemy_snapshot = enemy_nodes.filter(func(e): return e.current_hp > 0)
	print("Boss AI path active for %s | is_boss=%s" % [current_turn_actor.character_name, _is_boss_actor(current_turn_actor)])
	call_deferred("_emit_game_state_to_ai", party_snapshot, enemy_snapshot, current_turn_actor.data)

func _emit_game_state_to_ai(party_members: Array, enemy_members: Array, boss_data: CharacterData) -> void:
	print("Boss AI: sending battle snapshot for %s" % current_turn_actor.character_name)
	SignalBus.get_game_state.emit(party_members, enemy_members, boss_data)

func _is_boss_actor(actor: Node3D) -> bool:
	if actor == null or actor.data == null:
		return false
	var data: CharacterData = actor.data
	return data.is_boss or data.character_name.to_lower() == "boss"

func _execute_ai_logic():
	# Boss turns resolve through the AI controller's signal below; non-boss enemies fall
	# back to random selection.
	if _is_boss_actor(current_turn_actor):
		return

	_select_random_party_target()
	_select_random_enemy_move()

func _on_boss_action_selected(action: Dictionary) -> void:
	# Translates the boss AI's chosen move/target into selected_action so normal execution can run.
	if action.is_empty():
		return

	selected_action.actor = current_turn_actor
	selected_action.move = action.get("move")
	selected_action.targets = action.get("targets", [])
	if selected_action.move == null or selected_action.targets.is_empty():
		_select_random_party_target()
		_select_random_enemy_move()
		return

	print("Boss AI chose %s for %s" % [selected_action.move.move_name, selected_action.targets[0].character_name])
	change_state(CombatState.EXECUTE_ACTIONS)

# Sends a compact post-resolution outcome to the boss AI, keeping learning grounded in real
# hit/matchup results instead of exposing target typing directly.
func _emit_boss_attack_observation(attacker: Node3D, target: Node3D, move: MoveData, result: Dictionary) -> void:
	if not _is_boss_actor(attacker):
		return
	if move == null or target == null:
		return

	var observation: Dictionary = {
		"attacker_name": attacker.character_name,
		"target_id": target.get_instance_id(),
		"target_name": target.character_name,
		"move_type": move.typing,
		"move_category": move.category,
		"did_hit": bool(result.get("did_hit", false)),
		"type_result": String(result.get("type_result", "unknown")),
		"type_multiplier": float(result.get("type_multiplier", 1.0))
	}
	SignalBus.boss_attack_observation.emit(observation)

func _execute_action_logic():
	_hide_player_action_ui()
	_reset_camera_to_overview()

	var attacker = current_turn_actor
	var move = selected_action.move
	var targets = selected_action.targets

	if attacker in party_nodes and move.category != MoveData.MoveCategory.PHYSICAL and move.mana_cost > 0 and not _mana_waived_this_action and attacker.has_method("spend_mana"):
		attacker.spend_mana(move.mana_cost)
	_mana_waived_this_action = false

	_queue_battle_message("%s used %s!" % [attacker.character_name, move.move_name])
	await _wait_for_battle_messages()

	for target in targets:
		await _resolve_move_hit(attacker, target, move)

		# A fire move landing on an Oil-coated target also splashes onto the rest of that
		# side, at reduced damage.
		if is_instance_valid(target) and _is_fire_oil_ignite(move, target):
			var splash_targets = _same_side_nodes(target).filter(
				func(n): return n != target and is_instance_valid(n) and n.current_hp > 0)
			for splash_target in splash_targets:
				await _resolve_move_hit(attacker, splash_target, move, SPLASH_DAMAGE_MULTIPLIER)

	# clean and move to next turn
	_debug_turn_end(attacker)
	_clear_action()
	_next_turn()

# Resolves one move hit (damage, animation, popup, messages, defeat). Shared by the primary
# target and any splash targets. damage_multiplier scales the roll down for splash hits,
# applied after that target's own stats/matchup are already factored in.
func _resolve_move_hit(attacker: Node3D, target: Node3D, move: MoveData, damage_multiplier: float = 1.0) -> void:
	var result = CombatMath.calculate_damage(attacker, target, move)
	if result.did_hit and damage_multiplier != 1.0 and int(result.amount) > 0:
		result.amount = int(max(1, round(result.amount * damage_multiplier)))
	# Emitted right after resolution so learning data matches this turn's actual outcome.
	_emit_boss_attack_observation(attacker, target, move, result)

	# Physical moves get the full lunge (which flashes on impact); other hits just get the
	# flash directly, skipping Haze's own stat-reset flash.
	if move.category == MoveData.MoveCategory.PHYSICAL:
		await _play_move_animation(attacker, target, move)
	elif result.did_hit and target != attacker and not move.resets_stat_stages:
		_play_hit_flash(target)

	if not result.did_hit or int(result.amount) > 0:
		var popup = damage_text_scene.instantiate()
		get_parent().add_child(popup)
		popup.global_position = target.global_position + Vector3(0, 2, 0)
		popup.setup(result.amount, result.is_crit, result.did_hit)

	var action_messages: Array[String] = []
	var effect_messages: Array[String] = result.get("effect_messages", [])
	var target_defeated: bool = false

	if result.did_hit:
		if int(result.amount) > 0:
			target.take_damage(result.amount)
			action_messages.append("%s took %d damage." % [target.character_name, result.amount])
			var type_multiplier: float = result.get("type_multiplier", 1.0)
			if type_multiplier > 1.0:
				action_messages.append("It's super effective!")
			elif type_multiplier < 1.0:
				action_messages.append("It's not very effective...")
		elif effect_messages.is_empty():
			action_messages.append("No direct damage was dealt.")

		for effect_message in effect_messages:
			action_messages.append(effect_message)

		if result.is_crit:
			action_messages.append("A critical hit!")
		if DEBUG_BATTLE_LOGS:
			print("   - %s used %s dealing %d" % [attacker.character_name, move.move_name, result.amount])
		if target.current_hp <= 0:
			target_defeated = true
			if _should_announce_defeat(target):
				action_messages.append("%s was defeated!" % [target.character_name])
	else:
		action_messages.append("But it missed!")
		if DEBUG_BATTLE_LOGS:
			print("   - %s used %s but it missed." % [attacker.character_name, move.move_name])

	_queue_battle_messages(action_messages)
	await _wait_for_battle_messages()

	if target_defeated:
		if is_instance_valid(target):
			# _handle_potential_defeat is a coroutine in BossTurnBasedCombat's override (it
			# awaits a phase-transition cutscene); the analyzer only sees this non-async base.
			@warning_ignore("redundant_await")
			await _handle_potential_defeat(target)
		else:
			# Non-boss actors already freed themselves in take_damage(); nothing left to do
			# but bookkeeping.
			_prune_freed_battle_nodes()

# True when a fire-typed move lands on a target that's coated in Oil, triggering
# Ignite Slash-style splash damage to the rest of that target's side.
func _is_fire_oil_ignite(move: MoveData, target: Node3D) -> bool:
	if move.category == MoveData.MoveCategory.STATUS:
		return false
	return TypeData.get_primary_type(move.typing) == TypeData.Type.FIRE and target.data.has_status(StatusEffect.StatusType.COATING_OIL)

# Returns whichever tracked battle array (enemy_nodes or party_nodes) a node belongs to.
func _same_side_nodes(node: Node3D) -> Array:
	if node in enemy_nodes:
		return enemy_nodes
	return party_nodes

# Default always announces; boss fights suppress this for a phase-1 boss about to
# transition, moving straight into the phase-two dialogue instead.
func _should_announce_defeat(_target: Node3D) -> bool:
	return true

# Drops nodes that freed themselves (e.g. take_damage() queue_free on death) from turn
# tracking. is_instance_valid() is the only safe check on a possibly-freed reference.
func _prune_freed_battle_nodes() -> void:
	party_nodes = party_nodes.filter(func(n): return is_instance_valid(n))
	enemy_nodes = enemy_nodes.filter(func(n): return is_instance_valid(n))
	battle_nodes = battle_nodes.filter(func(n): return is_instance_valid(n))
	turn_queue = turn_queue.filter(func(n): return is_instance_valid(n))

# Party members go down instead of being freed, so they stay in party_nodes/battle_nodes —
# only pulled from turn_queue to skip this round — unlike a defeated Enemy.
func _handle_defeat(actor: Node3D):
	if actor is Enemy:
		print("Dead: ", actor.character_name)
		enemy_nodes.erase(actor)
		turn_queue.erase(actor)
		battle_nodes.erase(actor)
	elif actor is Character:
		print("Downed: ", actor.character_name)
		turn_queue.erase(actor)
	elif actor is PartyMember:
		print("Downed: ", actor.character_name)
		turn_queue.erase(actor)


# Default always defeats; boss fights override this to intercept a phase transition instead.
func _handle_potential_defeat(target: Node3D) -> void:
	if target.current_hp <= 0:
		_handle_defeat(target)

func _clear_action():
	selected_action.actor = null
	selected_action.move = null
	selected_action.targets.clear()


func _next_turn():
	if _check_battle_over():
		change_state(CombatState.END_BATTLE)
		return

	# Same analyzer note as _resolve_move_hit's defeat handling — the base is a no-op, but
	# BossTurnBasedCombat's override awaits a dialogue balloon.
	@warning_ignore("redundant_await")
	await _check_battle_interruptions()

	if turn_queue.is_empty():
		if DEBUG_BATTLE_LOGS:
			print("New Round! Recalculating speeds...")
		_queue_battle_message("A new round begins.")
		await _wait_for_battle_messages()
		_calculate_turn_queue()

	current_turn_actor = turn_queue.pop_front()
	_refresh_turn_queue_display()
	_debug_turn_start(current_turn_actor)

	# ---- Status Upkeep Tick ----
	var status_list = current_turn_actor.data.active_statuses
	var should_skip_turn: bool = false
	var expired_statuses: Array[StatusEffect] = []
	var upkeep_messages: Array[String] = []

	for effect in status_list:
		# 1. Handle turn mitigation
		if effect.type == StatusEffect.StatusType.FREEZE:
			if not effect.freeze_first_turn_passed:
				effect.freeze_first_turn_passed = true
				should_skip_turn = true
				upkeep_messages.append("%s is frozen solid and cannot act!" % [current_turn_actor.character_name])
				if DEBUG_BATTLE_LOGS:
					print("   *", current_turn_actor.character_name, " is frozen solid and cannot act!")

		# 2. Handle Fixed Scaling Damage
		if effect.type == StatusEffect.StatusType.POISON or effect.type == StatusEffect.StatusType.BURN:
			# scales with the inflicting character's magic power, scaled down against target's magic defense
			var scaled_damage = effect.base_tick_damage * (effect.inflicted_magic_power / max(current_turn_actor.data.base_magic_defense * 0.5, 1))
			var final_tick = int(max(1, ceil(scaled_damage)))

			upkeep_messages.append("%s took %d damage from %s." % [current_turn_actor.character_name, final_tick, effect.effect_name])
			if DEBUG_BATTLE_LOGS:
				print(current_turn_actor.character_name, " took ", final_tick, " damage from ", effect.effect_name)
			current_turn_actor.take_damage(final_tick)

			if current_turn_actor.current_hp <= 0:
				upkeep_messages.append("%s was defeated!" % [current_turn_actor.character_name])
				_queue_battle_messages(upkeep_messages)
				await _wait_for_battle_messages()
				if is_instance_valid(current_turn_actor):
					# Same analyzer note as _resolve_move_hit's defeat handling.
					@warning_ignore("redundant_await")
					await _handle_potential_defeat(current_turn_actor)
				else:
					_prune_freed_battle_nodes()
				_next_turn()
				return

		# 3. Decrement Duration
		effect.duration -= 1
		if effect.duration <= 0:
			expired_statuses.append(effect)

	# Clean up expired statuses
	for expired in expired_statuses:
		status_list.erase(expired)
		upkeep_messages.append("The %s wore off from %s." % [expired.effect_name, current_turn_actor.character_name])
		if DEBUG_BATTLE_LOGS:
			print("The ", expired.effect_name, " wore off from ", current_turn_actor.character_name)

	if not upkeep_messages.is_empty():
		_queue_battle_messages(upkeep_messages)
		await _wait_for_battle_messages()

	# 4. Execute turn phase skip if mitigation active
	if should_skip_turn:
		_next_turn()
		return

	if current_turn_actor is Character:
		change_state(CombatState.PLAYER_TURN_SELECT)
	elif current_turn_actor is PartyMember:
		change_state(CombatState.PLAYER_TURN_SELECT)
	elif current_turn_actor is Enemy:
		change_state(CombatState.ENEMY_TURN)


func _check_battle_over() -> bool:
	# party_nodes keeps downed members, so "wiped out" means no one standing, not an empty array.
	var party_wiped: bool = party_nodes.filter(func(p): return p.current_hp > 0).is_empty()
	return enemy_nodes.is_empty() or party_wiped


# Clears stat stages/statuses picked up during the fight, same as PartyMember's own
# faint/revive reset. Overridden to a no-op in BossTurnBasedCombat so the real fight's
# outcome carries forward as it always has; practice fights shouldn't leave buffs/debuffs
# behind for the player to (accidentally or not) carry into the real fight.
func reset_party_battle_modifiers() -> void:
	for node in party_nodes:
		if node and node.data:
			node.data.active_statuses.clear()
			node.data.reset_modifiers()


# Checked once per resolved turn (see _next_turn()); overridden in BossTurnBasedCombat to
# fire story barks off HP thresholds. A no-op here so practice fights (no boss, no Vorkoth
# dialogue) never try to run this.
func _check_battle_interruptions() -> void:
	pass


# ---- UI Hide and Show ----

func _hide_player_action_ui():
	if tbc_ui:
		tbc_ui.hide_action_canvas_layer()
	_close_move_info_popup()

## Opens the move info popup for the focused move button. Releases GUI focus so the
## button underneath can't catch a stray confirm and sneak a move through while it's open.
func _open_move_info_popup():
	if not move_info_popup or not tbc_ui or not current_turn_actor:
		return

	var move_index: int = tbc_ui.get_focused_move_index()
	if move_index < 0 or move_index >= current_turn_actor.data.moves.size():
		return

	_info_popup_move_index = move_index
	get_viewport().gui_release_focus()
	move_info_popup.show_move(current_turn_actor.data.moves[move_index])

## Closes the move info popup and restores focus to whichever button was focused before it opened.
func _close_move_info_popup():
	if not move_info_popup:
		return

	move_info_popup.hide_popup()

	if _info_popup_move_index >= 0 and tbc_ui and _info_popup_move_index < tbc_ui.action_buttons.size():
		var button = tbc_ui.action_buttons[_info_popup_move_index]
		if is_instance_valid(button) and button.visible and button.is_visible_in_tree():
			button.grab_focus()
	_info_popup_move_index = -1

func _open_target_info_popup() -> void:
	if not target_info_popup or target_cycle_list.is_empty():
		return
	target_info_popup.show_target(target_cycle_list[target_cycle_index])

func _close_target_info_popup() -> void:
	if target_info_popup:
		target_info_popup.hide_popup()

func _show_target_action_ui():
	if tbc_ui:
		tbc_ui.show_target_canvas_layer()

func _hide_target_action_ui():
	if tbc_ui:
		tbc_ui.hide_target_canvas_layer()
	_close_target_info_popup()

func _load_ui_for_party_member():
	if tbc_ui and current_turn_actor:
		_focus_camera_on(current_turn_actor)

		var moves = current_turn_actor.data.moves
		var any_affordable: bool = moves.any(func(m): return m.category == MoveData.MoveCategory.PHYSICAL or m.mana_cost <= current_turn_actor.current_mp)

		if not any_affordable:
			# No affordable move (whole kit is Magic/Status and out of mana) — force a random
			# move at no cost instead of showing an empty menu. Excludes revive when no one's
			# down, since _select_move() would just bounce it back.
			var has_downed_ally: bool = party_nodes.any(func(p): return is_instance_valid(p) and p.current_hp <= 0)
			var forced_pool: Array = moves.filter(func(m): return not m.revives or has_downed_ally)
			if forced_pool.is_empty():
				forced_pool = moves
			var forced_move: MoveData = forced_pool.pick_random()
			_queue_battle_message("%s is out of mana and acts on instinct!" % current_turn_actor.character_name)
			_mana_waived_this_action = true
			_select_move(moves.find(forced_move))
			return

		tbc_ui.show_action_canvas_layer()
		tbc_ui.button_one.visible = true
		tbc_ui.button_two.visible = true
		tbc_ui.button_three.visible = true
		tbc_ui.button_four.visible = true

		var buttons = [tbc_ui.button_one, tbc_ui.button_two, tbc_ui.button_three, tbc_ui.button_four]

		for i in range(buttons.size()):
			if i < moves.size():
				var move: MoveData = moves[i]
				if move.category == MoveData.MoveCategory.PHYSICAL:
					buttons[i].text = move.move_name
				else:
					buttons[i].text = "%s (MP %d)" % [move.move_name, move.mana_cost]
				buttons[i].visible = true
				buttons[i].disabled = move.category != MoveData.MoveCategory.PHYSICAL and move.mana_cost > current_turn_actor.current_mp
			else:
				buttons[i].visible = false

# ---- Animation Logic ----

func _lunge_animation(attacker: Node3D, target: Node3D):
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return

	var original_pos = attacker.global_position
	var target_pos = target.global_position + (original_pos - target.global_position).normalized() * 1.5
	var tween = create_tween()
	# Phase 1: lunge forward
	tween.tween_property(attacker, "global_position", target_pos, 0.2).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	# Hit moment: runs exactly when the lunge finishes
	tween.tween_callback(func():
		_shake_camera(0.3, 0.15)
		_play_hit_flash(target)
	)

	# Phase 2: return to start
	tween.tween_property(attacker, "global_position", original_pos, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _shake_camera(intensity: float = 0.2, duration: float = 0.2):
	if not is_instance_valid(battle_camera):
		return

	var original_pos = battle_camera.position
	var tween = create_tween()

	# Create 4-5 rapid, random movements
	for i in range(5):
		var offset = Vector3(randf_range(-intensity, intensity), randf_range(-intensity, intensity), 0)
		tween.tween_property(battle_camera, "position", original_pos + offset, duration / 5)

	tween.tween_property(battle_camera, "position", original_pos, 0.05)

# Dollies the camera in on `target` — rotation never changes, so keeping any target
# centered in frame at any spawn point is just this fixed offset added to their position.
func _focus_camera_on(target: Node3D) -> void:
	if not is_instance_valid(battle_camera) or not is_instance_valid(target):
		return
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(battle_camera, "position", target.global_position + _get_camera_focus_offset(target), CAMERA_FOCUS_DURATION)

# Overridable per-target camera offset, so a subclass can frame an unusually large combatant
# differently (see BossTurnBasedCombat, which pulls back further for the phase-2 boss).
func _get_camera_focus_offset(_target: Node3D) -> Vector3:
	return CAMERA_FOCUS_OFFSET

# Returns the camera to the default overview shot.
func _reset_camera_to_overview() -> void:
	if not is_instance_valid(battle_camera):
		return
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(battle_camera, "position", _camera_overview_position, CAMERA_OVERVIEW_DURATION)

# ---- Action Buttons Pressed ----

func _on_button_one_pressed() -> void:
	if move_info_popup and move_info_popup.visible:
		return
	if current_state == CombatState.PLAYER_TURN_SELECT:
		print("Attack one selected!")
		_select_move(0)

func _on_button_two_pressed() -> void:
	if move_info_popup and move_info_popup.visible:
		return
	if current_state == CombatState.PLAYER_TURN_SELECT:
		print("Attack two selected!")
		_select_move(1)


func _on_button_third_pressed() -> void:
	if move_info_popup and move_info_popup.visible:
		return
	if current_state == CombatState.PLAYER_TURN_SELECT:
		print("Attack three selected!")
		_select_move(2)


func _on_button_four_pressed() -> void:
	if move_info_popup and move_info_popup.visible:
		return
	if current_state == CombatState.PLAYER_TURN_SELECT:
		print("Attack four selected!")
		_select_move(3)

# Selects the move at move_index. Moves flagged targets_all (e.g. Downpour) skip
# manual target selection entirely and hit every active combatant on both sides.
func _select_move(move_index: int) -> void:
	var move: MoveData = current_turn_actor.data.moves[move_index]
	# Guards against an unaffordable move slipping through even though a disabled button
	# shouldn't allow it — skipped when this is the forced no-cost backstop move.
	if not _mana_waived_this_action and move.category != MoveData.MoveCategory.PHYSICAL and move.mana_cost > current_turn_actor.current_mp:
		return
	selected_action.move = move

	if selected_action.move.revives and party_nodes.filter(func(p): return p.current_hp <= 0).is_empty():
		selected_action.move = null
		# Same focus-release fix as _open_move_info_popup — otherwise the still-focused
		# button eats this confirm too.
		get_viewport().gui_release_focus()
		_queue_battle_message("No one needs reviving!")
		await _wait_for_battle_messages()
		if tbc_ui and move_index < tbc_ui.action_buttons.size():
			var button = tbc_ui.action_buttons[move_index]
			if is_instance_valid(button) and button.visible and button.is_visible_in_tree():
				button.grab_focus()
		return

	if selected_action.move.targets_all:
		selected_action.targets = (enemy_nodes + party_nodes).filter(func(n): return is_instance_valid(n) and n.current_hp > 0)
		_hide_target_action_ui()
		change_state(CombatState.EXECUTE_ACTIONS)
	elif selected_action.move.self_target_only:
		selected_action.targets = [current_turn_actor]
		_hide_target_action_ui()
		change_state(CombatState.EXECUTE_ACTIONS)
	else:
		change_state(CombatState.PLAYER_TURN_TARGET)

func change_state(new_state: CombatState):
	if new_state == current_state:
		return
	current_state = new_state
	print("State -> %s" % [CombatState.keys()[current_state]])

	match current_state:
		CombatState.PLAYER_TURN_SELECT:
			# Rebind the move UI exactly once on entry, then let normal focus navigation take over.
			selected_action.actor = current_turn_actor
			_load_ui_for_party_member()
		CombatState.PLAYER_TURN_TARGET:
			# Build the cycle list and position the pointer once, not every frame, so cycling stays stable.
			_hide_player_action_ui()
			_build_target_cycle_list()
			_update_target_pointer()
			_show_target_action_ui()
