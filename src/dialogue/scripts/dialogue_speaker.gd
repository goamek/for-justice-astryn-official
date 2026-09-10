extends Resource
class_name DialogueSpeaker

## unique id - this is what .dialogue files use as the speaker tag, e.g. "solider_one"
@export var speaker_key: String = ""
## what actually shows in the balloon's name label, e.g. "Soldier" (can repeat across rows)
@export var display_name: String = ""
@export var portrait: Texture2D
