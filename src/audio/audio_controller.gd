extends Node

@export var background_music: AudioStreamPlayer

@export var main_menu_music: AudioStreamPlayer

@export var battle_music: AudioStreamPlayer

@export var mute: bool = true

# The battle track battle_music.stream started with, restored at the start of every
# battle so a boss's phase-2 track from a previous fight doesn't carry over into the next.
var _default_battle_stream: AudioStream = null

func _ready() -> void:
	_default_battle_stream = battle_music.stream if battle_music else null
	if SignalBus != null and SignalBus.has_signal("boss_phase_transition_started"):
		SignalBus.boss_phase_transition_started.connect(_on_boss_phase_transition_started)

func stop_all_sounds():
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()

func play_main_menu_music(fade_duration: float = 5):
	if mute or not main_menu_music:
		return

	main_menu_music.volume_db = -10.0
	main_menu_music.play()

	var tween = create_tween()
	tween.tween_property(main_menu_music, "volume_db", 0.0, fade_duration)

func stop_main_menu_music(fade_duration: float = 0.99):
	if not main_menu_music or not main_menu_music.playing:
		return

	var tween = create_tween()
	tween.tween_property(main_menu_music, "volume_db", -80.0, fade_duration)

	await tween.finished
	main_menu_music.stop()


func play_background_music(fade_duration: float = 0.99):
	if mute or not background_music:
		return

	background_music.volume_db = -15.0
	background_music.play()

	var tween = create_tween()
	tween.tween_property(background_music, "volume_db", -5.0, fade_duration)

func stop_background_music(fade_duration: float = 0.99):
	if not background_music or not background_music.playing:
		return

	var tween = create_tween()
	tween.tween_property(background_music, "volume_db", -80.0, fade_duration)

	await tween.finished
	background_music.stop()


func play_battle_music(fade_duration: float = 0.99):
	if mute or not battle_music:
		return

	# Always start a fresh battle on the default track, even if the previous battle
	# ended mid-crossfade into a boss's phase-2 music.
	battle_music.stream = _default_battle_stream
	_fade_in_battle_music(fade_duration)

func stop_battle_music(fade_duration: float = 0.99):
	if not battle_music or not battle_music.playing:
		return

	var tween = create_tween()
	tween.tween_property(battle_music, "volume_db", -80.0, fade_duration)

	await tween.finished
	battle_music.stop()

func _fade_in_battle_music(fade_duration: float) -> void:
	battle_music.volume_db = -20.0
	battle_music.play()

	var tween = create_tween()
	tween.tween_property(battle_music, "volume_db", -10.0, fade_duration)

## Crossfades battle_music into a boss's phase-2 track as soon as its transition dialogue
## starts, rather than waiting for the whole transition sequence to finish.
## Bosses without a phase_two_music_loop assigned just keep whatever track is already playing.
func _on_boss_phase_transition_started(boss: Node3D) -> void:
	if mute or not battle_music:
		return
	if not (boss is BossEnemy) or boss.phase_two_music_loop == null:
		return

	await stop_battle_music()
	if boss.phase_two_music_intro != null:
		_play_intro_then_loop(boss.phase_two_music_intro, boss.phase_two_music_loop)
	else:
		battle_music.stream = boss.phase_two_music_loop
		_fade_in_battle_music(0.99)

## Plays intro once (not looping); when it naturally finishes, swaps in loop and plays it
## (loop's own import loop_mode is what makes it actually loop forever from there).
func _play_intro_then_loop(intro: AudioStream, loop: AudioStream) -> void:
	battle_music.stream = intro
	_fade_in_battle_music(0.99)
	battle_music.finished.connect(func():
		battle_music.stream = loop
		battle_music.volume_db = -10.0
		battle_music.play()
	, CONNECT_ONE_SHOT)
