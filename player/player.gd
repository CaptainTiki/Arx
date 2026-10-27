class_name Player
extends CharacterBody3D
## First-person controller. Reads PlayerIntent, moves and aims, forwards combat input to the WeaponRig.

## Equipped (through the Inventory) on ready. The bag starts empty.
@export var starting_weapon: WeaponData
## Pooled hit/block particles in the level (Main/FX). Optional, so Player.tscn still runs on its own.
@export var fx: FxPool
## Noise goes through here (Dungeon.emit_noise), and the map reads where you are from it.
## Optional; without it the player makes no noise and the map stays blank.
@export var dungeon: Dungeon

@export_group("Noise")
## Radii in meters (before each enemy's hearing). Walking is silent on purpose: that's the sneak.
@export var noise_sword_hit: float = 9.0
@export var noise_block: float = 9.0
@export var noise_whiff: float = 3.0
@export var noise_sprint_step: float = 5.0
@export var sprint_step_interval: float = 0.3
@export var noise_drop: float = 4.0

@export_group("Dropping")
## How far ahead of your feet a dropped item lands. The pickup itself is Dungeon.place_item()'s.
@export var drop_distance: float = 1.0

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var block_speed: float = 2.5
## Speed as a fraction of the forward speed when moving sideways or backwards. Diagonals blend.
## You can't kite: a grunt walks at 3 and lunges 1.4 m, so backing off at 3 means blocking instead.
@export var strafe_speed_mult: float = 0.7
@export var backpedal_speed_mult: float = 0.6
## How fast horizontal velocity reaches target speed, in m/s². High = snappy.
@export var acceleration: float = 45.0

@export_group("Look")
## Radians of turn per pixel of mouse motion.
@export var mouse_sensitivity: float = 0.0022
@export var pitch_limit_deg: float = 85.0

@export_group("Combat")
## dot(forward, to_attacker) above this counts as "in front" for blocking. 0.3 ≈ a 145° cone.
@export var block_cone_dot: float = 0.3
## Stamina a held block spends per point of damage it eats. Runs the bar dry = guard break: the
## block drops, the hit lands, and you're staggered for a beat.
@export var block_stamina_per_damage: float = 1.0
@export var guard_break_shake_deg: float = 3.0
@export var guard_break_shake_time: float = 0.4
@export var hurt_shake_deg: float = 1.2
@export var hurt_shake_time: float = 0.25
@export var death_restart_delay: float = 2.5
## Shown under the crosshair when a pickup bounces off a full bag.
@export var inventory_full_text: String = "Inventory full"
@export var notice_time: float = 1.0

@onready var _intent: PlayerIntent = %PlayerIntent
@onready var _health: Health = %Health
@onready var _stamina: Stamina = %Stamina
@onready var _inventory: Inventory = %Inventory
@onready var _effects: PlayerEffects = %Effects
@onready var _head: Node3D = %Head
@onready var _weapon_rig: WeaponRig = %WeaponRig
@onready var _hud: Hud = %HUD
@onready var _inventory_screen: InventoryScreen = %InventoryScreen
@onready var _hurt_sfx: AudioStreamPlayer = %HurtSfx
@onready var _interact_ray: RayCast3D = %InteractRay

var _move_velocity: Vector3 = Vector3.ZERO
var _lunge_direction: Vector3 = Vector3.ZERO
var _lunge_distance: float = 0.0
var _lunge_duration: float = 0.0
var _lunge_time: float = 0.0
var _dead: bool = false
var _interact_target: Node3D
var _interact_prompt: String = ""
var _sprint_step_left: float = 0.0

## Read-only access for scene-level code (Main's debug keys, the inventory screen, pickups).
var intent: PlayerIntent:
	get:
		return _intent
var inventory: Inventory:
	get:
		return _inventory
var health: Health:
	get:
		return _health
var stamina: Stamina:
	get:
		return _stamina
var effects: PlayerEffects:
	get:
		return _effects


## Emitted after the death delay when something (Main) is listening; otherwise the scene reloads.
signal respawn_requested

var _head_rest_y: float = 0.0
var _base_max_hp: int = 100
var _base_max_stamina: float = 100.0
var _base_regen: float = 30.0


## Gear changed: re-derive the maxima from the scene's base values plus worn affixes. HP keeps its
## current value (clamped), so swapping a +HP piece off doesn't heal or hurt you.
func _apply_gear_stats() -> void:
	var max_hp: int = _base_max_hp + roundi(_inventory.stat_total(Stat.Kind.MAX_HP))
	if max_hp != _health.max_hp:
		_health.set_max_hp(max_hp)
	_stamina.max_stamina = _base_max_stamina + _inventory.stat_total(Stat.Kind.MAX_STAMINA)
	_stamina.current = minf(_stamina.current, _stamina.max_stamina)
	_stamina.regen_per_second = _base_regen + _inventory.stat_total(Stat.Kind.STAMINA_REGEN)
	_stamina.changed.emit(_stamina.current, _stamina.max_stamina)


func _ready() -> void:
	_head_rest_y = _head.position.y
	_hud.bind(_health, _stamina)
	_effects.slow_changed.connect(_hud.set_slowed)
	_health.died.connect(_on_died)
	_base_max_hp = _health.max_hp
	_base_max_stamina = _stamina.max_stamina
	_base_regen = _stamina.regen_per_second
	_inventory.changed.connect(_apply_gear_stats)
	_inventory.equip(starting_weapon)
	_inventory_screen.bind(self)
	_hud.bind_map(dungeon, self)


func _process(delta: float) -> void:
	if _dead:
		return
	var look: Vector2 = _intent.look
	rotate_y(-look.x * mouse_sensitivity)
	var pitch_limit: float = deg_to_rad(pitch_limit_deg)
	_head.rotation.x = clampf(_head.rotation.x - look.y * mouse_sensitivity, -pitch_limit, pitch_limit)
	var flat_speed: float = Vector2(velocity.x, velocity.z).length()
	_weapon_rig.update_view(look, delta, flat_speed / walk_speed)


func _physics_process(delta: float) -> void:
	if _intent.restart_pressed:
		get_tree().reload_current_scene()
		return
	if not _dead:
		_weapon_rig.update_combat(_intent.attack_pressed, _intent.attack_held, _intent.block_held, delta)
		_hud.set_charge(_weapon_rig.is_charging(), _weapon_rig.charge_fraction(), _weapon_rig.overcharge_fraction(), _weapon_rig.charge_threshold())
		_update_interact()
	if _intent.map_pressed:
		_hud.toggle_full_map()
	_move(delta)
	_tick_sprint_noise(delta)
	if dungeon:
		# The map reveals whatever room this lands in; Dungeon ignores repeats of the same cell.
		dungeon.player_cell = dungeon.cell_at(global_position)


func take_hit(hit: HitInfo) -> void:
	if _dead:
		return
	var guard_broke: bool = false
	if hit.blockable and _weapon_rig.is_blocking and _is_in_front(hit.source):
		if _stamina.spend_or_break(hit.damage * block_stamina_per_damage * _weapon_rig.block_cost_mult()):
			hit.blocked = true
			_weapon_rig.play_block_impact()
			make_noise(noise_block)
			return
		# Guard break: the bar ran dry under the block. It drops, and the hit lands below.
		guard_broke = true
		_weapon_rig.break_guard()
	# PLACEHOLDER armour: flat reduction, never below 1.
	var damage: int = maxi(1, hit.damage - _inventory.total_armour())
	_health.take_hit(HitInfo.new(damage, hit.source, hit.direction, hit.blockable))
	_hud.flash_damage()
	if guard_broke:
		_weapon_rig.shake(guard_break_shake_deg, guard_break_shake_time)
	else:
		_weapon_rig.shake(hurt_shake_deg, hurt_shake_time)
	_hurt_sfx.play()


## Forward shove on swing start: an ease-out step of exactly `distance` over `duration` seconds.
func apply_lunge(distance: float, duration: float) -> void:
	if distance <= 0.0 or duration <= 0.0:
		return
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	_lunge_direction = forward.normalized()
	_lunge_distance = distance
	_lunge_duration = duration
	_lunge_time = 0.0


## Puts `item` on the floor about drop_distance ahead as a new Pickup (Dungeon.place_item(), which
## keeps it out of walls). Without a Dungeon there's nowhere to put it, so nothing happens.
func drop_item(item: ItemData) -> void:
	if item == null or dungeon == null:
		return
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	dungeon.place_item(item, global_position, forward.normalized() * drop_distance, rotation.y)
	make_noise(noise_drop)


## Tells every enemy within `radius` (scaled by its hearing) where you are.
## LMB is down right now. The rig asks at the end of a light whether to draw back for a heavy.
func attack_held() -> bool:
	return not _dead and _intent.attack_held


func make_noise(radius: float) -> void:
	if dungeon:
		dungeon.emit_noise(global_position, radius)


## Where enemies aim their line-of-sight ray.
func eye_position() -> Vector3:
	return _head.global_position


## Called by a Pickup that bounced off a full bag.
func notify_inventory_full() -> void:
	_hud.show_notice(inventory_full_text, notice_time)


func is_dead() -> bool:
	return _dead


## Teleports to a spawn: position and yaw from `xform`, level gaze, no leftover momentum.
func place_at(xform: Transform3D) -> void:
	global_position = xform.origin
	rotation.y = xform.basis.get_euler().y
	_head.rotation.x = 0.0
	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_lunge_time = _lunge_duration


func _move(delta: float) -> void:
	var input: Vector2 = Vector2.ZERO if _dead else _intent.move
	var wish: Vector3 = global_basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	wish = wish.limit_length(1.0)
	_move_velocity = _move_velocity.move_toward(wish * _max_speed() * _direction_speed_mult(input), acceleration * delta)
	var lunge: Vector3 = _lunge_step(delta)
	var vertical: float = velocity.y
	if not is_on_floor():
		vertical += get_gravity().y * delta
	velocity = Vector3(_move_velocity.x + lunge.x, vertical, _move_velocity.z + lunge.z)
	move_and_slide()
	if _lunge_time < _lunge_duration and _touching_enemy():
		_lunge_time = _lunge_duration


## The rest of a swing step is dropped once you touch an enemy. Otherwise move_and_slide turns any
## off-centre contact into a slide round its capsule and out of your own swing.
func _touching_enemy() -> bool:
	for i: int in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is Enemy:
			return true
	return false


## Velocity that moves this tick's slice of the lunge curve. Exact at any tick rate.
func _lunge_step(delta: float) -> Vector3:
	if _lunge_time >= _lunge_duration or delta <= 0.0:
		return Vector3.ZERO
	var before: float = _ease_out(_lunge_time / _lunge_duration)
	_lunge_time = minf(_lunge_time + delta, _lunge_duration)
	var now: float = _ease_out(_lunge_time / _lunge_duration)
	return _lunge_direction * (_lunge_distance * (now - before) / delta)


## Tracks what the interact ray points at and refreshes the HUD prompt only when it changes.
## No target while swinging, blocking or equipping, so you can't vacuum loot with block held.
func _update_interact() -> void:
	# A taken pickup frees itself; drop the stale reference.
	if not is_instance_valid(_interact_target):
		_interact_target = null
	# Act on last frame's target first, so the refresh below already reflects the result.
	if _intent.interact_pressed and _interact_target and _weapon_rig.can_interact():
		_interact_target.call(&"interact", self)
	var target: Node3D = null
	if _weapon_rig.can_interact():
		var hit: Node3D = _interact_ray.get_collider() as Node3D
		if hit and hit.is_in_group(&"interactable") and not hit.is_queued_for_deletion():
			target = hit
	var prompt: String = str(target.call(&"prompt_text")) if target else ""
	if target != _interact_target or prompt != _interact_prompt:
		_interact_target = target
		_interact_prompt = prompt
		if prompt.is_empty():
			_hud.hide_prompt()
		else:
			_hud.show_prompt(prompt)


## A footstep's worth of noise every sprint_step_interval while actually sprinting. Walking is silent.
func _tick_sprint_noise(delta: float) -> void:
	var flat_speed: float = Vector2(velocity.x, velocity.z).length()
	var sprinting: bool = not _dead and _intent.sprint_held and is_on_floor() and flat_speed > walk_speed * _effects.speed_mult
	if not sprinting:
		_sprint_step_left = 0.0
		return
	_sprint_step_left -= delta
	if _sprint_step_left <= 0.0:
		_sprint_step_left = sprint_step_interval
		make_noise(noise_sprint_step)


## 1 straight ahead, strafe_speed_mult sideways, backpedal_speed_mult straight back, blended
## by how much of the input points each way.
func _direction_speed_mult(input: Vector2) -> float:
	if input.is_zero_approx():
		return 1.0
	var dir: Vector2 = input.normalized()
	var forward: float = maxf(-dir.y, 0.0)
	var back: float = maxf(dir.y, 0.0)
	var side: float = absf(dir.x)
	return (forward + back * backpedal_speed_mult + side * strafe_speed_mult) / (forward + back + side)


func _max_speed() -> float:
	var base: float = walk_speed
	if _weapon_rig.is_blocking:
		base = block_speed
	elif _intent.sprint_held:
		base = sprint_speed
	return base * _effects.speed_mult * _inventory.stat_mult(Stat.Kind.MOVE_SPEED_PCT)


func _is_in_front(source: Node3D) -> bool:
	if source == null:
		return false
	var to_source: Vector3 = source.global_position - global_position
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		return true
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_source.normalized()) > _weapon_rig.block_cone_dot(block_cone_dot)


static func _ease_out(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


func _on_died() -> void:
	_dead = true
	_hud.show_death()
	var fall: Tween = create_tween().set_ignore_time_scale(true)
	fall.tween_property(_head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	fall.parallel().tween_property(_head, "rotation:z", deg_to_rad(25.0), 0.6)
	await get_tree().create_timer(death_restart_delay, true, false, true).timeout
	if respawn_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
	else:
		respawn_requested.emit()


## Back on your feet at full health. Main calls this after moving you to camp.
func revive() -> void:
	_dead = false
	_head.position.y = _head_rest_y
	_head.rotation.z = 0.0
	_health.restore()
	_hud.hide_death()
