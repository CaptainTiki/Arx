class_name HitInfo
extends RefCounted
## One hit, passed to take_hit(). Built fresh per hit; never stored.

var damage: int = 0
var source: Node3D
## Flattened attacker -> target direction. Used for knockback and flinch facing.
var direction: Vector3 = Vector3.ZERO
var blockable: bool = true
## Set by the receiver when a block ate the hit, so the attacker can react (no slow on a blocked charge).
var blocked: bool = false


func _init(p_damage: int = 0, p_source: Node3D = null, p_direction: Vector3 = Vector3.ZERO, p_blockable: bool = true) -> void:
	damage = p_damage
	source = p_source
	direction = p_direction
	blockable = p_blockable
