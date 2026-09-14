# Drives player movement/animation and permissions across scenes (free roam vs TBC), and
# loads TBC stats from `data` on spawn.

extends CharacterBody3D
class_name Character

# Free Roam movement variables
@export var VERTICAL_SPEED = 6
@export var HORIZONTAL_SPEED = 9
@export var JUMP_VELOCITY = 4.5
const LAST_DIRECTION_TOLERANCE = 0.1 # Threshold to prevent floating point errors

const FREE_ROAM_SCENE = "res://src/level/scenes/free_roam.tscn"
const TBC_SCENE = "res://src/level/scenes/tbc.tscn"
const BOSS_FIGHT_SCENE = "res://src/level/scenes/boss_fight_tbc.tscn"
@onready var camera = $Camera3D

# variables to help transition from Free roam and TBC
var can_move: bool = false
var is_talking: bool = false
var should_move_character: bool = false
var did_move_character: bool = false

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D

## Idle direction this character starts in; mirrors Enemy.gd's own idle_animation export
## for the same reason — the same character scene can rest differently depending on
## which scene it's placed in (e.g. the opening cutscene vs. normal free roam).
@export var initial_idle_animation: String = "Idle Down"

# Last non-zero movement direction, used to pick the correct idle animation (X/Z plane).
var last_direction: Vector2 = Vector2(0, 1) # Represents (right/left, down/up)

# variables for TBC
@export var data: CharacterData
@onready var health: HealthComponent = $HealthComponent
@onready var mana: ManaComponent = $ManaComponent
var character_name: String
var max_hp: float:
	get: return health.max_hp
var current_hp: float:
	get: return health.current_hp
var max_mp: float:
	get: return mana.max_mp
var current_mp: float:
	get: return mana.current_mp
var base_physical_attack: int
var base_magic_attack: int
var base_physical_defense: int
var base_magic_defense: int
var is_downed: bool = false
var heal_flash_tween: Tween
var stat_flash_tween: Tween

signal hp_changed(new_hp)
signal mana_changed(new_mp)


func _ready():
	if animated_sprite != null:
		animated_sprite.play(initial_idle_animation)
	else:
		print("ERROR: AnimatedSprite3D node not found at the specified path!")

	# Connect to dialogue signals
	InteractionManager.player = self
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

	# load in character data for TBC
	if data:
		character_name = data.character_name
		health.setup(data.base_max_hp)
		mana.setup(data.base_max_mp)
		base_physical_attack = data.base_physical_attack
		base_magic_attack = data.base_magic_attack
		base_physical_defense = data.base_physical_defense
		base_magic_defense = data.base_magic_defense
	else:
		push_error("Character data resource is missing")

# Freezes movement while a dialogue balloon is open.
func _on_dialogue_started(_resource: DialogueResource):
	is_talking = true
	velocity = Vector3.ZERO # Stop momentum instantly

# Restores movement permissions once dialogue ends.
func _on_dialogue_ended(_resource: DialogueResource):
	is_talking = false

func take_damage(damage: float) -> float:
	var was_defeated = health.apply_damage(damage)
	hp_changed.emit(current_hp)

	# if hp is zero, go down instead of leaving the fight — a revive move can bring
	# this character back rather than needing to re-instantiate a freed node
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

func _physics_process(delta: float) -> void:
	var current_scene_name = get_tree().current_scene.get_node("Current_Scene_Container").get_child(0)
	var path = current_scene_name.get_scene_file_path()

	# Will need extended handling as more scenes are added.
	if path == FREE_ROAM_SCENE:
		# Snap to a matching idle animation during dialogue so movement doesn't freeze mid-run.
		if is_talking:
			can_move = false
			var anim_name = "Idle"
			if abs(last_direction.x) > abs(last_direction.y):
				if last_direction.x > 0:
					anim_name += " Right"
				else:
					anim_name += " Left"
			else:
				if last_direction.y > 0:
					anim_name += " Down"
				else:
					anim_name += " Up"
			if animated_sprite.animation != anim_name:
				animated_sprite.play(anim_name)
		else:
			can_move = true
			should_move_character = false
			did_move_character = false
	# TBC scene: lock movement, park in battle-idle.
	if path == TBC_SCENE or path == BOSS_FIGHT_SCENE:
		can_move = false
		should_move_character = true
		if animated_sprite.animation != "Idle Battle":
			animated_sprite.play("Idle Battle")

	if can_move:
		if not is_on_floor():
			velocity += get_gravity() * delta

		var input_dir := Input.get_vector("left", "right", "up", "down")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		var is_moving = input_dir.length_squared() > LAST_DIRECTION_TOLERANCE

		if direction:
			velocity.x = direction.x * HORIZONTAL_SPEED
			velocity.z = direction.z * VERTICAL_SPEED
			last_direction = Vector2(direction.x, direction.z).normalized()
		else:
			velocity.x = move_toward(velocity.x, 0, HORIZONTAL_SPEED)
			velocity.z = move_toward(velocity.z, 0, VERTICAL_SPEED)

		var anim_name: String = ""
		if is_moving:
			anim_name = "Run"
		else:
			anim_name = "Idle"

		# Appends the dominant axis of last_direction (current/most recent movement) to the
		# animation name.
		if abs(last_direction.x) > abs(last_direction.y):
			if last_direction.x > 0:
				anim_name += " Right"
			else:
				anim_name += " Left"
		else:
			if last_direction.y > 0:
				anim_name += " Down"
			else:
				anim_name += " Up"

		if animated_sprite.animation != anim_name:
			animated_sprite.play(anim_name)

		move_and_slide()

	if !can_move:
		velocity.x = 0
		velocity.y = 0
		if should_move_character and !did_move_character:
			global_position.x -= 4.5
			global_position.z += 1
			did_move_character = true

## Applies a status effect to this character's data.
func apply_status_effect(effect: StatusEffect, inflicted_magic_power: float = 0.0) -> void:
	if data:
		data.apply_status(effect, inflicted_magic_power)
