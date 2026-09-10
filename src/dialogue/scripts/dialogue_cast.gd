extends Resource
class_name DialogueCast

## the central speaker roster - one row per character that can speak in dialogue, keyed by a
## unique speaker_key rather than the displayed name so multiple characters can share one
## display_name (e.g. all three soldiers show "Soldier") while still resolving distinct portraits
@export var speakers: Array[DialogueSpeaker] = []
