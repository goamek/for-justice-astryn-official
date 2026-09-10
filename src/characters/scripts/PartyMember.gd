# Non-boss ally combatant: holds CharacterData, HP/MP, and downed-state handling for the
# 3 recruitable party members (Character.gd covers the player-controlled 4th).

extends Node3D
class_name PartyMember

@export var data: CharacterData
@export var animated_sprite: AnimatedSprite3D
@export var free_world_anim: String = "Down Idle"
## forwarded to the InteractionArea child so it's toggleable without digging into
## the instanced scene's editable children (same pattern as Enemy.gd)
@export var interactable: bool = true

@onready var interaction_area: InteractionArea = $InteractionArea
@onready var health: HealthComponent = $HealthComponent
@onready var mana: ManaComponent = $ManaComponent

@export var dialogue_resource: DialogueResource
## Whether CinematicBars (letterboxing) slides in for this conversation; off by default. Can
## also be toggled per-section via CinematicBars.show_bars()/hide_bars() from the .dialogue file.
@export var show_cinematic_bars: bool = false

var character_name: String
var max_hp: float:
	get: return health.max_hp
var current_hp: float:
	get: return health.current_hp
var max_mp: float:
	get: return mana.max_mp
var current_mp: float:
	get: return mana.current_mp
var is_downed: bool = false
var heal_flash_tween: Tween
var stat_flash_tween: Tween

signal hp_changed(new_hp)
signal mana_changed(new_mp)

func _ready():
	if data:
		character_name = data.character_name
		health.setup(data.base_max_hp)
		mana.setup(data.base_max_mp)
	else:
		push_error("PartyMember data resource is missing")
	if animated_sprite != null:
		animated_sprite.play(free_world_anim)
		# Randomize the starting frame so identical NPCs placed together don't idle in lockstep.
		var frame_count: int = animated_sprite.sprite_frames.get_frame_count(free_world_anim)
		if frame_count > 1:
			animated_sprite.frame = randi() % frame_count
	if interaction_area:
		interaction_area.interactable = interactable
		interaction_area.interact = Callable(self, "_on_interact")

# Starts dialogue with the character, passed in as "speaker" so a .dialogue file can call
# `do speaker.set_interactable(false)` on itself, same as CinematicBars' direct calls.
func _on_interact():
	if dialogue_resource:
		dialogue_resource.set_meta("show_cinematic_bars", show_cinematic_bars)
	DialogueManager.show_dialogue_balloon(dialogue_resource, "start", [{"speaker": self}])

## Callable from a .dialogue file (`do speaker.set_interactable(false)`) to toggle this
## character's interactability mid-conversation, e.g. to stop repeat talks after a key moment.
func set_interactable(value: bool) -> void:
	interactable = value
	if interaction_area:
		interaction_area.interactable = value

func take_damage(damage: float) -> float:
	var was_defeated = health.apply_damage(damage)
	hp_changed.emit(current_hp)

	# if hp is zero, go down instead of leaving the fight — a revive move can bring
	# this party member back rather than needing to re-instantiate a freed node
	if was_defeated:
		_enter_downed_state()
		return -1

	return damage

func spend_mana(cost: float) -> void:
	mana.apply_cost(cost)
	mana_changed.emit(current_mp)

func heal(amount: float) -> float:
	var actual_heal: float = health.apply_heal(amount)
	hp_changed.emit(current_hp)
	if is_downed and current_hp > 0:
		_exit_downed_state()
	if actual_heal > 0:
		_flash_heal_tint()
	return actual_heal

# Blinks the sprite green a few times for a heal, mirroring Enemy.gd's low-HP pulse — same
# Tween/modulate approach, just a finite flash instead of a persistent loop.
func _flash_heal_tint() -> void:
	if animated_sprite == null:
		return
	if heal_flash_tween and heal_flash_tween.is_valid():
		heal_flash_tween.kill()
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	heal_flash_tween = create_tween().set_loops(3)
	heal_flash_tween.tween_property(animated_sprite, "modulate", Color(0.4, 1.0, 0.4, 1.0), 0.15)
	heal_flash_tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

## Blinks the sprite blue (buff) or orange (debuff) a few times, same mechanism as
## _flash_heal_tint() just a different color pair.
func flash_stat_change_tint(is_buff: bool) -> void:
	if animated_sprite == null:
		return
	if stat_flash_tween and stat_flash_tween.is_valid():
		stat_flash_tween.kill()
	var flash_color: Color = Color(0.4, 0.6, 1.0, 1.0) if is_buff else Color(1.0, 0.6, 0.2, 1.0)
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	stat_flash_tween = create_tween().set_loops(3)
	stat_flash_tween.tween_property(animated_sprite, "modulate", flash_color, 0.15)
	stat_flash_tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

## Blinks the sprite's opacity for a field-reset move (e.g. Haze) wiping every stat stage —
## same mechanism as the buff/debuff flash, but fading alpha since modulate is already white at rest.
func flash_stat_reset_tint() -> void:
	if animated_sprite == null:
		return
	if stat_flash_tween and stat_flash_tween.is_valid():
		stat_flash_tween.kill()
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	stat_flash_tween = create_tween().set_loops(3)
	stat_flash_tween.tween_property(animated_sprite, "modulate:a", 0.2, 0.15)
	stat_flash_tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.15)

func _enter_downed_state() -> void:
	is_downed = true
	_clear_statuses_and_stat_stages()
	if heal_flash_tween and heal_flash_tween.is_valid():
		heal_flash_tween.kill()
	if stat_flash_tween and stat_flash_tween.is_valid():
		stat_flash_tween.kill()
	if animated_sprite != null:
		animated_sprite.modulate = Color(0.3, 0.3, 0.3, 1.0)

func _exit_downed_state() -> void:
	is_downed = false
	_clear_statuses_and_stat_stages()
	if animated_sprite != null:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

# Clears statuses and stat stages on both ends of the downed state, so nothing carries
# over into being revived.
func _clear_statuses_and_stat_stages() -> void:
	if data:
		data.active_statuses.clear()
		data.reset_modifiers()

## Applies a status effect to this party member's data.
func apply_status_effect(effect: StatusEffect, inflicted_magic_power: float = 0.0) -> void:
	if data:
		data.apply_status(effect, inflicted_magic_power)
