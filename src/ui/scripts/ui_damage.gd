extends Label3D

# Floating damage-number popup spawned by TurnBasedCombat._resolve_move_hit().

func _ready():
	var tween = create_tween()
	tween.set_parallel(true) # Run animations at the same time

	tween.tween_property(self, "position:y", position.y + 2.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 1.0)

	# Delete itself when done
	tween.set_parallel(false)
	tween.tween_callback(queue_free)

func setup(amount: int, is_crit: bool, did_hit: bool = true):
	if not did_hit:
		text = "MISS"
		modulate = Color(0.8, 0.8, 0.8)
		outline_modulate = Color(0, 0, 0)
		scale = Vector3(1, 1, 1)
		return

	text = str(amount)
	if is_crit:
		text = "CRIT! " + text
		modulate = Color.YELLOW
		outline_modulate = Color.RED
		scale = Vector3(1.25, 1.25, 1.25)
