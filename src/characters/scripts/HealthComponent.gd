extends Node
class_name HealthComponent

## Shared HP state and damage math, composed into Character/Enemy/PartyMember (which can't
## share a base class — CharacterBody3D vs Node3D). Owners keep their own defeat handling.

var max_hp: float = 0.0
var current_hp: float = 0.0

func setup(starting_max_hp: float) -> void:
	max_hp = starting_max_hp
	current_hp = starting_max_hp

## Applies damage and clamps current_hp to zero. Returns true if this brought it to 0.
func apply_damage(damage: float) -> bool:
	current_hp -= damage
	if current_hp < 0:
		current_hp = 0
	return current_hp <= 0

## Restores HP, clamped to max_hp. Returns the actual amount healed.
func apply_heal(amount: float) -> float:
	var actual_heal: float = min(amount, max_hp - current_hp)
	current_hp += actual_heal
	return actual_heal
