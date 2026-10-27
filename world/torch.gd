class_name Torch
extends OmniLight3D
## Wall torch. Flickers its own energy and the flame mesh around the authored light_energy.
## The Dungeon lights and douses torches by room (Dungeon.light_reach): a doused torch is a dark
## sconce, no light and no flame. Torches outside a dungeon (the test arena) stay lit.

@export var flicker_amount: float = 0.15
@export var flicker_speed: float = 7.0
## Seconds to fade in or out when the room's lighting changes.
@export var relight_time: float = 0.35

var lit: bool = true

@onready var _flame: MeshInstance3D = %Flame

var _base_energy: float = 0.0
## 0 doused, 1 lit. Tweened; the flicker multiplies it.
var _lit_blend: float = 1.0
var _lit_tween: Tween
var _time: float = 0.0


func _ready() -> void:
	add_to_group(&"torches")
	_base_energy = light_energy
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	var wobble: float = sin(_time) * 0.5 + sin(_time * 2.31 + 1.7) * 0.3 + sin(_time * 5.13 + 0.4) * 0.2
	light_energy = _base_energy * (1.0 + wobble * flicker_amount) * _lit_blend
	_flame.scale = Vector3(_lit_blend, (1.0 + wobble * 0.25) * _lit_blend, _lit_blend)
	_flame.visible = _lit_blend > 0.01


## Fade the torch in or out. `instant` snaps it (used when a floor is first built).
func set_lit(value: bool, instant: bool = false) -> void:
	if value == lit and not instant:
		return
	lit = value
	if _lit_tween:
		_lit_tween.kill()
	var target: float = 1.0 if lit else 0.0
	if instant or relight_time <= 0.0:
		_lit_blend = target
		return
	_lit_tween = create_tween()
	_lit_tween.tween_property(self, ^"_lit_blend", target, relight_time)
