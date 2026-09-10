extends Control

# HUD row for one party member: binds to a target, updates on HP/mana changes, and
# positions itself by party index.

var target_node: Node3D = null

@onready var progress_bar = $ProgressBar
@onready var name_label = $NameLabel
@onready var hp_label = $HPLabel
@onready var mana_progress_bar = $ManaProgressBar
@onready var mp_label = $MPLabel
@onready var status_badges: Array[PanelContainer] = [$StatusBadgeRow/Badge1, $StatusBadgeRow/Badge2, $StatusBadgeRow/Badge3, $StatusBadgeRow/Badge4]

func setup(target: Node3D, display_index: int = 0):
	# Public initializer used by TurnBasedCombat when spawning bars.
	bind_to_target(target, display_index)

func bind_to_target(target: Node3D, display_index: int = 0):
	# Disconnect from any previously bound target before rebinding.
	if is_instance_valid(target_node) and target_node.has_signal("hp_changed") and target_node.hp_changed.is_connected(_on_hp_changed):
		target_node.hp_changed.disconnect(_on_hp_changed)
	if is_instance_valid(target_node) and target_node.has_signal("mana_changed") and target_node.mana_changed.is_connected(_on_mana_changed):
		target_node.mana_changed.disconnect(_on_mana_changed)

	target_node = target
	_apply_layout(display_index)
	_refresh_from_target()

	# Connect to the HP/mana signals so the bars update automatically.
	if is_instance_valid(target_node) and target_node.has_signal("hp_changed"):
		target_node.hp_changed.connect(_on_hp_changed)
	if is_instance_valid(target_node) and target_node.has_signal("mana_changed"):
		target_node.mana_changed.connect(_on_mana_changed)

func _refresh_from_target():
	if is_instance_valid(target_node):
		var display_name = target_node.get("character_name")
		if display_name == null or str(display_name) == "":
			display_name = target_node.name
		name_label.text = str(display_name)

		progress_bar.max_value = max(1.0, target_node.max_hp)
		progress_bar.value = max(0.0, target_node.current_hp)
		_update_hp_label(target_node.current_hp, target_node.max_hp)

		mana_progress_bar.max_value = max(1.0, target_node.max_mp)
		mana_progress_bar.value = max(0.0, target_node.current_mp)
		_update_mp_label(target_node.current_mp, target_node.max_mp)
	else:
		# If there is no valid target, keep the bars at zero.
		progress_bar.value = 0.0
		_update_hp_label(0.0, progress_bar.max_value)
		mana_progress_bar.value = 0.0
		_update_mp_label(0.0, mana_progress_bar.max_value)

	_refresh_status_badges()
	visible = true

func _apply_layout(display_index: int):
	# Position this control in a fixed column; display_index controls vertical spacing.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0

	offset_left = 10
	offset_top = 10 + (display_index * 82)
	offset_right = offset_left + 130
	offset_bottom = offset_top + 88

func _on_hp_changed(new_hp):
	progress_bar.value = max(0.0, new_hp)
	_update_hp_label(new_hp, progress_bar.max_value)
	visible = true

func _on_mana_changed(new_mp):
	mana_progress_bar.value = max(0.0, new_mp)
	_update_mp_label(new_mp, mana_progress_bar.max_value)
	visible = true

func _process(_delta):
	# Fallback sync in case a signal is missed or the target changes.
	if is_instance_valid(target_node):
		progress_bar.value = max(0.0, target_node.current_hp)
		_update_hp_label(target_node.current_hp, target_node.max_hp)
		mana_progress_bar.value = max(0.0, target_node.current_mp)
		_update_mp_label(target_node.current_mp, target_node.max_mp)
		visible = true
	else:
		# If the target no longer exists, preserve the current fill state.
		progress_bar.value = max(0.0, progress_bar.value)
		mana_progress_bar.value = max(0.0, mana_progress_bar.value)
		visible = true
	# active_statuses has no changed-signal, so this polls every frame same as HP/MP above.
	_refresh_status_badges()

func _refresh_status_badges() -> void:
	var statuses: Array = []
	if is_instance_valid(target_node) and target_node.data:
		statuses = target_node.data.active_statuses

	for i in range(status_badges.size()):
		var badge: PanelContainer = status_badges[i]
		if i < statuses.size():
			var effect: StatusEffect = statuses[i]
			var badge_style: StyleBoxFlat = badge.get_theme_stylebox("panel")
			badge_style.bg_color = StatusEffect.get_badge_color(effect.type)
			var badge_label: Label = badge.get_node("Label")
			badge_label.text = StatusEffect.get_badge_text(effect.type)
			badge.visible = true
		else:
			badge.visible = false

func _update_hp_label(current_hp: float, max_hp: float) -> void:
	# Shows real HP amounts (e.g. "25/50") instead of a percentage.
	hp_label.text = "%d/%d" % [int(round(max(0.0, current_hp))), int(round(max(1.0, max_hp)))]

func _update_mp_label(current_mp: float, max_mp: float) -> void:
	mp_label.text = "%d/%d" % [int(round(max(0.0, current_mp))), int(round(max(1.0, max_mp)))]
