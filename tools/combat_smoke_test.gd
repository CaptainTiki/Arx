class_name CombatSmokeTest
extends SceneTree
## Drives Main.tscn with synthetic input and checks the core loop end to end:
## data applied -> eat a strike (lunge distance) -> block one -> windup turn cap and facing lock
## -> hit-and-back-off gets caught -> early retreat escapes -> punish until dead.
## Run from the project root:
##   godot --headless --path . --script res://tools/combat_smoke_test.gd

## Spot where the enemy gets parked (facing +Z) before the scripted phases, clear of every wall.
const STAGE_ENEMY: Vector3 = Vector3(0.0, 0.0, -3.0)

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	var data: EnemyData = enemy.data
	var player_health: Health = player.get_node("Health") as Health
	var enemy_health: Health = enemy.get_node("Health") as Health
	await _seconds(0.3)

	print("-- data applied on ready")
	_check(enemy_health.max_hp == data.max_hp and enemy_health.hp == data.max_hp, "Health.max_hp = data.max_hp (%d)" % enemy_health.max_hp)
	var hitbox_shape: CollisionShape3D = enemy.get_node("Hitbox/HitboxShape") as CollisionShape3D
	var box: BoxShape3D = hitbox_shape.shape as BoxShape3D
	_check(is_equal_approx(box.size.z, data.attack_reach), "hitbox length = attack_reach (%.2f)" % box.size.z)

	print("-- walk in, eat a strike")
	Input.action_press(&"move_forward")
	var reached: bool = await _wait_until(func() -> bool: return _distance(player, enemy) < 2.0, 4.0)
	Input.action_release(&"move_forward")
	_check(reached, "player reached the enemy (dist %.2f)" % _distance(player, enemy))
	await _wait_until(func() -> bool: return enemy.get_state_name() == "STRIKE", 5.0)
	var strike_start: Vector3 = enemy.global_position
	var recovered: bool = await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 2.0)
	var lunged: float = _flat(enemy.global_position - strike_start).length()
	_check(recovered, "enemy completed an attack")
	_check(absf(lunged - data.strike_lunge) < 0.05, "strike lunged %.2f m (data %.2f)" % [lunged, data.strike_lunge])
	_check(player_health.hp == 85, "unblocked strike dealt 15 (hp %d)" % player_health.hp)

	print("-- blocked strike")
	Input.action_press(&"block")
	var winding: bool = await _wait_until(func() -> bool: return enemy.get_state_name() == "WINDUP", 5.0)
	_check(winding, "enemy started a second windup")
	recovered = await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 3.0)
	_check(recovered, "enemy completed the second attack")
	_check(player_health.hp == 85, "block absorbed the strike (hp %d)" % player_health.hp)
	Input.action_release(&"block")

	print("-- windup turn cap, facing lock")
	await _wait_until(func() -> bool: return enemy.get_state_name() == "COOLDOWN", 2.0)
	_stage(player, enemy, 1.6)
	await _wait_until(func() -> bool: return enemy.get_state_name() == "WINDUP", 3.0)
	# Jump nearly behind it: 0.7 s at 180°/s can't close a 170° gap, so the strike should whiff.
	var behind: Vector3 = Vector3(sin(deg_to_rad(170.0)), 0.0, cos(deg_to_rad(170.0))) * 1.6
	player.global_position = enemy.global_position + behind
	var yaw_before: float = enemy.rotation.y
	await _seconds(0.2)
	var turned: float = rad_to_deg(absf(angle_difference(yaw_before, enemy.rotation.y)))
	var expected: float = data.windup_turn_rate * 0.2
	_check(absf(turned - expected) < expected * 0.25, "windup turned %.0f° in 0.2 s (cap %.0f°)" % [turned, expected])
	await _wait_until(func() -> bool: return enemy.get_state_name() == "STRIKE", 2.0)
	var locked_yaw: float = enemy.rotation.y
	await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 1.0)
	var parked: Vector3 = enemy.global_position
	var max_turn: float = 0.0
	var max_drift: float = 0.0
	# Sample RECOVER and most of COOLDOWN; stop early enough to restage before CHASE resumes.
	var watch_until: float = _now() + data.recover_time + data.cooldown_time * 0.6
	while _now() < watch_until:
		max_turn = maxf(max_turn, absf(angle_difference(locked_yaw, enemy.rotation.y)))
		max_drift = maxf(max_drift, _flat(enemy.global_position - parked).length())
		await physics_frame
	_check(player_health.hp == 85, "strike from a locked facing whiffed (hp %d)" % player_health.hp)
	_check(max_turn < 0.001, "no turning in RECOVER/COOLDOWN (max %.4f rad)" % max_turn)
	_check(max_drift < 0.01, "no movement in RECOVER/COOLDOWN (max %.3f m)" % max_drift)

	print("-- hit once, then back off: caught by reach + lunge")
	_check(enemy.get_state_name() == "COOLDOWN", "still in COOLDOWN for restage (%s)" % enemy.get_state_name())
	_stage(player, enemy, 1.6)
	await _wait_until(func() -> bool: return enemy.get_state_name() == "WINDUP", 3.0)
	_click_attack()
	await _seconds(0.45)
	Input.action_press(&"move_back")
	await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 1.5)
	Input.action_release(&"move_back")
	_check(enemy_health.hp == 75, "the trade landed through super armor (enemy hp %d)" % enemy_health.hp)
	_check(player_health.hp == 70, "late retreat got caught (hp %d)" % player_health.hp)

	print("-- back off at windup start: escapes")
	await _wait_until(func() -> bool: return enemy.get_state_name() == "COOLDOWN", 2.0)
	_stage(player, enemy, 1.6)
	await _wait_until(func() -> bool: return enemy.get_state_name() == "WINDUP", 3.0)
	Input.action_press(&"move_back")
	await _wait_until(func() -> bool: return enemy.get_state_name() == "RECOVER", 1.5)
	Input.action_release(&"move_back")
	_check(player_health.hp == 70, "early retreat escaped (hp %d)" % player_health.hp)

	print("-- punish")
	player.global_position = enemy.global_position + enemy.global_basis.z * -1.4
	player.rotation.y = enemy.rotation.y + PI
	var swings: int = 0
	while not enemy.is_dead() and swings < 8:
		_click_attack()
		swings += 1
		await _seconds(0.5)
		print("   swing %d: enemy hp %d, state %s, time_scale %.2f" % [swings, enemy_health.hp, enemy.get_state_name(), Engine.time_scale])
	_check(enemy.is_dead(), "enemy died")
	_check(swings == 3, "3 more swings finished it (took %d)" % swings)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time_scale restored after hitstop")

	await _seconds(data.despawn_delay + 0.3)
	_check(not is_instance_valid(enemy), "corpse despawned")

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## Parks the enemy facing +Z and puts the player `gap` meters in front of it, facing it.
func _stage(player: Player, enemy: Enemy, gap: float) -> void:
	enemy.global_position = STAGE_ENEMY
	enemy.rotation.y = PI
	player.global_position = STAGE_ENEMY + Vector3(0.0, 0.0, gap)
	player.rotation.y = 0.0


func _click_attack() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = &"attack"
		event.pressed = pressed
		Input.parse_input_event(event)


func _distance(a: Node3D, b: Node3D) -> float:
	return _flat(a.global_position - b.global_position).length()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _check(ok: bool, label: String) -> void:
	print("   [%s] %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _seconds(duration: float) -> void:
	await create_timer(duration, true, false, true).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline: float = _now() + timeout
	while _now() < deadline:
		if condition.call():
			return true
		await physics_frame
	return false
