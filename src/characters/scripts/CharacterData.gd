extends Resource
class_name CharacterData

@export var character_name: String = "Hero"
@export var base_max_hp: int = 30
@export var base_max_mp: int = 15
@export var base_physical_attack: int = 15
@export var base_magic_attack: int = 15
@export var base_physical_defense: int = 15
@export var base_magic_defense: int = 15
@export var base_accuracy: int = 100
@export var base_evasion: int = 100
@export var base_speed: int = 15

@export var is_boss: bool = false

# ---- Modifier Section ----

var physical_attack_stage: int = 0
var physical_defense_stage: int = 0
var magic_attack_stage: int = 0
var magic_defense_stage: int = 0
var accuracy_stage: int = 0
var evasion_stage: int = 0
var speed_stage: int = 0

# Stage -4..+4 -> multiplier, indexed by (stage + 4). Debuffs are the reciprocal of the
# matching buff (e.g. -3 is 1/2.25) rather than a linear curve.
const STAGE_MULTIPLIERS: Array[float] = [0.4, 0.4444444444, 0.5, 0.6666666667, 1.0, 1.5, 2.0, 2.25, 2.5]

func get_stat_multiplier(stage: int) -> float:
	stage = clampi(stage, -4, 4)
	return STAGE_MULTIPLIERS[stage + 4]


enum StatType { NONE, PHYSICALATTACK, MAGICATTACK, PHYSICALDEFENSE, MAGICDEFENSE, ACCURACY, EVASION, SPEED }

func get_stat_stage(stat_name: StatType) -> int:
	match stat_name:
		StatType.PHYSICALATTACK:
			return physical_attack_stage
		StatType.PHYSICALDEFENSE:
			return physical_defense_stage
		StatType.MAGICATTACK:
			return magic_attack_stage
		StatType.MAGICDEFENSE:
			return magic_defense_stage
		StatType.ACCURACY:
			return accuracy_stage
		StatType.EVASION:
			return evasion_stage
		StatType.SPEED:
			return speed_stage
		_:
			return 0

func adjust_stat_stage(stat_name: StatType, amount: int):
	if stat_name == StatType.PHYSICALATTACK:
			physical_attack_stage = clampi(physical_attack_stage + amount, -4, 4)
			return physical_attack_stage
	if stat_name == StatType.PHYSICALDEFENSE:
			physical_defense_stage = clampi(physical_defense_stage + amount, -4, 4)
			return physical_defense_stage
	if stat_name == StatType.MAGICATTACK:
			magic_attack_stage = clampi(magic_attack_stage + amount, -4, 4)
			return magic_attack_stage
	if stat_name == StatType.MAGICDEFENSE:
			magic_defense_stage = clampi(magic_defense_stage + amount, -4, 4)
			return magic_defense_stage
	if stat_name == StatType.ACCURACY:
			accuracy_stage = clampi(accuracy_stage + amount, -4, 4)
			return accuracy_stage
	if stat_name == StatType.EVASION:
			evasion_stage = clampi(evasion_stage + amount, -4, 4)
			return evasion_stage
	if stat_name == StatType.SPEED:
			speed_stage = clampi(speed_stage + amount, -4, 4)
			return speed_stage

func reset_modifiers() -> void:
	physical_attack_stage = 0
	physical_defense_stage = 0
	magic_attack_stage = 0
	magic_defense_stage = 0
	accuracy_stage = 0
	evasion_stage = 0
	speed_stage = 0

@export var moves: Array[MoveData] = []
@export var typing: Array[TypeData.Type] = [TypeData.Type.BASIC]

# ---- Status Conditions ----
var active_statuses: Array[StatusEffect] = []

func has_status(status_type: StatusEffect.StatusType) -> bool:
	for effect in active_statuses:
		if effect.type == status_type:
			return true
	return false
	
func get_status(status_type: StatusEffect.StatusType) -> StatusEffect:
	for effect in active_statuses:
		if effect.type == status_type:
			return effect
	return null

func apply_status(new_status: StatusEffect, inflicted_magic_power: float = 0.0) -> void:
	var existing = get_status(new_status.type)
	if existing:
		existing.duration = new_status.duration
		existing.inflicted_magic_power = inflicted_magic_power
	else:
		var duplicated: StatusEffect = new_status.duplicate()
		duplicated.inflicted_magic_power = inflicted_magic_power
		active_statuses.append(duplicated)
