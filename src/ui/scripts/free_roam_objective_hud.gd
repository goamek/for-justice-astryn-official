extends CanvasLayer
## Persistent top-left free-roam objective reminders. Lives for the scene's whole lifetime
## and just reflects current QuestManager progress.

@onready var practice_row: Label = $Backer/VBoxContainer/PracticeRow
@onready var team_row: Label = $Backer/VBoxContainer/TeamRow
@onready var guards_row: Label = $Backer/VBoxContainer/GuardsRow


func _ready() -> void:
	SignalBus.team_ready_for_duel.connect(_refresh)
	SignalBus.cinematic_bars_shown.connect(func(): visible = false)
	SignalBus.cinematic_bars_hidden.connect(func(): visible = true)
	_refresh()


func _refresh() -> void:
	practice_row.text = QuestManager.practice_objective_text()
	team_row.text = QuestManager.team_objective_text()
	guards_row.visible = QuestManager.can_enter_boss_fight()
