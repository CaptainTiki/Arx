class_name Dungeon
extends Node3D
## Root of the generated floor (rooms + Spawned). Also where noise goes: anything loud calls
## emit_noise() and every living enemy within radius × its hearing gets hear(pos). No line-of-sight
## check, so noise carries through walls into the next room.


func emit_noise(pos: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.state == Enemy.State.DEAD:
			continue
		if pos.distance_to(enemy.global_position) <= radius * enemy.data.hearing:
			enemy.hear(pos)
