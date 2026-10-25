class_name CaptureViews
extends SceneTree
## Renders a contact sheet: pickups on the floor with the prompt, then each weapon's viewmodel at
## rest, mid-swing and blocking, then the hit puff and block spark.
## Needs a window (not --headless). Run from the project root:
##   godot --path . --script res://tools/capture_views.gd -- <output.png>

const CELL_SCALE: float = 0.5
const COLUMNS: int = 3
## Normalized swing clip time where the blade crosses the center of the screen.
const MID_SWING: float = 0.4444

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
	var rig: WeaponRig = player.get_node("%WeaponRig") as WeaponRig
	var anim: AnimationPlayer = player.get_node("%AnimationPlayer") as AnimationPlayer
	var head: Node3D = player.get_node("Head") as Node3D
	await _seconds(0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _seconds(0.6)

	# Spawn view tilted down a little so both floor pickups are in frame, then each one up close.
	head.rotation.x = deg_to_rad(-22.0)
	await _seconds(0.1)
	await _grab()
	for pickup_name: String in ["AxePickup", "DaggerPickup"]:
		var pickup: Node3D = main.get_node("Pickups/" + pickup_name) as Node3D
		player.global_position = pickup.global_position + Vector3(0.0, 0.0, 1.2)
		_aim_at(player, pickup.global_position + Vector3(0.0, 0.1, 0.0))
		await _seconds(0.15)
		await _grab()
	head.rotation.x = 0.0
	player.global_position = Vector3(0.0, 0.0, 3.0)
	player.rotation.y = 0.0

	# Each weapon: rest, mid-swing, block.
	for weapon_path: String in ["res://weapons/rusty_sword.tres", "res://weapons/woodcutters_axe.tres", "res://weapons/rusted_dagger.tres"]:
		rig.equip(load(weapon_path) as WeaponData)
		await _seconds(0.4)
		await _grab()
		anim.play(&"swing")
		anim.seek(MID_SWING, true)
		anim.pause()
		await _grab()
		anim.play(&"block_raise")
		anim.seek(0.12, true)
		anim.pause()
		await _grab()
		# Scrubbing can fire begin_swing without end_swing; close the hitbox and return to rest.
		(player.get_node("%Hitbox") as MeleeHitbox).end_swing()
		anim.play(&"RESET")
		await _seconds(0.05)

	# Hit puff and block spark up close.
	rig.equip(load("res://weapons/rusty_sword.tres") as WeaponData)
	await _seconds(0.4)
	player.global_position = enemy.global_position + Vector3(0.0, 0.0, 1.6)
	player.rotation.y = 0.0
	await _seconds(0.1)
	rig.call(&"_on_hit_landed", enemy)
	await _seconds(0.08)
	await _grab()
	anim.play(&"block_raise")
	anim.seek(0.12, true)
	anim.pause()
	await _seconds(0.1)
	rig.play_block_impact()
	await _seconds(0.08)
	await _grab()

	_write_sheet(out_path)
	quit()


func _aim_at(player: Player, point: Vector3) -> void:
	var head: Node3D = player.get_node("Head") as Node3D
	var to_point: Vector3 = point - head.global_position
	player.rotation.y = atan2(-to_point.x, -to_point.z)
	head.rotation.x = atan2(to_point.y, Vector2(to_point.x, to_point.z).length())


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
