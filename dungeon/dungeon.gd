class_name Dungeon
extends Node3D
## Root of the generated floor (rooms + Spawned). Also where noise goes: anything loud calls
## emit_noise() and every living enemy within radius × its hearing gets hear(pos). No line-of-sight
## check, so noise carries through walls into the next room.
## Owns the map too: the current plan, its MapModel and which cells the player has revealed.
## And where loot lands once the floor is built: drop_loot() for enemies, breakables and chests,
## place_item() for the player's own drops. Nothing else outside the generator makes a Pickup.

## A cell was revealed, or the floor was rebuilt and everything hidden again.
signal revealed_changed

## Stands for "no cell yet", so the first report after a rebuild always counts as a change.
const NO_CELL: Vector2i = Vector2i.MIN

@export_group("Loot")
## What a dropped item becomes. Same scene the generator uses for loot.
@export var pickup_scene: PackedScene
## Dropped pickups are added here (Dungeon/Spawned in Main, so they're cleared on regenerate).
@export var drop_parent: Node3D
## drop_loot() scatters each item this far from where it fell, in a random direction.
@export var drop_scatter_min: float = 0.3
@export var drop_scatter_max: float = 0.6
## Height of the ray that keeps a drop from landing inside a wall.
@export var drop_probe_height: float = 0.5
## How far a drop is pulled back from a wall the ray hits.
@export var drop_wall_margin: float = 0.4
@export_flags_3d_physics var drop_wall_mask: int = 1
## 0 = each floor's drops roll from its layout seed ^ the frame it was built on. Nonzero = every
## floor's drops roll from this seed, to chase a drop down.
@export var loot_seed: int = 0
## Print a line per item that drops, e.g. "drop: grunt → rawhide boots @ room 12".
@export var print_drop_log: bool = true

## This floor's drop lines, oldest first. Cleared on rebuild.
var drop_log: PackedStringArray = []
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
		_relight()

## Torches are lit by room: the room you're in plus every room within this many doorways (a hall
## between two rooms counts as one). Everything else is doused. Keeps the lit count small enough for
## the Compatibility renderer's per-mesh light cap, and dark rooms ahead read as unexplored.
@export var light_reach: int = 2

## The floor's drop RNG, for rolls that go with a drop (how many things a chest holds).
var loot_rng: RandomNumberGenerator:
	get:
		return _loot_rng

var _plan: Array[DungeonGenerator.Placement] = []
## Torches on this floor, keyed by the map group (room / hall / bridge) they sit in.
var _torches_by_group: Dictionary[int, Array] = {}
## Groups reachable through one used doorway, per group.
var _group_links: Dictionary[int, Array] = {}
var _lit_groups: Dictionary[int, bool] = {}
## Rolls runtime drops. Not seed-reproducible (the fight isn't), but off the global RNG.
var _loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	if loot_seed != 0:
		_loot_rng.seed = loot_seed


## The Dungeon `node` sits under, or null. How a breakable or chest placed by hand in a room scene
## finds where its noise and loot go.
static func find_above(node: Node) -> Dungeon:
	var parent: Node = node.get_parent()
	while parent and not (parent is Dungeon):
		parent = parent.get_parent()
	return parent as Dungeon


## Called by the generator after each build. Forgets the old floor's map, reveals and drop log,
## and reseeds the drop RNG from `floor_seed`.
func set_plan(plan: Array[DungeonGenerator.Placement], floor_seed: int = 0) -> void:
	_plan = plan
	map = MapModel.from_plan(plan)
	revealed.clear()
	_collect_torches()
	player_cell = NO_CELL
	_relight(true)
	drop_log.clear()
	_loot_rng.seed = loot_seed if loot_seed != 0 else floor_seed ^ Engine.get_process_frames()
	revealed_changed.emit()


## Rolls `table` `count` times and puts each item that comes up on the floor around `at` (a point
## on the floor), scattered drop_scatter_min..max away and kept out of walls. `rng` defaults to the
## floor's drop RNG. `source` names the dropper in the drop log. Returns what dropped.
func drop_loot(table: SpawnTable, at: Vector3, rng: RandomNumberGenerator = null, count: int = 1, source: String = "loot") -> Array[ItemData]:
	var dropped: Array[ItemData] = []
	if table == null:
		return dropped
	var roller: RandomNumberGenerator = rng if rng else _loot_rng
	for i: int in count:
		var entry: SpawnEntry = table.roll(roller)
		if entry == null or entry.item == null:
			continue
		var angle: float = roller.randf() * TAU
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * roller.randf_range(drop_scatter_min, drop_scatter_max)
		place_item(entry.item, at, offset, roller.randf() * TAU)
		dropped.append(entry.item)
		_log_drop(source, entry.item, at)
	return dropped


## Puts `item` on the floor as a new Pickup, `offset` from `from` (a point on the floor). A short
## ray pulls it back from any wall in the way, so it can always be picked up again.
func place_item(item: ItemData, from: Vector3, offset: Vector3, yaw: float) -> Pickup:
	if item == null or pickup_scene == null or drop_parent == null:
		return null
	var probe_from: Vector3 = from + Vector3.UP * drop_probe_height
	var landing: Vector3 = probe_from + offset
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(probe_from, landing, drop_wall_mask)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		landing = (hit["position"] as Vector3) - offset.normalized() * drop_wall_margin
	var pickup: Pickup = pickup_scene.instantiate() as Pickup
	pickup.position = drop_parent.to_local(Vector3(landing.x, from.y, landing.z))
	pickup.rotation.y = yaw
	drop_parent.add_child(pickup)
	pickup.set_item(item)
	return pickup


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


func _log_drop(source: String, item: ItemData, at: Vector3) -> void:
	var room: int = map.room_index_at(cell_at(at)) if map else -1
	var line: String = "drop: %s → %s @ room %s" % [source, item.display_name.to_lower(), str(room) if room >= 0 else "?"]
	drop_log.append(line)
	if print_drop_log:
		print(line)


## Finds every torch under this node and files it by the group of the cell it stands in. Also builds
## the group adjacency from used doors. Called once per floor, after the rooms are children.
func _collect_torches() -> void:
	_torches_by_group.clear()
	_group_links.clear()
	_lit_groups.clear()
	for node: Node in get_tree().get_nodes_in_group(&"torches"):
		var torch: Torch = node as Torch
		if torch == null or not is_ancestor_of(torch):
			continue
		var room: MapModel.MapRoom = map.room_at(cell_at(torch.global_position))
		if room == null:
			continue
		if not _torches_by_group.has(room.group):
			_torches_by_group[room.group] = []
		_torches_by_group[room.group].append(torch)
	for room: MapModel.MapRoom in map.rooms:
		if not _group_links.has(room.group):
			_group_links[room.group] = []
		for door: MapModel.MapDoor in room.doors:
			if not door.used:
				continue
			var other: MapModel.MapRoom = map.room_at(door.outside())
			if other and other.group != room.group and not _group_links[room.group].has(other.group):
				_group_links[room.group].append(other.group)


## Lights the groups within light_reach doorways of the player's cell and douses the rest.
func _relight(instant: bool = false) -> void:
	if map == null:
		return
	var want: Dictionary[int, bool] = {}
	var here: MapModel.MapRoom = map.room_at(player_cell)
	if here:
		var frontier: Array[int] = [here.group]
		want[here.group] = true
		for _hop: int in light_reach:
			var next: Array[int] = []
			for group: int in frontier:
				for linked: int in _group_links.get(group, []):
					if not want.has(linked):
						want[linked] = true
						next.append(linked)
			frontier = next
	for group: int in _torches_by_group:
		var lit: bool = want.has(group)
		if not instant and _lit_groups.get(group, false) == lit:
			continue
		_lit_groups[group] = lit
		for torch: Torch in _torches_by_group[group]:
			torch.set_lit(lit, instant)


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
