extends Control
class_name BossHealthBar

# Long horizontal health bar shown under the turn queue once a boss enters phase 2. Reuses
# battle_health_bar.gd's target-binding pattern with a full-width, name-only layout.

var target_node: Node3D = null

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var name_label: Label = $NameLabel

func setup(target: Node3D) -> void:
	if is_instance_valid(target_node) and target_node.has_signal("hp_changed") and target_node.hp_changed.is_connected(_on_hp_changed):
		target_node.hp_changed.disconnect(_on_hp_changed)

	target_node = target
	_refresh_from_target()

	if is_instance_valid(target_node) and target_node.has_signal("hp_changed"):
		target_node.hp_changed.connect(_on_hp_changed)

	visible = true

func _refresh_from_target() -> void:
	if is_instance_valid(target_node):
		var display_name = target_node.get("character_name")
		if display_name == null or str(display_name) == "":
			display_name = target_node.name
		name_label.text = str(display_name)

		progress_bar.max_value = max(1.0, target_node.max_hp)
		progress_bar.value = max(0.0, target_node.current_hp)
	else:
		progress_bar.value = 0.0

func _on_hp_changed(new_hp) -> void:
	progress_bar.value = max(0.0, new_hp)

func _process(_delta: float) -> void:
	if is_instance_valid(target_node):
		progress_bar.value = max(0.0, target_node.current_hp)
