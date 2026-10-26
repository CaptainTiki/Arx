class_name MapModel
extends RefCounted
## What the minimap needs from a floor plan, flattened once per generate: each room's cells, doors,
## type, main-path flag and optional authored tile. rooms[i] is plan[i].


var rooms: Array[MapRoom] = []

var _room_at: Dictionary[Vector2i, int] = {}


static func from_plan(plan: Array[DungeonGenerator.Placement]) -> MapModel:
	var model: MapModel = MapModel.new()
	var bridge_groups: Dictionary[int, int] = {}
	for i: int in plan.size():
		var placement: DungeonGenerator.Placement = plan[i]
		var room: MapRoom = MapRoom.new()
		room.group = i
		if placement.loop:
			# A bridge's pieces draw as one corridor: no seams between them.
			if not bridge_groups.has(placement.bridge_id):
				bridge_groups[placement.bridge_id] = i
			room.group = bridge_groups[placement.bridge_id]
		room.cells = placement.cells()
		room.type = placement.template.type
		room.main_path = placement.main_path
		room.map_tile = placement.template.map_tile
		room.footprint = placement.template.footprint
		room.turns = placement.turns
		room.grid_origin = placement.grid_origin
		for index: int in placement.template.door_dirs.size():
			var door: MapDoor = MapDoor.new()
			door.cell = placement.door_cell(index)
			door.dir = placement.door_dir(index)
			door.used = placement.used_doors.has(index)
			room.doors.append(door)
		for cell: Vector2i in room.cells:
			model._room_at[cell] = i
		model.rooms.append(room)
	return model


## Index of the room covering `cell`, or -1.
func room_index_at(cell: Vector2i) -> int:
	return _room_at.get(cell, -1)


func room_at(cell: Vector2i) -> MapRoom:
	var index: int = room_index_at(cell)
	return rooms[index] if index >= 0 else null


## Whether two cells are inside the same room (or the same loop bridge), so no wall runs between them.
func joined(a: Vector2i, b: Vector2i) -> bool:
	var first: MapRoom = room_at(a)
	var second: MapRoom = room_at(b)
	return first != null and second != null and first.group == second.group


class MapRoom:
	## Rooms sharing a group draw without walls between them: each room alone, except the pieces of a bridge.
	var group: int
	var cells: Array[Vector2i] = []
	var doors: Array[MapDoor] = []
	var type: int
	var main_path: bool
	## Room.map_tile, authored unrotated over `footprint`; drawn turned by `turns`.
	var map_tile: Texture2D
	var footprint: Vector2i
	var turns: int
	var grid_origin: Vector2i

	## Middle of the room, in cells.
	func center() -> Vector2:
		return Vector2(grid_origin) + Vector2(DungeonGenerator.rotated_footprint(footprint, turns)) * 0.5


class MapDoor:
	## The room's own cell the door sits on, and the side it opens through.
	var cell: Vector2i
	var dir: int
	## Connected to something; unused doors are plugged walls.
	var used: bool

	## The cell on the other side of the doorway.
	func outside() -> Vector2i:
		return cell + Door.offset(dir)
