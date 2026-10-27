class_name Camp
extends Node3D
## The yard outside the castle wall: fire, the gate, and the two station placeholders. Main shows it
## while the player is outside or in the entrance room and stows it (hidden, not processing) deeper in.

## Sky and ambient for outside; Main swaps the WorldEnvironment to this while the camp is up.
@export var environment: Environment

@export var fire_flicker: float = 0.25
@export var fire_flicker_speed: float = 9.0

@onready var gate: Gate = %Gate
## Where you stand after walking in through the gate, or after respawning.
@onready var arrival_gate: Marker3D = %ArrivalGate
## Where the far exit (garden stairs) puts you.
@onready var arrival_garden: Marker3D = %ArrivalGarden
@onready var _fire_light: OmniLight3D = %FireLight

var _fire_energy: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_fire_energy = _fire_light.light_energy
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * fire_flicker_speed
	var wobble: float = sin(_time) * 0.5 + sin(_time * 2.7 + 1.3) * 0.3 + sin(_time * 6.1) * 0.2
	_fire_light.light_energy = _fire_energy * (1.0 + wobble * fire_flicker)


## Show = visible and processing; stow = hidden and frozen (tweens and audio pause with it).
func set_stowed(stowed: bool) -> void:
	visible = not stowed
	process_mode = Node.PROCESS_MODE_DISABLED if stowed else Node.PROCESS_MODE_INHERIT
