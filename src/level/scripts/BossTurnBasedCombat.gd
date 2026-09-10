# Two-phase boss encounter: intercepts the boss's would-be death in phase 1 to trigger a
# phase transition instead of a normal defeat.
extends TurnBasedCombat
class_name BossTurnBasedCombat

## Dialogue played before the boss transforms from phase 1 to phase 2.
@export var phase_transition_dialogue: DialogueResource
@export var phase_transition_dialogue_title: String = "start"

## Long health bar shown under the turn queue once the boss enters phase 2. Left unset,
## the phase-2 transition simply skips showing it.
@export var boss_health_bar: BossHealthBar

## Where the boss is moved while hidden behind the phase-2 fade, before fading back in on
## its new form. Left unset, it stays at its phase-1 spawn point for the reveal.
@export var boss_phase_two_spawn_point: Marker3D

# Flat damage the boss deals to each remaining teammate after the transition dialogue,
# striking them down itself rather than them vanishing off-screen.
const TEAMMATE_EXECUTION_DAMAGE: int = 99

# Stays visible=true in the scene file for editor positioning; hidden here at runtime
# until _begin_boss_phase_two() reveals it via boss_health_bar.setup().
func _ready() -> void:
	super._ready()
	if boss_health_bar:
		boss_health_bar.visible = false

# PartySpawnPoint#1 is a dead marker in the base _spawn_party() (the add_child there is
# commented out; Character's position is hardcoded in the scene instead) — wired up here,
# not in the shared base class, since tbc.tscn's own PartySpawnPoint#1 doesn't match its
# Character's position either, so a shared fix would silently move that player too.
func _spawn_party() -> void:
	super._spawn_party()
	if player_node and partyspawn1:
		player_node.global_position = partyspawn1.global_position

# Phase 2's sprite is roughly double phase 1's height (see BossEnemy.PHASE_TWO_SPRITE_OFFSET),
# so the base CAMERA_FOCUS_OFFSET leaves its top out of frame — pulled back and raised
# further for a phase-2 boss. Starting values; nudge if framing still isn't right.
const CAMERA_FOCUS_OFFSET_PHASE_TWO: Vector3 = Vector3(0, 2.8, 6.0)

func _get_camera_focus_offset(target: Node3D) -> Vector3:
	if target is BossEnemy and target.phase == 2:
		return CAMERA_FOCUS_OFFSET_PHASE_TWO
	return super._get_camera_focus_offset(target)

# enemy1-4 in this scene use the same 50x internal sprite scale as the town NPCs (the boss's
# AnimatedSprite3D carries that 50x too, see boss_enemy.tscn) — the 0.1 correction is scoped
# here rather than the shared scenes (would break NPC free-roam placement) or the base
# _spawn_enemy() (regular tbc.tscn's enemies are scaled differently).
func _spawn_enemy() -> void:
	super._spawn_enemy()
	if enemy1_in:
		enemy1_in.scale = Vector3(0.1, 0.1, 0.1)
	if enemy2_in:
		enemy2_in.scale = Vector3(0.1, 0.1, 0.1)
	if enemy3_in:
		enemy3_in.scale = Vector3(0.1, 0.1, 0.1)
	if enemy4_in:
		enemy4_in.scale = Vector3(0.1, 0.1, 0.1)

# Suppresses "X was defeated!" for a phase-1 boss about to transition rather than actually
# die; a real death (phase 2, or non-boss) still announces normally.
func _should_announce_defeat(target: Node3D) -> bool:
	if target is BossEnemy and target.phase == 1:
		return false
	return true

func _handle_potential_defeat(target: Node3D) -> void:
	if target is BossEnemy and target.phase == 1 and target.current_hp <= 0:
		await _begin_boss_phase_two(target)
		return
	if target is BossEnemy and target.phase == 2 and target.current_hp <= 0:
		super._handle_potential_defeat(target)
		if _check_battle_over():
			change_state(CombatState.END_BATTLE)
		return
	super._handle_potential_defeat(target)

func _begin_boss_phase_two(boss: BossEnemy) -> void:
	await _wait_for_battle_messages()

	# Pre-transform banter plays first, still in phase 1, before any of the fade/swap below.
	await play_cutscene(phase_transition_dialogue, phase_transition_dialogue_title + "_intro")

	# Fires early so the existing phase-2 music crossfade (AudioController) starts
	# during the fade rather than waiting for the whole reveal sequence to finish.
	SignalBus.boss_phase_transition_started.emit(boss)

	await SceneTransition.transition(2.0)

	if boss_phase_two_spawn_point:
		boss.global_position = boss_phase_two_spawn_point.global_position

	boss.enter_phase_two()
	# Phase-2 data can have a very different speed stat, so the turn order computed under
	# phase-1 speed is stale — recalculate now instead of waiting for the round to run out.
	_calculate_turn_queue()
	_refresh_turn_queue_display()
	if boss.phase_two_opening_move != null:
		forced_enemy_move = boss.phase_two_opening_move
	SignalBus.boss_phase_changed.emit(boss, boss.phase)
	print("Boss entered phase %d" % boss.phase)

	await SceneTransition.fade_in()

	# The boss strikes down any teammates still standing itself, in its new phase-2 form, as
	# a "power display" beat right after the reveal, before it speaks.
	for enemy in enemy_nodes.duplicate():
		if enemy != boss and is_instance_valid(enemy) and enemy.current_hp > 0:
			await _boss_execute_teammate(boss, enemy)

	# Crowd/Vorkoth react to the now-revealed phase-2 form.
	await play_cutscene(phase_transition_dialogue, phase_transition_dialogue_title + "_reveal")

	if boss_health_bar:
		boss_health_bar.setup(boss)

# Deals TEAMMATE_EXECUTION_DAMAGE flat damage from the boss to one of its own
# teammates, with the same popup/message/defeat handling as a normal hit.
func _boss_execute_teammate(boss: BossEnemy, teammate: Node3D) -> void:
	if damage_text_scene != null:
		var popup = damage_text_scene.instantiate()
		get_parent().add_child(popup)
		popup.global_position = teammate.global_position + Vector3(0, 2, 0)
		popup.setup(TEAMMATE_EXECUTION_DAMAGE, false, true)

	teammate.take_damage(TEAMMATE_EXECUTION_DAMAGE)

	var messages: Array[String] = []
	messages.append("%s struck down %s for %d damage!" % [boss.character_name, teammate.character_name, TEAMMATE_EXECUTION_DAMAGE])
	if teammate.current_hp <= 0:
		messages.append("%s was defeated!" % [teammate.character_name])
	_queue_battle_messages(messages)
	await _wait_for_battle_messages()

	if is_instance_valid(teammate):
		_handle_defeat(teammate)
	else:
		# Enemy.take_damage() self-frees on death; nothing left to hand off to
		# _handle_defeat, just clean the freed reference out of tracking.
		_prune_freed_battle_nodes()
