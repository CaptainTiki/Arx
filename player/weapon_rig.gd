class_name WeaponRig
extends Node3D
## First-person viewmodel and where melee feel lives: swing/block state, hit feedback,
## camera kick and shake, bob and sway.
##
## Transform ownership: the AnimationPlayer drives SwordMesh; equip() sets ViewPivot (the
## per-weapon nudge); this script drives its own transform (bob/sway) and Camera3D.rotation
## (kick/shake). Head keeps mouse-look pitch, so kicks go on the camera beneath it.

enum State { IDLE, SWING, CHARGE, BLOCK, STAGGER, EQUIP }

@export_group("Hit Feedback")
## Engine.time_scale while hitstop holds. Duration comes from WeaponData.hitstop.
@export var hitstop_time_scale: float = 0.05
## Camera kick when a swing starts, in degrees (pitch, yaw, roll).
@export var swing_kick_deg: Vector3 = Vector3(-0.8, 0.9, 1.4)
## Camera kick when a swing connects, in degrees (pitch, yaw, roll).
@export var hit_kick_deg: Vector3 = Vector3(-2.4, -1.2, -2.2)
@export var kick_in_time: float = 0.035
@export var kick_out_time: float = 0.2

@export_group("Heavy")
## Where the weapon draws back to while charging, relative to its rest pose (rig space, m / deg).
@export var heavy_pose_offset: Vector3 = Vector3(0.06, 0.1, 0.12)
@export var heavy_pose_rot_deg: Vector3 = Vector3(38.0, 12.0, -28.0)
## Seconds to settle into the drawn-back pose.
@export var heavy_pose_time: float = 0.22
## Small camera nudge the moment the charge is ready, so you feel it without looking at a bar.
@export var heavy_ready_kick_deg: Vector3 = Vector3(0.5, 0.0, -0.7)
## Camera kick when a heavy starts and when it connects.
@export var heavy_swing_kick_deg: Vector3 = Vector3(-2.0, 1.6, 2.6)
@export var heavy_hit_kick_deg: Vector3 = Vector3(-4.5, -2.0, -4.0)

@export_group("Guard Break")
## Seconds the rig is locked (no swing, no block) after a block runs the stamina bar dry.
@export var guard_break_time: float = 0.45

@export_group("Block Impact")
@export var block_shake_deg: float = 0.7
@export var block_shake_time: float = 0.18
@export var block_hitstop: float = 0.035

@export_group("Bob & Sway")
## Bob offset in meters at walk speed (x = side, y = vertical).
@export var bob_amplitude: Vector2 = Vector2(0.01, 0.008)
## Bob cycles per second at walk speed. Scales with movement speed.
@export var bob_frequency: float = 1.7
## Degrees of sway per pixel/second of mouse motion.
@export var sway_per_pixel_speed: float = 0.0025
@export var sway_max_deg: float = 3.5
@export var sway_smoothing: float = 12.0

@export_group("Input")
## A click this long before the rig frees up (mid-swing, mid-block) still swings. 0 = no buffer.
@export var attack_buffer_time: float = 0.15

## What's in hand. Set only through equip().
var weapon: WeaponData

var is_blocking: bool:
	get:
		return _state == State.BLOCK

@onready var _player: Player = owner as Player
@onready var _stamina: Stamina = %Stamina
@onready var _camera: Camera3D = %Camera3D
@onready var _hitbox: MeleeHitbox = %Hitbox
@onready var _hitbox_shape: CollisionShape3D = %HitboxShape
@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _view_pivot: Node3D = %ViewPivot
@onready var _sword_mesh: MeshInstance3D = %SwordMesh
@onready var _whoosh_sfx: AudioStreamPlayer = %WhooshSfx
@onready var _impact_sfx: AudioStreamPlayer = %ImpactSfx
@onready var _clang_sfx: AudioStreamPlayer = %ClangSfx

var _state: State = State.IDLE
var _pending_weapon: WeaponData
## Separate flag because a pending null (unequip to fists) is a real request.
var _has_pending: bool = false
## Whether the current swing connected; a swing that ends without a hit makes whiff noise.
var _landed_this_swing: bool = false
var _hitbox_back_z: float = 0.0
var _swing_speed: float = 1.0
var _attack_buffer_left: float = 0.0
var _charge_time: float = 0.0
var _charge_ready: bool = false
var _stagger_left: float = 0.0
## Whether the swing in flight is a heavy. Read by the hit handler.
var _swing_is_heavy: bool = false
## 0 = rest pose, 1 = fully drawn back. Tweened; applied to ViewPivot every rendered frame.
var _heavy_blend: float = 0.0
var _heavy_tween: Tween
var _hitstop_token: int = 0
var _kick_rot: Vector3 = Vector3.ZERO
var _shake_rot: Vector3 = Vector3.ZERO
var _kick_tween: Tween
var _shake_tween: Tween
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _sway: Vector2 = Vector2.ZERO


func _ready() -> void:
	_hitbox.owner_body = _player
	_hitbox.hit_landed.connect(_on_hit_landed)
	_anim.animation_finished.connect(_on_animation_finished)
	# The hitbox's near edge stays where it's authored; attack_reach only moves the far edge.
	var box: BoxShape3D = _hitbox_shape.shape as BoxShape3D
	_hitbox_back_z = _hitbox_shape.position.z + box.size.z * 0.5


func _exit_tree() -> void:
	# A scene reload mid-hitstop would otherwise leave the game in slow motion.
	Engine.time_scale = 1.0


## Called by Player every physics frame. A click swings a light at once. Keep the button held
## through the light and the rig goes to CHARGE (the weapon draws back); let go for the heavy,
## or let go early to cancel.
func update_combat(attack_pressed: bool, attack_held: bool, block_held: bool, delta: float) -> void:
	if attack_pressed:
		_attack_buffer_left = maxf(attack_buffer_time, delta)
	match _state:
		State.IDLE:
			if weapon == null:
				pass  # Fists: nothing to swing or block with.
			elif block_held:
				_enter_block()
			elif _attack_buffer_left > 0.0:
				try_swing()
				_attack_buffer_left = 0.0
		State.CHARGE:
			_charge_time += delta
			if not _charge_ready and _charge_time >= weapon.heavy_charge_time:
				_charge_ready = true
				kick(heavy_ready_kick_deg)
			if block_held:
				_cancel_charge()
				_enter_block()
			elif not attack_held or _charge_time >= weapon.heavy_charge_time + weapon.heavy_auto_release:
				if _charge_ready:
					_release_heavy()
				else:
					_cancel_charge()
		State.BLOCK:
			if not block_held:
				_exit_block()
		State.STAGGER:
			_stagger_left -= delta
			if _stagger_left <= 0.0:
				_become_idle()
	# The held button that started a charge shouldn't also queue a light for when it ends.
	if _state == State.CHARGE:
		_attack_buffer_left = 0.0
	_attack_buffer_left = maxf(_attack_buffer_left - delta, 0.0)


## Called by Player every rendered frame with this frame's mouse delta.
func update_view(look: Vector2, delta: float, speed_ratio: float) -> void:
	# Sway runs on real time so it keeps tracking the mouse through hitstop.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	var look_speed: Vector2 = look / maxf(real_delta, 0.0001)
	var sway_target: Vector2 = (look_speed * sway_per_pixel_speed).clampf(-sway_max_deg, sway_max_deg)
	_sway = _sway.lerp(sway_target, 1.0 - exp(-sway_smoothing * real_delta))
	# Bob runs on scaled time so it freezes with the world during hitstop.
	var ratio: float = clampf(speed_ratio, 0.0, 1.5)
	_bob_weight = lerpf(_bob_weight, ratio, 1.0 - exp(-10.0 * delta))
	_bob_phase = wrapf(_bob_phase + delta * TAU * bob_frequency * ratio, 0.0, TAU)
	position = Vector3(sin(_bob_phase) * bob_amplitude.x, sin(_bob_phase * 2.0) * bob_amplitude.y, 0.0) * _bob_weight
	rotation = Vector3(deg_to_rad(_sway.y), deg_to_rad(_sway.x), deg_to_rad(_sway.x) * 0.5)
	if weapon:
		_view_pivot.position = weapon.view_offset + heavy_pose_offset * _heavy_blend
		_view_pivot.rotation_degrees = weapon.view_rotation + heavy_pose_rot_deg * _heavy_blend


## Swaps the held weapon; null = fists (no mesh, no swing, no block). Mid-swing it waits and
## applies when the swing ends, so a swap never lands in active frames. During a block or an
## equip it applies at once (restarting the raise), which keeps paused inventory swaps instant.
## Only Inventory calls this.
func equip(new_weapon: WeaponData) -> void:
	if _state == State.SWING:
		_pending_weapon = new_weapon
		_has_pending = true
		return
	_apply_weapon(new_weapon)


## Pickups and other interactions only work with the rig at rest (not swinging, blocking or equipping).
func can_interact() -> bool:
	return _state == State.IDLE


## Starts a light swing if the rig is free and there's stamina for it.
func try_swing() -> bool:
	if _state != State.IDLE or weapon == null or not _stamina.try_spend(weapon.stamina_cost):
		return false
	_start_swing(false)
	return true


func _start_swing(heavy: bool) -> void:
	_state = State.SWING
	_swing_is_heavy = heavy
	var time_mult: float = weapon.heavy_swing_time_mult if heavy else 1.0
	_anim.play(&"swing", 0.05, _swing_speed / time_mult)
	_landed_this_swing = false
	_whoosh_sfx.pitch_scale = 0.8 if heavy else 1.0
	_whoosh_sfx.play()
	# The step lands mid-active-window for every weapon, so it carries the body into the hit.
	_player.apply_lunge(weapon.lunge_distance, (weapon.active_start + weapon.active_end) * 0.5 * time_mult)
	kick(heavy_swing_kick_deg if heavy else swing_kick_deg)


## Keep the button held through a light and the rig lands here: the weapon draws back and waits.
func _enter_charge() -> void:
	_state = State.CHARGE
	_charge_time = 0.0
	_charge_ready = false
	_anim.play(&"RESET", 0.1)
	_blend_heavy_pose(1.0, heavy_pose_time)


func _release_heavy() -> void:
	if not _stamina.try_spend(weapon.heavy_stamina_cost):
		_cancel_charge()
		return
	# Whip from the drawn-back pose through the rest pose before the hitbox opens.
	_blend_heavy_pose(0.0, weapon.active_start * weapon.heavy_swing_time_mult)
	_start_swing(true)


func _cancel_charge() -> void:
	_blend_heavy_pose(0.0, heavy_pose_time)
	_become_idle()


## A block just ran the stamina bar dry: drop the guard and lock the rig for a beat.
func break_guard() -> void:
	_anim.play(&"block_lower", 0.05)
	_state = State.STAGGER
	_stagger_left = guard_break_time
	_clang_sfx.pitch_scale = 0.7
	_clang_sfx.play()
	_clang_sfx.pitch_scale = 1.0


func _blend_heavy_pose(target: float, duration: float) -> void:
	if _heavy_tween:
		_heavy_tween.kill()
	_heavy_tween = create_tween()
	_heavy_tween.tween_property(self, ^"_heavy_blend", target, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if target > 0.0 else Tween.EASE_IN)


func play_block_impact() -> void:
	_anim.play(&"block_impact")
	if _player.fx and _sword_mesh.mesh:
		_player.fx.play_block_spark(_sword_mesh.global_transform * _sword_mesh.mesh.get_aabb().get_center())
	_clang_sfx.play()
	shake(block_shake_deg, block_shake_time)
	_hitstop(block_hitstop)


## Rotational camera punch: snaps to `degrees` then eases back to zero. Ignores hitstop.
func kick(degrees: Vector3) -> void:
	if _kick_tween:
		_kick_tween.kill()
	var target: Vector3 = Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
	_kick_tween = create_tween().set_ignore_time_scale(true)
	_kick_tween.tween_method(_set_kick, _kick_rot, target, kick_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_kick_tween.tween_method(_set_kick, target, Vector3.ZERO, kick_out_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Random rotational jitter that decays to zero over `duration`. Ignores hitstop.
func shake(strength_deg: float, duration: float) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween().set_ignore_time_scale(true)
	_shake_tween.tween_method(_apply_shake.bind(deg_to_rad(strength_deg)), 1.0, 0.0, duration)


func _on_hit_landed(target: Node3D) -> void:
	var to_target: Vector3 = target.global_position - _player.global_position
	to_target.y = 0.0
	var damage: int = roundi(weapon.damage * weapon.heavy_damage_mult) if _swing_is_heavy else weapon.damage
	var hit: HitInfo = HitInfo.new(damage, _player, to_target.normalized(), true)
	hit.heavy = _swing_is_heavy
	var contact: Vector3 = _hitbox.overlap_point(target)
	target.call(&"take_hit", hit)
	_landed_this_swing = true
	_whoosh_sfx.stop()
	if not hit.muffle_thud:
		_impact_sfx.play()
	_player.make_noise(_player.noise_sword_hit)
	if _player.fx:
		_player.fx.play_hit_puff(contact, hit.direction, hit.puff_material)
	kick(heavy_hit_kick_deg if _swing_is_heavy else hit_kick_deg)
	_hitstop(weapon.heavy_hitstop if _swing_is_heavy else weapon.hitstop)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"swing":
		_hitbox.end_swing()
		if not _landed_this_swing:
			_player.make_noise(_player.noise_whiff)
		var still_held: bool = _player.attack_held()
		_become_idle()
		# Button still down after a light (and nothing swapped in under it): draw back for a heavy.
		if still_held and _state == State.IDLE and weapon and not _swing_is_heavy and _stamina.can_spend(weapon.heavy_stamina_cost):
			_enter_charge()
	elif anim_name == &"equip":
		_become_idle()


func _enter_block() -> void:
	_state = State.BLOCK
	_anim.play(&"block_raise", 0.05)


func _exit_block() -> void:
	_anim.play(&"block_lower", 0.05)
	_become_idle()


func _become_idle() -> void:
	_state = State.IDLE
	if _has_pending:
		_apply_weapon(_pending_weapon)


func _apply_weapon(new_weapon: WeaponData) -> void:
	weapon = new_weapon
	_pending_weapon = null
	_has_pending = false
	if weapon == null:
		# Fists: nothing in hand. Back to IDLE (even out of an unfinished equip or a block) so
		# pickups and equips keep working.
		_state = State.IDLE
		_sword_mesh.mesh = null
		_hitbox.end_swing()
		_anim.play(&"RESET")
		return
	_sword_mesh.mesh = weapon.view_mesh
	_heavy_blend = 0.0
	_view_pivot.position = weapon.view_offset
	_view_pivot.rotation_degrees = weapon.view_rotation
	_apply_attack_reach()
	_apply_weapon_timing()
	_state = State.EQUIP
	_anim.play(&"equip")
	# Pose the new mesh below the screen this frame instead of flashing it at rest first.
	_anim.seek(0.0, true)


func _apply_attack_reach() -> void:
	var box: BoxShape3D = _hitbox_shape.shape as BoxShape3D
	box.size.z = weapon.attack_reach
	_hitbox_shape.position.z = _hitbox_back_z - weapon.attack_reach * 0.5


func _hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	_hitstop_token += 1
	var token: int = _hitstop_token
	Engine.time_scale = hitstop_time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	# A newer hitstop started while we waited; it owns the restore.
	if token == _hitstop_token:
		Engine.time_scale = 1.0


## The `swing` clip is authored at 1 s with normalized keys. Playing it at speed 1 / swing_time
## makes it last swing_time, and the hitbox keys sit at active_start / swing_time and
## active_end / swing_time. This is a per-play speed, not AnimationPlayer.speed_scale, so block
## and equip clips keep their own timing.
func _apply_weapon_timing() -> void:
	var swing: Animation = _anim.get_animation(&"swing")
	_swing_speed = swing.length / weapon.swing_time
	var track: int = swing.find_track(NodePath("Hitbox"), Animation.TYPE_METHOD)
	if track == -1:
		push_error("WeaponRig: swing animation has no Hitbox method track")
		return
	_set_method_key_time(swing, track, &"end_swing", weapon.active_end * _swing_speed)
	_set_method_key_time(swing, track, &"begin_swing", weapon.active_start * _swing_speed)


func _set_method_key_time(anim: Animation, track: int, method: StringName, time: float) -> void:
	for key: int in anim.track_get_key_count(track):
		if anim.method_track_get_name(track, key) == method:
			anim.track_set_key_time(track, key, time)
			return
	push_error("WeaponRig: no '%s' key on the swing method track" % method)


func _set_kick(value: Vector3) -> void:
	_kick_rot = value
	_camera.rotation = _kick_rot + _shake_rot


func _apply_shake(falloff: float, strength: float) -> void:
	var amp: float = strength * falloff * falloff
	_shake_rot = Vector3(randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp) * 0.5)
	_camera.rotation = _kick_rot + _shake_rot
