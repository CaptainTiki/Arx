@tool
class_name Door
extends Marker3D
## A connection point on a room's footprint edge. Sits on the boundary at the center of a cell edge;
## its -Z axis points out through the doorway (set automatically from `dir`). If no neighbour
## connects here, the generator fills it with `plug_scene`.

enum Dir { NORTH, EAST, SOUTH, WEST }  # -Z, +X, +Z, -X. Also the number of clockwise quarter turns from north.

@export var dir: Dir = Dir.NORTH:
	set(value):
		dir = value
		rotation.y = -PI * 0.5 * dir
		_notify_room()
## Wall chunk placed at this marker if the door ends up unused.
@export var plug_scene: PackedScene = preload("res://dungeon/DoorPlug.tscn")

## Footprint cell this door belongs to, in the room's own (unrotated) cell space.
var cell: Vector2i
var used: bool = false


func _ready() -> void:
	update_cell()
	if Engine.is_editor_hint():
		set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_notify_room()


func update_cell() -> void:
	cell = cell_at(Room.local_position_of(self), dir)


func opposite() -> Dir:
	return opposite_of(dir) as Dir


static func opposite_of(d: int) -> int:
	return (d + 2) % 4


## Direction after `turns` clockwise quarter turns (see DungeonGenerator for the convention).
static func rotated(d: int, turns: int) -> int:
	return posmod(d + turns, 4)


## Cell step across an edge facing `d`.
static func offset(d: int) -> Vector2i:
	match d:
		Dir.NORTH:
			return Vector2i(0, -1)
		Dir.EAST:
			return Vector2i(1, 0)
		Dir.SOUTH:
			return Vector2i(0, 1)
		_:
			return Vector2i(-1, 0)


## Cell a door at room-local `position` facing `d` belongs to: step a hair inward off the edge, then floor.
static func cell_at(position: Vector3, d: int) -> Vector2i:
	var inward: Vector2i = -offset(d)
	var probe: Vector2 = Vector2(position.x, position.z) + Vector2(inward) * 0.01
	return Vector2i(floori(probe.x / Room.CELL_SIZE), floori(probe.y / Room.CELL_SIZE))


## Room-local position of the center of `cell`'s edge facing `d`.
static func edge_center(at_cell: Vector2i, d: int) -> Vector3:
	var center: Vector2 = (Vector2(at_cell) + Vector2(0.5, 0.5)) * Room.CELL_SIZE
	var edge: Vector2 = center + Vector2(offset(d)) * Room.CELL_SIZE * 0.5
	return Vector3(edge.x, 0.0, edge.y)


func _notify_room() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var room: Room = Room.owning_room(self)
	if room:
		room.update_configuration_warnings()
