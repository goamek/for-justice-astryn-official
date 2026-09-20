extends Node

@export var background_music: AudioStreamPlayer

@export var main_menu_music: AudioStreamPlayer

@export var battle_music: AudioStreamPlayer

## One-shot sound effects (distinct from the looping music players above) — e.g. a gunshot
## cue timed to a specific cutscene beat.
@export var sfx_player: AudioStreamPlayer

## Plays through the credits roll and the post-credits epilogue scene that follows it.
@export var credits_music: AudioStreamPlayer

## Plays under the pre-battle duel-intro cutscene, layered alongside the ducked background
## music.
@export var world_map_music: AudioStreamPlayer

@export var mute: bool = false

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
	# Safe to call on an already-playing track (e.g. free roam loading right after the
	# opening cutscene starts it) — avoids restarting it from 0 mid-loop.
	if background_music.playing:
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

## Silences battle music instantly, no fade — for a beat where the cut itself is the point
## (e.g. the music dropping dead the moment Astryn draws on Vorkoth).
func cut_battle_music() -> void:
	if not battle_music:
		return
	battle_music.stop()

## Ducks to roughly half as loud (-6dB) for the post-phase-2-defeat cutscenes (walk/shoot
## beat + both dialogue segments) — the track itself isn't stopping until they're done.
func duck_battle_music(duration: float = 0.5):
	if not battle_music or not battle_music.playing:
		return
	var tween = create_tween()
	tween.tween_property(battle_music, "volume_db", -16.0, duration)

## Plays a one-shot sound effect (a gunshot cue, etc.) — separate from the looping music
## players above, so it doesn't interrupt/get interrupted by whatever music is playing.
## Awaitable so a caller can wait for it to finish before moving on; callers that don't
## await it just fire it and continue immediately, same as before. volume_db lets a caller
## balance one cue against another without needing a separate player per sound.
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if mute or not sfx_player or stream == null:
		return
	sfx_player.stream = stream
	sfx_player.volume_db = volume_db
	sfx_player.play()
	await sfx_player.finished

func play_credits_music(fade_duration: float = 0.99):
	if mute or not credits_music:
		return
	# Safe to call again while already playing (e.g. if a later scene in the credits chain
	# called this too) — keeps it running instead of restarting from 0 mid-loop.
	if credits_music.playing:
		return

	credits_music.volume_db = -15.0
	credits_music.play()

	var tween = create_tween()
	tween.tween_property(credits_music, "volume_db", -5.0, fade_duration)

func stop_credits_music(fade_duration: float = 0.99):
	if not credits_music or not credits_music.playing:
		return

	var tween = create_tween()
	tween.tween_property(credits_music, "volume_db", -80.0, fade_duration)

	await tween.finished
	credits_music.stop()

## Ducks to roughly half as loud (-6dB) for the post-credits epilogue dialogue.
func duck_credits_music(duration: float = 0.5):
	if not credits_music or not credits_music.playing:
		return
	var tween = create_tween()
	tween.tween_property(credits_music, "volume_db", -11.0, duration)

func unduck_credits_music(duration: float = 0.5):
	if not credits_music:
		return
	var tween = create_tween()
	tween.tween_property(credits_music, "volume_db", -5.0, duration)

## Fades in under the pre-battle duel-intro cutscene, settling at roughly 25% volume (-12dB).
func play_world_map_music(fade_duration: float = 1.5):
	if mute or not world_map_music:
		return
	if world_map_music.playing:
		return

	world_map_music.volume_db = -80.0
	world_map_music.play()

	var tween = create_tween()
	tween.tween_property(world_map_music, "volume_db", -12.0, fade_duration)

func stop_world_map_music(fade_duration: float = 1.5):
	if not world_map_music or not world_map_music.playing:
		return

	var tween = create_tween()
	tween.tween_property(world_map_music, "volume_db", -80.0, fade_duration)

	await tween.finished
	world_map_music.stop()

func _fade_in_battle_music(fade_duration: float) -> void:
	battle_music.volume_db = -20.0
	battle_music.play()

	var tween = create_tween()
	tween.tween_property(battle_music, "volume_db", -10.0, fade_duration)

## Starts a boss's phase-2 track once the phase-2 reveal is fully on screen (the caller
## already faded phase-1 music out before the scene transition, so this stop_battle_music()
## call is normally a no-op — kept as a safety net in case that didn't happen).
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
