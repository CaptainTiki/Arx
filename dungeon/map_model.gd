class_name MapModel
extends RefCounted
## What the minimap needs from a floor plan, flattened once per generate: each room's cells, doors,
## type, main-path flag and optional authored tile. rooms[i] is plan[i].


var rooms: Array[MapRoom] = []

var _room_at: Dictionary[Vector2i, int] = {}


static func from_plan(plan: Array[DungeonGenerator.Placement]) -> MapModel:
	var model: MapModel = MapModel.new()
	for i: int in plan.size():
		var placement: DungeonGenerator.Placement = plan[i]
		var room: MapRoom = MapRoom.new()
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


class MapRoom:
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
