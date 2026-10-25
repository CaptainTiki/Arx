class_name CombatSmokeTest
extends SceneTree
## Drives Main.tscn with synthetic input and checks the core loop end to end:
## walk in -> eat one strike -> block the next -> swing until the dummy dies.
## Run from the project root:
##   godot --headless --path . --script res://tools/combat_smoke_test.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	var player_health: Health = player.get_node("Health") as Health
	var enemy_health: Health = enemy.get_node("Health") as Health
	await _seconds(0.3)

	print("-- walk in")
	Input.action_press(&"move_forward")
	var reached: bool = await _wait_until(func() -> bool: return _distance(player, enemy) < 2.0, 4.0)
	Input.action_release(&"move_forward")
	_check(reached, "player reached the enemy (dist %.2f)" % _distance(player, enemy))

	print("-- unblocked strike")
	var recovered: bool = await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 5.0)
	_check(recovered, "enemy completed an attack")
	_check(player_health.hp == 85, "unblocked strike dealt 15 (hp %d)" % player_health.hp)

	print("-- blocked strike")
	Input.action_press(&"block")
	var winding: bool = await _wait_until(func() -> bool: return enemy.get_state_name() == "WINDUP", 5.0)
	_check(winding, "enemy started a second windup")
	recovered = await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 3.0)
	_check(recovered, "enemy completed the second attack")
	_check(player_health.hp == 85, "block absorbed the strike (hp %d)" % player_health.hp)
	Input.action_release(&"block")

	print("-- punish")
	var swings: int = 0
	while not enemy.is_dead() and swings < 8:
		_click_attack()
		swings += 1
		await _seconds(0.5)
		print("   swing %d: enemy hp %d, state %s, time_scale %.2f" % [swings, enemy_health.hp, enemy.get_state_name(), Engine.time_scale])
	_check(enemy.is_dead(), "enemy died")
	_check(swings == 4, "took exactly 4 swings (took %d)" % swings)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time_scale restored after hitstop")

	await _seconds(3.3)
	_check(not is_instance_valid(enemy), "corpse despawned")

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _click_attack() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = &"attack"
		event.pressed = pressed
		Input.parse_input_event(event)


func _distance(a: Node3D, b: Node3D) -> float:
	var offset: Vector3 = a.global_position - b.global_position
	return Vector2(offset.x, offset.z).length()


func _check(ok: bool, label: String) -> void:
	print("   [%s] %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline: float = Time.get_ticks_msec() / 1000.0 + timeout
	while Time.get_ticks_msec() / 1000.0 < deadline:
		if condition.call():
			return true
		await physics_frame
	return false
