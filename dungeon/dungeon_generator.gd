class_name DungeonGenerator
extends Node
## Builds a floor from prefab rooms by attaching them door to door on a 4 m grid.
## Plans the whole layout as data first (restarts are free), then instantiates it. The plan runs in
## three passes: a main path START -> EXIT, branches off its spare doors, then loop-backs: short
## corridors routed through empty cells between unused doors of rooms that are far apart.
## Rooms never touch rooms: every link is room -> connector (a corridor) -> room.
##
## Rotation convention: `turns` = clockwise quarter turns seen from above (-Z is north).
## A room with `turns` gets rotation_degrees.y = -90 * turns, and its node is offset so the
## rotated footprint's min corner sits on grid_origin. One turn maps doors N->E->S->W, a
## (w, h) footprint to (h, w), and cell (x, z) to (h-1-z, x). See rotate_cell().

## The 1x1 pieces loop bridges are laid from, fetched by name: straight (doors N, S) and corner (N, E).
## Their weight of 0 keeps them out of normal rolls.
const LOOP_STUB: String = "Corridor_Stub"
const LOOP_CORNER: String = "Corridor_Corner"
## Separation of rooms with no connection at all.
const UNREACHABLE: int = 1 << 20

@export var catalog: RoomCatalog
## Placement tries that fail on overlap before this layout is abandoned (then restarted).
@export var max_attempts: int = 200
## 0 = random every generate; nonzero = reproducible.
@export var seed_value: int = 0

@export_group("Shape")
## Rooms (not connectors) between START and EXIT, counting neither. The exit is always this + 1 rooms deep.
@export var main_path_length: int = 6
## Rooms (not connectors) per branch, at most.
@export var max_branch_depth: int = 3
## Rooms (not connectors) on the whole floor, START and EXIT included. Branches fill up to this.
@export var target_rooms: int = 12
## Chance a room slot (main path or branch) is a treasure room.
@export_range(0.0, 1.0) var treasure_chance: float = 0.15
@export var max_treasure_per_floor: int = 2
## Chance each loop candidate (see below) gets bridged, shortest route first.
@export_range(0.0, 1.0) var loop_chance: float = 0.6
## Longest loop bridge, in cells. Shortcuts, not hallways. (4 found a loop on 7% of floors; 5 on 10%.)
@export var max_loop_length: int = 5
## Fewest rooms (not connectors) you'd walk through to get between two rooms before a bridge may
## join them. 1 = neighbours; 3 = you went somewhere and came back.
@export var loop_min_separation: int = 3
## How much the main path prefers doors (and room turns) that face back toward START, so it curls
## round instead of marching away. 0 = no preference. Branches never curl. Off by default: it pulls
## the exit closer (94 m -> 72 m at 0.5) but didn't raise the loop rate, and at 0.5 about 1 seed in
## 200 boxes itself in for all 5 restarts (raise max_restarts to 10 if you turn it on).
@export_range(0.0, 1.0) var main_path_curl: float = 0.0
## Placement tries per door (a fresh template and entry door each) before that door is given up on.
@export var door_retry_limit: int = 4
## Fresh-seed restarts when the main path boxes itself in, before giving up loudly.
@export var max_restarts: int = 5

@export_group("Scene")
## Rooms are added here. Also the noise hub every spawned enemy gets, and the owner of the map.
@export var dungeon: Dungeon
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
## Door pairs the loop pass could have bridged on the most recent plan, counted before it placed any.
var last_loop_candidates: int = 0

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
			print("Dungeon seed %d: %s%s" % [run_seed, describe_plan(plan, last_loop_candidates), " (after %d restart(s))" % restart if restart > 0 else ""])
			break
		print("Dungeon seed %d: main path boxed itself in, restarting" % run_seed)
	if plan.is_empty():
		push_error("DungeonGenerator: no main path reached an exit after %d restarts from seed %d. The catalog needs more multi-door rooms, or raise max_attempts." % [max_restarts, base_seed])
		return
	_clear()
	# The same RNG carries on from planning into the spawn rolls, so the seed fixes both.
	_build(plan, rng)
	dungeon.set_plan(plan)


## Pure layout for one seed: no nodes are placed. Empty if the main path boxed itself in.
func plan_layout(run_seed: int) -> Array[Placement]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = run_seed
	return _plan(rng)


## One-line shape summary, e.g. "main 6, branches 3 (max depth 2), treasure at depths [2, 5],
## loops 1 (len 3), candidates 4". The candidates part only when `loop_candidates` is given.
static func describe_plan(plan: Array[Placement], loop_candidates: int = -1) -> String:
	var main: int = 0
	var branches: int = 0
	var deepest: int = 0
	var treasure: Array[int] = []
	var bridge_cells: Dictionary[int, int] = {}
	for placement: Placement in plan:
		var type: int = placement.template.type
		if placement.loop:
			bridge_cells[placement.bridge_id] = bridge_cells.get(placement.bridge_id, 0) + 1
			continue
		if placement.main_path and not placement.template.is_connector and type != Room.Type.START and type != Room.Type.EXIT:
			main += 1
		if not placement.main_path and placement.parent.main_path:
			branches += 1
		deepest = maxi(deepest, placement.branch_depth())
		if type == Room.Type.TREASURE:
			treasure.append(placement.depth)
	treasure.sort()
	var loops: String = "loops %d" % bridge_cells.size()
	if not bridge_cells.is_empty():
		var lengths: PackedStringArray = []
		for bridge: int in bridge_cells:
			lengths.append(str(bridge_cells[bridge]))
		loops += " (len %s)" % ", ".join(lengths)
	if loop_candidates >= 0:
		loops += ", candidates %d" % loop_candidates
	return "main %d, branches %d (max depth %d), treasure at depths %s, %s" % [main, branches, deepest, treasure, loops]


func _plan(rng: RandomNumberGenerator) -> Array[Placement]:
	_load_templates()
	last_loop_candidates = 0
	var layout: Layout = Layout.new()
	layout.rng = rng
	if not _plan_main_path(layout):
		var failed: Array[Placement] = []
		return failed
	_plan_branches(layout)
	_plan_loops(layout)
	last_loop_candidates = layout.loop_candidates
	return layout.placements


## START -> C -> R -> C -> R ... -> C -> EXIT, with main_path_length rooms R and a connector C
## before each room and before the exit. False if it boxed itself in.
func _plan_main_path(layout: Layout) -> bool:
	var frontier: Array[OpenDoor] = []
	var start: RoomTemplate = _pick_template(layout, Room.Type.START, 0)
	var current: Placement = _place(start, Vector2i.ZERO, 0, null, -1, layout.placements, layout.occupied, frontier)
	current.main_path = true
	layout.count(current)
	layout.start_center = Vector2(current.grid_origin) + Vector2(rotated_footprint(start.footprint, 0)) * 0.5
	var rooms: int = 0
	while true:
		var type: int = _next_type(layout, current)
		if rooms == main_path_length and type != Room.Type.CORRIDOR:
			type = Room.Type.EXIT
		if type != Room.Type.EXIT and not _has_template(type, 2):
			# Every room of this type is a dead end (the treasure room has one door), so it can't be a
			# link in the chain. It goes on one of the connector's other doors instead, as long as the
			# path keeps one to carry on from, and doesn't use up a main-path slot.
			if frontier.size() >= 2:
				var side_doors: Array[OpenDoor] = []
				if _grow_one(layout, frontier, type, side_doors):
					_drop_used(frontier)
					continue
			type = Room.Type.COMBAT
		var opened: Array[OpenDoor] = []
		var next: Placement = _grow_one(layout, frontier, type, opened, 1 if type == Room.Type.EXIT else 2, main_path_curl)
		if next == null:
			return false
		next.main_path = true
		if type == Room.Type.EXIT:
			return true
		current = next
		frontier = opened
		if not next.template.is_connector:
			rooms += 1
	return false


## Chains of up to max_branch_depth rooms off the main path's spare doors (alternating with connectors,
## like the main path), until target_rooms is reached.
func _plan_branches(layout: Layout) -> void:
	var spare: Array[OpenDoor] = []
	for placement: Placement in layout.placements:
		if placement.main_path:
			spare.append_array(_unused_doors(placement))
	_shuffle(layout.rng, spare)
	while layout.rooms < target_rooms and not spare.is_empty():
		var doors: Array[OpenDoor] = [spare.pop_back()]
		var depth: int = 0
		while not doors.is_empty() and depth < max_branch_depth and layout.rooms < target_rooms:
			var opened: Array[OpenDoor] = []
			var room: Placement = _grow_one(layout, doors, _next_type(layout, doors[0].placement), opened)
			if room == null:
				break
			if not room.template.is_connector:
				depth += 1
			# The branch carries on through one of the new room's other doors (whichever fits first).
			doors = opened


## Bridges unused doors on rooms at least loop_min_separation rooms apart with a corridor routed
## through empty cells: one 1x1 piece per cell (straight or corner), at most max_loop_length cells.
## Candidates are tried shortest route first, ties in placement order, each at loop_chance. This is
## what turns the tree into a graph.
func _plan_loops(layout: Layout) -> void:
	var straight: RoomTemplate = _template_named(LOOP_STUB)
	var corner: RoomTemplate = _template_named(LOOP_CORNER)
	if straight == null or corner == null:
		push_warning("DungeonGenerator: %s or %s is missing from the catalog; floors will have no loops." % [LOOP_STUB, LOOP_CORNER])
		return
	for placement: Placement in layout.placements:
		if placement.parent:
			_link(layout, placement, placement.parent)
	# Unused doors opening onto empty cells, in placement order (then door order): the tie-break order.
	var doors: Array[OpenDoor] = []
	for placement: Placement in layout.placements:
		for door: OpenDoor in _unused_doors(placement):
			if not layout.occupied.has(door.cell + Door.offset(door.dir)):
				doors.append(door)
	var candidates: Array[LoopCandidate] = []
	for i: int in doors.size():
		var separation: Dictionary[Placement, int] = _separations(layout, doors[i].placement)
		for j: int in range(i + 1, doors.size()):
			if separation.get(doors[j].placement, UNREACHABLE) < loop_min_separation:
				continue
			var route: Array[Vector2i] = _route(layout, doors[i], doors[j])
			if route.is_empty():
				continue
			var candidate: LoopCandidate = LoopCandidate.new()
			candidate.a = doors[i]
			candidate.b = doors[j]
			candidate.first = i
			candidate.second = j
			candidate.length = route.size()
			candidates.append(candidate)
	layout.loop_candidates = candidates.size()
	candidates.sort_custom(func(x: LoopCandidate, y: LoopCandidate) -> bool:
		if x.length != y.length:
			return x.length < y.length
		return x.first < y.first or (x.first == y.first and x.second < y.second))
	for candidate: LoopCandidate in candidates:
		var a: OpenDoor = candidate.a
		var b: OpenDoor = candidate.b
		if a.placement.used_doors.has(a.index) or b.placement.used_doors.has(b.index):
			continue
		# Bridges placed since the candidates were listed can bring rooms closer or take route cells.
		if _separations(layout, a.placement).get(b.placement, UNREACHABLE) < loop_min_separation:
			continue
		var route: Array[Vector2i] = _route(layout, a, b)
		if route.is_empty() or layout.rng.randf() >= loop_chance:
			continue
		_lay_bridge(layout, a, b, route, straight, corner)


## Rooms entered on the shortest walk from `from` to each placement over the plan's connections so
## far (parents and bridges). Connectors are free, so neighbours are 1 apart.
func _separations(layout: Layout, from: Placement) -> Dictionary[Placement, int]:
	var steps: Dictionary[Placement, int] = {from: 0}
	# 0-1 BFS: a free step (into a corridor) goes to the front of the queue.
	var queue: Array[Placement] = [from]
	while not queue.is_empty():
		var at: Placement = queue.pop_front()
		for next: Placement in layout.links.get(at, []):
			var free: bool = next.template.is_connector
			var reached: int = steps[at] + (0 if free else 1)
			if steps.has(next) and steps[next] <= reached:
				continue
			steps[next] = reached
			if free:
				queue.push_front(next)
			else:
				queue.push_back(next)
	return steps


## Shortest run of empty cells from the cell outside door `a` to the cell outside door `b`, both
## included and at most max_loop_length long. Neighbours are tried N, E, S, W, so equal routes
## resolve the same way every time. Empty if there's none.
func _route(layout: Layout, a: OpenDoor, b: OpenDoor) -> Array[Vector2i]:
	var start: Vector2i = a.cell + Door.offset(a.dir)
	var goal: Vector2i = b.cell + Door.offset(b.dir)
	var route: Array[Vector2i] = []
	if layout.occupied.has(start) or layout.occupied.has(goal):
		return route
	var came_from: Dictionary[Vector2i, Vector2i] = {start: start}
	var frontier: Array[Vector2i] = [start]
	for length: int in max_loop_length:
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			if cell == goal:
				var at: Vector2i = cell
				while at != start:
					route.push_front(at)
					at = came_from[at]
				route.push_front(start)
				return route
			for dir: int in 4:
				var step: Vector2i = cell + Door.offset(dir)
				if came_from.has(step) or layout.occupied.has(step):
					continue
				came_from[step] = cell
				next.append(step)
		frontier = next
	return route


## Lays a bridge along `route`: one piece per cell, straight where the route runs on and a corner
## where it turns, each placed through _place so its doors are real used doors, chained from a's
## room to b's.
func _lay_bridge(layout: Layout, a: OpenDoor, b: OpenDoor, route: Array[Vector2i], straight: RoomTemplate, corner: RoomTemplate) -> void:
	layout.bridges += 1
	a.placement.used_doors.append(a.index)
	var previous: Placement = a.placement
	for k: int in route.size():
		var back: int = Door.opposite_of(a.dir) if k == 0 else _dir_to(route[k], route[k - 1])
		var ahead: int = Door.opposite_of(b.dir) if k == route.size() - 1 else _dir_to(route[k], route[k + 1])
		var template: RoomTemplate = straight if back == Door.opposite_of(ahead) else corner
		# Straight (N, S): one turn makes it E, W. Corner (N, E): t turns open sides t and t + 1.
		var turns: int = back % 2
		if template == corner:
			turns = back if posmod(ahead - back, 4) == 1 else ahead
		var exits: Array[OpenDoor] = []
		var piece: Placement = _place(template, route[k], turns, previous, _door_facing(template, turns, back), layout.placements, layout.occupied, exits)
		piece.loop = true
		piece.bridge_id = layout.bridges
		piece.used_doors.append(exits[0].index)
		_link(layout, previous, piece)
		previous = piece
	b.placement.used_doors.append(b.index)
	previous.bridge_end = b.placement
	_link(layout, previous, b.placement)


static func _link(layout: Layout, one: Placement, other: Placement) -> void:
	if not layout.links.has(one):
		layout.links[one] = []
	layout.links[one].append(other)
	if not layout.links.has(other):
		layout.links[other] = []
	layout.links[other].append(one)


## Index of the template door that faces `dir` once the template is turned `turns` times.
static func _door_facing(template: RoomTemplate, turns: int, dir: int) -> int:
	for index: int in template.door_dirs.size():
		if Door.rotated(template.door_dirs[index], turns) == dir:
			return index
	return -1


## Side of `from` that `to` lies across (they must be neighbours).
static func _dir_to(from: Vector2i, to: Vector2i) -> int:
	for dir: int in 4:
		if from + Door.offset(dir) == to:
			return dir
	return -1


## The door-attach step: tries `doors` in random order, each up to door_retry_limit times (a fresh
## template and entry door per try), and places the first fit. The new room's other doors go into
## `opened`. `min_doors` 2 keeps dead ends out where a way on is needed. Null if nothing fit.
## `curl` above 0 (main path only) favours doors, and entry doors, that turn the floor back toward START.
func _grow_one(layout: Layout, doors: Array[OpenDoor], type: int, opened: Array[OpenDoor], min_doors: int = 1, curl: float = 0.0) -> Placement:
	var order: Array[OpenDoor] = doors.duplicate()
	if curl > 0.0:
		var weights: Array[float] = []
		for door: OpenDoor in doors:
			weights.append(_curl_weight(curl, _faces_start(layout, door.cell, door.dir)))
		order.clear()
		for index: int in _weighted_order(layout.rng, weights):
			order.append(doors[index])
	else:
		_shuffle(layout.rng, order)
	for door: OpenDoor in order:
		var neighbor: Vector2i = door.cell + Door.offset(door.dir)
		if layout.occupied.has(neighbor):
			# Faces another room's wall; nothing can ever attach here.
			continue
		var depth: int = door.placement.depth + (0 if type == Room.Type.CORRIDOR else 1)
		for attempt: int in door_retry_limit:
			if layout.attempts >= max_attempts:
				return null
			var template: RoomTemplate = _pick_template(layout, type, depth, min_doors, door.placement)
			if template == null:
				return null
			var entry: int = layout.rng.randi_range(0, template.door_dirs.size() - 1) if curl <= 0.0 else _curled_entry(layout, door, template, curl)
			var turns: int = posmod(Door.opposite_of(door.dir) - template.door_dirs[entry], 4)
			var origin: Vector2i = neighbor - rotate_cell(template.door_cells[entry], template.footprint, turns)
			if not _fits(origin, rotated_footprint(template.footprint, turns), layout.occupied):
				layout.attempts += 1
				continue
			door.placement.used_doors.append(door.index)
			var placement: Placement = _place(template, origin, turns, door.placement, entry, layout.placements, layout.occupied, opened)
			layout.count(placement)
			return placement
	return null


## Which of the template's doors meets `door`, weighted by curl: an entry scores by the best of the
## room's other doors (as they'd end up placed) at pointing back toward START, so the path can turn.
func _curled_entry(layout: Layout, door: OpenDoor, template: RoomTemplate, curl: float) -> int:
	var neighbor: Vector2i = door.cell + Door.offset(door.dir)
	var weights: Array[float] = []
	for entry: int in template.door_dirs.size():
		var turns: int = posmod(Door.opposite_of(door.dir) - template.door_dirs[entry], 4)
		var origin: Vector2i = neighbor - rotate_cell(template.door_cells[entry], template.footprint, turns)
		var best: float = 0.0
		var first: bool = true
		for other: int in template.door_dirs.size():
			if other == entry:
				continue
			var cell: Vector2i = origin + rotate_cell(template.door_cells[other], template.footprint, turns)
			var score: float = _faces_start(layout, cell, Door.rotated(template.door_dirs[other], turns))
			best = score if first else maxf(best, score)
			first = false
		weights.append(_curl_weight(curl, best))
	return _weighted_pick(layout.rng, weights)


## How squarely a door on `cell` facing `dir` points back at START's middle: 1 straight at it, -1 away.
static func _faces_start(layout: Layout, cell: Vector2i, dir: int) -> float:
	var back: Vector2 = layout.start_center - (Vector2(cell) + Vector2(0.5, 0.5))
	return Vector2(Door.offset(dir)).dot(back.normalized())


static func _curl_weight(curl: float, score: float) -> float:
	# Clamped so nothing becomes impossible.
	return maxf(0.1, 1.0 + curl * score)


## One index of `weights`, drawn in proportion to its weight.
static func _weighted_pick(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	var total: float = 0.0
	for weight: float in weights:
		total += weight
	var roll: float = rng.randf() * total
	for index: int in weights.size():
		roll -= weights[index]
		if roll <= 0.0:
			return index
	return weights.size() - 1


## Indices of `weights` in a random order where heavier ones tend to come first (draws without replacement).
static func _weighted_order(rng: RandomNumberGenerator, weights: Array[float]) -> Array[int]:
	var indices: Array[int] = []
	for index: int in weights.size():
		indices.append(index)
	var left: Array[float] = weights.duplicate()
	var order: Array[int] = []
	while not indices.is_empty():
		var pick: int = _weighted_pick(rng, left)
		order.append(indices[pick])
		indices.remove_at(pick)
		left.remove_at(pick)
	return order


## The connector rule: a room is followed by a connector (CORRIDOR); a connector by a room, TREASURE
## at treasure_chance while under the floor cap, else COMBAT.
func _next_type(layout: Layout, from: Placement) -> int:
	if not from.template.is_connector:
		return Room.Type.CORRIDOR
	if layout.treasure < max_treasure_per_floor and layout.rng.randf() < treasure_chance:
		return Room.Type.TREASURE
	return Room.Type.COMBAT


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
		template.is_connector = room.is_connector
		template.min_depth_from_start = room.min_depth_from_start
		template.max_per_floor = room.max_per_floor
		template.map_tile = room.map_tile
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
		placements: Array[Placement], occupied: Dictionary[Vector2i, Placement], open_doors: Array[OpenDoor]) -> Placement:
	var placement: Placement = Placement.new()
	placement.template = template
	placement.grid_origin = origin
	placement.turns = turns
	placement.parent = parent
	# Depth counts rooms, not connectors: a connector sits at its parent's depth.
	if parent:
		placement.depth = parent.depth + (0 if template.is_connector else 1)
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
	return placement


## A weighted pick among the templates of `type` allowed at `depth`: weight above 0, at least
## `min_doors` doors, deep enough (min_depth_from_start), not used up (max_per_floor), and on the
## other side of the connector rule from `from` (the room it attaches to). Null if none is.
func _pick_template(layout: Layout, type: int, depth: int, min_doors: int = 1, from: Placement = null) -> RoomTemplate:
	var options: Array[RoomTemplate] = []
	var total: float = 0.0
	for template: RoomTemplate in _templates.get(type, []):
		if template.weight <= 0.0 or template.door_dirs.size() < min_doors or depth < template.min_depth_from_start:
			continue
		if from and template.is_connector == from.template.is_connector:
			continue
		if template.max_per_floor > 0 and layout.placed.get(template.name, 0) >= template.max_per_floor:
			continue
		options.append(template)
		total += template.weight
	if options.is_empty():
		return null
	var roll: float = layout.rng.randf() * total
	for template: RoomTemplate in options:
		roll -= template.weight
		if roll <= 0.0:
			return template
	return options.back()


## Whether any pickable template of `type` has at least `min_doors` doors.
func _has_template(type: int, min_doors: int) -> bool:
	for template: RoomTemplate in _templates.get(type, []):
		if template.weight > 0.0 and template.door_dirs.size() >= min_doors:
			return true
	return false


func _template_named(template_name: String) -> RoomTemplate:
	for type: int in _templates:
		for template: RoomTemplate in _templates[type]:
			if template.name == template_name:
				return template
	return null


## The placement's doors nothing is attached to, as OpenDoors.
static func _unused_doors(placement: Placement) -> Array[OpenDoor]:
	var doors: Array[OpenDoor] = []
	for index: int in placement.template.door_dirs.size():
		if placement.used_doors.has(index):
			continue
		var door: OpenDoor = OpenDoor.new()
		door.placement = placement
		door.index = index
		door.cell = placement.door_cell(index)
		door.dir = placement.door_dir(index)
		doors.append(door)
	return doors


## Removes doors something has been attached to since they were listed.
static func _drop_used(doors: Array[OpenDoor]) -> void:
	for i: int in range(doors.size() - 1, -1, -1):
		if doors[i].placement.used_doors.has(doors[i].index):
			doors.remove_at(i)


## Fisher-Yates with the plan's own RNG. Array.shuffle() would use the global one and break seeds.
static func _shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


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
			rolled.dungeon = dungeon
			rolled.transform = local
			spawned.add_child(rolled)
		else:
			_place_pickup(local, entry.item)
		return entry.describe(spawn.kind)
	if spawn.kind == SpawnPoint.Kind.ENEMY:
		var enemy: Node3D = spawn.fixed_scene.instantiate() as Node3D
		if enemy is Enemy:
			(enemy as Enemy).dungeon = dungeon
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
	var is_connector: bool = false
	var min_depth_from_start: int = 0
	var max_per_floor: int = 0
	var map_tile: Texture2D


## A room in a planned layout.
class Placement:
	var template: RoomTemplate
	var grid_origin: Vector2i
	var turns: int
	var used_doors: Array[int] = []
	var parent: Placement
	## Rooms (not connectors) between START and this one: START is 0, the exit main_path_length + 1.
	var depth: int = 0
	## On the START -> EXIT chain.
	var main_path: bool = false
	## A piece of a loop bridge (a 1x1 corridor between two otherwise unused doors).
	var loop: bool = false
	## Which bridge a loop piece belongs to, numbered from 1 in the order they were laid; 0 otherwise.
	var bridge_id: int = 0
	## On a bridge's last piece: the room it opens into. (Its first piece's parent is the other end.)
	var bridge_end: Placement
	## The player has been inside; Dungeon reveals it on the map.
	var visited: bool = false

	## Rooms (not connectors) from the main path out to this one; 0 on the main path itself.
	func branch_depth() -> int:
		var steps: int = 0
		var at: Placement = self
		while at and not at.main_path:
			if not at.template.is_connector:
				steps += 1
			at = at.parent
		return steps

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


## Shared state of one plan while it grows.
class Layout:
	var rng: RandomNumberGenerator
	var placements: Array[Placement] = []
	var occupied: Dictionary[Vector2i, Placement] = {}
	## Overlap failures so far, against max_attempts.
	var attempts: int = 0
	## Rooms (not connectors) placed, START and EXIT included.
	var rooms: int = 0
	var treasure: int = 0
	## Template name -> copies placed, for Room.max_per_floor.
	var placed: Dictionary[String, int] = {}
	## Middle of the START room, in cells: what main_path_curl turns the path back toward.
	var start_center: Vector2 = Vector2.ZERO
	## Who connects to whom (parents, then bridges), for the loop pass's separation rule.
	var links: Dictionary[Placement, Array] = {}
	## Door pairs the loop pass could bridge, counted before it laid any.
	var loop_candidates: int = 0
	var bridges: int = 0

	func count(placement: Placement) -> void:
		placed[placement.template.name] = placed.get(placement.template.name, 0) + 1
		if not placement.template.is_connector:
			rooms += 1
		if placement.template.type == Room.Type.TREASURE:
			treasure += 1


## A door pair the loop pass could bridge, with its route length when the list was made.
class LoopCandidate:
	var a: OpenDoor
	var b: OpenDoor
	## Positions of a and b in the placement-ordered door list: the tie-break after length.
	var first: int
	var second: int
	var length: int


## A placed door nothing is attached to yet.
class OpenDoor:
	var placement: Placement
	var index: int
	var cell: Vector2i
	var dir: int
