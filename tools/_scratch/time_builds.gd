extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var generator: DungeonGenerator = main.get_node("DungeonGenerator") as DungeonGenerator
	generator.print_spawn_log = false
	var t0: int = Time.get_ticks_msec()
	for s: int in range(1, 21):
		generator.generate(s)
		await process_frame
	print("20 builds: %d ms" % (Time.get_ticks_msec() - t0))
	quit()
