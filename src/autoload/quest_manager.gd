extends Node

# Tracks who's been talked to: character_id -> was_talked_to.
var talked_to_team: Dictionary = {
	"Aegrandir": false,
	"Novius": false,
	"Spero": false
}

# Set once the Novius follow-up conversation (dialogue_novius.dialogue's
# ~ novius_followup node) has played, so it only plays once.
var novius_bonded: bool = false

# Separate from talked_to_team since that dict doubles as the boss-fight gate — an NPC
# shouldn't block progress just by existing. Starts empty and grows as NPCs are added.
var talked_to_npcs: Dictionary = {}

func mark_as_talked_to(character_id: String):
	talked_to_team[character_id] = true
	print("Progress updated: ", character_id, " is ", talked_to_team[character_id])

func mark_npc_talked_to(npc_id: String) -> void:
	talked_to_npcs[npc_id] = true

func can_enter_boss_fight() -> bool:
	return talked_to_team.values().all(func(val): return val == true)

# Called when starting a brand-new playthrough (main menu's Start button) so a previous
# session's progress doesn't carry over. Quitting a battle should never call this — quest
# flags are meant to survive that.
func reset_progress() -> void:
	for character_id in talked_to_team.keys():
		talked_to_team[character_id] = false
	novius_bonded = false
	talked_to_npcs.clear()
