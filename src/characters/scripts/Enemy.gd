# Non-boss combatant: holds CharacterData, HP, and defeat/tint handling shared by ordinary
# enemies and BossEnemy (which overrides _on_defeated for the phase transition).

extends Node3D
class_name Enemy

@export var data: CharacterData
@export var animated_sprite: AnimatedSprite3D
## soldiers double as decorative free-roam NPCs and TBC combatants (see solider_one/two/three.tscn) -
## set per-instance so the same scene can idle differently depending on where it's placed
@export_enum("Battle Idle", "Down Idle", "Left Idle", "Right Idle") var idle_animation: String = "Battle Idle"
## forwarded to the InteractionArea child so it's toggleable without digging into
## the instanced scene's editable children
@export var interactable: bool = true
## shown via DialogueManager when this soldier is talked to in free roam (see PartyMember.gd's
## identical pattern) - unused while acting as a TBC combatant
@export var dialogue_resource: DialogueResource
## Whether CinematicBars (letterboxing) slides in for this conversation; off by default. Can
## also be toggled per-section via CinematicBars.show_bars()/hide_bars() from the .dialogue file.
@export var show_cinematic_bars: bool = false
@onready var health: HealthComponent = $HealthComponent
@onready var interaction_area: InteractionArea = get_node_or_null("InteractionArea")

var character_name: String
var max_hp: float:
	get: return health.max_hp
var current_hp: float:
	get: return health.current_hp

var pulse_tween: Tween
var stat_flash_tween: Tween

signal hp_changed(new_hp)


func _ready():
	if data:
		character_name = data.character_name
		health.setup(data.base_max_hp)
	else:
		push_error("Enemy data resource is missing")
	if animated_sprite != null:
		animated_sprite.play(idle_animation)
		# Randomize the starting frame so identical enemies placed together don't idle in
		# lockstep (same pattern as PartyMember.gd's free-roam NPCs).
		var frame_count: int = animated_sprite.sprite_frames.get_frame_count(idle_animation)
		if frame_count > 1:
			animated_sprite.frame = randi() % frame_count
	if interaction_area != null:
		interaction_area.interactable = interactable
		interaction_area.interact = Callable(self, "_on_interact")

# Starts dialogue with this soldier, passed in as "speaker" so a .dialogue file can call
# `do speaker.set_interactable(false)` on itself, same as CinematicBars' direct calls.
func _on_interact():
	if dialogue_resource:
		dialogue_resource.set_meta("show_cinematic_bars", show_cinematic_bars)
	DialogueManager.show_dialogue_balloon(dialogue_resource, "start", [{"speaker": self}])

## Callable from a .dialogue file (`do speaker.set_interactable(false)`) to toggle this
## character's interactability mid-conversation, e.g. to stop repeat talks after a key moment.
func set_interactable(value: bool) -> void:
	interactable = value
	if interaction_area != null:
		interaction_area.interactable = value

func take_damage(damage: float) -> float:
	var was_defeated = health.apply_damage(damage)
	update_enemy_tint(current_hp / max_hp)
	hp_changed.emit(current_hp)

	# if hp is zero, hand off to the defeat hook (overridable by subclasses like BossEnemy)
	if was_defeated:
		_on_defeated()
		return -1

	return damage

# called once current_hp reaches zero; default behavior removes the enemy from the scene
func _on_defeated() -> void:
	queue_free()

# Call this whenever the enemy takes damage
func update_enemy_tint(hp_ratio: float):
	# 1. Kill any existing pulse
	if pulse_tween and pulse_tween.is_valid(): # check is_valid() instead of is_running()
		pulse_tween.kill()
		pulse_tween = null

	# 2. Only start tinting if below 50% (0.5)
	if hp_ratio < 0.5:
		var danger_ratio = hp_ratio / 0.5
		var tint_intensity = 1.0 - danger_ratio
		animated_sprite.modulate = Color(1.0, 1.0 - tint_intensity, 1.0 - tint_intensity, 1.0)

		# 3. Add the pulse if they are really low (< 20%)
		if hp_ratio < 0.2:
			pulse_tween = create_tween().set_loops()
			pulse_tween.tween_property(animated_sprite, "modulate", Color(1.0, 0.0, 0.0, 1.0), 0.75)
			pulse_tween.tween_property(animated_sprite, "modulate", Color(0.4, 0.0, 0.0, 1.0), 0.75)
	else:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

## Blinks the sprite blue (buff) or orange (debuff), same mechanism as update_enemy_tint()'s
## pulse but a finite flash. Pauses the low-health pulse during the flash so the two tweens
## don't fight over modulate, then resumes it after if still critical.
func flash_stat_change_tint(is_buff: bool) -> void:
	if animated_sprite == null:
		return
	if stat_flash_tween and stat_flash_tween.is_valid():
		stat_flash_tween.kill()
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null
	var flash_color: Color = Color(0.4, 0.6, 1.0, 1.0) if is_buff else Color(1.0, 0.6, 0.2, 1.0)
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	stat_flash_tween = create_tween().set_loops(3)
	stat_flash_tween.tween_property(animated_sprite, "modulate", flash_color, 0.15)
	stat_flash_tween.tween_property(animated_sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
	stat_flash_tween.finished.connect(func(): update_enemy_tint(current_hp / max_hp))

## Blinks the sprite's opacity for a field-reset move (e.g. Haze) wiping every stat stage —
## same pulse-pause/resume handling as flash_stat_change_tint(), but fading alpha since a
## same-color flash against white didn't read.
func flash_stat_reset_tint() -> void:
	if animated_sprite == null:
		return
	if stat_flash_tween and stat_flash_tween.is_valid():
		stat_flash_tween.kill()
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null
	animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	stat_flash_tween = create_tween().set_loops(3)
	stat_flash_tween.tween_property(animated_sprite, "modulate:a", 0.2, 0.15)
	stat_flash_tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.15)
	stat_flash_tween.finished.connect(func(): update_enemy_tint(current_hp / max_hp))

## Applies a status effect to this enemy's data.
func apply_status_effect(effect: StatusEffect, inflicted_magic_power: float = 0.0) -> void:
	if data:
		data.apply_status(effect, inflicted_magic_power)
