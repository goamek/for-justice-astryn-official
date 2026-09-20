# Extends Enemy to support a two-phase boss: phase 1 behaves like a normal random-move
# enemy (own CharacterData), phase 2 swaps to the boss's real data file and boss AI.
extends Enemy
class_name BossEnemy

# CharacterData to switch to when entering phase 2 (the boss's "real" stats/moves).
@export var phase_two_data: CharacterData

## Battle tracks AudioController crossfades to on phase 2: phase_two_music_intro plays once
## then phase_two_music_loop takes over (or loops immediately with no intro). Leaving the
## loop unset keeps whatever battle music is already playing.
@export var phase_two_music_intro: AudioStream
@export var phase_two_music_loop: AudioStream

## Move this boss is forced to open phase 2 with (e.g. Smoke) before normal AI selection
## takes over. Must already be in phase_two_data's moves array — only controls turn order,
## not whether the AI can pick it again later. Left unset, phase 2 starts under normal AI.
@export var phase_two_opening_move: MoveData

## SpriteFrames to switch animated_sprite to on entering phase 2 (its own "Battle Idle"
## animation, same convention as phase 1's). Left unset, the sprite just keeps phase 1's look.
@export var phase_two_sprite_frames: SpriteFrames

# AnimatedSprite3D centers on its own origin; phase 2's frames (48x96) are double phase 1's
# height (48x48), so without correction the boss's feet sink into the ground by half the
# difference instead of the growth extending upward. This offset keeps feet planted.
const PHASE_TWO_SPRITE_OFFSET: Vector2 = Vector2(0, 24)

var phase: int = 1

# Both defeat paths route through BossTurnBasedCombat's own interception (phase 1 -> the
# transition, phase 2 -> the ending sequence) rather than normal combat cleanup, so this
# node never needs to free itself — the whole scene is torn down when the ending routes to
# credits/game-over.
func _on_defeated() -> void:
	return

# Cached right before enter_phase_two() overwrites them, so revert_to_phase_one_appearance()
# can restore Vorkoth's human-scale look for the final defeat's kneel.
var _phase_one_sprite_frames: SpriteFrames
var _phase_one_sprite_offset: Vector2
var _phase_one_scale: Vector3
var _phase_one_position_y: float

func enter_phase_two() -> void:
	if phase_two_data == null:
		push_error("BossEnemy has no phase_two_data assigned")
		return
	data = phase_two_data
	data.reset_modifiers()
	character_name = data.character_name
	health.setup(data.base_max_hp)
	update_enemy_tint(current_hp / max_hp)
	hp_changed.emit(current_hp)
	if phase_two_sprite_frames != null and animated_sprite != null:
		_phase_one_sprite_frames = animated_sprite.sprite_frames
		_phase_one_sprite_offset = animated_sprite.offset
		animated_sprite.sprite_frames = phase_two_sprite_frames
		animated_sprite.play("Battle Idle")
		animated_sprite.offset = PHASE_TWO_SPRITE_OFFSET
	# No longer scaling phase 2 up beyond phase 1's base 0.1 (_spawn_enemy() sets that) —
	# the phase-2 sprite art itself is now sized to look bigger, so an extra scale multiplier
	# on top would double it again. _phase_one_scale/_phase_one_position_y are still captured
	# for revert_to_phase_one_appearance() in case scale/position ever diverge here again.
	_phase_one_scale = scale
	_phase_one_position_y = position.y
	phase = 2

## Reverts phase 2's bigger transformed appearance back to phase 1's human-scale look, then
## kneels — used for the final defeat, so Vorkoth visually collapses back down rather than
## kneeling at his oversized phase-2 proportions.
func revert_to_phase_one_appearance() -> void:
	if animated_sprite == null:
		return
	if _phase_one_sprite_frames != null:
		animated_sprite.sprite_frames = _phase_one_sprite_frames
		animated_sprite.offset = _phase_one_sprite_offset
	scale = _phase_one_scale
	position.y = _phase_one_position_y
	animated_sprite.play("Kneel")

## Same opacity-dip technique as Enemy.flash_stat_reset_tint(), but without reapplying the
## HP-based tint afterward. At 0 HP that tint would restart the critical-health red pulse
## (update_enemy_tint()'s pulse_tween) right on top of the kneel pose — this masks the pose
## swap for the post-defeat cutscenes without that pulse ever coming back.
func flash_for_pose_swap() -> void:
	if animated_sprite == null:
		return
	if stat_flash_tween and stat_flash_tween.is_valid():
		stat_flash_tween.kill()
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	stat_flash_tween = create_tween().set_loops(3)
	stat_flash_tween.tween_property(animated_sprite, "modulate:a", 0.2, 0.15)
	stat_flash_tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.15)

## Blinks the sprite into view a few times before settling fully visible — used for
## Vorkoth's dramatic reveal in the opening cutscene, where he starts invisible.
func play_teleport_in() -> void:
	if animated_sprite == null:
		return
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween = create_tween().set_loops(4)
	tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.1)
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.1)
	await tween.finished
	animated_sprite.modulate.a = 1.0

## Blinks the sprite out of view a few times before disappearing — the reverse of
## play_teleport_in(), for Vorkoth's exit at the end of the opening cutscene.
func play_teleport_out() -> void:
	if animated_sprite == null:
		return
	var tween = create_tween().set_loops(4)
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.1)
	tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.1)
	await tween.finished
	animated_sprite.modulate.a = 0.0
