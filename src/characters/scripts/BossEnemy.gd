# extends Enemy to support a two-phase boss: phase 1 behaves like a normal random-move
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

## Move this boss is forced to open phase 2 with (e.g. Haze) before normal AI selection
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

# phase 1 must not free the node on defeat; BossTurnBasedCombat drives the transition instead.
func _on_defeated() -> void:
	if phase == 1:
		return
	super._on_defeated()

# swaps in the phase-2 data, fully heals to its max hp, and resets stat stages.
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
		animated_sprite.sprite_frames = phase_two_sprite_frames
		animated_sprite.play("Battle Idle")
		animated_sprite.offset = PHASE_TWO_SPRITE_OFFSET
	# Phase 2 is visually bigger overall - scale up from the base 0.1 _spawn_enemy() sets
	# every enemy to, and lift off the ground slightly to match.
	scale = Vector3(0.2, 0.2, 0.2)
	position.y = 1.0
	phase = 2
