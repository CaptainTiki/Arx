class_name DungeonGenerator
extends Node
## Builds a floor from prefab rooms by attaching them door to door on a 4 m grid.
## Plans the whole layout as data first (restarts are free), then instantiates it.
##
## Rotation convention: `turns` = clockwise quarter turns seen from above (-Z is north).
## A room with `turns` gets rotation_degrees.y = -90 * turns, and its node is offset so the
## rotated footprint's min corner sits on grid_origin. One turn maps doors N->E->S->W, a
## (w, h) footprint to (h, w), and cell (x, z) to (h-1-z, x). See rotate_cell().

@export var catalog: RoomCatalog
@export var target_rooms: int = 10
## Placement tries that fail on overlap before this layout is abandoned (then restarted).
@export var max_attempts: int = 200
## 0 = random every generate; nonzero = reproducible.
@export var seed_value: int = 0

@export_group("Shape")
## Chance the next non-special room is a corridor instead of a combat room.
@export_range(0.0, 1.0) var corridor_chance: float = 0.3
## Corridors in a row, at most.
@export var max_corridor_chain: int = 2
## How strongly growth favours the most recently opened doors. 1 = uniform (bushy), higher = snakier.
@export var recency_bias: float = 2.0
## A door that fails this many placements is given up on (it gets plugged).
@export var door_retry_limit: int = 4
## Fresh-seed restarts when no exit could be placed, before giving up loudly.
@export var max_restarts: int = 5

@export_group("Scene")
## Rooms are added here.
@export var dungeon: Node3D
## Enemies and pickups are added here. Must be a child of `dungeon`; it survives regeneration.
@export var spawned: Node3D
@export var player: Player
## Instantiated for WEAPON spawn points.
@export var pickup_scene: PackedScene
## Instantiated for ENEMY rows rolled from a table; the row's EnemyData is set on it.
@export var enemy_scene: PackedScene
## Print every spawn decision after the seed line, e.g. "room 4 (CombatRoom_B) spawn 1 → skitterer".
@export var print_spawn_log: bool = true

## Seed of the layout currently built. Put it in seed_value (or press F6) to rebuild exactly this floor.
var last_seed: int = 0
## One line per spawn point of the current floor, in build order. Same seed = same lines.
var last_spawn_log: PackedStringArray = []

## Room.Type -> Array of RoomTemplate.
var _templates: Dictionary[int, Array] = {}


## Throws away the current floor and builds a new one. `forced_seed` (nonzero) overrides seed_value,
## e.g. last_seed to rebuild the same floor.
func generate(forced_seed: int = 0) -> void:
	var base_seed: int = forced_seed if forced_seed != 0 else (seed_value if seed_value != 0 else randi())
	var plan: Array[Placement] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for restart: int in max_restarts + 1:
		var run_seed: int = base_seed + restart * 7919
		rng.seed = run_seed
		plan = _plan(rng)
		if not plan.is_empty():
			last_seed = run_seed
			print("Dungeon seed %d: %d rooms%s" % [run_seed, plan.size(), " (after %d restart(s))" % restart if restart > 0 else ""])
			break
		print("Dungeon seed %d: no exit placed, restarting" % run_seed)
	if plan.is_empty():
		push_error("DungeonGenerator: no layout reached an exit after %d restarts from seed %d. The catalog needs more multi-door rooms, or raise max_attempts." % [max_restarts, base_seed])
		return
	_clear()
	# The same RNG carries on from planning into the spawn rolls, so the seed fixes both.
	_build(plan, rng)


## Pure layout for one seed: no nodes are placed. Empty if no exit could be placed.
func plan_layout(run_seed: int) -> Array[Placement]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = run_seed
	return _plan(rng)


func _plan(rng: RandomNumberGenerator) -> Array[Placement]:
	_load_templates()
	var placements: Array[Placement] = []
	var occupied: Dictionary[Vector2i, Placement] = {}
	var open_doors: Array[OpenDoor] = []
	_place(_pick_template(rng, Room.Type.START), Vector2i.ZERO, 0, null, -1, placements, occupied, open_doors)
	var attempts: int = 0
	var has_treasure: bool = false
	var has_exit: bool = false
	while placements.size() < target_rooms and attempts < max_attempts and not open_doors.is_empty():
		var slot: int = _pick_open_door(rng, open_doors.size())
		var door: OpenDoor = open_doors[slot]
		var neighbor: Vector2i = door.cell + Door.offset(door.dir)
		if occupied.has(neighbor):
			# Faces another room's wall; nothing can ever attach here.
			open_doors.remove_at(slot)
			continue
		var type: int = _next_type(rng, placements.size(), has_treasure, door.placement)
		var template: RoomTemplate = _pick_template(rng, type)
		var entry: int = rng.randi_range(0, template.door_dirs.size() - 1)
		var turns: int = posmod(Door.opposite_of(door.dir) - template.door_dirs[entry], 4)
		var origin: Vector2i = neighbor - rotate_cell(template.door_cells[entry], template.footprint, turns)
		if not _fits(origin, rotated_footprint(template.footprint, turns), occupied):
			attempts += 1
			door.failures += 1
			if door.failures >= door_retry_limit:
				open_doors.remove_at(slot)
			continue
		open_doors.remove_at(slot)
		door.placement.used_doors.append(door.index)
		_place(template, origin, turns, door.placement, entry, placements, occupied, open_doors)
		has_treasure = has_treasure or type == Room.Type.TREASURE
		has_exit = has_exit or type == Room.Type.EXIT
	if not has_exit:
		var failed: Array[Placement] = []
		return failed
	return placements


## Cell (x, z) of a (w, h) footprint after `turns` clockwise quarter turns, in the rotated footprint.
static func rotate_cell(cell: Vector2i, footprint: Vector2i, turns: int) -> Vector2i:
	match posmod(turns, 4):
		1:
			return Vector2i(footprint.y - 1 - cell.y, cell.x)
		2:
			return Vector2i(footprint.x - 1 - cell.x, footprint.y - 1 - cell.y)
		3:
			return Vector2i(cell.y, footprint.x - 1 - cell.x)
		_:
			return cell


static func rotated_footprint(footprint: Vector2i, turns: int) -> Vector2i:
	return Vector2i(footprint.y, footprint.x) if posmod(turns, 2) == 1 else footprint


## Node transform (under Dungeon) that puts a room's rotated footprint's min corner on grid_origin.
static func placement_transform(grid_origin: Vector2i, footprint: Vector2i, turns: int) -> Transform3D:
	var size: Vector2 = Vector2(footprint) * Room.CELL_SIZE
	var offset: Vector2 = Vector2.ZERO
	match posmod(turns, 4):
		1:
			offset = Vector2(size.y, 0.0)
		2:
			offset = size
		3:
			offset = Vector2(0.0, size.x)
	var corner: Vector2 = Vector2(grid_origin) * Room.CELL_SIZE + offset
	return Transform3D(Basis(Vector3.UP, -PI * 0.5 * turns), Vector3(corner.x, 0.0, corner.y))


func _load_templates() -> void:
	if not _templates.is_empty():
		return
	assert(catalog != null, "DungeonGenerator needs a RoomCatalog")
	for scene: PackedScene in catalog.get_scenes():
		# Off-tree instance: read its metadata, never add it to the tree, free it.
		var room: Room = scene.instantiate() as Room
		if room == null:
			push_error("DungeonGenerator: %s has no Room root; skipped." % scene.resource_path)
			continue
		var problems: PackedStringArray = room.get_authoring_problems()
		if not problems.is_empty():
			push_error("DungeonGenerator: %s skipped:\n  %s" % [scene.resource_path, "\n  ".join(problems)])
			room.free()
			continue
		var template: RoomTemplate = RoomTemplate.new()
		template.scene = scene
		template.name = scene.resource_path.get_file().get_basename()
		template.type = room.type
		template.weight = room.weight
		template.footprint = room.footprint
		for door: Door in room.get_doors():
			door.update_cell()
			template.door_cells.append(door.cell)
			template.door_dirs.append(door.dir)
		room.free()
		if not _templates.has(template.type):
			_templates[template.type] = []
		_templates[template.type].append(template)
	for type: int in Room.Type.values():
		if not _templates.has(type):
			push_error("DungeonGenerator: catalog has no %s room." % Room.Type.keys()[type])


func _place(template: RoomTemplate, origin: Vector2i, turns: int, parent: Placement, entry: int,
		placements: Array[Placement], occupied: Dictionary[Vector2i, Placement], open_doors: Array[OpenDoor]) -> void:
	var placement: Placement = Placement.new()
	placement.template = template
	placement.grid_origin = origin
	placement.turns = turns
	placement.parent = parent
	placement.depth = parent.depth + 1 if parent else 0
	if template.type == Room.Type.CORRIDOR:
		var chained: bool = parent != null and parent.template.type == Room.Type.CORRIDOR
		placement.corridor_chain = (parent.corridor_chain if chained else 0) + 1
	if entry >= 0:
		placement.used_doors.append(entry)
	for cell: Vector2i in placement.cells():
		occupied[cell] = placement
	for index: int in template.door_dirs.size():
		if index == entry:
			continue
		var door: OpenDoor = OpenDoor.new()
		door.placement = placement
		door.index = index
		door.cell = placement.door_cell(index)
		door.dir = placement.door_dir(index)
		open_doors.append(door)
	placements.append(placement)


## 70/30 combat/corridor until two rooms before the target, then one treasure room, then the exit.
func _next_type(rng: RandomNumberGenerator, placed: int, has_treasure: bool, from: Placement) -> int:
	if placed >= target_rooms - 1 and has_treasure:
		return Room.Type.EXIT
	if placed >= target_rooms - 2 and not has_treasure:
		return Room.Type.TREASURE
	if from.corridor_chain < max_corridor_chain and rng.randf() < corridor_chance:
		return Room.Type.CORRIDOR
	return Room.Type.COMBAT


## Index into the open-door list, skewed toward the end (most recently opened).
func _pick_open_door(rng: RandomNumberGenerator, count: int) -> int:
	var back: int = mini(int(pow(rng.randf(), recency_bias) * count), count - 1)
	return count - 1 - back


func _pick_template(rng: RandomNumberGenerator, type: int) -> RoomTemplate:
	var options: Array = _templates.get(type, [])
	var total: float = 0.0
	for template: RoomTemplate in options:
		total += maxf(template.weight, 0.0)
	var roll: float = rng.randf() * total
	for template: RoomTemplate in options:
		roll -= maxf(template.weight, 0.0)
		if roll <= 0.0:
			return template
	return options.back() as RoomTemplate


static func _fits(origin: Vector2i, size: Vector2i, occupied: Dictionary[Vector2i, Placement]) -> bool:
	for z: int in size.y:
		for x: int in size.x:
			if occupied.has(origin + Vector2i(x, z)):
				return false
	return true


func _clear() -> void:
	for child: Node in dungeon.get_children():
		if child != spawned:
			dungeon.remove_child(child)
			child.queue_free()
	for child: Node in spawned.get_children():
		spawned.remove_child(child)
		child.queue_free()


func _build(plan: Array[Placement], rng: RandomNumberGenerator) -> void:
	var rooms: Array[Room] = []
	for i: int in plan.size():
		var placement: Placement = plan[i]
		var room: Room = placement.template.scene.instantiate() as Room
		room.name = "%02d_%s" % [i, placement.template.name]
		room.grid_origin = placement.grid_origin
		room.turns = placement.turns
		room.transform = placement_transform(placement.grid_origin, placement.template.footprint, placement.turns)
		dungeon.add_child(room)
		var doors: Array[Door] = room.get_doors()
		for index: int in placement.used_doors:
			doors[index].used = true
		rooms.append(room)
	for room: Room in rooms:
		for door: Door in room.get_doors():
			if not door.used and door.plug_scene:
				# Child of the marker = exactly at the marker's transform, and freed with the room.
				door.add_child(door.plug_scene.instantiate())
	last_spawn_log.clear()
	for room_index: int in rooms.size():
		var room: Room = rooms[room_index]
		var spawns: Array[SpawnPoint] = room.get_spawn_points()
		for spawn_index: int in spawns.size():
			var outcome: String = _spawn(spawns[spawn_index], rng)
			last_spawn_log.append("room %d (%s) spawn %d → %s" % [room_index, plan[room_index].template.name, spawn_index, outcome])
	if print_spawn_log:
		for line: String in last_spawn_log:
			print("  " + line)


## Places what one spawn point produces and returns a short description for the log.
## Table first (a "nothing" row places nothing); no table = step-3 fixed fallback.
func _spawn(spawn: SpawnPoint, rng: RandomNumberGenerator) -> String:
	var local: Transform3D = spawned.global_transform.affine_inverse() * spawn.global_transform
	if spawn.kind == SpawnPoint.Kind.PLAYER:
		player.place_at(spawn.global_transform)
		return "player"
	if spawn.table:
		var entry: SpawnEntry = spawn.table.roll(rng)
		if entry == null or entry.payload_for(spawn.kind) == null:
			return "nothing"
		if spawn.kind == SpawnPoint.Kind.ENEMY:
			var rolled: Enemy = enemy_scene.instantiate() as Enemy
			rolled.data = entry.enemy
			rolled.transform = local
			spawned.add_child(rolled)
		else:
			_place_pickup(local, entry.item)
		return entry.describe(spawn.kind)
	if spawn.kind == SpawnPoint.Kind.ENEMY:
		var enemy: Node3D = spawn.fixed_scene.instantiate() as Node3D
		enemy.transform = local
		spawned.add_child(enemy)
		return "fixed %s" % spawn.fixed_scene.resource_path.get_file().get_basename()
	_place_pickup(local, spawn.fixed_item)
	return "fixed %s" % spawn.fixed_item.display_name.to_lower()


func _place_pickup(local: Transform3D, item: ItemData) -> void:
	var pickup: Pickup = pickup_scene.instantiate() as Pickup
	pickup.transform = local
	spawned.add_child(pickup)
	pickup.set_item(item)


## One catalog room's metadata, read once from an off-tree instance.
class RoomTemplate:
	var scene: PackedScene
	var name: String
	var type: int
	var weight: float
	var footprint: Vector2i
	var door_cells: Array[Vector2i] = []
	var door_dirs: Array[int] = []


## A room in a planned layout.
class Placement:
	var template: RoomTemplate
	var grid_origin: Vector2i
	var turns: int
	var used_doors: Array[int] = []
	var corridor_chain: int = 0
	var parent: Placement
	var depth: int = 0

	func cells() -> Array[Vector2i]:
		var size: Vector2i = DungeonGenerator.rotated_footprint(template.footprint, turns)
		var result: Array[Vector2i] = []
		for z: int in size.y:
			for x: int in size.x:
				result.append(grid_origin + Vector2i(x, z))
		return result

	func door_cell(index: int) -> Vector2i:
		return grid_origin + DungeonGenerator.rotate_cell(template.door_cells[index], template.footprint, turns)

	func door_dir(index: int) -> int:
		return Door.rotated(template.door_dirs[index], turns)


## A placed door nothing is attached to yet.
class OpenDoor:
	var placement: Placement
	var index: int
	var cell: Vector2i
	var dir: int
	var failures: int = 0
