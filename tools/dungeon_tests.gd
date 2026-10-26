class_name DungeonTests
extends SceneTree
## Generator checks and layout statistics:
## 1. rotate_cell() against the real node transform, for every footprint up to 5x5 and every turn.
## 2. Every catalog door, at every rotation, lands on the edge center the planner thinks it does.
## 3. A batch of seeded layouts: exit depth, main path length, branch depth, treasure cap and depth
##    spread, loop bridge length and separation, loop candidates (and whether the length cap is what
##    limits them), overlaps, restarts, size. Plus same seed = same plan, and the placement rules.
## 4. Real builds: every connected door pair (loop stubs included) meets in world space, every other
##    door is plugged.
## 5. The map: the player's cell reveals rooms, a rebuild hides them.
## 6. Spawn tables: roll frequencies match weights, enemy variants apply, same seed = same spawns.
## Run from the project root:
##   godot --headless --path . --script res://tools/dungeon_tests.gd [-- <batch size> <build count> <per-seed lines>]

const RESTART_STRIDE: int = 7919

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var batch_size: int = int(args[0]) if args.size() > 0 else 500
	var build_count: int = int(args[1]) if args.size() > 1 else 20
	var summary_lines: int = int(args[2]) if args.size() > 2 else 20
	var table_seeds: int = int(args[3]) if args.size() > 3 else 300

	print("-- rotate_cell vs node transforms")
	_test_rotation()

	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var generator: DungeonGenerator = main.get_node("DungeonGenerator") as DungeonGenerator

	print("-- catalog doors at every rotation")
	_test_catalog_doors(generator)

	print("-- authoring warnings catch broken rooms")
	_test_authoring_warnings()

	print("-- %d seeded layouts" % batch_size)
	_batch(generator, batch_size, summary_lines)

	print("-- loop table, %d seeds per cell" % table_seeds)
	_loop_table(generator, table_seeds)
	print("-- main path curl, %d seeds each" % table_seeds)
	_curl_table(generator, table_seeds)
	_test_same_plan(generator)
	_test_placement_rules(generator)

	print("-- %d real builds" % build_count)
	await _test_builds(main, generator, build_count)

	print("-- map reveal")
	await _test_reveal(main, generator)

	print("-- spawn tables")
	_test_table_weights()
	await _test_enemy_variants(main)
	await _test_same_seed(generator)

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _test_rotation() -> void:
	var checked: int = 0
	var bad: int = 0
	for w: int in range(1, 6):
		for h: int in range(1, 6):
			var footprint: Vector2i = Vector2i(w, h)
			for turns: int in 4:
				var xform: Transform3D = DungeonGenerator.placement_transform(Vector2i.ZERO, footprint, turns)
				var rotated: Vector2i = DungeonGenerator.rotated_footprint(footprint, turns)
				for z: int in h:
					for x: int in w:
						var cell: Vector2i = Vector2i(x, z)
						var center: Vector3 = Vector3(x + 0.5, 0.0, z + 0.5) * Room.CELL_SIZE
						var world: Vector3 = xform * center
						var expected: Vector2i = Vector2i(floori(world.x / Room.CELL_SIZE), floori(world.z / Room.CELL_SIZE))
						var got: Vector2i = DungeonGenerator.rotate_cell(cell, footprint, turns)
						var in_bounds: bool = got.x >= 0 and got.y >= 0 and got.x < rotated.x and got.y < rotated.y
						checked += 1
						if got != expected or not in_bounds:
							bad += 1
							if bad <= 5:
								print("   mismatch: %s in %s, %d turns -> %s, transform says %s" % [cell, footprint, turns, got, expected])
				# Four single turns must come back to the start.
				var back: Vector2i = Vector2i(0, 0)
				var size: Vector2i = footprint
				for i: int in 4:
					back = DungeonGenerator.rotate_cell(back, size, 1)
					size = DungeonGenerator.rotated_footprint(size, 1)
				if back != Vector2i.ZERO or size != footprint:
					bad += 1
	_check(bad == 0, "%d cell rotations agree with Transform3D (%d bad)" % [checked, bad])


func _test_catalog_doors(generator: DungeonGenerator) -> void:
	generator._load_templates()
	var checked: int = 0
	var bad: int = 0
	for type: int in generator._templates:
		for template: DungeonGenerator.RoomTemplate in generator._templates[type]:
			for turns: int in 4:
				var placement: DungeonGenerator.Placement = DungeonGenerator.Placement.new()
				placement.template = template
				placement.turns = turns
				var xform: Transform3D = DungeonGenerator.placement_transform(Vector2i.ZERO, template.footprint, turns)
				for i: int in template.door_dirs.size():
					var authored: Vector3 = xform * Door.edge_center(template.door_cells[i], template.door_dirs[i])
					var planned: Vector3 = Door.edge_center(placement.door_cell(i), placement.door_dir(i))
					checked += 1
					if authored.distance_to(planned) > 0.001:
						bad += 1
						print("   %s door %d at %d turns: node puts it at %s, planner at %s" % [template.name, i, turns, authored, planned])
	_check(bad == 0, "%d door placements agree between planner and node transform" % checked)


func _test_authoring_warnings() -> void:
	var scene: PackedScene = load("res://dungeon/rooms/StartRoom.tscn") as PackedScene
	for path: String in _catalog_paths():
		var room: Room = (load(path) as PackedScene).instantiate() as Room
		var problems: PackedStringArray = room.get_authoring_problems()
		_check(problems.is_empty(), "%s is clean%s" % [path.get_file(), "" if problems.is_empty() else ": " + "; ".join(problems)])
		room.free()
	var cases: Dictionary[String, Callable] = {
		"door off its edge": func(r: Room) -> void: (r.get_node("Doors/DoorS") as Node3D).position.x += 1.0,
		"door in the middle of the room": func(r: Room) -> void: (r.get_node("Doors/DoorS") as Node3D).position.z = 6.0,
		"spawn outside the footprint": func(r: Room) -> void: (r.get_node("Spawns/Player") as Node3D).position.x = 13.0,
		"doorway cutter missing": func(r: Room) -> void: r.get_node("Geometry/Walls/DoorwayS").free(),
		"START without a PLAYER spawn": func(r: Room) -> void: r.get_node("Spawns/Player").free(),
	}
	# Table checks need a WEAPON point; the treasure room has two.
	var treasure: PackedScene = load("res://dungeon/rooms/TreasureRoom.tscn") as PackedScene
	var treasure_cases: Dictionary[String, Callable] = {
		"enemy table on a WEAPON point": func(r: Room) -> void: (r.get_node("Spawns/WeaponA") as SpawnPoint).table = load("res://data/tables/combat_enemy.tres") as SpawnTable,
	}
	for label: String in cases.keys() + treasure_cases.keys():
		var on_treasure: bool = treasure_cases.has(label)
		var room: Room = (treasure if on_treasure else scene).instantiate() as Room
		((treasure_cases[label] if on_treasure else cases[label]) as Callable).call(room)
		var problems: PackedStringArray = room.get_authoring_problems()
		_check(not problems.is_empty(), "warns on %s: %s" % [label, problems[0] if not problems.is_empty() else "(nothing)"])
		room.free()


func _catalog_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	for scene: PackedScene in (load("res://dungeon/catalog.tres") as RoomCatalog).get_scenes():
		paths.append(scene.resource_path)
	return paths


func _batch(generator: DungeonGenerator, count: int, summary_lines: int) -> void:
	var first_try: int = 0
	var hard_failures: int = 0
	var restart_histogram: Dictionary[int, int] = {}
	var overlaps: int = 0
	var wrong_exit_depth: int = 0
	var wrong_main_length: int = 0
	var too_deep: int = 0
	var too_much_treasure: int = 0
	var too_many_rooms: int = 0
	var rooms_sum: int = 0
	var touching: int = 0
	var main_cells_sum: int = 0
	var exit_distance_sum: float = 0.0
	var branches_sum: int = 0
	var deepest_sum: int = 0
	var treasure_sum: int = 0
	var no_treasure: int = 0
	var treasure_by_depth: Dictionary[int, int] = {}
	var main_treasure: int = 0
	var loops_sum: int = 0
	var floors_with_loops: int = 0
	var candidates_sum: int = 0
	var no_candidate: int = 0
	var unlocked_at_5: int = 0
	var unlocked_at_8: int = 0
	var bridge_lengths: Dictionary[int, int] = {}
	var too_long: int = 0
	var bad_pieces: int = 0
	var too_close: int = 0
	var closest: int = 1 << 20
	var plugs: int = 0
	var dead_end_corridors: int = 0
	var corridors: int = 0
	var area_sum: int = 0
	var span_sum: Vector2i = Vector2i.ZERO
	var built: int = 0
	var example: Array[DungeonGenerator.Placement] = []
	for seed_index: int in count:
		var base: int = seed_index + 1
		var plan: Array[DungeonGenerator.Placement] = []
		var restarts: int = 0
		while restarts <= generator.max_restarts:
			plan = generator.plan_layout(base + restarts * RESTART_STRIDE)
			if not plan.is_empty():
				break
			restarts += 1
		if plan.is_empty():
			hard_failures += 1
			continue
		restart_histogram[restarts] = restart_histogram.get(restarts, 0) + 1
		if restarts == 0:
			first_try += 1
		built += 1
		if example.is_empty():
			example = plan
		var candidates: int = generator.last_loop_candidates
		if seed_index < summary_lines:
			print("   seed %d: %s" % [base, DungeonGenerator.describe_plan(plan, candidates)])
		var occupied: Dictionary[Vector2i, bool] = {}
		var min_cell: Vector2i = Vector2i(1 << 20, 1 << 20)
		var max_cell: Vector2i = -min_cell
		var rooms: int = 0
		var main_rooms: int = 0
		var treasure: int = 0
		var bridge_cells: Dictionary[int, int] = {}
		var deepest: int = 0
		for placement: DungeonGenerator.Placement in plan:
			var type: int = placement.template.type
			for cell: Vector2i in placement.cells():
				if occupied.has(cell):
					overlaps += 1
				occupied[cell] = true
				min_cell = min_cell.min(cell)
				max_cell = max_cell.max(cell)
			plugs += placement.template.door_dirs.size() - placement.used_doors.size()
			if placement.loop:
				bridge_cells[placement.bridge_id] = bridge_cells.get(placement.bridge_id, 0) + 1
				if placement.template.footprint != Vector2i.ONE or placement.used_doors.size() != 2 or not placement.template.is_connector:
					bad_pieces += 1
				continue
			deepest = maxi(deepest, placement.branch_depth())
			# The connector rule: every tree link joins a room and a connector.
			if placement.parent and placement.template.is_connector == placement.parent.template.is_connector:
				touching += 1
			if placement.main_path:
				main_cells_sum += placement.cells().size()
			if not placement.main_path and placement.parent.main_path:
				branches_sum += 1
			if placement.template.is_connector:
				corridors += 1
				if placement.used_doors.size() < 2:
					dead_end_corridors += 1
				continue
			rooms += 1
			if placement.main_path and type != Room.Type.START and type != Room.Type.EXIT:
				main_rooms += 1
			if type == Room.Type.EXIT:
				exit_distance_sum += _center(placement).distance_to(_center(plan[0]))
				if placement.depth != generator.main_path_length + 1:
					wrong_exit_depth += 1
			if type == Room.Type.TREASURE:
				treasure += 1
				treasure_by_depth[placement.depth] = treasure_by_depth.get(placement.depth, 0) + 1
				if placement.parent.main_path:
					main_treasure += 1
		for separation: int in _bridge_separations(plan):
			closest = mini(closest, separation)
			if separation < generator.loop_min_separation:
				too_close += 1
		for bridge: int in bridge_cells:
			bridge_lengths[bridge_cells[bridge]] = bridge_lengths.get(bridge_cells[bridge], 0) + 1
			if bridge_cells[bridge] > generator.max_loop_length:
				too_long += 1
		candidates_sum += candidates
		if candidates == 0:
			no_candidate += 1
			# Is the length cap what stops it? Everything before the loop pass is the same at any cap.
			var cap: int = generator.max_loop_length
			var plan_seed: int = base + restarts * RESTART_STRIDE
			generator.max_loop_length = cap + 1
			generator.plan_layout(plan_seed)
			if generator.last_loop_candidates > 0:
				unlocked_at_5 += 1
			generator.max_loop_length = 8
			generator.plan_layout(plan_seed)
			if generator.last_loop_candidates > 0:
				unlocked_at_8 += 1
			generator.max_loop_length = cap
		if main_rooms != generator.main_path_length:
			wrong_main_length += 1
		if deepest > generator.max_branch_depth:
			too_deep += 1
		if treasure > generator.max_treasure_per_floor:
			too_much_treasure += 1
		if rooms > generator.target_rooms:
			too_many_rooms += 1
		rooms_sum += rooms
		deepest_sum += deepest
		treasure_sum += treasure
		if treasure == 0:
			no_treasure += 1
		loops_sum += bridge_cells.size()
		if not bridge_cells.is_empty():
			floors_with_loops += 1
		area_sum += occupied.size()
		span_sum += max_cell - min_cell + Vector2i.ONE
	if count > summary_lines:
		print("   (per-seed lines for the first %d seeds; pass a third argument for more)" % summary_lines)
	var n: float = maxf(built, 1)
	_check(hard_failures == 0, "every seed reached an exit within %d restarts (%d failed)" % [generator.max_restarts, hard_failures])
	_check(overlaps == 0, "no overlapping cells across %d layouts" % built)
	_check(wrong_exit_depth == 0, "exit depth is exactly %d on every seed (%d wrong)" % [generator.main_path_length + 1, wrong_exit_depth])
	_check(wrong_main_length == 0, "main path holds exactly %d rooms between START and EXIT (%d wrong)" % [generator.main_path_length, wrong_main_length])
	_check(too_deep == 0, "no branch deeper than %d rooms (%d seeds over)" % [generator.max_branch_depth, too_deep])
	_check(too_much_treasure == 0, "never more than %d treasure rooms (%d seeds over)" % [generator.max_treasure_per_floor, too_much_treasure])
	_check(too_many_rooms == 0, "never more than %d non-corridor rooms (%d seeds over)" % [generator.target_rooms, too_many_rooms])
	_check(touching == 0, "every link is room <-> connector: no rooms touching rooms, no connectors touching connectors (%d bad links)" % touching)
	_check(too_long == 0 and bad_pieces == 0, "every loop bridge is 1x1 pieces, both doors used, at most %d cells (%d too long, %d bad pieces)" % [generator.max_loop_length, too_long, bad_pieces])
	_check(too_close == 0, "every bridge joins rooms at least %d rooms apart before it (closest %d, %d too close)" % [generator.loop_min_separation, closest, too_close])
	print("   first-try success: %.1f%%   restarts needed: %s" % [100.0 * first_try / count, _histogram_text(restart_histogram)])
	print("   rooms (non-corridor): %.1f of %d per floor; %.1f branches, deepest %.1f rooms" % [rooms_sum / n, generator.target_rooms, branches_sum / n, deepest_sum / n])
	print("   treasure: %.2f per floor, %.0f%% of floors have none, %d of %d hang straight off the main path" % [treasure_sum / n, 100.0 * no_treasure / n, main_treasure, treasure_sum])
	print("   treasure by depth (exit is %d): %s" % [generator.main_path_length + 1, _histogram_text(treasure_by_depth)])
	print("   loops: %.2f per floor (%.0f%% of floors have one), from %.2f candidates per floor; bridge lengths: %s" % [loops_sum / n, 100.0 * floors_with_loops / n, candidates_sum / n, _histogram_text(bridge_lengths)])
	print("   no candidate within %d cells on %.0f%% of floors; of those, %d would have one at %d cells, %d at 8" % [generator.max_loop_length, 100.0 * no_candidate / n, unlocked_at_5, generator.max_loop_length + 1, unlocked_at_8])
	print("   per floor: %.1f plugged doors, %.2f of %.2f connectors dead-end into a plug" % [plugs / n, dead_end_corridors / n, corridors / n])
	print("   main path: %.1f cells from START to EXIT inclusive (%.0f m of floor to walk through); EXIT sits %.1f cells (%.0f m) from START as the crow flies" % [main_cells_sum / n, main_cells_sum / n * Room.CELL_SIZE, exit_distance_sum / n, exit_distance_sum / n * Room.CELL_SIZE])
	print("   size: %.0f cells occupied, bounding box %.1f x %.1f cells (%.0f x %.0f m)" % [area_sum / n, span_sum.x / n, span_sum.y / n, span_sum.x / n * Room.CELL_SIZE, span_sum.y / n * Room.CELL_SIZE])
	if not example.is_empty():
		print("   example (seed 1): S start, E exit; capitals main path, lower case branches; C/# c/x combat, T/t treasure, = / - corridor, o loop")
		for line: String in _ascii_map(example):
			print("     " + line)


## For each loop bridge, in the order laid: the separation of its two end rooms over the layout
## as it stood just before (tree plus earlier bridges). Non-corridor rooms entered; corridors free.
func _bridge_separations(plan: Array[DungeonGenerator.Placement]) -> Array[int]:
	var links: Dictionary[DungeonGenerator.Placement, Array] = {}
	for placement: DungeonGenerator.Placement in plan:
		if placement.parent and not placement.loop:
			_join(links, placement, placement.parent)
	var separations: Array[int] = []
	for placement: DungeonGenerator.Placement in plan:
		if not placement.loop or placement.bridge_end == null:
			continue
		var first: DungeonGenerator.Placement = placement
		while first.parent.loop:
			first = first.parent
		separations.append(_steps(links, first.parent, placement.bridge_end))
		# Walking a bridge is free (all corridor), so it joins its ends directly.
		_join(links, first.parent, placement.bridge_end)
	return separations


func _join(links: Dictionary[DungeonGenerator.Placement, Array], one: DungeonGenerator.Placement, other: DungeonGenerator.Placement) -> void:
	if not links.has(one):
		links[one] = []
	if not links.has(other):
		links[other] = []
	links[one].append(other)
	links[other].append(one)


## Fewest rooms (not connectors) entered walking from `from` to `to`; a plain Dijkstra, independent of the generator's.
func _steps(links: Dictionary[DungeonGenerator.Placement, Array], from: DungeonGenerator.Placement, to: DungeonGenerator.Placement) -> int:
	var best: Dictionary[DungeonGenerator.Placement, int] = {from: 0}
	var open: Array[DungeonGenerator.Placement] = [from]
	while not open.is_empty():
		var at_index: int = 0
		for i: int in open.size():
			if best[open[i]] < best[open[at_index]]:
				at_index = i
		var at: DungeonGenerator.Placement = open[at_index]
		open.remove_at(at_index)
		if at == to:
			return best[at]
		for next: DungeonGenerator.Placement in links.get(at, []):
			var cost: int = best[at] + (0 if next.template.is_connector else 1)
			if not best.has(next) or cost < best[next]:
				best[next] = cost
				open.append(next)
	return 1 << 20


## Same seed, same plan: every placement's template, position, turns, doors and flags match.
## Share of floors with at least one loop (and loops per floor) for loop_min_separation 1/2/3 by
## max_loop_length 4/5/6, everything else at its current value. The generator's settings are restored after.
func _loop_table(generator: DungeonGenerator, seeds: int) -> void:
	var separation_was: int = generator.loop_min_separation
	var cap_was: int = generator.max_loop_length
	print("     separation | cap 4        | cap 5        | cap 6")
	for separation: int in [1, 2, 3]:
		var cells: PackedStringArray = []
		for cap: int in [4, 5, 6]:
			generator.loop_min_separation = separation
			generator.max_loop_length = cap
			var with_loop: int = 0
			var loops: int = 0
			for s: int in range(1, seeds + 1):
				var bridges: Dictionary[int, bool] = {}
				for placement: DungeonGenerator.Placement in _plan_with_restarts(generator, s):
					if placement.loop:
						bridges[placement.bridge_id] = true
				loops += bridges.size()
				if not bridges.is_empty():
					with_loop += 1
			cells.append("%3.0f%% (%.2f)" % [100.0 * with_loop / seeds, float(loops) / seeds])
		print("     >= %d        | %s" % [separation, " | ".join(cells)])
	generator.loop_min_separation = separation_was
	generator.max_loop_length = cap_was


## The same floors at main_path_curl 0 / 0.5 / 1.0: how far the exit ends up from START, how long
## the main path is, and the loop rate at cap 5 for separation 3 (and 2). Settings are restored after.
func _curl_table(generator: DungeonGenerator, seeds: int) -> void:
	var curl_was: float = generator.main_path_curl
	var separation_was: int = generator.loop_min_separation
	var cap_was: int = generator.max_loop_length
	generator.max_loop_length = 5
	print("     curl | exit from START | main path   | first try | loops, sep 3 cap 5 | loops, sep 2 cap 5")
	for curl: float in [0.0, 0.5, 1.0]:
		generator.main_path_curl = curl
		var columns: PackedStringArray = []
		for separation: int in [3, 2]:
			generator.loop_min_separation = separation
			var exit_distance: float = 0.0
			var main_cells: int = 0
			var first_try: int = 0
			var with_loop: int = 0
			var loops: int = 0
			for s: int in range(1, seeds + 1):
				if not generator.plan_layout(s).is_empty():
					first_try += 1
				var plan: Array[DungeonGenerator.Placement] = _plan_with_restarts(generator, s)
				var bridges: Dictionary[int, bool] = {}
				for placement: DungeonGenerator.Placement in plan:
					if placement.loop:
						bridges[placement.bridge_id] = true
					elif placement.main_path:
						main_cells += placement.cells().size()
						if placement.template.type == Room.Type.EXIT:
							exit_distance += _center(placement).distance_to(_center(plan[0]))
				loops += bridges.size()
				if not bridges.is_empty():
					with_loop += 1
			if separation == 3:
				columns.append("%4.1f cells (%3.0f m)" % [exit_distance / seeds, exit_distance / seeds * Room.CELL_SIZE])
				columns.append("%5.1f cells" % (float(main_cells) / seeds))
				columns.append("%7.0f%%" % (100.0 * first_try / seeds))
			columns.append("%9.0f%% (%.2f)" % [100.0 * with_loop / seeds, float(loops) / seeds])
		print("     %.1f  | %s" % [curl, " | ".join(columns)])
	generator.main_path_curl = curl_was
	generator.loop_min_separation = separation_was
	generator.max_loop_length = cap_was


## Middle of a placement's footprint, in cells.
static func _center(placement: DungeonGenerator.Placement) -> Vector2:
	return Vector2(placement.grid_origin) + Vector2(DungeonGenerator.rotated_footprint(placement.template.footprint, placement.turns)) * 0.5


## The plan generate() would build for `base`: the first restart that reaches an exit (empty if none does).
func _plan_with_restarts(generator: DungeonGenerator, base: int) -> Array[DungeonGenerator.Placement]:
	var plan: Array[DungeonGenerator.Placement] = []
	for restart: int in generator.max_restarts + 1:
		plan = generator.plan_layout(base + restart * RESTART_STRIDE)
		if not plan.is_empty():
			break
	return plan


func _test_same_plan(generator: DungeonGenerator) -> void:
	var differing: int = 0
	for s: int in range(1, 101):
		if _plan_signature(generator.plan_layout(s)) != _plan_signature(generator.plan_layout(s)):
			differing += 1
	_check(differing == 0, "same seed twice gives the same plan (%d of 100 differ)" % differing)


func _plan_signature(plan: Array[DungeonGenerator.Placement]) -> String:
	var parts: PackedStringArray = []
	for placement: DungeonGenerator.Placement in plan:
		var used: Array[int] = placement.used_doors.duplicate()
		used.sort()
		parts.append("%s@%s/%d%s%s%s" % [placement.template.name, placement.grid_origin, placement.turns, used, "M" if placement.main_path else "", "L%d" % placement.bridge_id if placement.loop else ""])
	return " ".join(parts)


## Room.min_depth_from_start and max_per_floor, set on a catalog room in memory, are honoured.
func _test_placement_rules(generator: DungeonGenerator) -> void:
	generator._load_templates()
	var pillars: DungeonGenerator.RoomTemplate = generator._template_named("CombatRoom_Pillars")
	var seeds: int = 200
	pillars.max_per_floor = 1
	var worst_count: int = 0
	for s: int in range(1, seeds + 1):
		var copies: int = 0
		for placement: DungeonGenerator.Placement in generator.plan_layout(s):
			if placement.template == pillars:
				copies += 1
		worst_count = maxi(worst_count, copies)
	pillars.max_per_floor = 0
	_check(worst_count <= 1, "max_per_floor 1 on CombatRoom_Pillars: at most %d per floor over %d seeds" % [worst_count, seeds])
	pillars.min_depth_from_start = 4
	var shallowest: int = 1 << 20
	var failed: int = 0
	for s: int in range(1, seeds + 1):
		var plan: Array[DungeonGenerator.Placement] = generator.plan_layout(s)
		if plan.is_empty():
			failed += 1
		for placement: DungeonGenerator.Placement in plan:
			if placement.template == pillars:
				shallowest = mini(shallowest, placement.depth)
	pillars.min_depth_from_start = 0
	_check(shallowest >= 4, "min_depth_from_start 4 on CombatRoom_Pillars: shallowest at depth %d over %d seeds (%d would need a restart)" % [shallowest, seeds, failed])


## The map side: the player's cell reveals whole rooms once, and a rebuild hides everything again.
func _test_reveal(main: Node, generator: DungeonGenerator) -> void:
	var dungeon: Dungeon = main.get_node("Dungeon") as Dungeon
	var player: Player = main.get_node("Player") as Player
	var emitted: Array[int] = [0]
	var count_emit: Callable = func() -> void: emitted[0] += 1
	dungeon.revealed_changed.connect(count_emit)
	generator.generate(3)
	_check(dungeon.revealed.is_empty() and emitted[0] == 1, "a rebuild clears the map (%d cells revealed, %d signal)" % [dungeon.revealed.size(), emitted[0]])
	await process_frame
	var rooms: Array[Room] = []
	for child: Node in dungeon.get_children():
		if child is Room and not child.is_queued_for_deletion():
			rooms.append(child as Room)
	_check(dungeon.map.rooms.size() == rooms.size(), "MapModel has one entry per built room (%d / %d)" % [dungeon.map.rooms.size(), rooms.size()])
	var doors_agree: bool = true
	var tiles: int = 0
	for i: int in rooms.size():
		var built_doors: Array[Door] = rooms[i].get_doors()
		for d: int in built_doors.size():
			doors_agree = doors_agree and built_doors[d].used == dungeon.map.rooms[i].doors[d].used
		if dungeon.map.rooms[i].map_tile:
			tiles += 1
	_check(doors_agree, "MapModel door used-flags match the built rooms")
	_check(tiles == 0, "no room sets map_tile yet (%d do)" % tiles)
	await physics_frame
	await physics_frame
	var start: MapModel.MapRoom = dungeon.map.room_at(dungeon.cell_at(player.global_position))
	_check(start != null and start.type == Room.Type.START and dungeon.revealed.size() == start.cells.size(),
		"spawning reveals just the start room (%d cells)" % dungeon.revealed.size())
	var next: MapModel.MapRoom = null
	for room: MapModel.MapRoom in dungeon.map.rooms:
		if room.main_path and room.type != Room.Type.START:
			next = room
			break
	var before: int = emitted[0]
	player.global_position = Vector3(next.center().x, 0.0, next.center().y) * Room.CELL_SIZE
	await physics_frame
	await physics_frame
	var all_in: bool = true
	for cell: Vector2i in next.cells:
		all_in = all_in and dungeon.revealed.has(cell)
	_check(all_in and dungeon.revealed.size() == start.cells.size() + next.cells.size() and emitted[0] == before + 1,
		"walking into the next room reveals all %d of its cells, one signal" % next.cells.size())
	player.global_position += Vector3(0.5, 0.0, 0.5)
	await physics_frame
	await physics_frame
	_check(emitted[0] == before + 1, "moving around a room already seen changes nothing")
	generator.generate(4)
	_check(emitted[0] == before + 2 and dungeon.revealed.is_empty(), "a rebuild hides the map again")
	dungeon.revealed_changed.disconnect(count_emit)
	var hud: Hud = player.get_node("%HUD") as Hud
	var corner: Control = player.get_node("%Minimap") as Control
	var opened: bool = await _press_until(&"toggle_map", func() -> bool: return hud.is_full_map_open() and not corner.visible)
	var closed: bool = await _press_until(&"toggle_map", func() -> bool: return not hud.is_full_map_open() and corner.visible)
	_check(opened and closed and not paused, "M swaps the corner map for the full map and back, without pausing")


## Taps `action` and waits up to a second for `condition`.
func _press_until(action: StringName, condition: Callable) -> bool:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
	var deadline: int = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await physics_frame
	return false


func _test_builds(main: Node, generator: DungeonGenerator, count: int) -> void:
	var dungeon: Node3D = main.get_node("Dungeon") as Node3D
	var spawned: Node3D = main.get_node("Dungeon/Spawned") as Node3D
	var player: Player = main.get_node("Player") as Player
	var mismatched_doors: int = 0
	var missing_plugs: int = 0
	var bad_spawn_counts: int = 0
	var misplaced_players: int = 0
	var stubs: int = 0
	var seeds: Array[int] = []
	for i: int in count:
		seeds.append(1000 + i)
	# Loops are rare, so add a few seeds known to have one, at least one with a corner piece:
	# the bridge pieces' doors need checking too.
	var with_loops: int = 0
	var corner_seen: bool = false
	var probe: int = 1
	while (with_loops < 3 or not corner_seen) and probe < 5000:
		var has_loop: bool = false
		var has_corner: bool = false
		for placement: DungeonGenerator.Placement in generator.plan_layout(probe):
			has_loop = has_loop or placement.loop
			has_corner = has_corner or placement.template.name == DungeonGenerator.LOOP_CORNER
		if (has_loop and with_loops < 3) or (has_corner and not corner_seen):
			seeds.append(probe)
			with_loops += 1
			corner_seen = corner_seen or has_corner
		probe += 1
	for build_seed: int in seeds:
		generator.seed_value = build_seed
		generator.generate()
		await process_frame
		var rooms: Array[Room] = []
		for child: Node in dungeon.get_children():
			if child is Room:
				rooms.append(child as Room)
		var open_ends: Array[Vector3] = []
		for room: Room in rooms:
			if room.name.ends_with(DungeonGenerator.LOOP_STUB) or room.name.ends_with(DungeonGenerator.LOOP_CORNER):
				stubs += 1
			for door: Door in room.get_doors():
				if door.used:
					open_ends.append(door.global_position)
				elif door.get_child_count() == 0:
					missing_plugs += 1
			for spawn: SpawnPoint in room.get_spawn_points():
				if spawn.kind == SpawnPoint.Kind.PLAYER and player.global_position.distance_to(spawn.global_position) > 0.01:
					misplaced_players += 1
		# Rolled "nothing" places nothing, so count what the log says was placed.
		var expected_spawns: int = 0
		for line: String in generator.last_spawn_log:
			if not line.ends_with("→ nothing") and not line.ends_with("→ player"):
				expected_spawns += 1
		# Every used door must meet exactly one other used door at the same point.
		for a: int in open_ends.size():
			var partners: int = 0
			for b: int in open_ends.size():
				if a != b and open_ends[a].distance_to(open_ends[b]) < 0.01:
					partners += 1
			if partners != 1:
				mismatched_doors += 1
		if spawned.get_child_count() != expected_spawns:
			bad_spawn_counts += 1
	generator.seed_value = 0
	_check(mismatched_doors == 0, "every connected door meets its partner in world space, %d loop pieces included (%d bad)" % [stubs, mismatched_doors])
	_check(missing_plugs == 0, "every unused door is plugged (%d missing)" % missing_plugs)
	_check(bad_spawn_counts == 0, "spawned enemies + pickups match the spawn log in every build")
	_check(misplaced_players == 0, "player lands on the START spawn every build")


## Rolls each table many times with a seeded RNG; every row's share should match weight / total.
func _test_table_weights() -> void:
	var rolls: int = 22000
	for path: String in ["res://data/tables/combat_enemy.tres", "res://data/tables/treasure_loot.tres", "res://data/tables/combat_weapon.tres"]:
		var table: SpawnTable = load(path) as SpawnTable
		var kind: SpawnPoint.Kind = SpawnPoint.Kind.ENEMY if path.contains("enemy") else SpawnPoint.Kind.WEAPON
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 42
		var counts: Dictionary[SpawnEntry, int] = {}
		for i: int in rolls:
			var entry: SpawnEntry = table.roll(rng)
			counts[entry] = counts.get(entry, 0) + 1
		var worst: float = 0.0
		var parts: PackedStringArray = []
		for entry: SpawnEntry in table.entries:
			var expected: float = entry.weight / table.total_weight()
			var got: float = float(counts.get(entry, 0)) / rolls
			worst = maxf(worst, absf(got - expected))
			parts.append("%s %.1f%% (%.1f%%)" % [entry.describe(kind), got * 100.0, expected * 100.0])
		_check(worst < 0.015, "%s: %s" % [path.get_file(), ", ".join(parts)])


## Each variant on the real Enemy scene: HP, scale, capsule and tint come from its EnemyData.
func _test_enemy_variants(main: Node) -> void:
	var scene: PackedScene = load("res://enemy/Enemy.tscn") as PackedScene
	var base: Enemy = scene.instantiate() as Enemy
	var base_radius: float = ((base.get_node("BodyShape") as CollisionShape3D).shape as CapsuleShape3D).radius
	base.free()
	for path: String in ["res://enemy/grunt.tres", "res://enemy/skitterer.tres", "res://enemy/bruiser.tres"]:
		var data: EnemyData = load(path) as EnemyData
		var enemy: Enemy = scene.instantiate() as Enemy
		enemy.data = data
		enemy.position = Vector3(0.0, -500.0, 0.0)
		main.add_child(enemy)
		await process_frame
		var radius: float = ((enemy.get_node("BodyShape") as CollisionShape3D).shape as CapsuleShape3D).radius
		var rig_scale: float = (enemy.get_node("Rig") as Node3D).scale.x
		var torso: MeshInstance3D = enemy.get_node("Rig/Body/Torso") as MeshInstance3D
		var health: Health = enemy.get_node("Health") as Health
		var tinted: bool = torso.material_override == data.body_material
		_check(health.max_hp == data.max_hp and is_equal_approx(rig_scale, data.body_scale)
			and is_equal_approx(radius, base_radius * data.body_scale) and tinted,
			"%s: %d HP, scale %.1f, capsule r %.2f, %s" % [data.display_name, health.max_hp, rig_scale, radius,
				"tinted " + data.body_material.resource_path.get_file() if data.body_material else "scene burlap"])
		enemy.queue_free()
	await process_frame


## F6's promise: rebuilding with the same seed gives the same layout and the same spawns.
func _test_same_seed(generator: DungeonGenerator) -> void:
	var differing: int = 0
	var seeds: Array[int] = [7, 77, 777, 4165243132]
	for s: int in seeds:
		generator.generate(s)
		var first: PackedStringArray = generator.last_spawn_log.duplicate()
		await process_frame
		generator.generate(generator.last_seed)
		var second: PackedStringArray = generator.last_spawn_log.duplicate()
		await process_frame
		if first != second:
			differing += 1
			for i: int in maxi(first.size(), second.size()):
				var a: String = first[i] if i < first.size() else "(none)"
				var b: String = second[i] if i < second.size() else "(none)"
				if a != b:
					print("   seed %d differs: '%s' vs '%s'" % [s, a, b])
	_check(differing == 0, "same seed twice gives identical spawn logs (%d of %d differ)" % [differing, seeds.size()])
	generator.generate(1)
	var one: PackedStringArray = generator.last_spawn_log.duplicate()
	generator.generate(2)
	_check(one != generator.last_spawn_log, "different seeds give different spawn logs")
	print("   seed 1 spawn log:")
	for line: String in one:
		print("     " + line)


func _ascii_map(plan: Array[DungeonGenerator.Placement]) -> PackedStringArray:
	var glyph: Dictionary[Vector2i, String] = {}
	var min_cell: Vector2i = Vector2i(1 << 20, 1 << 20)
	var max_cell: Vector2i = -min_cell
	var letters: Dictionary[int, String] = {
		Room.Type.START: "S", Room.Type.CORRIDOR: "=", Room.Type.COMBAT: "C", Room.Type.TREASURE: "T", Room.Type.EXIT: "E",
	}
	for i: int in plan.size():
		var placement: DungeonGenerator.Placement = plan[i]
		var letter: String = "o" if placement.loop else letters[placement.template.type]
		if not placement.main_path and not placement.loop:
			letter = "-" if letter == "=" else letter.to_lower()
		# Alternate combat glyphs so neighbouring combat rooms stay distinguishable.
		if i % 2 == 1 and placement.template.type == Room.Type.COMBAT:
			letter = "#" if placement.main_path else "x"
		for cell: Vector2i in placement.cells():
			glyph[cell] = letter
			min_cell = min_cell.min(cell)
			max_cell = max_cell.max(cell)
	var lines: PackedStringArray = []
	for z: int in range(min_cell.y, max_cell.y + 1):
		var line: String = ""
		for x: int in range(min_cell.x, max_cell.x + 1):
			line += glyph.get(Vector2i(x, z), ".")
		lines.append(line)
	return lines


func _histogram_text(histogram: Dictionary[int, int]) -> String:
	var keys: Array[int] = histogram.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k: int in keys:
		parts.append("%d:%d" % [k, histogram[k]])
	return ", ".join(parts)


func _check(ok: bool, label: String) -> void:
	print("   [%s] %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failures += 1
