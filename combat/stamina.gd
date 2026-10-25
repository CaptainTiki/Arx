class_name Stamina
extends Node
## Swing budget. Spending pauses regen for regen_delay seconds.

signal changed(value: float, maximum: float)

@export var max_stamina: float = 100.0
@export var regen_per_second: float = 25.0
## Seconds after the last spend before regen kicks in.
@export var regen_delay: float = 0.6

var current: float = 0.0
var _regen_wait: float = 0.0


func _ready() -> void:
	current = max_stamina


func can_spend(amount: float) -> bool:
	return current >= amount


func try_spend(amount: float) -> bool:
	if not can_spend(amount):
		return false
	current -= amount
	_regen_wait = regen_delay
	changed.emit(current, max_stamina)
	return true


func _physics_process(delta: float) -> void:
	if _regen_wait > 0.0:
		_regen_wait -= delta
		return
	if current < max_stamina:
		current = minf(current + regen_per_second * delta, max_stamina)
		changed.emit(current, max_stamina)
