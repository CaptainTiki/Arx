class_name CaptureDungeon
extends SceneTree
## Renders generated floors: for each seed, a top-down view (ceilings hidden) and the view from spawn.
## Needs a window (not --headless). Run from the project root:
##   godot --path . --script res://tools/capture_dungeon.gd -- <output.png> [seed seed ...]

const CELL_SCALE: float = 0.5

var _cells: Array[Image] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://capture_dungeon.png"
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
	var dungeon: Node3D = main.get_node("Dungeon") as Node3D
	var player: Player = main.get_node("Player") as Player
	var player_camera: Camera3D = player.get_node("%Camera3D") as Camera3D
	var environment: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var overhead: Camera3D = (load("res://tests/OverheadCamera.tscn") as PackedScene).instantiate() as Camera3D
	main.add_child(overhead)

	var overview: Array[Image] = []
	var spawn_views: Array[Image] = []
	for s: int in seeds:
		generator.seed_value = s
		generator.generate()
		await _seconds(0.3)
		# View from spawn first, as the player sees it.
		player_camera.make_current()
		await _seconds(0.1)
		spawn_views.append(await _grab())
		# Top-down: ceilings off, flat bright light, no fog, framed on the floor's bounds.
		var bounds: AABB = AABB()
		var first: bool = true
		for child: Node in dungeon.get_children():
			var room: Room = child as Room
			if room == null:
				continue
			(room.get_node("Geometry/Ceiling") as Node3D).visible = false
			var size: Vector2 = Vector2(DungeonGenerator.rotated_footprint(room.footprint, room.turns)) * Room.CELL_SIZE
			var box: AABB = AABB(Vector3(room.grid_origin.x * Room.CELL_SIZE, 0.0, room.grid_origin.y * Room.CELL_SIZE), Vector3(size.x, 1.0, size.y))
			bounds = box if first else bounds.merge(box)
			first = false
		var center: Vector3 = bounds.get_center()
		overhead.position = Vector3(center.x, 80.0, center.z)
		# Orthographic size is the view height; widen for a 16:9 window when the floor is wider than tall.
		overhead.size = maxf(bounds.size.z, bounds.size.x / 1.78) * 1.05
		var energy: float = environment.ambient_light_energy
		environment.ambient_light_energy = 2.5
		environment.fog_enabled = false
		overhead.make_current()
		await _seconds(0.1)
		overview.append(await _grab())
		environment.ambient_light_energy = energy
		environment.fog_enabled = true
	_cells.append_array(overview)
	_cells.append_array(spawn_views)
	_write_sheet(out_path, seeds.size())
	quit()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.resize(int(image.get_width() * CELL_SCALE), int(image.get_height() * CELL_SCALE), Image.INTERPOLATE_BILINEAR)
	return image


func _write_sheet(path: String, columns: int) -> void:
	var cell_w: int = _cells[0].get_width()
	var cell_h: int = _cells[0].get_height()
	var rows: int = ceili(float(_cells.size()) / columns)
	var sheet: Image = Image.create_empty(cell_w * columns, cell_h * rows, false, _cells[0].get_format())
	for i: int in _cells.size():
		var at: Vector2i = Vector2i((i % columns) * cell_w, floori(float(i) / columns) * cell_h)
		sheet.blit_rect(_cells[i], Rect2i(Vector2i.ZERO, Vector2i(cell_w, cell_h)), at)
	sheet.save_png(path)
	print("Wrote ", path)


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout
