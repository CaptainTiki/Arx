class_name CombatSmokeTest
extends SceneTree
## Drives Main.tscn with synthetic input and checks the loop end to end.
## Part A: inventory and weapons. Pickups into the bag, Tab pause, every drop rule through the
## slots' own handlers, right-click shortcuts, drop to world and back, armour, full-bag reject,
## equip queued mid-swing, and a probe per weapon measuring the actual swing against its WeaponData.
## Part B (fresh scene): grunt behaviour. Data applied, lunge, block, windup turn cap, facing
## lock, hit-and-back-off caught, early retreat escapes, punish to the kill.
## Part C (fresh scene): variants. Bruiser hits for its damage and doesn't flinch; skitterer
## outruns your walk and winds up in its 0.35 s.
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
	var main: Node = (load("res://tests/CombatArena.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _seconds(0.5)
	await _part_inventory(main)

	print("== reloading for part B")
	reload_current_scene()
	await process_frame
	await process_frame
	await _seconds(0.5)
	await _part_grunt(current_scene)

	print("== reloading for part C")
	reload_current_scene()
	await process_frame
	await process_frame
	await _seconds(0.5)
	await _part_variants(current_scene)

	# Let in-flight SFX finish so the audio server releases them before shutdown.
	await _seconds(1.0)
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _part_inventory(main: Node) -> void:
	var player: Player = main.get_node("Player") as Player
	var enemy: Enemy = main.get_node("Enemy") as Enemy
	var rig: WeaponRig = player.get_node("%WeaponRig") as WeaponRig
	var inventory: Inventory = player.inventory
	var hud: Hud = player.get_node("%HUD") as Hud
	var screen: InventoryScreen = player.get_node("%InventoryScreen") as InventoryScreen
	var drops: Node3D = main.get_node("Pickups") as Node3D
	var axe_pickup: Pickup = main.get_node("Pickups/AxePickup") as Pickup
	var dagger_pickup: Pickup = main.get_node("Pickups/DaggerPickup") as Pickup
	var sword_pickup: Pickup = main.get_node("Pickups/SwordPickup") as Pickup
	var sword: WeaponData = player.starting_weapon
	var axe: WeaponData = axe_pickup.item as WeaponData
	var dagger: WeaponData = dagger_pickup.item as WeaponData
	var iron_cap: ArmorData = load("res://items/armor/iron_cap.tres") as ArmorData
	var vest: ArmorData = load("res://items/armor/rawhide_vest.tres") as ArmorData
	var weapon_slot: EquipSlot = screen.get_node("Root/PaperDoll/WeaponSlot") as EquipSlot
	var head_slot: EquipSlot = screen.get_node("Root/PaperDoll/HeadSlot") as EquipSlot
	var chest_slot: EquipSlot = screen.get_node("Root/PaperDoll/ChestSlot") as EquipSlot
	const WEAPON: ItemData.Slot = ItemData.Slot.WEAPON

	print("-- start: sword equipped, bag empty")
	_check(inventory.get_equipped(WEAPON) == sword and rig.weapon == sword and inventory.bag.count(null) == Inventory.COLS * Inventory.ROWS,
		"equipped %s, %d empty squares" % [rig.weapon.display_name, inventory.bag.count(null)])

	print("-- E puts pickups in the bag")
	_look_at_pickup(player, axe_pickup)
	await _physics_frames(5)
	_check(hud.prompt_text_shown() == "[E] Take Woodcutter's Axe", "prompt shows '%s'" % hud.prompt_text_shown())
	Input.action_press(&"block")
	await _physics_frames(3)
	_tap(&"interact")
	await _physics_frames(3)
	_check(hud.prompt_text_shown() == "" and is_instance_valid(axe_pickup) and inventory.bag[0] == null, "prompt hidden and E ignored while blocking")
	Input.action_release(&"block")
	await _physics_frames(3)
	_tap(&"interact")
	await _physics_frames(3)
	_check(inventory.bag[0] == axe and not is_instance_valid(axe_pickup) and rig.weapon == sword, "axe went to square 0, pickup consumed, still holding the sword")
	_look_at_pickup(player, dagger_pickup)
	await _physics_frames(5)
	_tap(&"interact")
	await _physics_frames(3)
	_check(inventory.bag[1] == dagger, "dagger went to square 1")

	print("-- Tab opens a paused screen")
	_tap(&"inventory")
	# The screen consumes Tab in its _process, so wait on the result rather than a frame count.
	await _wait_until(func() -> bool: return screen.is_open(), 1.0)
	_check(screen.is_open() and paused, "screen open, tree paused")

	print("-- drop rules (driving the slots' own drop handlers)")
	_check(not head_slot._can_drop_data(Vector2.ZERO, _bag(screen, 0).make_payload()), "bag -> equip: axe refused by the HEAD slot")
	_check(weapon_slot._can_drop_data(Vector2.ZERO, _bag(screen, 0).make_payload()), "bag -> equip: axe accepted by the WEAPON slot")
	weapon_slot._drop_data(Vector2.ZERO, _bag(screen, 0).make_payload())
	_check(inventory.get_equipped(WEAPON) == axe and inventory.bag[0] == sword and rig.weapon == axe and _held_mesh(player) == axe.view_mesh,
		"axe equipped while paused (viewmodel already swapped), sword dropped into its square")
	_bag(screen, 1)._drop_data(Vector2.ZERO, _bag(screen, 0).make_payload())
	_check(inventory.bag[0] == dagger and inventory.bag[1] == sword, "bag -> bag swaps")
	_bag(screen, 5)._drop_data(Vector2.ZERO, _bag(screen, 1).make_payload())
	_check(inventory.bag[5] == sword and inventory.bag[1] == null, "bag -> empty bag square moves")
	_check(not head_slot._can_drop_data(Vector2.ZERO, weapon_slot.make_payload()) and not weapon_slot._can_drop_data(Vector2.ZERO, weapon_slot.make_payload()),
		"equip -> equip refused")
	_check(_bag(screen, 0)._can_drop_data(Vector2.ZERO, weapon_slot.make_payload()), "equip -> bag onto a fitting item allowed")
	_bag(screen, 0)._drop_data(Vector2.ZERO, weapon_slot.make_payload())
	_check(inventory.get_equipped(WEAPON) == dagger and inventory.bag[0] == axe, "equip -> bag onto a weapon swaps them")
	inventory.put_in_bag(2, vest)
	_check(not _bag(screen, 2)._can_drop_data(Vector2.ZERO, weapon_slot.make_payload()), "equip -> bag onto a non-fitting item (vest) refused")
	_bag(screen, 3)._drop_data(Vector2.ZERO, weapon_slot.make_payload())
	_check(inventory.get_equipped(WEAPON) == null and inventory.bag[3] == dagger and rig.weapon == null and _held_mesh(player) == null,
		"equip -> empty square: weapon off, fists (no mesh)")
	_check(not rig.try_swing(), "fists can't swing")
	_bag(screen, 3).quick_action()
	_check(inventory.get_equipped(WEAPON) == dagger and inventory.bag[3] == null, "right-click bag item equips it")
	_bag(screen, 2).quick_action()
	_check(inventory.get_equipped(ItemData.Slot.CHEST) == vest and chest_slot.get_item() == vest, "right-click vest wears it")
	weapon_slot.quick_action()
	_check(inventory.get_equipped(WEAPON) == null and inventory.bag[1] == dagger, "right-click equipped item unequips to the first free square")
	_bag(screen, 0).quick_action()
	_check(inventory.get_equipped(WEAPON) == axe, "axe back in hand")
	_check(InventoryScreen.describe(iron_cap) == "Iron Cap\nHead\nArmour 3" and InventoryScreen.describe(axe) == "Woodcutter's Axe\nWeapon\nDamage 45",
		"tooltip text: name, slot, damage/armour")
	var armour_label: Label = screen.get_node("%ArmourLabel") as Label
	_check(armour_label.text == "Armour: 2", "stats show '%s'" % armour_label.text)
	var tooltip: Control = screen.get_node("%Tooltip") as Control
	var tooltip_label: Label = screen.get_node("%TooltipLabel") as Label
	screen._on_slot_hovered(chest_slot)
	_check(tooltip.visible and tooltip_label.text == "Rawhide Vest\nChest\nArmour 2", "hovering the vest shows '%s'" % tooltip_label.text.replace("\n", " / "))
	screen._on_slot_unhovered(chest_slot)
	screen._on_slot_hovered(_bag(screen, Inventory.COLS * Inventory.ROWS - 1))
	_check(not tooltip.visible, "hovering an empty square shows nothing")
	screen._on_slot_unhovered(_bag(screen, Inventory.COLS * Inventory.ROWS - 1))

	print("-- drop to world")
	var before_drop: int = drops.get_child_count()
	screen.drop_to_world(weapon_slot.make_payload())
	var dropped: Pickup = drops.get_child(drops.get_child_count() - 1) as Pickup
	var ahead: float = _flat(dropped.global_position - player.global_position).length()
	_check(drops.get_child_count() == before_drop + 1 and dropped.item == axe and inventory.get_equipped(WEAPON) == null and rig.weapon == null,
		"dragged the axe onto the background: it's on the floor, hands empty")
	_check(absf(ahead - player.drop_distance) < 0.05 and is_equal_approx(dropped.global_position.y, player.global_position.y), "landed %.2f m ahead, on the floor" % ahead)
	_tap(&"inventory")
	await _wait_until(func() -> bool: return not screen.is_open(), 1.0)
	_check(not screen.is_open() and not paused, "Tab closes and unpauses")
	_look_at_pickup(player, dropped)
	await _physics_frames(5)
	_tap(&"interact")
	await _physics_frames(3)
	var axe_square: int = inventory.bag.find(axe)
	_check(not is_instance_valid(dropped) and axe_square >= 0, "picked the dropped axe back up (square %d)" % axe_square)
	_bag(screen, axe_square).quick_action()
	await _wait_until(func() -> bool: return rig.can_interact(), 1.0)
	_check(rig.weapon == axe and rig.try_swing(), "re-equipped it and it swings")
	await _wait_until(func() -> bool: return rig.can_interact(), 2.0)

	print("-- armour")
	inventory.put_in_bag(inventory.first_free_index(), inventory.unequip(ItemData.Slot.CHEST))
	inventory.equip(iron_cap)
	var player_health: Health = player.health
	var hp_at_hit: int = player_health.hp
	player.take_hit(HitInfo.new(15, enemy, Vector3.FORWARD, true))
	var health_text: Label = player.get_node("%HealthText") as Label
	_check(hp_at_hit - player_health.hp == 12, "iron cap (3): a 15 hit costs %d, HUD reads %s" % [hp_at_hit - player_health.hp, health_text.text])
	hp_at_hit = player_health.hp
	player.take_hit(HitInfo.new(2, enemy, Vector3.FORWARD, true))
	_check(hp_at_hit - player_health.hp == 1, "never below 1 damage")

	print("-- full bag")
	var filler: ItemData = load("res://items/armor/rawhide_boots.tres") as ItemData
	while inventory.try_add(filler):
		pass
	_check(inventory.first_free_index() == -1 and not inventory.try_add(filler), "bag full at %d items" % (Inventory.COLS * Inventory.ROWS))
	_look_at_pickup(player, sword_pickup)
	await _physics_frames(5)
	_tap(&"interact")
	await _physics_frames(3)
	_check(is_instance_valid(sword_pickup) and sword_pickup.is_rejecting() and hud.prompt_text_shown() == "Inventory full",
		"full bag: pickup stays, flips, prompt says '%s'" % hud.prompt_text_shown())
	await _seconds(1.1)
	_check(not hud.is_notice_showing() and hud.prompt_text_shown() == "[E] Take Rusty Sword", "notice clears after 1 s, prompt returns")
	(screen.get_node("Root/PaperDoll/HeadSlot") as EquipSlot).quick_action()
	_check(inventory.get_equipped(ItemData.Slot.HEAD) == iron_cap, "right-click unequip refused with a full bag")
	for i: int in Inventory.COLS * Inventory.ROWS:
		inventory.take_from_bag(i)

	print("-- equip mid-swing waits for IDLE")
	inventory.equip(sword)
	await _wait_until(func() -> bool: return rig.can_interact(), 1.0)
	player.global_position = Vector3(0.0, 0.0, 3.0)
	player.rotation.y = PI
	var swing_start: float = _now()
	rig.try_swing()
	await _seconds(0.05)
	inventory.equip(dagger)
	_check(rig.weapon == sword and inventory.get_equipped(WEAPON) == dagger, "model says dagger, rig still swings the sword")
	await _wait_until(func() -> bool: return rig.weapon == dagger, 1.5)
	var swapped_at: float = _now() - swing_start
	_check(rig.weapon == dagger and swapped_at >= sword.swing_time - TIME_TOLERANCE, "dagger applied after the swing (%.2f s in)" % swapped_at)
	await _wait_until(func() -> bool: return rig.can_interact(), 1.0)
	_check(is_equal_approx(_hitbox_box(player).size.z, dagger.attack_reach) and is_equal_approx(_hitbox_back(player), -0.15),
		"hitbox length = dagger reach (%.2f), near edge stayed put" % _hitbox_box(player).size.z)
	var keys: Vector2 = _swing_keys(player)
	_check(is_equal_approx(keys.x, dagger.active_start / dagger.swing_time) and is_equal_approx(keys.y, dagger.active_end / dagger.swing_time),
		"swing keys at %.3f / %.3f normalized" % [keys.x, keys.y])

	print("-- per-weapon whiff probe (facing away from the grunt)")
	for weapon: WeaponData in [sword, axe, dagger]:
		await _equip_and_wait(inventory, rig, weapon)
		await _probe_swing(player, rig, weapon)

	print("-- per-weapon damage")
	for weapon: WeaponData in [sword, axe, dagger]:
		enemy.global_position = PARK_ENEMY
		player.global_position = Vector3(0.0, 0.0, 2.0)
		await _equip_and_wait(inventory, rig, weapon)
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


func _part_variants(main: Node) -> void:
	var player: Player = main.get_node("Player") as Player
	var player_health: Health = player.get_node("Health") as Health
	var sword: WeaponData = player.starting_weapon
	(main.get_node("Enemy") as Node).queue_free()
	await process_frame

	print("-- bruiser: heavy hit, no flinch")
	var bruiser: Enemy = await _spawn_variant(main, "res://enemy/bruiser.tres")
	_stage(player, bruiser, 2.0)
	var hp_before: int = player_health.hp
	await _wait_until(func() -> bool: return bruiser.get_state_name() == "RECOVER", 4.0)
	var taken: int = hp_before - player_health.hp
	_check(taken == bruiser.data.damage, "bruiser strike dealt %d (data %d): dead in %d hits from full"
		% [taken, bruiser.data.damage, ceili(float(player_health.max_hp) / bruiser.data.damage)])
	var bruiser_health: Health = bruiser.get_node("Health") as Health
	var bruiser_hp: int = bruiser_health.hp
	_tap(&"attack")
	await _seconds(0.35)
	_check(bruiser_health.hp == bruiser_hp - sword.damage and bruiser.get_state_name() == "RECOVER",
		"sword hit in RECOVER: -%d HP, still %s (no flinch)" % [bruiser_hp - bruiser_health.hp, bruiser.get_state_name()])
	bruiser.queue_free()
	await _seconds(0.5)

	print("-- skitterer: outruns your walk, quick tell")
	var skitterer: Enemy = await _spawn_variant(main, "res://enemy/skitterer.tres")
	_stage(player, skitterer, 3.5)
	await _wait_until(func() -> bool: return skitterer.get_state_name() == "CHASE", 1.0)
	await _physics_frames(2)
	var gap_before: float = _distance(player, skitterer)
	await _seconds(0.15)
	var speed: float = (gap_before - _distance(player, skitterer)) / 0.15
	_check(speed > player.walk_speed, "skitterer closes at %.1f m/s (you walk %.1f)" % [speed, player.walk_speed])
	await _wait_until(func() -> bool: return skitterer.get_state_name() == "WINDUP", 2.0)
	var windup_start: float = _now()
	hp_before = player_health.hp
	await _wait_until(func() -> bool: return skitterer.get_state_name() == "STRIKE", 1.0)
	var windup: float = _now() - windup_start
	_check(absf(windup - skitterer.data.windup_time) < TIME_TOLERANCE, "skitterer windup %.2f s (data %.2f)" % [windup, skitterer.data.windup_time])
	await _wait_until(func() -> bool: return skitterer.get_state_name() == "RECOVER", 1.0)
	_check(hp_before - player_health.hp == skitterer.data.damage, "skitterer strike dealt %d (data %d)" % [hp_before - player_health.hp, skitterer.data.damage])


func _spawn_variant(main: Node, data_path: String) -> Enemy:
	var enemy: Enemy = (load("res://enemy/Enemy.tscn") as PackedScene).instantiate() as Enemy
	enemy.data = load(data_path) as EnemyData
	enemy.position = PARK_ENEMY
	main.add_child(enemy)
	await process_frame
	return enemy


func _equip_and_wait(inventory: Inventory, rig: WeaponRig, weapon: WeaponData) -> void:
	await _wait_until(func() -> bool: return rig.can_interact(), 1.5)
	inventory.equip(weapon)
	await _wait_until(func() -> bool: return rig.can_interact(), 1.5)


func _bag(screen: InventoryScreen, index: int) -> BagSlot:
	return screen.get_node("Root/Bag/BagSlot%d" % index) as BagSlot


func _held_mesh(player: Player) -> Mesh:
	return (player.get_node("%SwordMesh") as MeshInstance3D).mesh


## Stands 1.2 m from a pickup and looks at it, so the interact ray lands on it.
func _look_at_pickup(player: Player, pickup: Node3D) -> void:
	player.global_position = pickup.global_position + Vector3(0.0, 0.0, 1.2)
	_aim_at(player, pickup.global_position + Vector3(0.0, 0.1, 0.0))


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


func _process_frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline: float = _now() + timeout
	while _now() < deadline:
		if condition.call():
			return true
		await physics_frame
	return false
