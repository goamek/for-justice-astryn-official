extends Node

# Global signal bus for cross-system communication — scene changes, boss AI state
# exchange, battle messages.


@warning_ignore("unused_signal")
signal request_scene_change(scene: PackedScene, data: Dictionary)

@warning_ignore("unused_signal")
signal get_game_state(party_members: Array, enemy_members: Array, boss_data: CharacterData)

@warning_ignore("unused_signal")
signal boss_action_selected(action: Dictionary)

@warning_ignore("unused_signal")
signal boss_attack_observation(observation: Dictionary)

@warning_ignore("unused_signal")
signal battle_message_requested(message: String, options: Dictionary)

# Emitted once per battle, when a TurnBasedCombat scene finishes setting up.
@warning_ignore("unused_signal")
signal battle_started()

# placeholder hook for a future boss transformation cutscene; not subscribed to yet
@warning_ignore("unused_signal")
signal boss_phase_changed(boss: Node3D, new_phase: int)

# Emitted as the phase-2 dialogue starts (before data/stats actually swap) so systems like
# battle music can react immediately instead of waiting for the full transition sequence.
@warning_ignore("unused_signal")
signal boss_phase_transition_started(boss: Node3D)

# Tracks the boss's phase across the whole session (not just this battle) for systems with
# no direct node reference (e.g. the dialogue balloon's portrait pick). Synced via boss_phase_changed.
var current_boss_phase: int = 1

func _ready() -> void:
	boss_phase_changed.connect(func(_boss: Node3D, new_phase: int): current_boss_phase = new_phase)
