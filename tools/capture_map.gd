class_name CaptureMap
extends SceneTree
## Renders the maps for generated floors. For each seed it walks the floor (teleporting room to room,
## which reveals them) except the last two branch rooms, ending in the exit, then grabs the corner
## minimap (cropped and doubled) and the M full map. One row per seed.
## Needs a window (not --headless). Run from the project root:
##   godot --path . --script res://tools/capture_map.gd -- <output.png> [seed seed ...]

## Top-left screen area holding the corner map, grabbed at full size then doubled.
const CORNER: Rect2i = Rect2i(0, 24, 200, 200)
const ROW_HEIGHT: int = 400


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://capture_map.png"
	var seeds: Array[int] = [1, 2, 3]
	if args.size() > 1:
		seeds.clear()
		for i: int in range(1, args.size()):
			seeds.append(int(args[i]))
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var generator: DungeonGenerator = main.get_node("DungeonGenerator") as DungeonGenerator
	var dungeon: Dungeon = main.get_node("Dungeon") as Dungeon
	var player: Player = main.get_node("Player") as Player
	var hud: Hud = player.get_node("%HUD") as Hud
	var rows: Array[Image] = []
	for s: int in seeds:
		generator.seed_value = s
		generator.generate()
		await _seconds(0.3)
		# Walk everything but the last two branch rooms planned, so some doorways still lead somewhere unseen.
		var plan: Array[DungeonGenerator.Placement] = _plan_of(generator, s)
		var skip: Dictionary[int, bool] = {}
		for i: int in range(plan.size() - 1, -1, -1):
			if skip.size() < 2 and not plan[i].main_path and not plan[i].loop:
				skip[i] = true
		var last: MapModel.MapRoom = null
		for i: int in dungeon.map.rooms.size():
			if skip.has(i) or dungeon.map.rooms[i].type == Room.Type.EXIT:
				continue
			last = dungeon.map.rooms[i]
			player.global_position = Vector3(last.center().x, 0.0, last.center().y) * Room.CELL_SIZE
			await physics_frame
			await physics_frame
		# Peek into the exit last, so the player stands next to it.
		for room: MapModel.MapRoom in dungeon.map.rooms:
			if room.type == Room.Type.EXIT:
				player.global_position = Vector3(room.center().x, 0.0, room.center().y) * Room.CELL_SIZE
				await physics_frame
				await physics_frame
		player.rotation.y = deg_to_rad(30.0)
		await _seconds(0.25)
		var frame: Image = await _grab()
		var corner: Image = frame.get_region(CORNER)
		corner.resize(CORNER.size.x * 2, CORNER.size.y * 2, Image.INTERPOLATE_NEAREST)
		hud.toggle_full_map()
		await _seconds(0.25)
		var full: Image = await _grab()
		hud.toggle_full_map()
		full.resize(int(full.get_width() * float(ROW_HEIGHT) / full.get_height()), ROW_HEIGHT, Image.INTERPOLATE_BILINEAR)
		var row: Image = Image.create_empty(corner.get_width() + full.get_width(), ROW_HEIGHT, false, full.get_format())
		corner.convert(full.get_format())
		row.blit_rect(corner, Rect2i(Vector2i.ZERO, corner.get_size()), Vector2i.ZERO)
		row.blit_rect(full, Rect2i(Vector2i.ZERO, full.get_size()), Vector2i(corner.get_width(), 0))
		rows.append(row)
		print("seed %d: %s" % [s, DungeonGenerator.describe_plan(_plan_of(generator, s))])
	var sheet: Image = Image.create_empty(rows[0].get_width(), ROW_HEIGHT * rows.size(), false, rows[0].get_format())
	for i: int in rows.size():
		sheet.blit_rect(rows[i], Rect2i(Vector2i.ZERO, rows[i].get_size()), Vector2i(0, i * ROW_HEIGHT))
	sheet.save_png(out_path)
	print("Wrote ", out_path)
	quit()


func _plan_of(generator: DungeonGenerator, s: int) -> Array[DungeonGenerator.Placement]:
	return generator.plan_layout(generator.last_seed if generator.last_seed != 0 else s)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout
