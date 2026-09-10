class_name TypeData

# Primary types and secondary subtypes. Subtypes are resolved to their parent
# primary type for matchup calculations, preserving an accurate main chart.
enum Type {
	BASIC,
	FIRE,
	WATER,
	PLANT,
	EARTH,
	DARK,
	ICE,
	ELECTRIC,
	LEAF,
	WOOD,
	ROCK,
	GROUND,
	POISON,
	PSYCHIC,
	NONE
}

const TYPE_PARENT = {
	Type.ICE: Type.WATER,
	Type.ELECTRIC: Type.FIRE,
	Type.LEAF: Type.PLANT,
	Type.WOOD: Type.PLANT,
	Type.ROCK: Type.EARTH,
	Type.GROUND: Type.EARTH,
	Type.POISON: Type.DARK,
	Type.PSYCHIC: Type.DARK
}

static func get_primary_type(type_value: Type) -> Type:
	if TYPE_PARENT.has(type_value):
		return TYPE_PARENT[type_value]
	return type_value

static func type_to_string(type_value: Type) -> String:
	return Type.keys()[type_value].capitalize()

const DEFENDING_CHART = {
	Type.BASIC: {
		Type.BASIC: 1,
		Type.FIRE: 1,
		Type.WATER: 1,
		Type.PLANT: 1,
		Type.EARTH: 2,
		Type.DARK: 0.25
	},
	Type.FIRE: {
		Type.BASIC: 1,
		Type.FIRE: 1,
		Type.WATER: 2,
		Type.PLANT: 0.5,
		Type.EARTH: 2,
		Type.DARK: 2
	},
	Type.WATER: {
		Type.BASIC: 1,
		Type.FIRE: 0.5,
		Type.WATER: 1,
		Type.PLANT: 2,
		Type.EARTH: 0.5,
		Type.DARK: 2
	},
	Type.PLANT: {
		Type.BASIC: 1,
		Type.FIRE: 2,
		Type.WATER: 0.5,
		Type.PLANT: 1,
		Type.EARTH: 0.5,
		Type.DARK: 2
	},
	Type.EARTH: {
		Type.BASIC: 0.5,
		Type.FIRE: 2,
		Type.WATER: 0.5,
		Type.PLANT: 0.5,
		Type.EARTH: 1,
		Type.DARK: 1
	},
	Type.DARK: {
		Type.BASIC: 2,
		Type.FIRE: 1,
		Type.WATER: 0.5,
		Type.PLANT: 0.5,
		Type.EARTH: 1,
		Type.DARK: 1
	}
}
