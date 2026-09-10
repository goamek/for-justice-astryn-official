extends Resource
class_name StatusEffect

enum StatusType {
	NONE,
	PARALYZE,
	FREEZE,
	POISON,
	BURN,
	PROVOKE,
	TAUNT,
	COATING_OIL,
	COATING_WATER,
	COATING_TAR,
	COATING_ROOTED
}

@export var effect_name: String = "Status"
@export var effect_name_past: String = ""
@export var type: StatusType = StatusType.NONE
@export var duration: int = 3

@export var base_tick_damage: float = 0.0

@export var diables_action: bool = false
var freeze_first_turn_passed: bool = false

## Snapshot of the inflicting character's magic attack at the moment this status was
## applied (see CharacterData.apply_status) — Poison/Burn ticks scale with the caster, not
## just the victim's own defense.
var inflicted_magic_power: float = 0.0

## The one place a StatusType becomes a short badge label, mirroring TypeData.type_to_string() —
## use this rather than building another enum->text mapping elsewhere.
static func get_badge_text(status_type: StatusType) -> String:
	match status_type:
		StatusType.PARALYZE: return "PAR"
		StatusType.FREEZE: return "FRZ"
		StatusType.POISON: return "PSN"
		StatusType.BURN: return "BRN"
		StatusType.PROVOKE: return "PRV"
		StatusType.TAUNT: return "TAU"
		StatusType.COATING_OIL: return "OIL"
		StatusType.COATING_WATER: return "WTR"
		StatusType.COATING_TAR: return "TAR"
		StatusType.COATING_ROOTED: return "ROOT"
		_: return ""

## The one place a StatusType becomes a badge color — pairs with get_badge_text().
static func get_badge_color(status_type: StatusType) -> Color:
	match status_type:
		StatusType.PARALYZE: return Color(0.9, 0.85, 0.2)
		StatusType.FREEZE: return Color(0.5, 0.85, 1.0)
		StatusType.POISON: return Color(0.6, 0.3, 0.8)
		StatusType.BURN: return Color(0.95, 0.4, 0.15)
		StatusType.PROVOKE: return Color(0.85, 0.2, 0.2)
		StatusType.TAUNT: return Color(0.85, 0.2, 0.2)
		StatusType.COATING_OIL: return Color(0.25, 0.2, 0.15)
		StatusType.COATING_WATER: return Color(0.2, 0.45, 0.9)
		StatusType.COATING_TAR: return Color(0.15, 0.1, 0.05)
		StatusType.COATING_ROOTED: return Color(0.3, 0.6, 0.25)
		_: return Color.WHITE
