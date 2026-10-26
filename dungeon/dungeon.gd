class_name Dungeon
extends Node3D
## Root of the generated floor (rooms + Spawned). Also where noise goes: anything loud calls
## emit_noise() and every living enemy within radius × its hearing gets hear(pos). No line-of-sight
## check, so noise carries through walls into the next room.
## Owns the map too: the current plan, its MapModel and which cells the player has revealed.

## A cell was revealed, or the floor was rebuilt and everything hidden again.
signal revealed_changed

## Stands for "no cell yet", so the first report after a rebuild always counts as a change.
const NO_CELL: Vector2i = Vector2i.MIN

## Cells the player has uncovered. Per cell, so a sub-room reveal brush only changes _reveal_at().
var revealed: Dictionary[Vector2i, bool] = {}
## Draw-ready view of the current plan. Null until the first floor is built.
var map: MapModel
## Reported by the Player every physics frame. Moving into a new cell reveals what's there.
var player_cell: Vector2i = NO_CELL:
	set(value):
		if value == player_cell:
			return
		player_cell = value
		_reveal_at(value)

var _plan: Array[DungeonGenerator.Placement] = []


## Called by the generator after each build. Forgets the old floor's map and reveals.
func set_plan(plan: Array[DungeonGenerator.Placement]) -> void:
	_plan = plan
	map = MapModel.from_plan(plan)
	revealed.clear()
	player_cell = NO_CELL
	revealed_changed.emit()


## Grid cell under a world position.
func cell_at(world_position: Vector3) -> Vector2i:
	var local: Vector3 = to_local(world_position)
	return Vector2i(floori(local.x / Room.CELL_SIZE), floori(local.z / Room.CELL_SIZE))


func emit_noise(pos: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy: Enemy = node as Enemy
		if enemy == null or enemy.state == Enemy.State.DEAD:
			continue
		if pos.distance_to(enemy.global_position) <= radius * enemy.data.hearing:
			enemy.hear(pos)


## First visit to a room reveals its whole footprint.
func _reveal_at(cell: Vector2i) -> void:
	if map == null:
		return
	var index: int = map.room_index_at(cell)
	if index < 0 or _plan[index].visited:
		return
	_plan[index].visited = true
	for room_cell: Vector2i in _plan[index].cells():
		revealed[room_cell] = true
	revealed_changed.emit()
