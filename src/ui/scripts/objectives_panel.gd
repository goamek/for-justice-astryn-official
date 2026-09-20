extends Control
## Pause-menu subpage letting the player re-check the free-roam objective reminders —
## mirrors the persistent free-roam HUD exactly.

@onready var practice_row: Label = $ContentColumn/PracticeRow
@onready var team_row: Label = $ContentColumn/TeamRow
@onready var guards_row: Label = $ContentColumn/GuardsRow


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible:
		return
	practice_row.text = QuestManager.practice_objective_text()
	team_row.text = QuestManager.team_objective_text()
	guards_row.visible = QuestManager.can_enter_boss_fight()
