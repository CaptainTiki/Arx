class_name DungeonGenerator
extends Node
## Builds a floor from prefab rooms by attaching them door to door on a 4 m grid.
## Plans the whole layout as data first (restarts are free), then instantiates it. The plan runs in
## three passes: a main path START -> EXIT, branches off its spare doors (some of them aimed at a far
## room's door, closing a loop when they get close), then loop-backs: short corridors routed through
## empty cells between whatever unused doors of far-apart rooms are left close together.
## Rooms never touch rooms: every link is room -> hall -> room, where a hall is a chain of 1 to
## max_hall_pieces connector pieces that bends round whatever is in the way (see _grow_link).
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
## Placement tries that fail on overlap before this layout is abandoned (then restarted). Every
## template and entry door a hall or room tries counts: at the defaults a floor spends about 320
## (1,240 at worst over 1000 seeds), so this is twice the worst and never binds.
@export var max_attempts: int = 2500
## 0 = random every generate; nonzero = reproducible.
@export var seed_value: int = 0

@export_group("Shape")
## Rooms (not connectors) between START and EXIT, counting neither. The exit is always this + 1 rooms deep.
@export var main_path_length: int = 12
## Branches each floor tries to grow off the main path, rolled per floor between these two. Only a
## branch that placed at least one room counts; one that places nothing makes way for the next door.
@export var branch_count_min: int = 4
@export var branch_count_max: int = 6
## Rooms (not connectors) per branch, at most.
@export var max_branch_depth: int = 6
## Hard ceiling on rooms (not connectors), START and EXIT included. A safety stop for big presets;
## it shouldn't bind at the defaults.
@export var max_rooms: int = 64
## Most connector pieces in one hall (the chain between two rooms). A hall starts at 1 or 2 pieces
## and extends one piece at a time, up to this, while no room fits on its end.
@export var max_hall_pieces: int = 4
## Connectors an extending hall tries, in this order, before any others: bends first, so a blocked
## hall turns round the obstacle instead of running straight into it.
@export var hall_extend_order: PackedStringArray = ["Corridor_L", "Corridor_Straight", "Corridor_T", "Corridor_4", "Corridor_2"]
## Chance a room slot (main path or branch) is a treasure room.
@export_range(0.0, 1.0) var treasure_chance: float = 0.15
@export var max_treasure_per_floor: int = 2
## Chance each loop candidate (see below) gets bridged, shortest route first.
@export_range(0.0, 1.0) var loop_chance: float = 0.6
## Longest loop bridge, in cells, an aimed branch's closing bridge included.
@export var max_loop_length: int = 10
## Fewest rooms (not connectors) you'd walk through to get between two rooms before a bridge may
## join them. 1 = neighbours; 3 = you went somewhere and came back.
@export var loop_min_separation: int = 3
## How much the main path prefers doors (and room turns) that face back toward START, so it curls
## round instead of marching away. 0 = no preference. Branches never curl. Off by default: it pulls
## the exit closer but didn't raise the loop rate, and costs restarts (see NOTES, step 7.1).
@export_range(0.0, 1.0) var main_path_curl: float = 0.0
## Chance a branch off the main path is aimed: it picks the nearest free door on a room at least
## loop_min_separation rooms away, grows toward it, and closes the loop with a bridge (at most
## max_loop_length cells) as soon as one fits. Otherwise, or with no such door, a normal branch.
@export_range(0.0, 1.0) var aimed_branch_chance: float = 0.6
## How hard an aimed branch steers toward its target (the weighting curl uses). 0 = it doesn't steer.
@export var aim_strength: float = 1.0
## Fresh-seed restarts when the main path boxes itself in, before giving up loudly. A 12-room main
## path boxes itself in about 1 seed in 5; 1 seed in 1000 needed 5 restarts, so 10 leaves headroom.
@export var max_restarts: int = 10
## Refuse any cell with grid y below this. The camp sits north of the start room's wall (y < 0),
## so the castle grows south and nothing pokes out into the yard.
@export var min_grid_y: int = -1000000
## Whether the START room's player spawn moves the player. Off when the player walks in from camp.
@export var place_player: bool = true
## A START room that already lives under `dungeon` and is never freed: the entrance hall the gate
## opens into. When set, placement 0 reuses it instead of instancing one. Its scene must be the
## catalog's START template.
@export var entrance_room: Room

## Fired by generate_async when the last room is in and the spawns are rolled.
signal floor_ready
## Print a timing breakdown of each build phase (plan, room batches, spawns, torches).
@export var profile_build: bool = false


func _ready() -> void:
	if entrance_room:
		for door: Door in entrance_room.get_doors():
			if door.plug_scene and door.get_child_count() == 0:
				door.add_child(door.plug_scene.instantiate())

@export_group("Scene")
## Rooms are added here. Also the noise hub every spawned enemy gets, and the owner of the map.
@export var dungeon: Dungeon
## Enemies and pickups are added here. Must be a child of `dungeon`; it survives regeneration.
@export var spawned: Node3D
@export var player: Player
## Instantiated for WEAPON spawn points.
@export var pickup_scene: PackedScene
## Instantiated for CHEST spawn points; the rolled row's ChestData goes on it.
@export var chest_scene: PackedScene
## Instantiated for ENEMY rows rolled from a table; the row's EnemyData is set on it.
@export var enemy_scene: PackedScene
## Print every spawn decision after the seed line, e.g. "room 4 (CombatRoom_B) spawn 1 → skitterer".
@export var print_spawn_log: bool = true

## Seed of the layout currently built. Put it in seed_value (or press F6) to rebuild exactly this floor.
var last_seed: int = 0
## One line per spawn point of the current floor, in build order. Same seed = same lines.
var last_spawn_log: PackedStringArray = []
## What the most recent plan's passes did beyond the placements: halls, loop candidates, aimed branches.
var last_stats: PlanStats = PlanStats.new()
## For the tests: every failed link checks that taking its hall back out left the layout exactly as
## it found it (PlanStats.unplace_checked / unplace_leaks). Off in the game; it copies the layout.
var verify_unplace: bool = false

## Room.Type -> Array of RoomTemplate.
var _templates: Dictionary[int, Array] = {}


## Throws away the current floor and builds a new one. `forced_seed` (nonzero) overrides seed_value,
## e.g. last_seed to rebuild the same floor.
## Builds a whole floor this frame. Tools and tests use this; the game uses generate_async.
func generate(forced_seed: int = 0) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var plan: Array[Placement] = _plan_with_restarts(forced_seed, rng)
	if plan.is_empty():
		return
	_clear()
	_begin_build()
	_instance_rooms(plan, 0, plan.size())
	# The same RNG carries on from planning into the spawn rolls, so the seed fixes both.
	_finish_build(plan, rng)
	dungeon.set_plan(plan, last_seed)


## Same floor, spread over frames: `rooms_per_frame` rooms go in, then a frame passes. Adding a CSG
## room to the tree bakes it on the main thread, so this is what keeps the gate theatre smooth.
## Awaitable; also emits floor_ready.
func generate_async(forced_seed: int = 0, rooms_per_frame: int = 6, spawns_per_frame: int = 4) -> void:
	var t0: int = Time.get_ticks_usec()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Template metadata is read from off-tree instances, so it loads here on the main thread; the
	# plan itself is pure arithmetic over that and runs on a worker thread while frames keep going.
	_load_templates()
	var planner: Thread = Thread.new()
	planner.start(_plan_with_restarts.bind(forced_seed, rng))
	while planner.is_alive():
		await get_tree().process_frame
	var plan: Array[Placement] = planner.wait_to_finish()
	var t_plan: int = Time.get_ticks_usec()
	if plan.is_empty():
		floor_ready.emit()
		return
	_clear()
	var t_clear: int = Time.get_ticks_usec()
	_begin_build()
	var batches: PackedStringArray = []
	var i: int = 0
	while i < plan.size():
		var end: int = mini(i + maxi(rooms_per_frame, 1), plan.size())
		var tb: int = Time.get_ticks_usec()
		_instance_rooms(plan, i, end)
		batches.append("%d-%d: %.1f" % [i, end - 1, (Time.get_ticks_usec() - tb) / 1000.0])
		i = end
		await get_tree().process_frame
	var t_rooms: int = Time.get_ticks_usec()
	await _finish_build_async(plan, rng, spawns_per_frame)
	var t_spawn: int = Time.get_ticks_usec()
	dungeon.set_plan(plan, last_seed)
	var t_done: int = Time.get_ticks_usec()
	if profile_build:
		print("Build profile (ms): plan %.1f, clear %.1f, rooms %.1f over %d batches, spawns %.1f, set_plan/torches %.1f, total %.1f" % [
			(t_plan - t0) / 1000.0, (t_clear - t_plan) / 1000.0, (t_rooms - t_clear) / 1000.0, batches.size(),
			(t_spawn - t_rooms) / 1000.0, (t_done - t_spawn) / 1000.0, (t_done - t0) / 1000.0])
		print("  room batches (ms, wall time incl. the frame they ran in): " + ", ".join(batches))
	floor_ready.emit()


func _plan_with_restarts(forced_seed: int, rng: RandomNumberGenerator) -> Array[Placement]:
	var base_seed: int = forced_seed if forced_seed != 0 else (seed_value if seed_value != 0 else randi())
	var plan: Array[Placement] = []
	for restart: int in max_restarts + 1:
		var run_seed: int = base_seed + restart * 7919
		rng.seed = run_seed
		plan = _plan(rng)
		if not plan.is_empty():
			last_seed = run_seed
			print("Dungeon seed %d: %s%s" % [run_seed, describe_plan(plan, last_stats), " (after %d restart(s))" % restart if restart > 0 else ""])
			return plan
		print("Dungeon seed %d: main path boxed itself in, restarting" % run_seed)
	push_error("DungeonGenerator: no main path reached an exit after %d restarts from seed %d. The catalog needs more multi-door rooms, or raise max_attempts." % [max_restarts, base_seed])
	return plan


## Pure layout for one seed: no nodes are placed. Empty if the main path boxed itself in.
func plan_layout(run_seed: int) -> Array[Placement]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = run_seed
	return _plan(rng)


## One-line shape summary, e.g. "main 12, branches 5/5 (depths 6,2,4,1,6), aimed 3 (closed 1),
## halls 41 (mean 1.6, 7 extended, 3 capped), loops 2 (len 4, 9), treasure at depths [3, 8],
## candidates 4". Without `stats` the branch part is counted from the plan ("branches 4 (max depth
## 3)") and the aimed, hall and candidate parts are left out.
static func describe_plan(plan: Array[Placement], stats: PlanStats = null) -> String:
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
	if stats == null:
		return "main %d, branches %d (max depth %d), %s, treasure at depths %s" % [main, branches, deepest, loops, treasure]
	var depths: PackedStringArray = []
	for depth: int in stats.branch_depths:
		depths.append(str(depth))
	var hall_pieces: int = 0
	for pieces: int in stats.hall_lengths:
		hall_pieces += pieces
	return "main %d, branches %d/%d (depths %s), aimed %d (closed %d), halls %d (mean %.1f, %d extended, %d capped), %s, treasure at depths %s, candidates %d" % [
		main, stats.branch_depths.size(), stats.branches_wanted, ",".join(depths), stats.aimed, stats.aimed_closed,
		stats.hall_lengths.size(), float(hall_pieces) / maxi(stats.hall_lengths.size(), 1), stats.halls_extended, stats.links_capped,
		loops, treasure, stats.loop_candidates]


func _plan(rng: RandomNumberGenerator) -> Array[Placement]:
	_load_templates()
	last_stats = PlanStats.new()
	var layout: Layout = Layout.new()
	layout.rng = rng
	var reached_exit: bool = _plan_main_path(layout)
	layout.stats.attempts = layout.attempts
	last_stats = layout.stats
	if not reached_exit:
		var failed: Array[Placement] = []
		return failed
	_plan_branches(layout)
	_plan_loops(layout)
	layout.stats.attempts = layout.attempts
	return layout.placements


## START -> hall -> R -> hall -> R ... -> hall -> EXIT, with main_path_length rooms R. Each step
## tries the current room's free doors until a link takes. False if it boxed itself in.
func _plan_main_path(layout: Layout) -> bool:
	var start: RoomTemplate = _pick_template(layout, Room.Type.START, 0)
	var current: Placement = _place(layout, start, Vector2i.ZERO, 0, null, -1)
	current.main_path = true
	layout.start_center = Vector2(current.grid_origin) + Vector2(rotated_footprint(start.footprint, 0)) * 0.5
	for slot: int in main_path_length + 1:
		var exit: bool = slot == main_path_length
		var type: int = Room.Type.EXIT if exit else _room_type(layout)
		if type == Room.Type.TREASURE and not _has_template(type, 2):
			# Every treasure room is a dead end (one door), so it can't be a link in the chain. It hangs
			# off one of this room's other doors on a hall of its own instead, as long as the room keeps
			# a door to carry on from, and doesn't use up a main-path slot.
			var doors: Array[OpenDoor] = _growable_doors(layout, current)
			if doors.size() >= 2:
				_grow_link(layout, doors[layout.rng.randi_range(0, doors.size() - 1)], type, 1)
			type = Room.Type.COMBAT
		var next: Placement = _link_from(layout, _unused_doors(current), type, 1 if exit else 2, main_path_curl, layout.start_center)
		if next == null:
			return false
		# The room and the hall that leads to it.
		var at: Placement = next
		while at != current:
			at.main_path = true
			at = at.parent
		current = next
	return true


## Branches off the main path's spare doors (its rooms' and its halls' T junctions'): chains of up to
## max_branch_depth rooms, each behind its own hall. Each floor rolls how many it wants
## (branch_count_min..max) and keeps starting branches until that many have placed a room, the
## spare doors run out, or max_rooms is hit. At aimed_branch_chance a branch is aimed: it steers
## toward a far room's free door and ends early by bridging to it (see _close_aimed).
func _plan_branches(layout: Layout) -> void:
	var straight: RoomTemplate = _template_named(LOOP_STUB)
	var corner: RoomTemplate = _template_named(LOOP_CORNER)
	layout.stats.branches_wanted = layout.rng.randi_range(mini(branch_count_min, branch_count_max), maxi(branch_count_min, branch_count_max))
	var spare: Array[OpenDoor] = []
	for placement: Placement in layout.placements:
		if placement.main_path:
			spare.append_array(_unused_doors(placement))
	_shuffle(layout.rng, spare)
	while layout.stats.branch_depths.size() < layout.stats.branches_wanted and not spare.is_empty() and layout.rooms < max_rooms:
		var start: OpenDoor = spare.pop_back()
		if start.placement.used_doors.has(start.index):
			# An aimed branch's bridge ended here.
			continue
		var target: OpenDoor = null
		# No roll at all at chance 0, so those floors match the ones built before aiming existed.
		if aimed_branch_chance > 0.0 and straight and corner and layout.rng.randf() < aimed_branch_chance:
			target = _pick_target(layout, start)
			if target == null:
				layout.stats.aimed_no_target += 1
		var aim: float = 0.0
		var toward: Vector2 = Vector2.ZERO
		if target:
			layout.stats.aimed += 1
			aim = aim_strength
			toward = Vector2(target.cell + Door.offset(target.dir)) + Vector2(0.5, 0.5)
		# Every piece and room the branch places, for _close_aimed.
		var branch: Array[Placement] = []
		var doors: Array[OpenDoor] = [start]
		var depth: int = 0
		var closed: bool = target != null and _close_aimed(layout, start, branch, target, straight, corner)
		while not closed and not doors.is_empty() and depth < max_branch_depth and layout.rooms < max_rooms:
			var type: int = _room_type(layout)
			# An aimed branch has to keep a way on, so no one-door rooms (the treasure room) for it.
			if target and not _has_template(type, 2):
				type = Room.Type.COMBAT
			var placed_before: int = layout.placements.size()
			var room: Placement = _link_from(layout, doors, type, 2 if target else 1, aim, toward)
			if room == null:
				break
			# A failed link takes its pieces back out, so everything past placed_before is this link.
			branch.append_array(layout.placements.slice(placed_before))
			depth += 1
			# The branch carries on through one of the new room's other doors (whichever links first).
			doors = _unused_doors(room)
			closed = target != null and _close_aimed(layout, start, branch, target, straight, corner)
		if depth > 0:
			layout.stats.branch_depths.append(depth)
		if target:
			layout.stats.aimed_pieces.append(branch.size())
			if closed:
				layout.stats.aimed_closed += 1
			elif depth >= max_branch_depth:
				layout.stats.aimed_gave_up += 1
			elif layout.rooms >= max_rooms:
				layout.stats.aimed_out_of_rooms += 1
			elif doors.is_empty():
				layout.stats.aimed_dead_end += 1
			else:
				layout.stats.aimed_blocked += 1
	layout.stats.hit_max_rooms = layout.rooms >= max_rooms


## Tries `doors` in random order (or, with `bias`, favouring doors that face `toward`), growing a
## link from each one that can still grow, and returns the first room that took. Null if none did;
## every door that failed is capped by then.
func _link_from(layout: Layout, doors: Array[OpenDoor], type: int, min_doors: int, bias: float, toward: Vector2) -> Placement:
	var order: Array[OpenDoor] = doors.duplicate()
	if bias > 0.0:
		var weights: Array[float] = []
		for door: OpenDoor in doors:
			weights.append(_bias_weight(bias, _faces(toward, door.cell, door.dir)))
		order.clear()
		for index: int in _weighted_order(layout.rng, weights):
			order.append(doors[index])
	else:
		_shuffle(layout.rng, order)
	for door: OpenDoor in order:
		if not _can_grow(layout, door):
			continue
		var room: Placement = _grow_link(layout, door, type, min_doors, bias, toward)
		if room:
			return room
	return null


## One link: a hall from `from`, then a room of `type` (with at least `min_doors` doors) on its far
## end. The hall starts as 1 or 2 connectors picked by weight. While no room fits on its end it
## extends one piece at a time, up to max_hall_pieces, trying bends first so it steers round
## whatever is in the way. If no room ever fits, every piece is taken back out and `from` is capped:
## never grown from again, and plugged at build unless a loop bridge ends there. Null then.
func _grow_link(layout: Layout, from: OpenDoor, type: int, min_doors: int, bias: float = 0.0, toward: Vector2 = Vector2.ZERO) -> Placement:
	layout.stats.links += 1
	var snapshot: LayoutSnapshot = LayoutSnapshot.take(layout, from) if verify_unplace else null
	var pieces: Array[Placement] = []
	var frontier: OpenDoor = from
	var extended: bool = false
	for i: int in mini(layout.rng.randi_range(1, 2), max_hall_pieces):
		var next: OpenDoor = _add_connector(layout, frontier, pieces, false, bias, toward)
		if next == null:
			break
		frontier = next
	# No pieces means not even the first one fit; a room straight on `from` would touch a room.
	while not pieces.is_empty():
		var room: Placement = _try_room(layout, frontier, type, min_doors, bias, toward)
		if room:
			layout.stats.hall_lengths.append(pieces.size())
			if extended:
				layout.stats.halls_extended += 1
			return room
		if pieces.size() >= max_hall_pieces:
			break
		var next: OpenDoor = _add_connector(layout, frontier, pieces, true, bias, toward)
		if next == null:
			break
		extended = true
		frontier = next
	for k: int in range(pieces.size() - 1, -1, -1):
		_unplace(layout, pieces[k])
	from.placement.capped_doors.append(from.index)
	layout.stats.links_capped += 1
	if extended:
		layout.stats.capped_after_extend += 1
	if snapshot:
		layout.stats.unplace_checked += 1
		if not snapshot.matches(layout, from):
			layout.stats.unplace_leaks += 1
	return null


## Adds one connector to a hall on `door`: by weight, or on an extend step in hall_extend_order
## first. Every template and entry door is tried until one fits with an exit onto an empty cell (a
## piece with no way on would be a dead end). Returns the exit the hall carries on through; a T's
## other exit stays free for a branch or a bridge. Null if nothing fits.
func _add_connector(layout: Layout, door: OpenDoor, pieces: Array[Placement], extend: bool, bias: float, toward: Vector2) -> OpenDoor:
	var neighbor: Vector2i = door.cell + Door.offset(door.dir)
	var options: Array[RoomTemplate] = []
	var weights: Array[float] = []
	for template: RoomTemplate in _templates.get(Room.Type.CORRIDOR, []):
		if template.is_connector and _allowed(layout, template, door.placement.depth, 2):
			options.append(template)
			weights.append(template.weight)
	var order: Array[RoomTemplate] = []
	if extend:
		for template_name: String in hall_extend_order:
			for template: RoomTemplate in options:
				if template.name == template_name:
					order.append(template)
		for template: RoomTemplate in options:
			if not order.has(template):
				order.append(template)
	else:
		for index: int in _weighted_order(layout.rng, weights):
			order.append(options[index])
	for template: RoomTemplate in order:
		for entry: int in _entry_order(layout, door, template, bias, toward):
			if layout.attempts >= max_attempts:
				return null
			var turns: int = posmod(Door.opposite_of(door.dir) - template.door_dirs[entry], 4)
			var origin: Vector2i = neighbor - rotate_cell(template.door_cells[entry], template.footprint, turns)
			if not _fits(origin, rotated_footprint(template.footprint, turns), layout.occupied, min_grid_y):
				layout.attempts += 1
				continue
			var exits: Array[int] = []
			for index: int in template.door_dirs.size():
				var cell: Vector2i = origin + rotate_cell(template.door_cells[index], template.footprint, turns)
				if index != entry and not layout.occupied.has(cell + Door.offset(Door.rotated(template.door_dirs[index], turns))):
					exits.append(index)
			if exits.is_empty():
				layout.attempts += 1
				continue
			var piece: Placement = _place(layout, template, origin, turns, door, entry)
			pieces.append(piece)
			var exit: int = exits[0]
			if exits.size() > 1:
				if bias > 0.0:
					var exit_weights: Array[float] = []
					for index: int in exits:
						exit_weights.append(_bias_weight(bias, _faces(toward, piece.door_cell(index), piece.door_dir(index))))
					exit = exits[_weighted_pick(layout.rng, exit_weights)]
				else:
					exit = exits[layout.rng.randi_range(0, exits.size() - 1)]
			return _open_door(piece, exit)
	return null


## The room on a hall's end: every template of `type` allowed here, in a weighted random order, at
## every entry door (random order, or with `bias` favouring turns that face `toward`). The first
## that fits is placed. Null if none fits.
func _try_room(layout: Layout, door: OpenDoor, type: int, min_doors: int, bias: float, toward: Vector2) -> Placement:
	var neighbor: Vector2i = door.cell + Door.offset(door.dir)
	var options: Array[RoomTemplate] = []
	var weights: Array[float] = []
	for template: RoomTemplate in _templates.get(type, []):
		if _allowed(layout, template, door.placement.depth + 1, min_doors):
			options.append(template)
			weights.append(template.weight)
	for index: int in _weighted_order(layout.rng, weights):
		var template: RoomTemplate = options[index]
		for entry: int in _entry_order(layout, door, template, bias, toward):
			if layout.attempts >= max_attempts:
				return null
			var turns: int = posmod(Door.opposite_of(door.dir) - template.door_dirs[entry], 4)
			var origin: Vector2i = neighbor - rotate_cell(template.door_cells[entry], template.footprint, turns)
			if not _fits(origin, rotated_footprint(template.footprint, turns), layout.occupied, min_grid_y):
				layout.attempts += 1
				continue
			return _place(layout, template, origin, turns, door, entry)
	return null


## The order to try a template's doors as the one meeting `door`: a plain shuffle, or with `bias`
## a weighted one where an entry scores by the best of the template's other doors (as they'd end up
## placed) at pointing toward `toward`, so the growth can turn.
func _entry_order(layout: Layout, door: OpenDoor, template: RoomTemplate, bias: float, toward: Vector2) -> Array[int]:
	var entries: Array[int] = []
	for entry: int in template.door_dirs.size():
		entries.append(entry)
	if bias <= 0.0:
		_shuffle(layout.rng, entries)
		return entries
	var neighbor: Vector2i = door.cell + Door.offset(door.dir)
	var weights: Array[float] = []
	for entry: int in entries:
		var turns: int = posmod(Door.opposite_of(door.dir) - template.door_dirs[entry], 4)
		var origin: Vector2i = neighbor - rotate_cell(template.door_cells[entry], template.footprint, turns)
		var best: float = 0.0
		var first: bool = true
		for other: int in template.door_dirs.size():
			if other == entry:
				continue
			var cell: Vector2i = origin + rotate_cell(template.door_cells[other], template.footprint, turns)
			var score: float = _faces(toward, cell, Door.rotated(template.door_dirs[other], turns))
			best = score if first else maxf(best, score)
			first = false
		weights.append(_bias_weight(bias, best))
	return _weighted_order(layout.rng, weights)


## An aimed branch's goal: the free door on a room (not a connector) at least loop_min_separation
## rooms from where the branch starts, nearest the start door on the grid. Its outside cell must be
## empty so a bridge can end there. Ties go to placement order, then door order. Null if none.
func _pick_target(layout: Layout, start: OpenDoor) -> OpenDoor:
	_rebuild_links(layout)
	var separation: Dictionary[Placement, int] = _separations(layout, start.placement)
	var from: Vector2i = start.cell + Door.offset(start.dir)
	var best: OpenDoor = null
	var best_distance: int = UNREACHABLE
	for placement: Placement in layout.placements:
		if placement.template.is_connector or separation.get(placement, UNREACHABLE) < loop_min_separation:
			continue
		for door: OpenDoor in _unused_doors(placement):
			var outside: Vector2i = door.cell + Door.offset(door.dir)
			if layout.occupied.has(outside):
				continue
			var distance: int = absi(outside.x - from.x) + absi(outside.y - from.y)
			if distance < best_distance:
				best = door
				best_distance = distance
	return best


## Closes an aimed branch if it can: of the branch's free doors (the start door included, until
## something attaches there), those whose routed bridge to the target fits in max_loop_length cells
## between rooms still loop_min_separation apart, lays the shortest. True if it laid one.
func _close_aimed(layout: Layout, start: OpenDoor, branch: Array[Placement], target: OpenDoor, straight: RoomTemplate, corner: RoomTemplate) -> bool:
	if target.placement.used_doors.has(target.index):
		return false
	var goal: Vector2i = target.cell + Door.offset(target.dir)
	var doors: Array[OpenDoor] = []
	if not start.placement.used_doors.has(start.index):
		doors.append(start)
	for placement: Placement in branch:
		doors.append_array(_unused_doors(placement))
	var best_door: OpenDoor = null
	var best_route: Array[Vector2i] = []
	var linked: bool = false
	for door: OpenDoor in doors:
		var from: Vector2i = door.cell + Door.offset(door.dir)
		# A route of n cells spans at most n - 1 steps; skip the search when it can't fit.
		if absi(goal.x - from.x) + absi(goal.y - from.y) + 1 > max_loop_length:
			continue
		var route: Array[Vector2i] = _route(layout, door, target)
		if route.is_empty() or (best_door and route.size() >= best_route.size()):
			continue
		if not linked:
			_rebuild_links(layout)
			linked = true
		if _separations(layout, door.placement).get(target.placement, UNREACHABLE) < loop_min_separation:
			continue
		best_door = door
		best_route = route
	if best_door == null:
		return false
	_lay_bridge(layout, best_door, target, best_route, straight, corner)
	return true


## Bridges unused doors on rooms at least loop_min_separation rooms apart with a corridor routed
## through empty cells: one 1x1 piece per cell (straight or corner), at most max_loop_length cells.
## Candidates are tried shortest route first, ties in placement order, each at loop_chance. This is
## what turns the tree into a graph. Capped doors count: a bridge needs far less room than a hall.
func _plan_loops(layout: Layout) -> void:
	var straight: RoomTemplate = _template_named(LOOP_STUB)
	var corner: RoomTemplate = _template_named(LOOP_CORNER)
	if straight == null or corner == null:
		push_warning("DungeonGenerator: %s or %s is missing from the catalog; floors will have no loops." % [LOOP_STUB, LOOP_CORNER])
		return
	_rebuild_links(layout)
	# Unused doors opening onto empty cells, in placement order (then door order): the tie-break order.
	var doors: Array[OpenDoor] = []
	for placement: Placement in layout.placements:
		for door: OpenDoor in _unused_doors(placement):
			if not layout.occupied.has(door.cell + Door.offset(door.dir)):
				doors.append(door)
	var candidates: Array[LoopCandidate] = []
	for i: int in doors.size():
		var separation: Dictionary[Placement, int] = _separations(layout, doors[i].placement)
		var from: Vector2i = doors[i].cell + Door.offset(doors[i].dir)
		for j: int in range(i + 1, doors.size()):
			var to: Vector2i = doors[j].cell + Door.offset(doors[j].dir)
			# A route of n cells spans at most n - 1 steps; skip the search when it can't fit.
			if absi(to.x - from.x) + absi(to.y - from.y) + 1 > max_loop_length:
				continue
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
	layout.stats.loop_candidates = candidates.size()
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
## far (parents and bridges). Connectors are free, so rooms one hall apart are 1 apart.
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
	var via: OpenDoor = a
	var piece: Placement = null
	for k: int in route.size():
		var back: int = Door.opposite_of(a.dir) if k == 0 else _dir_to(route[k], route[k - 1])
		var ahead: int = Door.opposite_of(b.dir) if k == route.size() - 1 else _dir_to(route[k], route[k + 1])
		var template: RoomTemplate = straight if back == Door.opposite_of(ahead) else corner
		# Straight (N, S): one turn makes it E, W. Corner (N, E): t turns open sides t and t + 1.
		var turns: int = back % 2
		if template == corner:
			turns = back if posmod(ahead - back, 4) == 1 else ahead
		piece = _place(layout, template, route[k], turns, via, _door_facing(template, turns, back))
		piece.loop = true
		piece.bridge_id = layout.bridges
		_link(layout, via.placement, piece)
		via = _open_door(piece, _door_facing(template, turns, ahead))
	piece.used_doors.append(via.index)
	b.placement.used_doors.append(b.index)
	piece.bridge_end = b.placement
	_link(layout, piece, b.placement)


## Who connects to whom right now: every parent link, plus each bridge's far end.
static func _rebuild_links(layout: Layout) -> void:
	layout.links.clear()
	for placement: Placement in layout.placements:
		if placement.parent:
			_link(layout, placement, placement.parent)
		if placement.bridge_end:
			_link(layout, placement, placement.bridge_end)


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


## How squarely a door on `cell` facing `dir` points at `toward` (cells): 1 straight at it, -1 away.
static func _faces(toward: Vector2, cell: Vector2i, dir: int) -> float:
	var to: Vector2 = toward - (Vector2(cell) + Vector2(0.5, 0.5))
	return Vector2(Door.offset(dir)).dot(to.normalized())


static func _bias_weight(bias: float, score: float) -> float:
	# Clamped so nothing becomes impossible.
	return maxf(0.1, 1.0 + bias * score)


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


## TREASURE at treasure_chance while under the floor cap, else COMBAT.
func _room_type(layout: Layout) -> int:
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


## Adds `template` to the layout with its rotated footprint's min corner on `origin`, hanging off
## `via` (null for START) by its own door `entry`. Marks `via` used and counts the placement.
func _place(layout: Layout, template: RoomTemplate, origin: Vector2i, turns: int, via: OpenDoor, entry: int) -> Placement:
	var placement: Placement = Placement.new()
	placement.template = template
	placement.grid_origin = origin
	placement.turns = turns
	if via:
		via.placement.used_doors.append(via.index)
		placement.parent = via.placement
		placement.parent_door = via.index
		# Depth counts rooms, not connectors: a connector sits at its parent's depth.
		placement.depth = via.placement.depth + (0 if template.is_connector else 1)
	if entry >= 0:
		placement.used_doors.append(entry)
	for cell: Vector2i in placement.cells():
		layout.occupied[cell] = placement
	layout.placements.append(placement)
	layout.count(placement)
	return placement


## Takes the most recent placement back out: the exact reverse of _place (cells freed, the parent's
## door free again, the counts undone).
func _unplace(layout: Layout, placement: Placement) -> void:
	assert(layout.placements.back() == placement, "_unplace takes placements out in reverse order")
	layout.placements.pop_back()
	for cell: Vector2i in placement.cells():
		layout.occupied.erase(cell)
	if placement.parent:
		placement.parent.used_doors.erase(placement.parent_door)
	layout.uncount(placement)


## A weighted pick among the templates of `type` allowed at `depth` (see _allowed). Null if none is.
func _pick_template(layout: Layout, type: int, depth: int, min_doors: int = 1) -> RoomTemplate:
	var options: Array[RoomTemplate] = []
	var weights: Array[float] = []
	for template: RoomTemplate in _templates.get(type, []):
		if _allowed(layout, template, depth, min_doors):
			options.append(template)
			weights.append(template.weight)
	if options.is_empty():
		return null
	return options[_weighted_pick(layout.rng, weights)]


## The placement rules: weight above 0, at least `min_doors` doors, deep enough
## (min_depth_from_start) and not used up (max_per_floor).
func _allowed(layout: Layout, template: RoomTemplate, depth: int, min_doors: int) -> bool:
	if template.weight <= 0.0 or template.door_dirs.size() < min_doors or depth < template.min_depth_from_start:
		return false
	return template.max_per_floor <= 0 or layout.placed.get(template.name, 0) < template.max_per_floor


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


## The placement's doors nothing is attached to, as OpenDoors. Capped ones included.
static func _unused_doors(placement: Placement) -> Array[OpenDoor]:
	var doors: Array[OpenDoor] = []
	for index: int in placement.template.door_dirs.size():
		if not placement.used_doors.has(index):
			doors.append(_open_door(placement, index))
	return doors


## The placement's doors a link could still grow from: unused, not capped, opening onto an empty cell.
static func _growable_doors(layout: Layout, placement: Placement) -> Array[OpenDoor]:
	var doors: Array[OpenDoor] = []
	for door: OpenDoor in _unused_doors(placement):
		if _can_grow(layout, door):
			doors.append(door)
	return doors


static func _can_grow(layout: Layout, door: OpenDoor) -> bool:
	return not door.placement.used_doors.has(door.index) and not door.placement.capped_doors.has(door.index) \
		and not layout.occupied.has(door.cell + Door.offset(door.dir))


static func _open_door(placement: Placement, index: int) -> OpenDoor:
	var door: OpenDoor = OpenDoor.new()
	door.placement = placement
	door.index = index
	door.cell = placement.door_cell(index)
	door.dir = placement.door_dir(index)
	return door


## Fisher-Yates with the plan's own RNG. Array.shuffle() would use the global one and break seeds.
static func _shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


static func _fits(origin: Vector2i, size: Vector2i, occupied: Dictionary[Vector2i, Placement], min_y: int = -1000000) -> bool:
	if origin.y < min_y:
		return false
	for z: int in size.y:
		for x: int in size.x:
			if occupied.has(origin + Vector2i(x, z)):
				return false
	return true


## Throws away the current floor (rooms, spawned enemies, drops). Public so Main can empty the
## castle when the player leaves it.
func clear() -> void:
	_clear()
	dungeon.map = null


func _clear() -> void:
	for child: Node in dungeon.get_children():
		if child == spawned:
			continue
		if child == entrance_room:
			# Stays. With no floor behind it, every doorway gets a plug so it's a closed room.
			for door: Door in entrance_room.get_doors():
				door.used = false
				_strip_plugs(door)
				if door.plug_scene:
					door.add_child(door.plug_scene.instantiate())
			continue
		dungeon.remove_child(child)
		child.queue_free()
	for child: Node in spawned.get_children():
		spawned.remove_child(child)
		child.queue_free()


## Rooms of the floor in plan order, filled by _instance_rooms during a build.
var _rooms: Array[Room] = []


func _begin_build() -> void:
	_rooms.clear()


## Instances plan[from..to) into the dungeon. Placement 0 reuses `entrance_room` when it's set.
func _instance_rooms(plan: Array[Placement], from: int, to: int) -> void:
	for i: int in range(from, to):
		var placement: Placement = plan[i]
		var room: Room
		if i == 0 and entrance_room:
			room = entrance_room
			for door: Door in room.get_doors():
				_strip_plugs(door)  # _finish_build re-plugs whichever stay unused
		else:
			room = placement.template.scene.instantiate() as Room
			room.name = "%02d_%s" % [i, placement.template.name]
		room.grid_origin = placement.grid_origin
		room.turns = placement.turns
		room.transform = placement_transform(placement.grid_origin, placement.template.footprint, placement.turns)
		if room != entrance_room:
			dungeon.add_child(room)
		var doors: Array[Door] = room.get_doors()
		for index: int in placement.used_doors:
			doors[index].used = true
		_rooms.append(room)


func _strip_plugs(door: Door) -> void:
	for plug: Node in door.get_children():
		door.remove_child(plug)
		plug.queue_free()


## Door plugs and spawn rolls, once every room is in.
func _finish_build(plan: Array[Placement], rng: RandomNumberGenerator) -> void:
	_plug_doors()
	last_spawn_log.clear()
	for room_index: int in _rooms.size():
		_spawn_room(plan, room_index, rng)
	if print_spawn_log:
		for line: String in last_spawn_log:
			print("  " + line)


## Same, with a frame between every `spawns_per_frame` spawn points. Enemy scenes are the heavy
## instances (several ms each), so the spread counts points, not rooms.
func _finish_build_async(plan: Array[Placement], rng: RandomNumberGenerator, spawns_per_frame: int) -> void:
	# Plugs are CSG too: a dozen a frame.
	var since_frame: int = 0
	for room: Room in _rooms:
		for door: Door in room.get_doors():
			if not door.used and door.plug_scene:
				door.add_child(door.plug_scene.instantiate())
				since_frame += 1
				if since_frame >= 12:
					since_frame = 0
					await get_tree().process_frame
	last_spawn_log.clear()
	since_frame = 0
	for room_index: int in _rooms.size():
		var room: Room = _rooms[room_index]
		var spawns: Array[SpawnPoint] = room.get_spawn_points()
		for spawn_index: int in spawns.size():
			var outcome: String = _spawn(spawns[spawn_index], rng)
			last_spawn_log.append("room %d (%s) spawn %d → %s" % [room_index, plan[room_index].template.name, spawn_index, outcome])
			since_frame += 1
			if since_frame >= maxi(spawns_per_frame, 1):
				since_frame = 0
				await get_tree().process_frame
	if print_spawn_log:
		for line: String in last_spawn_log:
			print("  " + line)


func _plug_doors() -> void:
	for room: Room in _rooms:
		for door: Door in room.get_doors():
			if not door.used and door.plug_scene:
				# Child of the marker = exactly at the marker's transform, and freed with the room.
				door.add_child(door.plug_scene.instantiate())


## Rolls every spawn point of one room.
func _spawn_room(plan: Array[Placement], room_index: int, rng: RandomNumberGenerator) -> void:
	var room: Room = _rooms[room_index]
	var spawns: Array[SpawnPoint] = room.get_spawn_points()
	for spawn_index: int in spawns.size():
		var outcome: String = _spawn(spawns[spawn_index], rng)
		last_spawn_log.append("room %d (%s) spawn %d → %s" % [room_index, plan[room_index].template.name, spawn_index, outcome])


## Places what one spawn point produces and returns a short description for the log.
## Table first (a "nothing" row places nothing); no table = step-3 fixed fallback.
func _spawn(spawn: SpawnPoint, rng: RandomNumberGenerator) -> String:
	var local: Transform3D = spawned.global_transform.affine_inverse() * spawn.global_transform
	if spawn.kind == SpawnPoint.Kind.PLAYER:
		if place_player:
			player.place_at(spawn.global_transform)
		return "player"
	if spawn.table:
		var entry: SpawnEntry = spawn.table.roll(rng)
		if entry == null or entry.payload_for(spawn.kind) == null:
			return "nothing"
		match spawn.kind:
			SpawnPoint.Kind.ENEMY:
				var rolled: Enemy = enemy_scene.instantiate() as Enemy
				rolled.data = entry.enemy
				rolled.dungeon = dungeon
				rolled.transform = local
				spawned.add_child(rolled)
			SpawnPoint.Kind.BREAKABLE:
				_place_breakable(local, entry.scene)
			SpawnPoint.Kind.CHEST:
				var chest: Chest = chest_scene.instantiate() as Chest
				chest.data = entry.chest
				chest.dungeon = dungeon
				chest.transform = local
				spawned.add_child(chest)
			_:
				_place_pickup(local, entry.item)
		return entry.describe(spawn.kind)
	match spawn.kind:
		SpawnPoint.Kind.ENEMY:
			var enemy: Node3D = spawn.fixed_scene.instantiate() as Node3D
			if enemy is Enemy:
				(enemy as Enemy).dungeon = dungeon
			enemy.transform = local
			spawned.add_child(enemy)
		SpawnPoint.Kind.BREAKABLE:
			_place_breakable(local, spawn.fixed_scene)
		SpawnPoint.Kind.CHEST:
			# No fallback: a chest needs a table (the room's authoring check says so).
			return "nothing"
		_:
			_place_pickup(local, spawn.fixed_item)
			return "fixed %s" % spawn.fixed_item.display_name.to_lower()
	return "fixed %s" % spawn.fixed_scene.resource_path.get_file().get_basename()


func _place_pickup(local: Transform3D, item: ItemData) -> void:
	var pickup: Pickup = pickup_scene.instantiate() as Pickup
	pickup.transform = local
	spawned.add_child(pickup)
	pickup.set_item(item)


func _place_breakable(local: Transform3D, scene: PackedScene) -> void:
	var breakable: Node3D = scene.instantiate() as Node3D
	if breakable is Breakable:
		(breakable as Breakable).dungeon = dungeon
	breakable.transform = local
	spawned.add_child(breakable)


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
	## Doors a link failed to grow from: never tried again, plugged at build unless a bridge ends there.
	var capped_doors: Array[int] = []
	var parent: Placement
	## The parent's door this one hangs off; -1 for START.
	var parent_door: int = -1
	## Rooms (not connectors) between START and this one: START is 0, the exit main_path_length + 1.
	var depth: int = 0
	## On the START -> EXIT chain (its halls included).
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
	var stats: PlanStats = PlanStats.new()
	var bridges: int = 0

	func count(placement: Placement) -> void:
		placed[placement.template.name] = placed.get(placement.template.name, 0) + 1
		if not placement.template.is_connector:
			rooms += 1
		if placement.template.type == Room.Type.TREASURE:
			treasure += 1

	func uncount(placement: Placement) -> void:
		placed[placement.template.name] -= 1
		if placed[placement.template.name] == 0:
			placed.erase(placement.template.name)
		if not placement.template.is_connector:
			rooms -= 1
		if placement.template.type == Room.Type.TREASURE:
			treasure -= 1


## The parts of a Layout a failed link must leave as it found them, copied before the link starts.
class LayoutSnapshot:
	var occupied: Dictionary[Vector2i, Placement]
	var placements: int
	var placed: Dictionary[String, int]
	var rooms: int
	var treasure: int
	var from_used: Array[int]

	static func take(layout: Layout, from: OpenDoor) -> LayoutSnapshot:
		var snapshot: LayoutSnapshot = LayoutSnapshot.new()
		snapshot.occupied = layout.occupied.duplicate()
		snapshot.placements = layout.placements.size()
		snapshot.placed = layout.placed.duplicate()
		snapshot.rooms = layout.rooms
		snapshot.treasure = layout.treasure
		snapshot.from_used = from.placement.used_doors.duplicate()
		return snapshot

	func matches(layout: Layout, from: OpenDoor) -> bool:
		return layout.occupied == occupied and layout.placements.size() == placements and layout.placed == placed \
			and layout.rooms == rooms and layout.treasure == treasure and from.placement.used_doors == from_used


## What a plan's passes did beyond the placements themselves, for the log line and the tests.
class PlanStats:
	## Branches this floor rolled for (branch_count_min..max), and the room depth of each one that
	## placed a room, in the order they grew. Fewer depths than wanted = the spare doors ran out.
	var branches_wanted: int = 0
	var branch_depths: Array[int] = []
	## The branch pass stopped on max_rooms (it shouldn't, at the defaults).
	var hit_max_rooms: bool = false
	## Links tried (_grow_link calls); the pieces in each hall that got a room on its end, in order;
	## how many of those halls had to extend past their first 1-2 pieces; links that found no room and
	## capped their door, and how many of those had extended first.
	var links: int = 0
	var hall_lengths: Array[int] = []
	var halls_extended: int = 0
	var links_capped: int = 0
	var capped_after_extend: int = 0
	## With verify_unplace: failed links checked, and how many left the layout changed (must be 0).
	var unplace_checked: int = 0
	var unplace_leaks: int = 0
	## Placement tries that didn't fit, against max_attempts.
	var attempts: int = 0
	## Door pairs the loop pass (the last one) could bridge, counted before it laid any.
	var loop_candidates: int = 0
	## Aimed branches that found a target, and how each ended: closed into a loop, hit
	## max_branch_depth first, ran into max_rooms, ended in a one-door room (they can't pick one, so
	## this should stay 0), or found nothing that fit.
	var aimed: int = 0
	var aimed_closed: int = 0
	var aimed_gave_up: int = 0
	var aimed_out_of_rooms: int = 0
	var aimed_dead_end: int = 0
	var aimed_blocked: int = 0
	## Rolled aimed but found no far room's free door to aim at, so grew as a normal branch.
	var aimed_no_target: int = 0
	## Rooms and connectors each aimed branch placed before it ended, its closing bridge not counted.
	var aimed_pieces: Array[int] = []


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
