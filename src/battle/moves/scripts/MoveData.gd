extends Resource
class_name MoveData

enum MoveCategory {
	PHYSICAL,
	MAGIC,
	STATUS
}

enum StatType { NONE, PHYSICALATTACK, MAGICATTACK, PHYSICALDEFENSE, MAGICDEFENSE, ACCURACY, EVASION, SPEED }

@export var move_name: String = "Move Name Here"
@export_multiline var description: String = ""
@export var damage: int = 10
@export_range(0, 100) var accuracy: int = 100
@export var category: MoveCategory = MoveCategory.PHYSICAL
## Mana cost to use this move — only meaningful for MAGIC/STATUS moves (PHYSICAL moves
## are always free). Enemies/bosses have unlimited mana, so this is never read for them.
@export var mana_cost: int = 0
@export_range(0, 100) var crit_chance: int = 10 # Default 10% chance
@export var typing: TypeData.Type = TypeData.Type.BASIC
@export var subtype: TypeData.Type = TypeData.Type.NONE

@export var stat_to_change: StatType = StatType.NONE
@export_enum("-2:-2", "-1:-1", "0:0", "+1:1", "+2:2") var stat_change_amount: int = 0

## Optional second stat change, applied alongside the first (e.g. a move that raises
## both Attack and Speed at once).
@export var stat_to_change_2: StatType = StatType.NONE
@export_enum("-2:-2", "-1:-1", "0:0", "+1:1", "+2:2") var stat_change_amount_2: int = 0

@export var status_to_inflict: StatusEffect = null
@export_range(0,100) var status_chance: int = 100

## If > 0, this status move heals the target for this fraction of their max HP
## (e.g. 0.333 = heal 1/3 max HP) instead of/alongside a stat change or status effect.
@export_range(0.0, 1.0) var heal_fraction_of_max_hp: float = 0.0

## Status types this move removes from the target on use (e.g. Cauterize curing Poison/Burn).
@export var cures_statuses: Array[StatusEffect.StatusType] = []

## Clears all 7 stat stages (buffs/debuffs) on the target — not status conditions like
## poison/paralyze. Meant to be paired with targets_all (e.g. Haze) for a field-wide reset.
@export var resets_stat_stages: bool = false

## If true, this move skips manual target selection entirely and hits every active
## combatant on both sides of the battlefield (e.g. Downpour).
@export var targets_all: bool = false

## If true, this move skips manual target selection and always targets its own user
## (e.g. a self-buff like Dead Calm). Ignored if targets_all is also set.
@export var self_target_only: bool = false

## Can only target a downed (0 HP) party member instead of someone standing — target
## cycling flips to offer downed allies only. Actual HP restored comes from heal_fraction_of_max_hp.
@export var revives: bool = false

## Target cycling only offers living party members, never enemies (e.g. Farmer's Taunt).
## Needed since the enemy-TAUNT-forces-targeting check in _build_target_cycle_list() only
## makes sense when TAUNT is applied to a party member, not an enemy.
@export var ally_target_only: bool = false

## Always hits regardless of accuracy/evasion (e.g. Haze). Self/ally/revive moves already
## bypass the accuracy roll; this covers a move that isn't any of those but still shouldn't miss.
@export var never_misses: bool = false
