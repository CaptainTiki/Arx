class_name DungeonTests
extends SceneTree
## Generator checks and layout statistics:
## 1. rotate_cell() against the real node transform, for every footprint up to 5x5 and every turn.
## 2. Every catalog door, at every rotation, lands on the edge center the planner thinks it does.
## 3. A batch of seeded layouts: restarts, overlaps, dead ends, depth (floor vs hallway), size.
## 4. Real builds: every connected door pair meets in world space, every other door is plugged.
## Run from the project root:
##   godot --headless --path . --script res://tools/dungeon_tests.gd [-- <batch size> <build count>]

const RESTART_STRIDE: int = 7919

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var batch_size: int = int(args[0]) if args.size() > 0 else 500
	var build_count: int = int(args[1]) if args.size() > 1 else 20

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
	_batch(generator, batch_size)

	print("-- %d real builds" % build_count)
	await _test_builds(main, generator, build_count)

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
		"spawn outside the footprint": func(r: Room) -> void: (r.get_node("Spawns/Sword") as Node3D).position.x = 13.0,
		"doorway cutter missing": func(r: Room) -> void: r.get_node("Geometry/Walls/DoorwayS").free(),
		"START without a PLAYER spawn": func(r: Room) -> void: r.get_node("Spawns/Player").free(),
	}
	for label: String in cases:
		var room: Room = scene.instantiate() as Room
		(cases[label] as Callable).call(room)
		var problems: PackedStringArray = room.get_authoring_problems()
		_check(not problems.is_empty(), "warns on %s: %s" % [label, problems[0] if not problems.is_empty() else "(nothing)"])
		room.free()


func _catalog_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	for scene: PackedScene in (load("res://dungeon/catalog.tres") as RoomCatalog).get_scenes():
		paths.append(scene.resource_path)
	return paths


func _batch(generator: DungeonGenerator, count: int) -> void:
	var first_try: int = 0
	var hard_failures: int = 0
	var restart_histogram: Dictionary[int, int] = {}
	var overlaps: int = 0
	var plugs: int = 0
	var dead_end_corridors: int = 0
	var corridors: int = 0
	var max_depth_sum: int = 0
	var exit_depth_sum: int = 0
	var pure_chains: int = 0
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
		var occupied: Dictionary[Vector2i, bool] = {}
		var min_cell: Vector2i = Vector2i(1 << 20, 1 << 20)
		var max_cell: Vector2i = -min_cell
		var max_depth: int = 0
		for placement: DungeonGenerator.Placement in plan:
			for cell: Vector2i in placement.cells():
				if occupied.has(cell):
					overlaps += 1
				occupied[cell] = true
				min_cell = min_cell.min(cell)
				max_cell = max_cell.max(cell)
			plugs += placement.template.door_dirs.size() - placement.used_doors.size()
			max_depth = maxi(max_depth, placement.depth)
			if placement.template.type == Room.Type.CORRIDOR:
				corridors += 1
				if placement.used_doors.size() < 2:
					dead_end_corridors += 1
			if placement.template.type == Room.Type.EXIT:
				exit_depth_sum += placement.depth
		max_depth_sum += max_depth
		if max_depth + 1 == plan.size():
			pure_chains += 1
		area_sum += occupied.size()
		span_sum += max_cell - min_cell + Vector2i.ONE
	var n: float = maxf(built, 1)
	_check(overlaps == 0, "no overlapping cells across %d layouts" % built)
	_check(hard_failures == 0, "every seed reached an exit within %d restarts (%d failed)" % [generator.max_restarts, hard_failures])
	print("   first-try success: %.1f%%   restarts needed: %s" % [100.0 * first_try / count, _histogram_text(restart_histogram)])
	print("   per floor: %.1f plugged doors, %.2f of %.2f corridors dead-end into a plug" % [plugs / n, dead_end_corridors / n, corridors / n])
	print("   depth: deepest room %.1f steps from start, exit %.1f steps; %.0f%% of floors are a single chain" % [max_depth_sum / n, exit_depth_sum / n, 100.0 * pure_chains / n])
	print("   size: %.0f cells occupied, bounding box %.1f x %.1f cells (%.0f x %.0f m)" % [area_sum / n, span_sum.x / n, span_sum.y / n, span_sum.x / n * Room.CELL_SIZE, span_sum.y / n * Room.CELL_SIZE])
	if not example.is_empty():
		print("   example (seed 1): S start, c corridor, C combat, T treasure, E exit, # second room of a kind next door")
		for line: String in _ascii_map(example):
			print("     " + line)


func _test_builds(main: Node, generator: DungeonGenerator, count: int) -> void:
	var dungeon: Node3D = main.get_node("Dungeon") as Node3D
	var spawned: Node3D = main.get_node("Dungeon/Spawned") as Node3D
	var player: Player = main.get_node("Player") as Player
	var mismatched_doors: int = 0
	var missing_plugs: int = 0
	var bad_spawn_counts: int = 0
	var misplaced_players: int = 0
	for i: int in count:
		generator.seed_value = 1000 + i
		generator.generate()
		await process_frame
		var rooms: Array[Room] = []
		for child: Node in dungeon.get_children():
			if child is Room:
				rooms.append(child as Room)
		var open_ends: Array[Vector3] = []
		var expected_spawns: int = 0
		for room: Room in rooms:
			for door: Door in room.get_doors():
				if door.used:
					open_ends.append(door.global_position)
				elif door.get_child_count() == 0:
					missing_plugs += 1
			for spawn: SpawnPoint in room.get_spawn_points():
				if spawn.kind == SpawnPoint.Kind.PLAYER:
					if player.global_position.distance_to(spawn.global_position) > 0.01:
						misplaced_players += 1
				else:
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
	_check(mismatched_doors == 0, "every connected door meets its partner in world space (%d bad)" % mismatched_doors)
	_check(missing_plugs == 0, "every unused door is plugged (%d missing)" % missing_plugs)
	_check(bad_spawn_counts == 0, "spawned enemies + pickups match spawn points in every build")
	_check(misplaced_players == 0, "player lands on the START spawn every build")


func _ascii_map(plan: Array[DungeonGenerator.Placement]) -> PackedStringArray:
	var glyph: Dictionary[Vector2i, String] = {}
	var min_cell: Vector2i = Vector2i(1 << 20, 1 << 20)
	var max_cell: Vector2i = -min_cell
	var letters: Dictionary[int, String] = {
		Room.Type.START: "S", Room.Type.CORRIDOR: "c", Room.Type.COMBAT: "C", Room.Type.TREASURE: "T", Room.Type.EXIT: "E",
	}
	for i: int in plan.size():
		var placement: DungeonGenerator.Placement = plan[i]
		# Alternate glyph per room so neighbours of the same type stay distinguishable.
		var letter: String = letters[placement.template.type]
		if i % 2 == 1 and placement.template.type == Room.Type.COMBAT:
			letter = "#"
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
