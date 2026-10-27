class_name Enemy
extends CharacterBody3D
## Melee enemy with eyes and ears. Unaware, it looks around. Seeing you, getting hit or hearing a
## noise makes it bark and turn (ALERT); then it chases what it saw or investigates what it heard
## (SEARCH). How it opens a fight depends on data.behavior: MELEE walks in and swings, POUNCE leaps
## from mid-range, CHARGE rushes from afar. All tuning comes from `data`; the only literals here are
## crossfades, math guards and the named constants below.

enum State { IDLE, ALERT, CHASE, SEARCH, WINDUP, STRIKE, CROUCH, POUNCE, CHARGE_WINDUP, CHARGING, WALL_STUN, RECOVER, COOLDOWN, FLINCH, GUARD_BROKEN, DEAD }
enum SearchPhase { GOTO, LOOK, RETURN }

## Animation crossfade times. Presentation plumbing, not enemy tuning.
const BLEND_ACTION: float = 0.06
const BLEND_FLINCH: float = 0.03
const BLEND_LOOP: float = 0.15
## A pounce counts as landed once it touches the floor after this long in the air.
const POUNCE_LIFTOFF_GRACE: float = 0.1
## Safety net for a pounce that never lands.
const POUNCE_MAX_FLIGHT: float = 2.0
## Collision normals steeper than this are floor or ceiling, not a wall.
const FLOOR_NORMAL_Y: float = 0.7

@export var data: EnemyData
## Who to fight. Falls back to the first node in the "player" group.
@export var target: Player
## Noise goes through here (Dungeon.emit_noise). Set by the generator; null = this enemy is silent.
@export var dungeon: Dungeon
## Overlay shared by every body mesh and tinted on hit. Must be local to scene.
@export var flash_material: StandardMaterial3D

@onready var _health: Health = %Health
@onready var _perception: Perception = %Perception
@onready var _hitbox: MeleeHitbox = %Hitbox
@onready var _hitbox_shape: CollisionShape3D = %HitboxShape
@onready var _rig: Node3D = %Rig
@onready var _tinted_meshes: Array[MeshInstance3D] = [%Torso, %ArmL, %Arm]
@onready var _shield_mesh: Node3D = %Shield
@onready var _shield_arm: Node3D = %ArmL

@export_group("Shield Arm")
## Guard up: arm across the chest, shield square to the front. (Rig/Body space, m / rad.)
@export var shield_up_position: Vector3 = Vector3(-0.12, 0.36, -0.28)
@export var shield_up_rotation: Vector3 = Vector3(0.0, 0.25, 0.1)
## Guard down (attacking): arm back at the side, shield turned edge-on. The opening.
@export var shield_down_position: Vector3 = Vector3(-0.4, 0.28, 0.08)
@export var shield_down_rotation: Vector3 = Vector3(0.35, 1.3, -0.25)
## Guard broken: flung wide.
@export var shield_broken_position: Vector3 = Vector3(-0.58, 0.3, 0.18)
@export var shield_broken_rotation: Vector3 = Vector3(0.6, 2.0, -0.7)
@export var shield_pose_time: float = 0.14

var _shield_tween: Tween
@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _body_shape: CollisionShape3D = %BodyShape
@onready var _tell_flash: OmniLight3D = %TellFlash
@onready var _health_bar: Sprite3D = %HealthBar3D
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _grunt_sfx: AudioStreamPlayer3D = %GruntSfx
@onready var _bark_sfx: AudioStreamPlayer3D = %BarkSfx
@onready var _chitter_sfx: AudioStreamPlayer3D = %ChitterSfx
@onready var _roar_sfx: AudioStreamPlayer3D = %RoarSfx
@onready var _swing_sfx: AudioStreamPlayer3D = %SwingSfx
@onready var _death_sfx: AudioStreamPlayer3D = %DeathSfx

## Read-only state for listeners like Dungeon.emit_noise.
var state: State:
	get:
		return _state

var _state: State = State.IDLE
var _state_time: float = 0.0
var _cooldown_left: float = 0.0
var _tell_left: float = 0.0
var _chase_velocity: Vector3 = Vector3.ZERO
var _knockback: Vector3 = Vector3.ZERO
## Light hits taken since the last stagger or attack (see EnemyData.poise).
var _poise_hits: int = 0
var _strike_direction: Vector3 = Vector3.FORWARD
var _lunge_spent: bool = false
var _flash_tween: Tween
var _unseen_time: float = 0.0
var _alert_from_hit: bool = false
var _search_phase: SearchPhase = SearchPhase.GOTO
var _search_time: float = 0.0
var _look_origin: float = 0.0
var _look_offset: float = 0.0
var _home_position: Vector3
var _home_yaw: float = 0.0
var _pounce_target: Vector3
var _pounce_velocity: Vector3 = Vector3.ZERO
var _charge_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	assert(data != null, "Enemy needs an EnemyData")
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Player
	_perception.target = target
	_home_position = global_position
	_home_yaw = rotation.y
	# Deterministic per spawn spot, so neighbours don't sweep their cones in lockstep.
	_look_offset = fposmod(global_position.x * 0.37 + global_position.z * 0.73, 1.0) * data.idle_look_period
	_hitbox.owner_body = self
	_hitbox.hit_landed.connect(_on_hit_landed)
	_health.changed.connect(_on_health_changed)
	_health.died.connect(_on_died)
	_health.set_max_hp(data.max_hp)
	_apply_body()
	_set_hitbox_reach(data.attack_reach)
	for voice: AudioStreamPlayer3D in [_grunt_sfx, _bark_sfx, _death_sfx]:
		voice.pitch_scale *= data.voice_pitch
	_enter(State.IDLE)


func take_hit(hit: HitInfo) -> void:
	if _state == State.DEAD:
		return
	_flash()
	var was_unaware: bool = not is_aware() or _state == State.SEARCH or _state == State.ALERT
	if hit.source:
		_perception.last_known_pos = hit.source.global_position
	var stunned: bool = _state == State.WALL_STUN or _state == State.GUARD_BROKEN
	# Openings: a hit it never saw, or one from behind, lands harder.
	if was_unaware and data.sneak_mult > 1.0:
		hit.bonus = data.sneak_mult
	elif hit.source and data.backstab_mult > 1.0 and _is_behind(hit.source):
		hit.bonus = data.backstab_mult
	if hit.bonus > 1.0:
		hit.damage = roundi(hit.damage * hit.bonus)
	if data.guard and _guard_up() and hit.source and _guard_covers(hit.source):
		if hit.heavy:
			# Smashed open. The heavy lands, and the guard stays down for the punish window.
			hit.guard_broken = true
			_health.take_hit(hit)
			if _state != State.DEAD:
				_knockback = Vector3(hit.direction.x, 0.0, hit.direction.z).normalized() * data.guard_break_knockback
				_enter(State.GUARD_BROKEN)
			_make_noise(data.hurt_noise_radius)
			return
		# Clang. Nothing gets through, but it knows you're there.
		hit.blocked = true
		if was_unaware:
			_alert(true)
		_make_noise(data.hurt_noise_radius)
		return
	if _state == State.POUNCE and data.pounce_swattable:
		_health.take_hit(hit)
		if _state != State.DEAD:
			_swat(hit.direction)
		_make_noise(data.hurt_noise_radius)
		return
	# Super armor through the attack itself: hitting it mid-swing is a trade, not an interrupt.
	var can_flinch: bool = (data.can_flinch or stunned) and not _in_attack()
	if can_flinch and not stunned and not hit.heavy:
		_poise_hits += 1
		can_flinch = _poise_hits >= data.poise
	_health.take_hit(hit)
	if _state != State.DEAD:
		var push: Vector3 = Vector3(hit.direction.x, 0.0, hit.direction.z).normalized()
		if stunned:
			# Dazed: it reels from each hit, but the punish window stays open.
			_knockback = push * data.flinch_knockback
			_play_timed(&"flinch", data.flinch_time, BLEND_FLINCH)
		elif can_flinch:
			_poise_hits = 0
			_knockback = push * data.flinch_knockback
			_enter(State.FLINCH)
		elif was_unaware:
			_alert(true)
	# After the state change, so this enemy doesn't "hear" its own grunt.
	_make_noise(data.hurt_noise_radius)


## Noise reaction (Dungeon.emit_noise). Unaware or searching enemies turn toward it and go look;
## they only chase once they actually see you. Already fighting = ignored.
func hear(pos: Vector3) -> void:
	if _state != State.IDLE and _state != State.SEARCH:
		return
	_perception.last_known_pos = pos
	_alert(false)


func is_dead() -> bool:
	return _state == State.DEAD


## Knows something is up: anything but resting IDLE (and dead).
func is_aware() -> bool:
	return _state != State.IDLE and _state != State.DEAD


func get_state_name() -> String:
	return str(State.keys()[_state])


func _physics_process(delta: float) -> void:
	_state_time += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_tick_tell(delta)
	match _state:
		State.IDLE:
			if _perception.can_see:
				_alert(false)
			else:
				_look_around(_home_yaw, _state_time, delta)
		State.ALERT:
			_face_point(_perception.last_known_pos, data.chase_turn_rate, delta)
			if _state_time >= data.alert_time:
				_enter(State.CHASE if _perception.can_see or _alert_from_hit else State.SEARCH)
		State.CHASE:
			_tick_chase(delta)
		State.SEARCH:
			_tick_search(delta)
		State.WINDUP:
			_face_target(data.windup_turn_rate, delta)
			if _state_time >= data.windup_time:
				_enter(State.STRIKE)
		State.STRIKE:
			if _state_time >= data.strike_time:
				_enter(State.RECOVER)
		State.CROUCH:
			_tick_crouch(delta)
		State.POUNCE:
			if (_state_time > POUNCE_LIFTOFF_GRACE and is_on_floor()) or _state_time > POUNCE_MAX_FLIGHT:
				_enter(State.RECOVER)
		State.CHARGE_WINDUP:
			_face_target(data.chase_turn_rate, delta)
			if _state_time >= data.charge_windup:
				_enter(State.CHARGING)
		State.CHARGING:
			if _target_alive():
				_face_target(data.charge_turn_rate, delta)
			_charge_direction = _facing()
			if _state_time >= data.charge_max_time:
				_enter(State.RECOVER)
		State.GUARD_BROKEN:
			if not _anim.is_playing():
				_play_loop(&"stun")
			if _state_time >= data.guard_break_time:
				_enter(State.COOLDOWN)
		State.WALL_STUN:
			if not _anim.is_playing():
				_play_loop(&"stun")
			if _state_time >= data.wall_stun_time:
				_enter(State.COOLDOWN)
		State.RECOVER:
			if _state_time >= data.recover_time:
				_enter(State.COOLDOWN)
		State.COOLDOWN:
			# Recovery was the opening; cooldown it spends turning back to you, so circling doesn't
			# buy a second one.
			if _target_alive() and _perception.can_see:
				_face_target(data.chase_turn_rate, delta)
			if _cooldown_left <= 0.0:
				_enter(State.CHASE)
		State.FLINCH:
			if _state_time >= data.flinch_time:
				_enter(State.COOLDOWN if _cooldown_left > 0.0 else State.CHASE)
		State.DEAD:
			if _state_time >= data.despawn_delay:
				queue_free()
			return
	_move(delta)
	if _state == State.CHARGING:
		_check_wall_hit()
	elif _state == State.STRIKE and not _lunge_spent:
		_lunge_spent = _touching_target()


func _tick_chase(delta: float) -> void:
	_chase_velocity = Vector3.ZERO
	if not _target_alive():
		_enter(State.IDLE)
		return
	var seeing: bool = _perception.can_see
	_unseen_time = 0.0 if seeing else _unseen_time + delta
	if _unseen_time >= data.lose_sight_time:
		_enter(State.SEARCH)
		return
	var goal: Vector3 = target.global_position if seeing else _perception.last_known_pos
	_face_point(goal, data.chase_turn_rate, delta)
	var to_goal: Vector3 = _flat(goal - global_position)
	var distance: float = to_goal.length()
	if seeing and _try_attack(distance):
		return
	var stop_at: float = data.trigger_range if seeing else data.search_arrive_distance
	if distance > stop_at:
		_chase_velocity = to_goal / distance * data.move_speed
		_play_loop(&"walk")
	else:
		_play_loop(&"idle")


## In range and cooldown ready: pick the opener for this behavior. MELEE (and everyone up close)
## winds up a normal strike; POUNCE leaps from mid-range; CHARGE rushes from afar.
func _try_attack(distance: float) -> bool:
	match data.behavior:
		EnemyData.Behavior.POUNCE:
			if distance > data.pounce_min_range and distance < data.pounce_range:
				_enter(State.CROUCH)
				return true
		EnemyData.Behavior.CHARGE:
			if distance > data.charge_min_range:
				_enter(State.CHARGE_WINDUP)
				return true
	if distance <= data.trigger_range:
		_enter(State.WINDUP)
		return true
	return false


## Walk to where it last saw or heard you, look around, then walk home.
func _tick_search(delta: float) -> void:
	_chase_velocity = Vector3.ZERO
	if _perception.can_see:
		_bark_sfx.play()
		_enter(State.CHASE)
		return
	_search_time += delta
	match _search_phase:
		SearchPhase.GOTO:
			if _walk_to(_perception.last_known_pos, delta) or _search_time >= data.search_give_up_time:
				_begin_search_phase(SearchPhase.LOOK)
		SearchPhase.LOOK:
			_play_loop(&"idle")
			_look_around(_look_origin, _search_time, delta)
			if _search_time >= data.search_look_time:
				_begin_search_phase(SearchPhase.RETURN)
		SearchPhase.RETURN:
			if _walk_to(_home_position, delta) or _search_time >= data.search_give_up_time:
				_enter(State.IDLE)


func _begin_search_phase(phase: SearchPhase) -> void:
	_search_phase = phase
	_search_time = 0.0
	_look_origin = rotation.y


## Steps toward `point` at search speed. True once there.
func _walk_to(point: Vector3, delta: float) -> bool:
	var to_point: Vector3 = _flat(point - global_position)
	var distance: float = to_point.length()
	if distance <= data.search_arrive_distance:
		_play_loop(&"idle")
		return true
	_face_point(point, data.chase_turn_rate, delta)
	_chase_velocity = to_point / distance * data.move_speed * data.search_speed_mult
	_play_loop(&"walk")
	return false


func _tick_crouch(delta: float) -> void:
	_face_target(data.windup_turn_rate, delta)
	var squash: float = lerpf(1.0, data.pounce_squash, clampf(_state_time / maxf(data.pounce_crouch_time * 0.5, 0.001), 0.0, 1.0))
	_rig.scale = Vector3(data.body_scale, data.body_scale * squash, data.body_scale)
	if _state_time >= data.pounce_crouch_time:
		# Locked here: the leap goes where you were at the end of the crouch.
		_pounce_target = target.global_position if _target_alive() else _perception.last_known_pos
		_enter(State.POUNCE)


func _move(delta: float) -> void:
	var horizontal: Vector3 = _knockback
	match _state:
		State.CHASE, State.SEARCH:
			horizontal += _chase_velocity
		State.STRIKE:
			if not _lunge_spent:
				horizontal += _strike_lunge_velocity(delta)
		State.POUNCE:
			horizontal = _pounce_velocity
		State.CHARGING:
			horizontal = _charge_direction * data.charge_speed
	_knockback = _knockback.move_toward(Vector3.ZERO, data.knockback_decel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	move_and_slide()


## Knocked out of a pounce: the leap stops dead, it drops, and lies in the punish window.
func _swat(push_direction: Vector3) -> void:
	_pounce_velocity = Vector3.ZERO
	velocity.y = minf(velocity.y, 0.0)
	_knockback = _flat(push_direction).normalized() * data.swat_knockback
	_enter(State.RECOVER)
	_play_timed(&"flinch", data.flinch_time, BLEND_FLINCH)


## A head-on bump into anything that isn't the player ends the charge in a daze.
func _check_wall_hit() -> void:
	for i: int in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		if collision.get_collider() is Player:
			continue
		var normal: Vector3 = collision.get_normal()
		if absf(normal.y) > FLOOR_NORMAL_Y:
			continue
		if normal.dot(-_charge_direction) >= data.charge_wall_dot:
			_enter(State.WALL_STUN)
			return


## The rest of a lunge is dropped once it touches the target. Otherwise move_and_slide turns any
## off-centre contact into a slide round your capsule, ending at your side or past you.
func _touching_target() -> bool:
	for i: int in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == target:
			return true
	return false


## Ease-out step along the locked facing. Covers strike_lunge over strike_time at any tick rate.
## Walls stop it through move_and_slide; touching the target ends it (_lunge_spent).
func _strike_lunge_velocity(delta: float) -> Vector3:
	if data.strike_lunge <= 0.0 or delta <= 0.0:
		return Vector3.ZERO
	var duration: float = maxf(data.strike_time, 0.001)
	var now: float = _ease_out(_state_time / duration)
	var before: float = _ease_out((_state_time - delta) / duration)
	return _strike_direction * (data.strike_lunge * (now - before) / delta)


func _alert(from_hit: bool) -> void:
	_alert_from_hit = from_hit
	_enter(State.ALERT)


func _enter(next: State) -> void:
	var previous: State = _state
	_state = next
	_state_time = 0.0
	if next == State.WINDUP or next == State.CROUCH or next == State.CHARGE_WINDUP:
		_poise_hits = 0
	if data.guard:
		_pose_shield_arm()
	_chase_velocity = Vector3.ZERO
	match previous:
		State.RECOVER, State.WALL_STUN, State.GUARD_BROKEN:
			_cooldown_left = data.cooldown_time
		State.STRIKE, State.POUNCE:
			# Method tracks / landing normally close the hitbox; this covers interruptions.
			_hitbox.end_swing()
		State.CROUCH:
			_rig.scale = Vector3.ONE * data.body_scale
		State.CHARGING:
			_hitbox.end_swing()
			# Deferred: this can run inside the hitbox's own physics callback.
			_set_hitbox_reach.call_deferred(data.attack_reach)
	match next:
		State.IDLE:
			_home_yaw = rotation.y if previous != State.SEARCH else _home_yaw
			_play_loop(&"idle")
		State.COOLDOWN:
			_play_loop(&"idle")
		State.ALERT:
			_bark_sfx.play()
			_play_timed(&"alert", data.alert_time)
		State.CHASE:
			_unseen_time = 0.0
		State.SEARCH:
			_begin_search_phase(SearchPhase.GOTO)
		State.WINDUP:
			_play_timed(&"windup", data.windup_time)
			_show_tell(data.tell_flash_time)
			_grunt_sfx.play()
		State.STRIKE:
			# Facing locks here through STRIKE and RECOVER; COOLDOWN turns back toward the target.
			_strike_direction = _facing()
			_lunge_spent = false
			_play_timed(&"strike", data.strike_time)
			_swing_sfx.play()
		State.CROUCH:
			_play_timed(&"crouch", data.pounce_crouch_time)
			_show_tell(data.tell_flash_time)
			_chitter_sfx.play()
		State.POUNCE:
			_launch_pounce()
		State.CHARGE_WINDUP:
			_play_timed(&"windup", data.charge_windup)
			_show_tell(data.charge_windup)
			_roar_sfx.play()
			_make_noise(data.roar_noise_radius)
		State.CHARGING:
			_charge_direction = _facing()
			_set_hitbox_reach(data.charge_hit_reach)
			_hitbox.begin_swing()
			_play_loop(&"charge")
		State.GUARD_BROKEN:
			_play_timed(&"flinch", data.flinch_time, BLEND_FLINCH)
			_grunt_sfx.play()
		State.WALL_STUN:
			_play_loop(&"stun")
			_grunt_sfx.play()
		State.RECOVER:
			_play_timed(&"recover", data.recover_time)
		State.FLINCH:
			_play_timed(&"flinch", data.flinch_time, BLEND_FLINCH)
		State.DEAD:
			_die()


## Ballistic leap toward the locked spot: horizontal at pounce_speed, vertical for a pounce_arc peak,
## then gravity. The hitbox is live for the whole flight; it ends in RECOVER wherever it lands.
func _launch_pounce() -> void:
	var to_target: Vector3 = _flat(_pounce_target - global_position)
	var direction: Vector3 = to_target.normalized() if to_target.length_squared() > 0.0001 else _facing()
	_pounce_velocity = direction * data.pounce_speed
	velocity.y = sqrt(2.0 * get_gravity().length() * data.pounce_arc)
	_hitbox.begin_swing()
	_play_loop(&"pounce")
	_swing_sfx.play()


func _die() -> void:
	_hitbox.end_swing()
	_tell_flash.visible = false
	_body_shape.set_deferred(&"disabled", true)
	_health_bar.visible = false
	velocity = Vector3.ZERO
	_anim.play(&"die", BLEND_ACTION)
	_death_sfx.play()
	remove_from_group(&"enemies")


## Scales the rig, its capsule and the things that hang off its height; tints torso and arms.
## The capsule shape is local to scene, so resizing it is per enemy.
func _apply_body() -> void:
	var s: float = data.body_scale
	_rig.scale = Vector3.ONE * s
	var capsule: CapsuleShape3D = _body_shape.shape as CapsuleShape3D
	capsule.radius *= s
	capsule.height *= s
	_body_shape.position.y *= s
	_health_bar.position.y *= s
	_tell_flash.position.y *= s
	_perception.position.y *= s
	if data.body_material:
		for mesh: MeshInstance3D in _tinted_meshes:
			mesh.material_override = data.body_material
	_shield_mesh.visible = data.guard
	if data.guard:
		_pose_shield_arm(true)


## The shield is up whenever it isn't attacking, staggered or down.
func _guard_up() -> bool:
	match _state:
		State.IDLE, State.ALERT, State.CHASE, State.SEARCH, State.COOLDOWN:
			return true
	return false


func _is_behind(source: Node3D) -> bool:
	var to_source: Vector3 = _flat(source.global_position - global_position)
	if to_source.length_squared() < 0.0001:
		return false
	return _facing().dot(to_source.normalized()) <= data.backstab_dot


## Moves the shield arm to match the state: up while guarding, down while attacking, flung when
## broken. The arm isn't in any animation clip, so this owns it.
func _pose_shield_arm(instant: bool = false) -> void:
	var pos: Vector3
	var rot: Vector3
	if _state == State.GUARD_BROKEN:
		pos = shield_broken_position
		rot = shield_broken_rotation
	elif _guard_up():
		pos = shield_up_position
		rot = shield_up_rotation
	else:
		pos = shield_down_position
		rot = shield_down_rotation
	if _shield_tween:
		_shield_tween.kill()
	if instant:
		_shield_arm.position = pos
		_shield_arm.rotation = rot
		return
	_shield_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shield_tween.tween_property(_shield_arm, ^"position", pos, shield_pose_time)
	_shield_tween.tween_property(_shield_arm, ^"rotation", rot, shield_pose_time)


func _guard_covers(source: Node3D) -> bool:
	var to_source: Vector3 = _flat(source.global_position - global_position)
	if to_source.length_squared() < 0.0001:
		return true
	return _facing().dot(to_source.normalized()) >= data.guard_cone_dot


## Box runs from the enemy's center forward to `reach`. The shape is local to scene, so this is per enemy.
func _set_hitbox_reach(reach: float) -> void:
	var box: BoxShape3D = _hitbox_shape.shape as BoxShape3D
	box.size.z = reach
	_hitbox_shape.position.z = -reach * 0.5


func _in_attack() -> bool:
	match _state:
		State.WINDUP, State.STRIKE, State.CROUCH, State.POUNCE, State.CHARGE_WINDUP, State.CHARGING:
			return true
	return false


func _make_noise(radius: float) -> void:
	if dungeon:
		dungeon.emit_noise(global_position, radius)


func _show_tell(duration: float) -> void:
	_tell_flash.visible = true
	_tell_left = duration


func _play_timed(anim_name: StringName, duration: float, blend: float = BLEND_ACTION) -> void:
	var length: float = _anim.get_animation(anim_name).length
	_anim.play(anim_name, blend, length / maxf(duration, 0.001))


func _play_loop(anim_name: StringName) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, BLEND_LOOP)


## IDLE / SEARCH look-around: sweep the cone either side of `origin`.
func _look_around(origin: float, time: float, delta: float) -> void:
	var t: float = time + _look_offset
	var wanted: float = origin + deg_to_rad(data.idle_look_angle) * sin(TAU * t / maxf(data.idle_look_period, 0.001))
	rotation.y = rotate_toward(rotation.y, wanted, deg_to_rad(data.chase_turn_rate) * delta)


## Yaw-only turn toward the target, capped at `rate_deg` degrees per second.
func _face_target(rate_deg: float, delta: float) -> void:
	if is_instance_valid(target):
		_face_point(target.global_position, rate_deg, delta)


func _face_point(point: Vector3, rate_deg: float, delta: float) -> void:
	var to_point: Vector3 = _flat(point - global_position)
	if to_point.length_squared() < 0.0001:
		return
	var desired_yaw: float = atan2(-to_point.x, -to_point.z)
	rotation.y = rotate_toward(rotation.y, desired_yaw, deg_to_rad(rate_deg) * delta)


func _facing() -> Vector3:
	return _flat(-global_basis.z).normalized()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _target_alive() -> bool:
	return is_instance_valid(target) and not target.is_dead()


func _tick_tell(delta: float) -> void:
	if _tell_left <= 0.0:
		return
	_tell_left -= delta
	if _tell_left <= 0.0:
		_tell_flash.visible = false


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	flash_material.albedo_color = data.flash_color
	# Scaled time on purpose: the flash holds at full white through hitstop.
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_material, "albedo_color", data.flash_fade_color, data.flash_time)
	_flash_tween.tween_property(flash_material, "albedo_color", Color(data.flash_fade_color, 0.0), data.flash_fade_time)


func _on_hit_landed(body: Node3D) -> void:
	var direction: Vector3 = _flat(body.global_position - global_position).normalized()
	var hit: HitInfo = HitInfo.new(data.damage, self, direction, true)
	body.call(&"take_hit", hit)
	if _state == State.POUNCE and hit.blocked and data.pounce_swattable:
		_swat(-direction)
		return
	if _state == State.CHARGING:
		# A charge ends on contact either way; only an unblocked one slows you.
		var player: Player = body as Player
		if player and not hit.blocked:
			player.effects.apply_slow(data.charge_slow_mult, data.charge_slow_time)
		_enter(State.RECOVER)


func _on_health_changed(current: int, maximum: int) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current


## Loot first, where the body falls, so the drop and the corpse share a spot.
func _on_died() -> void:
	if dungeon and data.drop_table:
		dungeon.drop_loot(data.drop_table, global_position, null, data.drop_rolls, data.display_name.to_lower())
	_enter(State.DEAD)


static func _ease_out(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)
