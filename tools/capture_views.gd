class_name CaptureViews
extends SceneTree
## Renders key poses (rest, swing frames, block, enemy windup) into one contact sheet PNG.
## Needs a window (not --headless). Run from the project root:
##   godot --path . --script res://tools/capture_views.gd -- <output.png>

const CELL_SCALE: float = 0.5
const COLUMNS: int = 3

var _cells: Array[Image] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://capture_views.png"
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	var anim: AnimationPlayer = player.get_node("%AnimationPlayer") as AnimationPlayer
	await _seconds(0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _seconds(0.8)
	await _grab()

	# Viewmodel poses at fixed animation times.
	for t: float in [0.09, 0.15, 0.2, 0.27]:
		anim.play(&"swing")
		anim.seek(t, true)
		anim.pause()
		await _grab()
	anim.play(&"block_raise")
	anim.seek(0.12, true)
	anim.pause()
	await _grab()

	# Scrubbing can fire the swing's begin_swing key without its end_swing; close the hitbox.
	(player.get_node("%Hitbox") as MeleeHitbox).end_swing()

	# Step in and catch the enemy mid-windup.
	anim.play(&"RESET")
	player.global_position = Vector3(0.0, 0.0, -0.1)
	await _wait_until(func() -> bool: return enemy.get_state_name() == "WINDUP", 4.0)
	await _seconds(0.05)
	await _grab()
	await _seconds(0.45)
	await _grab()

	# Land a hit (flash, hit puff, hitstop) and catch it during and just after the freeze.
	var rig: WeaponRig = player.get_node("%WeaponRig") as WeaponRig
	rig.call(&"_on_hit_landed", enemy)
	await _seconds(0.02)
	await _grab()
	await _seconds(0.1)
	await _grab()

	# Raise the block and take a strike on it (clang, block spark, shake).
	anim.play(&"block_raise")
	anim.seek(0.12, true)
	anim.pause()
	await _seconds(0.3)
	rig.play_block_impact()
	await _seconds(0.03)
	await _grab()
	await _seconds(0.08)
	await _grab()

	_write_sheet(out_path)
	quit()


func _grab() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.resize(int(image.get_width() * CELL_SCALE), int(image.get_height() * CELL_SCALE), Image.INTERPOLATE_BILINEAR)
	_cells.append(image)


func _write_sheet(path: String) -> void:
	var cell_w: int = _cells[0].get_width()
	var cell_h: int = _cells[0].get_height()
	var rows: int = ceili(float(_cells.size()) / COLUMNS)
	var sheet: Image = Image.create_empty(cell_w * COLUMNS, cell_h * rows, false, _cells[0].get_format())
	for i: int in _cells.size():
		var at: Vector2i = Vector2i((i % COLUMNS) * cell_w, floori(float(i) / COLUMNS) * cell_h)
		sheet.blit_rect(_cells[i], Rect2i(Vector2i.ZERO, Vector2i(cell_w, cell_h)), at)
	sheet.save_png(path)
	print("Wrote ", path)


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline: float = Time.get_ticks_msec() / 1000.0 + timeout
	while Time.get_ticks_msec() / 1000.0 < deadline:
		if condition.call():
			return true
		await physics_frame
	return false
