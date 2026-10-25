class_name Torch
extends OmniLight3D
## Wall torch. Flickers its own energy and the flame mesh around the authored light_energy.

@export var flicker_amount: float = 0.15
@export var flicker_speed: float = 7.0

@onready var _flame: MeshInstance3D = %Flame

var _base_energy: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_base_energy = light_energy
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	var wobble: float = sin(_time) * 0.5 + sin(_time * 2.31 + 1.7) * 0.3 + sin(_time * 5.13 + 0.4) * 0.2
	light_energy = _base_energy * (1.0 + wobble * flicker_amount)
	_flame.scale.y = 1.0 + wobble * 0.25
