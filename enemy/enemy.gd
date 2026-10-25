class_name Enemy
extends CharacterBody3D
## Deliberately dumb melee enemy: walk up, telegraph a smash, lunge-strike, then stand there being hittable.
## All tuning comes from `data`. The only literals here are animation crossfades and math guards.

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, COOLDOWN, FLINCH, DEAD }

## Animation crossfade times. Presentation plumbing, not enemy tuning.
const BLEND_ACTION: float = 0.06
const BLEND_FLINCH: float = 0.03
const BLEND_LOOP: float = 0.15

@export var data: EnemyData
## Who to fight. Falls back to the first node in the "player" group.
@export var target: Player
## Overlay shared by every body mesh and tinted on hit. Must be local to scene.
@export var flash_material: StandardMaterial3D

@onready var _health: Health = %Health
@onready var _hitbox: MeleeHitbox = %Hitbox
@onready var _hitbox_shape: CollisionShape3D = %HitboxShape
@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _body_shape: CollisionShape3D = %BodyShape
@onready var _tell_flash: OmniLight3D = %TellFlash
@onready var _health_bar: Sprite3D = %HealthBar3D
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _grunt_sfx: AudioStreamPlayer3D = %GruntSfx
@onready var _swing_sfx: AudioStreamPlayer3D = %SwingSfx
@onready var _death_sfx: AudioStreamPlayer3D = %DeathSfx

var _state: State = State.IDLE
var _state_time: float = 0.0
var _cooldown_left: float = 0.0
var _tell_left: float = 0.0
var _chase_velocity: Vector3 = Vector3.ZERO
var _knockback: Vector3 = Vector3.ZERO
var _strike_direction: Vector3 = Vector3.FORWARD
var _flash_tween: Tween


func _ready() -> void:
	assert(data != null, "Enemy needs an EnemyData")
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Player
	_hitbox.owner_body = self
	_hitbox.hit_landed.connect(_on_hit_landed)
	_health.changed.connect(_on_health_changed)
	_health.died.connect(_on_died)
	_health.set_max_hp(data.max_hp)
	_apply_attack_reach()
	_enter(State.IDLE)


func take_hit(hit: HitInfo) -> void:
	if _state == State.DEAD:
		return
	_flash()
	# Super armor through the attack itself: hitting it mid-swing is a trade, not an interrupt.
	var can_flinch: bool = data.can_flinch and _state != State.WINDUP and _state != State.STRIKE
	_health.take_hit(hit)
	if _state == State.DEAD or not can_flinch:
		return
	var push: Vector3 = Vector3(hit.direction.x, 0.0, hit.direction.z)
	_knockback = push.normalized() * data.flinch_knockback
	_enter(State.FLINCH)


func is_dead() -> bool:
	return _state == State.DEAD


func get_state_name() -> String:
	return str(State.keys()[_state])


func _physics_process(delta: float) -> void:
	_state_time += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_tick_tell(delta)
	match _state:
		State.IDLE:
			if _target_alive() and _flat_to_target().length() <= data.aggro_range:
				_enter(State.CHASE)
		State.CHASE:
			_tick_chase(delta)
		State.WINDUP:
			_face_target(data.windup_turn_rate, delta)
			if _state_time >= data.windup_time:
				_enter(State.STRIKE)
		State.STRIKE:
			if _state_time >= data.strike_time:
				_enter(State.RECOVER)
		State.RECOVER:
			if _state_time >= data.recover_time:
				_enter(State.COOLDOWN)
		State.COOLDOWN:
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


func _tick_chase(delta: float) -> void:
	_chase_velocity = Vector3.ZERO
	if not _target_alive():
		_enter(State.IDLE)
		return
	_face_target(data.chase_turn_rate, delta)
	var to_target: Vector3 = _flat_to_target()
	var distance: float = to_target.length()
	if distance > data.trigger_range:
		_chase_velocity = to_target / distance * data.move_speed
		_play_loop(&"walk")
	else:
		_enter(State.WINDUP)


func _move(delta: float) -> void:
	var horizontal: Vector3 = _knockback
	match _state:
		State.CHASE:
			horizontal += _chase_velocity
		State.STRIKE:
			horizontal += _strike_lunge_velocity(delta)
	_knockback = _knockback.move_toward(Vector3.ZERO, data.knockback_decel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	move_and_slide()


## Ease-out step along the locked facing. Covers strike_lunge over strike_time at any tick rate,
## and move_and_slide stops it at walls and the player's capsule.
func _strike_lunge_velocity(delta: float) -> Vector3:
	if data.strike_lunge <= 0.0 or delta <= 0.0:
		return Vector3.ZERO
	var duration: float = maxf(data.strike_time, 0.001)
	var now: float = _ease_out(_state_time / duration)
	var before: float = _ease_out((_state_time - delta) / duration)
	return _strike_direction * (data.strike_lunge * (now - before) / delta)


func _enter(next: State) -> void:
	var previous: State = _state
	_state = next
	_state_time = 0.0
	if previous == State.RECOVER:
		_cooldown_left = data.cooldown_time
	if previous == State.STRIKE:
		# The strike animation's method track normally closes the hitbox; this covers interruptions.
		_hitbox.end_swing()
	match next:
		State.IDLE, State.COOLDOWN:
			_play_loop(&"idle")
		State.WINDUP:
			_play_timed(&"windup", data.windup_time)
			_tell_flash.visible = true
			_tell_left = data.tell_flash_time
			_grunt_sfx.play()
		State.STRIKE:
			# Facing locks here for the rest of STRIKE, RECOVER and COOLDOWN.
			_strike_direction = _facing()
			_play_timed(&"strike", data.strike_time)
			_swing_sfx.play()
		State.RECOVER:
			_play_timed(&"recover", data.recover_time)
		State.FLINCH:
			_play_timed(&"flinch", data.flinch_time, BLEND_FLINCH)
		State.DEAD:
			_die()


func _die() -> void:
	_hitbox.end_swing()
	_tell_flash.visible = false
	_body_shape.set_deferred(&"disabled", true)
	_health_bar.visible = false
	velocity = Vector3.ZERO
	_anim.play(&"die", BLEND_ACTION)
	_death_sfx.play()
	remove_from_group(&"enemies")


## Box runs from the enemy's center forward to attack_reach. The shape is local to scene, so this is per enemy.
func _apply_attack_reach() -> void:
	var box: BoxShape3D = _hitbox_shape.shape as BoxShape3D
	box.size.z = data.attack_reach
	_hitbox_shape.position.z = -data.attack_reach * 0.5


func _play_timed(anim_name: StringName, duration: float, blend: float = BLEND_ACTION) -> void:
	var length: float = _anim.get_animation(anim_name).length
	_anim.play(anim_name, blend, length / maxf(duration, 0.001))


func _play_loop(anim_name: StringName) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, BLEND_LOOP)


## Yaw-only turn toward the target, capped at `rate_deg` degrees per second.
func _face_target(rate_deg: float, delta: float) -> void:
	var to_target: Vector3 = _flat_to_target()
	if to_target.length_squared() < 0.0001:
		return
	var desired_yaw: float = atan2(-to_target.x, -to_target.z)
	rotation.y = rotate_toward(rotation.y, desired_yaw, deg_to_rad(rate_deg) * delta)


func _facing() -> Vector3:
	var forward: Vector3 = -global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _flat_to_target() -> Vector3:
	if not is_instance_valid(target):
		return Vector3.ZERO
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	return offset


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
	var direction: Vector3 = body.global_position - global_position
	direction.y = 0.0
	body.call(&"take_hit", HitInfo.new(data.damage, self, direction.normalized(), true))


func _on_health_changed(current: int, maximum: int) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current


func _on_died() -> void:
	_enter(State.DEAD)


static func _ease_out(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)
