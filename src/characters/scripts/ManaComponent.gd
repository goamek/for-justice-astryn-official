extends Node
class_name ManaComponent

## Shared mana state, composed into Character/PartyMember (mirrors HealthComponent.gd).
## Enemies/bosses have unlimited mana, so they don't get one.

var max_mp: float = 0.0
var current_mp: float = 0.0

func setup(starting_max_mp: float) -> void:
	max_mp = starting_max_mp
	current_mp = starting_max_mp

func can_afford(cost: float) -> bool:
	return current_mp >= cost

## Deducts cost, clamped to zero.
func apply_cost(cost: float) -> void:
	current_mp = max(0.0, current_mp - cost)
