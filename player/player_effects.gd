class_name PlayerEffects
extends Node
## Deliberately minimal status stub: one effect (slow). It exists so there's a place to put the real
## system later. Don't generalize it yet.

signal slow_changed(slowed: bool)

## Multiplies the player's move speed. 1 = normal.
var speed_mult: float = 1.0

var _slow_left: float = 0.0


## Slows to `mult` for `duration` seconds. Stacking keeps the stronger slow and refreshes the time.
func apply_slow(mult: float, duration: float) -> void:
	var was_slowed: bool = is_slowed()
	speed_mult = minf(speed_mult, mult) if was_slowed else mult
	_slow_left = maxf(_slow_left, duration)
	if not was_slowed:
		slow_changed.emit(true)


func is_slowed() -> bool:
	return _slow_left > 0.0


func _physics_process(delta: float) -> void:
	if _slow_left <= 0.0:
		return
	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_left = 0.0
		speed_mult = 1.0
		slow_changed.emit(false)
