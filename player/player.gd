class_name Player
extends CharacterBody3D
## First-person controller. Reads PlayerIntent, moves and aims, forwards combat input to the WeaponRig.

## Equipped on ready.
@export var starting_weapon: WeaponData
## Pooled hit/block particles in the level (Main/FX). Optional, so Player.tscn still runs on its own.
@export var fx: FxPool

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var block_speed: float = 2.5
## How fast horizontal velocity reaches target speed, in m/s². High = snappy.
@export var acceleration: float = 45.0

@export_group("Look")
## Radians of turn per pixel of mouse motion.
@export var mouse_sensitivity: float = 0.0022
@export var pitch_limit_deg: float = 85.0

@export_group("Combat")
## dot(forward, to_attacker) above this counts as "in front" for blocking. 0.3 ≈ a 145° cone.
@export var block_cone_dot: float = 0.3
@export var hurt_shake_deg: float = 1.2
@export var hurt_shake_time: float = 0.25
@export var death_restart_delay: float = 2.5

@onready var _intent: PlayerIntent = %PlayerIntent
@onready var _health: Health = %Health
@onready var _stamina: Stamina = %Stamina
@onready var _head: Node3D = %Head
@onready var _weapon_rig: WeaponRig = %WeaponRig
@onready var _hud: Hud = %HUD
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

## Read-only access for scene-level debug keys (Main reads regenerate_pressed).
var intent: PlayerIntent:
	get:
		return _intent


func _ready() -> void:
	_hud.bind(_health, _stamina)
	_health.died.connect(_on_died)
	_weapon_rig.equip(starting_weapon)


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
		_weapon_rig.update_combat(_intent.attack_pressed, _intent.block_held, delta)
		_update_interact()
	_move(delta)


func take_hit(hit: HitInfo) -> void:
	if _dead:
		return
	if hit.blockable and _weapon_rig.is_blocking and _is_in_front(hit.source):
		# v1: infinite block, zero damage.
		_weapon_rig.play_block_impact()
		return
	_health.take_hit(hit)
	_hud.flash_damage()
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


## Swap-in-place: we take the pickup's weapon and the pickup ends up holding the one we had.
func swap_weapon(pickup: Pickup) -> void:
	var incoming: WeaponData = pickup.item as WeaponData
	if incoming == null or not _weapon_rig.can_interact():
		return
	var old: WeaponData = _weapon_rig.weapon
	_weapon_rig.equip(incoming)
	pickup.set_item(old)


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
	_move_velocity = _move_velocity.move_toward(wish * _max_speed(), acceleration * delta)
	var lunge: Vector3 = _lunge_step(delta)
	var vertical: float = velocity.y
	if not is_on_floor():
		vertical += get_gravity().y * delta
	velocity = Vector3(_move_velocity.x + lunge.x, vertical, _move_velocity.z + lunge.z)
	move_and_slide()


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
	# Act on last frame's target first, so the refresh below already reflects the result.
	if _intent.interact_pressed and _interact_target and _weapon_rig.can_interact():
		_interact_target.call(&"interact", self)
	var target: Node3D = null
	if _weapon_rig.can_interact():
		var hit: Node3D = _interact_ray.get_collider() as Node3D
		if hit and hit.is_in_group(&"interactable"):
			target = hit
	var prompt: String = str(target.call(&"prompt_text")) if target else ""
	if target != _interact_target or prompt != _interact_prompt:
		_interact_target = target
		_interact_prompt = prompt
		if prompt.is_empty():
			_hud.hide_prompt()
		else:
			_hud.show_prompt(prompt)


func _max_speed() -> float:
	if _weapon_rig.is_blocking:
		return block_speed
	if _intent.sprint_held:
		return sprint_speed
	return walk_speed


func _is_in_front(source: Node3D) -> bool:
	if source == null:
		return false
	var to_source: Vector3 = source.global_position - global_position
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		return true
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(to_source.normalized()) > block_cone_dot


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
	get_tree().reload_current_scene()
