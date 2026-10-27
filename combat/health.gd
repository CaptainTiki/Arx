class_name Health
extends Node
## Hit points. The only place hp changes; everything goes through take_hit().

signal changed(current: int, maximum: int)
signal died

@export var max_hp: int = 100

var hp: int = 0


func _ready() -> void:
	hp = max_hp


## Sets a new maximum and refills to it. Owners call this on ready to apply their data.
func set_max_hp(value: int) -> void:
	max_hp = value
	hp = value
	changed.emit(hp, max_hp)


## Back to full. Used when the player respawns at camp.
func restore() -> void:
	hp = max_hp
	changed.emit(hp, max_hp)


func is_dead() -> bool:
	return hp <= 0


func take_hit(hit: HitInfo) -> void:
	if hp <= 0 or hit.damage <= 0:
		return
	hp = maxi(hp - hit.damage, 0)
	changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()
