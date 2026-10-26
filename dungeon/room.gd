@tool
class_name Room
extends Node3D
## A prefab room. Footprint is whole 4 m cells from this node's origin toward +X / +Z.
## Children: Geometry (CSG), Lights, Doors (Door markers), Spawns (SpawnPoint markers).
## The generator rotates and places it; author it once, unrotated.

enum Type { START, CORRIDOR, COMBAT, TREASURE, EXIT }

const CELL_SIZE: float = 4.0
## How close a door must sit to an edge center, and a doorway cutter to its door, in meters.
const SNAP_TOLERANCE: float = 0.05
const CUTTER_TOLERANCE: float = 0.5

@export var type: Type = Type.COMBAT
## Pick probability within its type.
@export var weight: float = 1.0
## Cells, x by z, from the origin corner.
@export var footprint: Vector2i = Vector2i(3, 3):
	set(value):
		footprint = value
		update_configuration_warnings()

@export_group("Placement Rules")
## Fewest non-corridor rooms between START and this one (e.g. a boss room kept deep). 0 = anywhere.
@export var min_depth_from_start: int = 0
## Most copies of this room on one floor. 0 = unlimited.
@export var max_per_floor: int = 0

@export_group("Map")
## Authored minimap art, drawn over the footprint (unrotated art, turned with the room). Null = plain cells.
@export var map_tile: Texture2D

## Set by the generator on placement.
var grid_origin: Vector2i
## Clockwise quarter turns applied on placement.
var turns: int = 0


func get_doors() -> Array[Door]:
	var doors: Array[Door] = []
	var root: Node = get_node_or_null(^"Doors")
	if root:
		for child: Node in root.get_children():
			if child is Door:
				doors.append(child as Door)
	return doors


func get_spawn_points() -> Array[SpawnPoint]:
	var spawns: Array[SpawnPoint] = []
	var root: Node = get_node_or_null(^"Spawns")
	if root:
		for child: Node in root.get_children():
			if child is SpawnPoint:
				spawns.append(child as SpawnPoint)
	return spawns


## Problems with how this room is authored; empty when it's generator-ready. Shown as editor warnings.
func get_authoring_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	if footprint.x < 1 or footprint.y < 1:
		problems.append("Footprint must be at least 1x1 cells.")
	var doors: Array[Door] = get_doors()
	if doors.is_empty():
		problems.append("Room has no Door markers under Doors.")
	var cutters: Array[Vector3] = _doorway_cutter_positions()
	for door: Door in doors:
		var at: Vector3 = local_position_of(door)
		var door_cell: Vector2i = Door.cell_at(at, door.dir)
		var expected: Vector3 = Door.edge_center(door_cell, door.dir)
		var dir_name: String = Door.Dir.keys()[door.dir]
		if not _in_footprint(door_cell):
			problems.append("Door '%s' (%s) at %s is outside the footprint." % [door.name, dir_name, _fmt(at)])
		elif Vector2(at.x - expected.x, at.z - expected.z).length() > SNAP_TOLERANCE:
			problems.append("Door '%s' (%s) at %s isn't on a %s edge center. Nearest: %s." % [door.name, dir_name, _fmt(at), dir_name.to_lower(), _fmt(expected)])
		elif not _has_cutter_near(cutters, expected):
			problems.append("Door '%s' has no doorway cutter (subtraction CSG under Geometry) within %.1f m." % [door.name, CUTTER_TOLERANCE])
	var players: int = 0
	for spawn: SpawnPoint in get_spawn_points():
		var at: Vector3 = local_position_of(spawn)
		if at.x <= 0.0 or at.z <= 0.0 or at.x >= footprint.x * CELL_SIZE or at.z >= footprint.y * CELL_SIZE:
			problems.append("SpawnPoint '%s' at %s is outside the footprint." % [spawn.name, _fmt(at)])
		if spawn.kind == SpawnPoint.Kind.PLAYER:
			players += 1
		elif spawn.table:
			problems.append_array(_table_problems(spawn))
		elif spawn.kind == SpawnPoint.Kind.ENEMY and spawn.fixed_scene == null:
			problems.append("ENEMY SpawnPoint '%s' has neither a table nor a fixed_scene." % spawn.name)
		elif spawn.kind == SpawnPoint.Kind.WEAPON and spawn.fixed_item == null:
			problems.append("WEAPON SpawnPoint '%s' has neither a table nor a fixed_item." % spawn.name)
	if type == Type.START and players != 1:
		problems.append("START rooms need exactly one PLAYER SpawnPoint (found %d)." % players)
	return problems


func _get_configuration_warnings() -> PackedStringArray:
	return get_authoring_problems()


## Position of `node` in this room's space, walking local transforms (works off-tree too).
static func local_position_of(node: Node3D) -> Vector3:
	var xform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent and not (parent is Room):
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform.origin


static func owning_room(node: Node) -> Room:
	var parent: Node = node.get_parent()
	while parent and not (parent is Room):
		parent = parent.get_parent()
	return parent as Room


## A table on an ENEMY point should only carry enemies, and one on a WEAPON point only items.
static func _table_problems(spawn: SpawnPoint) -> PackedStringArray:
	var problems: PackedStringArray = []
	var table_name: String = spawn.table.resource_path.get_file()
	if spawn.table.total_weight() <= 0.0:
		problems.append("SpawnPoint '%s': table %s has no weighted entries." % [spawn.name, table_name])
	for entry: SpawnEntry in spawn.table.entries:
		if entry == null:
			problems.append("SpawnPoint '%s': table %s has an empty slot." % [spawn.name, table_name])
		elif spawn.kind == SpawnPoint.Kind.ENEMY and entry.item:
			problems.append("ENEMY SpawnPoint '%s': table %s has an item row (%s); it would spawn nothing." % [spawn.name, table_name, entry.item.display_name])
		elif spawn.kind == SpawnPoint.Kind.WEAPON and entry.enemy:
			problems.append("WEAPON SpawnPoint '%s': table %s has an enemy row (%s); it would spawn nothing." % [spawn.name, table_name, entry.enemy.display_name])
	return problems


func _in_footprint(at_cell: Vector2i) -> bool:
	return at_cell.x >= 0 and at_cell.y >= 0 and at_cell.x < footprint.x and at_cell.y < footprint.y


func _doorway_cutter_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var geometry: Node = get_node_or_null(^"Geometry")
	if geometry:
		_collect_cutters(geometry, positions)
	return positions


func _collect_cutters(node: Node, into: Array[Vector3]) -> void:
	for child: Node in node.get_children():
		var shape: CSGShape3D = child as CSGShape3D
		if shape and shape.operation == CSGShape3D.OPERATION_SUBTRACTION:
			into.append(local_position_of(shape))
		_collect_cutters(child, into)


static func _has_cutter_near(cutters: Array[Vector3], at: Vector3) -> bool:
	for cutter: Vector3 in cutters:
		if Vector2(cutter.x - at.x, cutter.z - at.z).length() <= CUTTER_TOLERANCE:
			return true
	return false


static func _fmt(v: Vector3) -> String:
	return "(%.2f, %.2f)" % [v.x, v.z]
