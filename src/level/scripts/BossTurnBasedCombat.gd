# Two-phase boss encounter: intercepts the boss's would-be death in phase 1 to trigger a
# phase transition instead of a normal defeat.
extends TurnBasedCombat
class_name BossTurnBasedCombat

## Dialogue played before the boss transforms from phase 1 to phase 2.
@export var phase_transition_dialogue: DialogueResource
@export var phase_transition_dialogue_title: String = "start"

## Pre-fight cutscene explaining the duel, played before the first turn (and before battle
## music replaces whatever's already playing).
@export var duel_intro_dialogue: DialogueResource

## Long health bar shown under the turn queue once the boss enters phase 2. Left unset,
## the phase-2 transition simply skips showing it.
@export var boss_health_bar: BossHealthBar

## Where the boss is moved while hidden behind the phase-2 fade, before fading back in on
## its new form. Left unset, it stays at its phase-1 spawn point for the reveal.
@export var boss_phase_two_spawn_point: Marker3D

## Story barks interjected mid-battle (dialogue_battle_interruptions.dialogue) — separate
## from phase_transition_dialogue, which only covers the phase-1->2 transition itself.
@export var battle_interruptions_dialogue: DialogueResource

# Flat damage the boss deals to each remaining teammate after the transition dialogue,
# striking them down itself rather than them vanishing off-screen.
const TEAMMATE_EXECUTION_DAMAGE: int = 99

# Checked once per resolved turn (TurnBasedCombat._next_turn()). Every entry rolls the same
# chance the moment its target's move finishes (party members or, for the crowd's reaction,
# Vorkoth's own turn) and never repeats once played. Astryn's three-part phase-2 thread
# (_stage2_1/_2/_3) shares one target name on purpose — _check_battle_interruptions() below
# only ever rolls the earliest still-unplayed entry for a given target per tick, so _2 can't
# fire before _1 has. Purely data — retune the chance or reorder beats without touching the
# check logic below.
const INTERRUPTION_CHANCE: float = 0.20
var _battle_interruptions: Array[Dictionary] = [
	{"phase": 1, "target": "Astryn", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_astryn", "played": false},
	{"phase": 1, "target": "Novius", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_novius", "played": false},
	{"phase": 1, "target": "Aegrandir", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_aegrandir", "played": false},
	{"phase": 1, "target": "Spero", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_spero", "played": false},
	{"phase": 2, "target": "Astryn", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_astryn_stage2_1", "played": false},
	{"phase": 2, "target": "Spero", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_spero_stage2", "played": false},
	{"phase": 2, "target": "Aegrandir", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_aegrandir_stage2", "played": false},
	{"phase": 2, "target": "Novius", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_novius_stage2", "played": false},
	{"phase": 2, "target": "Astryn", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_astryn_stage2_2", "played": false},
	{"phase": 2, "target": "Vorkoth", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_crowd_stage2", "played": false},
	{"phase": 2, "target": "Astryn", "chance": INTERRUPTION_CHANCE, "title": "vorkoth_to_astryn_stage2_3", "played": false},
]

func _check_battle_interruptions() -> void:
	if current_turn_actor == null or current_turn_actor.data == null:
		return
	var bosses: Array = enemy_nodes.filter(func(e): return e is BossEnemy)
	if bosses.is_empty():
		return
	var boss: BossEnemy = bosses.front()
	var mover_name: String = current_turn_actor.data.character_name
	# Only the earliest still-unplayed entry for this mover is eligible this tick, so a
	# missed roll on _1 can't let _2/_3 jump the queue in the same tick.
	for entry in _battle_interruptions:
		if entry.phase != boss.phase or entry.target != mover_name or entry.played:
			continue
		if randf() < entry.chance:
			entry.played = true
			await play_cutscene(battle_interruptions_dialogue, entry.title, false)
		return

# Stays visible=true in the scene file for editor positioning; hidden here at runtime
# until _begin_boss_phase_two() reveals it via boss_health_bar.setup().
func _ready() -> void:
	super._ready()
	if boss_health_bar:
		boss_health_bar.visible = false

func _play_pre_battle_cutscene() -> void:
	await play_cutscene(duel_intro_dialogue, "duel_intro")

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

# The real fight's stat stages/statuses persist through battle end as they always have —
# only practice fights (base TurnBasedCombat) get a clean slate.
func reset_party_battle_modifiers() -> void:
	pass

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

	# Let phase-1 music fade all the way out before the screen goes black, instead of
	# letting it keep playing through the transition.
	await AudioController.stop_battle_music()

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

	# Fires once the transition has fully finished (screen back to normal) so AudioController
	# starts the phase-2 track on the reveal — phase-1 music was already faded out before
	# the transition even began (see above), so there's silence during the transition itself.
	SignalBus.boss_phase_transition_started.emit(boss)

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
