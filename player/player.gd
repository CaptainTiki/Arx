class_name Player
extends CharacterBody3D
## First-person controller. Reads PlayerIntent, moves and aims, forwards combat input to the WeaponRig.

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
## Seconds the swing lunge takes to bleed off. Distance comes from WeaponData.lunge_distance.
@export var lunge_duration: float = 0.18
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

var _move_velocity: Vector3 = Vector3.ZERO
var _lunge_velocity: Vector3 = Vector3.ZERO
var _lunge_decel: float = 0.0
var _dead: bool = false


func _ready() -> void:
	_hud.bind(_health, _stamina)
	_health.died.connect(_on_died)


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


## Forward shove on swing start. Linear decel, so total travel equals `distance`.
func apply_lunge(distance: float) -> void:
	if distance <= 0.0 or lunge_duration <= 0.0:
		return
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	var speed: float = 2.0 * distance / lunge_duration
	_lunge_velocity = forward.normalized() * speed
	_lunge_decel = speed / lunge_duration


func is_dead() -> bool:
	return _dead


func _move(delta: float) -> void:
	var input: Vector2 = Vector2.ZERO if _dead else _intent.move
	var wish: Vector3 = global_basis * Vector3(input.x, 0.0, input.y)
	wish.y = 0.0
	wish = wish.limit_length(1.0)
	_move_velocity = _move_velocity.move_toward(wish * _max_speed(), acceleration * delta)
	_lunge_velocity = _lunge_velocity.move_toward(Vector3.ZERO, _lunge_decel * delta)
	var vertical: float = velocity.y
	if not is_on_floor():
		vertical += get_gravity().y * delta
	velocity = Vector3(_move_velocity.x + _lunge_velocity.x, vertical, _move_velocity.z + _lunge_velocity.z)
	move_and_slide()


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


func _on_died() -> void:
	_dead = true
	_hud.show_death()
	var fall: Tween = create_tween().set_ignore_time_scale(true)
	fall.tween_property(_head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	fall.parallel().tween_property(_head, "rotation:z", deg_to_rad(25.0), 0.6)
	await get_tree().create_timer(death_restart_delay, true, false, true).timeout
	get_tree().reload_current_scene()
