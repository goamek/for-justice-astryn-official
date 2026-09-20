extends Node

# Tracks who's been talked to: character_id -> was_talked_to.
var talked_to_team: Dictionary = {
	"Aegrandir": false,
	"Novius": false,
	"Spero": false
}

# Set once the Novius follow-up conversation (dialogue_novius.dialogue's
# ~ full_conversation_2 node) has played, so it only auto-plays once.
var novius_bonded: bool = false

# Separate from talked_to_team since that dict doubles as the boss-fight gate — an NPC
# shouldn't block progress just by existing. Starts empty and grows as NPCs are added.
var talked_to_npcs: Dictionary = {}

# Set by solider_battle_dialogue.dialogue when the practice bout is accepted. Never cleared by
# quitting or losing it, since accepting once is what completes the objective.
var practice_battle_started: bool = false

# Gates TurnBasedCombat's one-shot onboarding popups (HP/MP, type matchups, status moves) so
# each only ever shows the first time its concept occurs this session — naturally the practice
# fight, since it's always the player's first battle. Cleared by reset_progress() so a fresh
# playthrough sees them again.
var tutorial_tips_seen: Dictionary = {
	"hp_mp": false,
	"type_matchup": false,
	"status_move": false,
	"coating": false,
}

# Set by dialogue_battle_cutscenes.dialogue's three vorkoth_* end-branches (via
# `do QuestManager.vorkoth_ending = "..."`), since play_cutscene()/dialogue_ended carry no
# return value and this is the only way BossTurnBasedCombat can tell which branch fired.
# One of: "" (undecided), "kill", "spare_novius_intervened", "spare_fail".
var vorkoth_ending: String = ""

# Tracks which Vorkoth-fight endings have been reached this session, so the main menu can
# offer to replay their post-credits epilogue. Session-only (resets on a full game restart,
# there's no save system) — but deliberately NOT cleared by reset_progress(), since starting
# a new playthrough shouldn't hide a replay option already unlocked this session.
var endings_seen: Dictionary = {
	"kill": false,
	"spare_novius_intervened": false,
}

func mark_as_talked_to(character_id: String):
	var was_ready := can_enter_boss_fight()
	talked_to_team[character_id] = true
	print("Progress updated: ", character_id, " is ", talked_to_team[character_id])
	# Edge-triggered so this only ever fires once — including staying quiet if a party
	# member's conversation is replayed afterward via its "talk again?" choice.
	if not was_ready and can_enter_boss_fight():
		SignalBus.team_ready_for_duel.emit()

func mark_npc_talked_to(npc_id: String) -> void:
	talked_to_npcs[npc_id] = true

func can_enter_boss_fight() -> bool:
	return talked_to_team.values().all(func(val): return val == true)

# Shared by the free-roam objective HUD and the pause menu's Objectives panel so the two
# never drift out of sync. The line stays and its checkbox flips; the separate "talk to the
# guards" line is gated on can_enter_boss_fight() instead.
func team_objective_text() -> String:
	var checkbox := "🗸" if can_enter_boss_fight() else "☐"
	return checkbox + " Talk to your team"

func practice_objective_text() -> String:
	var checkbox := "🗸" if practice_battle_started else "☐"
	return checkbox + " Try a practice battle"

func mark_ending_seen(ending: String) -> void:
	if endings_seen.has(ending):
		endings_seen[ending] = true

# Called when starting a brand-new playthrough (main menu's Start button) so a previous
# session's progress doesn't carry over. Quitting a battle should never call this — quest
# flags are meant to survive that.
func reset_progress() -> void:
	for character_id in talked_to_team.keys():
		talked_to_team[character_id] = false
	novius_bonded = false
	talked_to_npcs.clear()
	practice_battle_started = false
	vorkoth_ending = ""
	for tip_id in tutorial_tips_seen.keys():
		tutorial_tips_seen[tip_id] = false
