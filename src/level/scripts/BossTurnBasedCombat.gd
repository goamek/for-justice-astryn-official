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

## Dialogue played the instant phase-2 Vorkoth's HP hits 0 (the `~ vorkoth_defeat` node in
## dialogue_battle_cutscenes.dialogue) — branches internally into all 3 endings and stamps
## QuestManager.vorkoth_ending so this script can tell which one fired.
@export var vorkoth_defeat_dialogue: DialogueResource

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

# Debug-only: pressing "0" zeroes Vorkoth's HP through the same take_damage() path a real
# hit uses, so testers can jump straight to the phase-1->2 transition or, from phase 2,
# straight into the ending cutscenes without playing out a full fight. Guarded against
# re-entrancy (_debug_kill_in_progress) and against firing once the ending sequence has
# already started (_vorkoth_ending_started) or on an already-defeated/freed boss.
var _debug_kill_in_progress: bool = false

func _process(_delta: float) -> void:
	if not _debug_kill_in_progress and not _vorkoth_ending_started \
			and Input.is_action_just_pressed("debug kill vorkoth (for testing)"):
		_debug_kill_vorkoth()
	super._process(_delta)

func _debug_kill_vorkoth() -> void:
	var bosses: Array = enemy_nodes.filter(func(e): return e is BossEnemy and e.current_hp > 0)
	if bosses.is_empty():
		return
	_debug_kill_in_progress = true
	var boss: BossEnemy = bosses.front()
	print("[DEBUG] Zeroing %s's HP (was %d) via debug key" % [boss.character_name, boss.current_hp])
	boss.take_damage(boss.current_hp)
	if is_instance_valid(boss):
		await _handle_potential_defeat(boss)
	_debug_kill_in_progress = false

func _play_pre_battle_cutscene() -> void:
	# Free-roam music fades all the way out (rather than just ducking) so the world-map
	# theme can fade in and take over cleanly underneath the cutscene.
	AudioController.stop_background_music()
	AudioController.play_world_map_music()
	await play_cutscene(duel_intro_dialogue, "duel_intro")
	AudioController.stop_world_map_music()

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

# Set once the post-battle ending sequence begins, so the unconditional _next_turn() call
# right after _handle_potential_defeat returns can't also push the state machine into
# END_BATTLE and race combat_ended's normal FREE_ROAM_SCENE routing against this method's
# own scene change.
var _vorkoth_ending_started: bool = false

func _next_turn() -> void:
	if _vorkoth_ending_started:
		return
	super._next_turn()

func _handle_potential_defeat(target: Node3D) -> void:
	if target is BossEnemy and target.phase == 1 and target.current_hp <= 0:
		await _begin_boss_phase_two(target)
		return
	if target is BossEnemy and target.phase == 2 and target.current_hp <= 0:
		super._handle_potential_defeat(target)
		if _check_battle_over():
			await _play_vorkoth_ending_sequence(target)
		return
	super._handle_potential_defeat(target)

# Runs once phase-2 Vorkoth is actually dead: plays the branching defeat dialogue, reads
# back which ending it resolved to (QuestManager.vorkoth_ending, stamped by the dialogue
# file itself), then routes to Credits+epilogue (the two win branches) or Game Over (the
# fail branch). All three endings land on the main menu, so this fully replaces the normal
# END_BATTLE -> combat_ended -> FREE_ROAM_SCENE flow rather than feeding into it.
func _play_vorkoth_ending_sequence(boss: BossEnemy) -> void:
	_vorkoth_ending_started = true
	set_process(false)

	# The fight is over — wipe the battle HUD for the rest of this sequence (walk/shoot,
	# both dialogue segments) instead of leaving it hanging over the cutscene. Never shown
	# again afterward since this always ends in a scene change (credits/game over).
	health_bar_canvas.visible = false
	if turn_queue_display:
		turn_queue_display.visible = false
	if boss_health_bar:
		boss_health_bar.visible = false

	# Ducked for the whole ending sequence rather than stopped outright — stop_battle_music()
	# further down still handles the actual fade-out once both dialogue segments are done.
	AudioController.duck_battle_music()

	await _wait_for_battle_messages()

	# Masks the instant pose/scale swap below the same way the phase-1 kneel does.
	boss.flash_for_pose_swap()
	await get_tree().create_timer(0.15).timeout
	boss.revert_to_phase_one_appearance()

	QuestManager.vorkoth_ending = ""
	# Keeps CinematicBars from auto-hiding the instant either dialogue segment below ends —
	# hidden manually further down, once the fade-to-black actually covers the screen, so
	# the bars stay in place through the walk/shoot beat and right up until the scene
	# changes instead of retracting early.
	vorkoth_defeat_dialogue.set_meta("keep_cinematic_bars_on_end", true)
	await play_cutscene(vorkoth_defeat_dialogue, "vorkoth_defeat")

	# Astryn walks up and draws on him — acted out for real instead of a stage-direction
	# comment. is_in_cutscene_pose stops character.gd's own per-frame battle-idle override
	# from fighting the Run/Shoot animations set here.
	player_node.is_in_cutscene_pose = true
	player_node.animated_sprite.play("Run Right")
	var walk_target: Vector3 = boss.global_position + Vector3(-3.0, 0, 0)
	# Linear tween based on her normal free-roam speed, not an arbitrary fixed duration.
	# HORIZONTAL_SPEED alone isn't enough here — this scene's player_node is scaled to 0.1
	# (matching every other combatant in this small arena, see _spawn_party()/_spawn_enemy()),
	# so without correcting for that a numerically-correct units/sec speed covers ~10x her own
	# body-lengths per second. Halved again on top of that (slower than her real walk pace) —
	# reads better for this cutscene beat than her actual speed did.
	var walk_duration: float = player_node.global_position.distance_to(walk_target) / (player_node.HORIZONTAL_SPEED * player_node.scale.x * 0.5)
	var walk_tween := create_tween().set_trans(Tween.TRANS_LINEAR)
	walk_tween.tween_property(player_node, "global_position", walk_target, walk_duration)
	await walk_tween.finished

	player_node.flash_stat_reset_tint()
	await get_tree().create_timer(0.15).timeout
	player_node.animated_sprite.play("Shoot")
	AudioController.cut_battle_music()

	await play_cutscene(vorkoth_defeat_dialogue, "vorkoth_defeat_confrontation")

	reset_party_battle_modifiers()
	await AudioController.stop_battle_music()

	# Loaded here rather than preloaded at the top of the script — preloading these would
	# force credits.tscn/game_over.tscn (and their scripts, which themselves preload
	# main_menu.tscn) to compile as part of loading this script, which itself only gets
	# compiled because main.gd preloads boss_fight_tbc.tscn — a deep eager chain that loops
	# back to a scene main.gd already preloads independently. Godot can hand back a broken/
	# stub PackedScene somewhere in a chain like that; load() at point-of-use avoids it.
	match QuestManager.vorkoth_ending:
		"kill":
			# The balloon has already closed by this point (play_cutscene() above only
			# returns once dialogue fully ends), so the gunshot plays with "...For justice."
			# off screen — and plays out completely before the transition to credits starts.
			await AudioController.play_sfx(load("res://assets/sounds/mrfriends-pistol-shot-233473.mp3"))
			# Starts here rather than waiting for Credits.gd's own _ready() to kick it off,
			# so it's already playing under the wait/teleport-out below instead of starting
			# cold once the credits scene loads. play_credits_music() no-ops harmlessly if
			# Credits.gd calls it again once that scene is up.
			AudioController.play_credits_music()
			await get_tree().create_timer(0.5).timeout
			# Same blink-out technique as his exit in the opening cutscene — awaited so he's
			# fully gone before the scene starts fading to black below.
			await boss.play_teleport_out()
			await get_tree().create_timer(0.5).timeout
			QuestManager.mark_ending_seen("kill")
			var credits_scene: PackedScene = load("res://src/level/scenes/credits.tscn")
			SignalBus.request_scene_change.emit(credits_scene, {"epilogue_title": "post_credits_epilogue"})
		"spare_novius_intervened":
			# She turns to walk back toward the team, believing it's over — same pattern as
			# spare_fail's walk-away.
			player_node.animated_sprite.play("Run Left")
			var walk_back_target: Vector3 = player_node.global_position + Vector3(-3.0, 0, 0)
			var walk_back_tween := create_tween().set_trans(Tween.TRANS_LINEAR)
			walk_back_tween.tween_property(player_node, "global_position", walk_back_target, 1.0)
			await walk_back_tween.finished
			player_node.animated_sprite.play("Idle Left")

			await play_cutscene(vorkoth_defeat_dialogue, "vorkoth_spare_novius_mercy_taunt")

			# Novius and Vorkoth both teleport in near her — Novius driving the blade, Vorkoth on
			# the receiving end. Positioned off her global_position (not local), since they're
			# landing near wherever she ended up, not at a fixed spot in the arena. Landing
			# spacing is a starting guess — expect to hand-tune once it's visible in the editor.
			party2_in.play_teleport_out()
			await boss.play_teleport_out()
			party2_in.global_position = walk_back_target + Vector3(1.25, 0, 0)
			party2_in.animated_sprite.play("Stab")
			boss.global_position = walk_back_target + Vector3(2.0, 0, 0)
			boss.animated_sprite.play("Stabbed")
			party2_in.play_teleport_in()
			await boss.play_teleport_in()

			await get_tree().create_timer(2.0).timeout

			AudioController.play_credits_music()

			await play_cutscene(vorkoth_defeat_dialogue, "vorkoth_spare_novius_aftermath")

			QuestManager.mark_ending_seen("spare_novius_intervened")
			var credits_scene: PackedScene = load("res://src/level/scenes/credits.tscn")
			SignalBus.request_scene_change.emit(credits_scene, {"epilogue_title": "post_credits_epilogue_novius_intervened"})
		"spare_fail":
			# She holsters the weapon and settles back to a normal idle pose before he speaks.
			player_node.flash_stat_reset_tint()
			await get_tree().create_timer(0.15).timeout
			player_node.animated_sprite.play("Idle Right")

			await play_cutscene(vorkoth_defeat_dialogue, "vorkoth_spare_mercy_taunt")

			# She turns to walk away, believing it's over.
			player_node.animated_sprite.play("Run Left")
			var walk_away_target: Vector3 = player_node.global_position + Vector3(-3.0, 0, 0)
			var walk_away_tween := create_tween().set_trans(Tween.TRANS_LINEAR)
			walk_away_tween.tween_property(player_node, "global_position", walk_away_target, 1.0)
			await walk_away_tween.finished
			player_node.animated_sprite.play("Idle Left")

			# Vorkoth teleports directly beside her and strikes. Both pose swaps happen
			# together, right before he blinks back into view, so the instant he's visible
			# they're both already in Stab/Stabbed rather than one lagging the other.
			await boss.play_teleport_out()
			boss.position = Vector3(-8.35, 0, -0.15)
			boss.animated_sprite.play("Stab")
			player_node.flash_stat_reset_tint()
			player_node.animated_sprite.play("Stabbed")
			await boss.play_teleport_in()

			await get_tree().create_timer(1.0).timeout

			# Cut to black — the aftermath dialogue plays over darkness; cinematic bars and
			# the balloon both render above SceneTransition's overlay already (layers 90/100
			# vs. its default 1), so nothing needs to change there.
			await SceneTransition.transition()
			await play_cutscene(vorkoth_defeat_dialogue, "vorkoth_spare_aftermath")

			# Screen is already black from the manual cut above — reset the flag
			# switch_scene() checks, or it'll refuse to start the real transition into
			# game_over, thinking one is still in flight.
			SceneTransition.is_transitioning = false
			var game_over_scene: PackedScene = load("res://src/level/scenes/game_over.tscn")
			SignalBus.request_scene_change.emit(game_over_scene, {})
		_:
			# Unexpectedly empty/unknown value — fail safe to game over without the extra sequence.
			var game_over_scene: PackedScene = load("res://src/level/scenes/game_over.tscn")
			SignalBus.request_scene_change.emit(game_over_scene, {})

	# Bars stay up (see keep_cinematic_bars_on_end above) until the fade-to-black from the
	# scene change above actually covers the screen, then get cleared so they don't linger
	# into credits/game over.
	await SceneTransition.on_transition_finished
	CinematicBars.hide_bars()

func _begin_boss_phase_two(boss: BossEnemy) -> void:
	await _wait_for_battle_messages()

	# Kneel before he starts talking — flash masks the instant pose swap (same technique
	# the final defeat below reuses via revert_to_phase_one_appearance()). Uses
	# flash_for_pose_swap(), not flash_stat_reset_tint(), so the 0-HP critical pulse doesn't
	# restart on top of the kneel during this and the later defeat cutscene.
	boss.flash_for_pose_swap()
	await get_tree().create_timer(0.15).timeout
	boss.animated_sprite.play("Kneel")

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
