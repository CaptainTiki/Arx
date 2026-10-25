class_name CombatSmokeTest
extends SceneTree
## Drives Main.tscn with synthetic input and checks the loop end to end.
## Part A: pickups and equip. Prompt, blocked while blocking, swap-in-place both ways, equip
## queued mid-swing, and a probe per weapon measuring the actual swing against its WeaponData.
## Part B (fresh scene): grunt behaviour. Data applied, lunge, block, windup turn cap, facing
## lock, hit-and-back-off caught, early retreat escapes, punish to the kill.
## Run from the project root:
##   godot --headless --path . --script res://tools/combat_smoke_test.gd

## Spot where the enemy gets parked (facing +Z) before scripted phases, clear of every wall.
const STAGE_ENEMY: Vector3 = Vector3(0.0, 0.0, -3.0)
## Somewhere the grunt can't reach the player for a couple of seconds.
const PARK_ENEMY: Vector3 = Vector3(4.5, 0.0, -4.5)
## Timing tolerance for measured swings: physics ticks are 1/60 s and the hitbox toggle is deferred.
const TIME_TOLERANCE: float = 0.04

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _seconds(0.5)
	await _part_pickups(main)

	print("== reloading for part B")
	reload_current_scene()
	await process_frame
	await process_frame
	await _seconds(0.5)
	await _part_grunt(current_scene)

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _part_pickups(main: Node) -> void:
	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	var rig: WeaponRig = player.get_node("%WeaponRig") as WeaponRig
	var prompt: Label = player.get_node("%PromptLabel") as Label
	var axe_pickup: Pickup = main.get_node("Pickups/AxePickup") as Pickup
	var sword: WeaponData = player.starting_weapon
	var axe: WeaponData = axe_pickup.item as WeaponData
	var dagger: WeaponData = (main.get_node("Pickups/DaggerPickup") as Pickup).item as WeaponData

	print("-- starting weapon")
	_check(rig.weapon == sword and rig.can_interact(), "equipped %s on ready" % rig.weapon.display_name)

	print("-- prompt and swap-in-place")
	player.global_position = axe_pickup.global_position + Vector3(0.0, 0.0, 1.2)
	_aim_at(player, axe_pickup.global_position + Vector3(0.0, 0.1, 0.0))
	await _physics_frames(3)
	_check(prompt.visible and prompt.text == "[E] Take Woodcutter's Axe", "prompt shows '%s'" % prompt.text)

	Input.action_press(&"block")
	await _physics_frames(3)
	_check(not prompt.visible, "prompt hidden while blocking")
	_tap(&"interact")
	await _physics_frames(3)
	_check(rig.weapon == sword and axe_pickup.item == axe, "interact ignored while blocking")
	Input.action_release(&"block")
	await _physics_frames(3)

	_tap(&"interact")
	await _physics_frames(2)
	_check(rig.weapon == axe and axe_pickup.item == sword, "took the axe; pickup now holds the sword")
	_check(not prompt.visible and not rig.can_interact(), "equip animation locks interaction")
	await _wait_until(func() -> bool: return rig.can_interact(), 1.0)
	await _physics_frames(2)
	_check(prompt.visible and prompt.text == "[E] Take Rusty Sword", "prompt now '%s'" % prompt.text)
	_check(is_equal_approx(_hitbox_box(player).size.z, axe.attack_reach), "hitbox length = axe reach (%.2f)" % _hitbox_box(player).size.z)
	_check(is_equal_approx(_hitbox_back(player), -0.15), "hitbox near edge stayed put (%.3f)" % _hitbox_back(player))
	var keys: Vector2 = _swing_keys(player)
	_check(is_equal_approx(keys.x, axe.active_start / axe.swing_time) and is_equal_approx(keys.y, axe.active_end / axe.swing_time),
		"swing keys at %.3f / %.3f normalized" % [keys.x, keys.y])

	_tap(&"interact")
	await _physics_frames(2)
	_check(rig.weapon == sword and axe_pickup.item == axe, "swapped back: sword in hand, axe on the floor")
	await _wait_until(func() -> bool: return rig.can_interact(), 1.0)

	print("-- equip mid-swing waits for IDLE")
	player.global_position = Vector3(0.0, 0.0, 3.0)
	player.rotation.y = PI
	var swing_start: float = _now()
	rig.try_swing()
	await _seconds(0.05)
	rig.equip(dagger)
	_check(rig.weapon == sword, "still holding the sword mid-swing")
	await _wait_until(func() -> bool: return rig.weapon == dagger, 1.5)
	var swapped_at: float = _now() - swing_start
	_check(rig.weapon == dagger and swapped_at >= sword.swing_time - TIME_TOLERANCE, "dagger applied after the swing (%.2f s in)" % swapped_at)
	await _wait_until(func() -> bool: return rig.can_interact(), 1.0)

	print("-- per-weapon whiff probe (facing away from the grunt)")
	for weapon: WeaponData in [sword, axe, dagger]:
		await _equip_and_wait(rig, weapon)
		await _probe_swing(player, rig, weapon)

	print("-- per-weapon damage")
	for weapon: WeaponData in [sword, axe, dagger]:
		enemy.global_position = PARK_ENEMY
		player.global_position = Vector3(0.0, 0.0, 2.0)
		await _equip_and_wait(rig, weapon)
		_stage(player, enemy, 1.3)
		var enemy_health: Health = enemy.get_node("Health") as Health
		var hp_before: int = enemy_health.hp
		rig.try_swing()
		await _wait_until(func() -> bool: return rig.can_interact(), weapon.swing_time + 0.5)
		var dealt: int = hp_before - enemy_health.hp
		_check(dealt == weapon.damage, "%s dealt %d (data %d) -> %d hits to kill a %d HP grunt"
			% [weapon.display_name, dealt, weapon.damage, ceili(float(enemy.data.max_hp) / weapon.damage), enemy.data.max_hp])
	enemy.global_position = PARK_ENEMY


## Swings at nothing and compares what happened with the weapon's data.
func _probe_swing(player: Player, rig: WeaponRig, weapon: WeaponData) -> void:
	var stamina: Stamina = player.get_node("Stamina") as Stamina
	var hitbox: MeleeHitbox = player.get_node("%Hitbox") as MeleeHitbox
	player.rotation.y = PI
	var start_pos: Vector3 = player.global_position
	var stamina_before: float = stamina.current
	var t0: float = _now()
	rig.try_swing()
	var spent: float = stamina_before - stamina.current
	var opened: float = -1.0
	var closed: float = -1.0
	while not rig.can_interact() and _now() - t0 < weapon.swing_time + 1.0:
		await physics_frame
		var t: float = _now() - t0
		if hitbox.monitoring and opened < 0.0:
			opened = t
		if not hitbox.monitoring and opened >= 0.0 and closed < 0.0:
			closed = t
	var duration: float = _now() - t0
	var lunged: float = _flat(player.global_position - start_pos).length()
	print("   %s: swing %.3f s (data %.2f), hitbox %.3f-%.3f s (data %.2f-%.2f), lunge %.2f m (data %.2f), stamina -%d (data %d)"
		% [weapon.display_name, duration, weapon.swing_time, opened, closed, weapon.active_start, weapon.active_end,
		lunged, weapon.lunge_distance, int(spent), weapon.stamina_cost])
	_check(absf(duration - weapon.swing_time) < TIME_TOLERANCE, "%s swing length" % weapon.display_name)
	_check(absf(opened - weapon.active_start) < TIME_TOLERANCE and absf(closed - weapon.active_end) < TIME_TOLERANCE, "%s active window" % weapon.display_name)
	_check(absf(lunged - weapon.lunge_distance) < 0.05, "%s lunge" % weapon.display_name)
	_check(is_equal_approx(spent, float(weapon.stamina_cost)), "%s stamina cost" % weapon.display_name)
	player.global_position = start_pos


func _part_grunt(main: Node) -> void:
	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	var data: EnemyData = enemy.data
	var player_health: Health = player.get_node("Health") as Health
	var enemy_health: Health = enemy.get_node("Health") as Health

	print("-- data applied on ready")
	_check(enemy_health.max_hp == data.max_hp and enemy_health.hp == data.max_hp, "Health.max_hp = data.max_hp (%d)" % enemy_health.max_hp)
	var box: BoxShape3D = (enemy.get_node("Hitbox/HitboxShape") as CollisionShape3D).shape as BoxShape3D
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
	_tap(&"attack")
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
		_tap(&"attack")
		swings += 1
		await _seconds(0.5)
		print("   swing %d: enemy hp %d, state %s, time_scale %.2f" % [swings, enemy_health.hp, enemy.get_state_name(), Engine.time_scale])
	_check(enemy.is_dead(), "enemy died")
	_check(swings == 3, "3 more swings finished it (took %d)" % swings)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time_scale restored after hitstop")

	await _seconds(data.despawn_delay + 0.3)
	_check(not is_instance_valid(enemy), "corpse despawned")


func _equip_and_wait(rig: WeaponRig, weapon: WeaponData) -> void:
	await _wait_until(func() -> bool: return rig.can_interact(), 1.5)
	rig.equip(weapon)
	await _wait_until(func() -> bool: return rig.can_interact(), 1.5)


## Parks the enemy facing +Z and puts the player `gap` meters in front of it, facing it.
func _stage(player: Player, enemy: Enemy, gap: float) -> void:
	enemy.global_position = STAGE_ENEMY
	enemy.rotation.y = PI
	player.global_position = STAGE_ENEMY + Vector3(0.0, 0.0, gap)
	player.rotation.y = 0.0


func _aim_at(player: Player, point: Vector3) -> void:
	var head: Node3D = player.get_node("Head") as Node3D
	var to_point: Vector3 = point - head.global_position
	player.rotation.y = atan2(-to_point.x, -to_point.z)
	head.rotation.x = atan2(to_point.y, Vector2(to_point.x, to_point.z).length())


func _hitbox_box(player: Player) -> BoxShape3D:
	return (player.get_node("%HitboxShape") as CollisionShape3D).shape as BoxShape3D


func _hitbox_back(player: Player) -> float:
	var shape: CollisionShape3D = player.get_node("%HitboxShape") as CollisionShape3D
	return shape.position.z + (shape.shape as BoxShape3D).size.z * 0.5


## Normalized times of the swing clip's begin_swing / end_swing keys.
func _swing_keys(player: Player) -> Vector2:
	var swing: Animation = (player.get_node("%AnimationPlayer") as AnimationPlayer).get_animation(&"swing")
	var track: int = swing.find_track(NodePath("Hitbox"), Animation.TYPE_METHOD)
	var keys: Vector2 = Vector2.ZERO
	for key: int in swing.track_get_key_count(track):
		var t: float = swing.track_get_key_time(track, key) / swing.length
		if swing.method_track_get_name(track, key) == &"begin_swing":
			keys.x = t
		else:
			keys.y = t
	return keys


func _tap(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
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


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline: float = _now() + timeout
	while _now() < deadline:
		if condition.call():
			return true
		await physics_frame
	return false
