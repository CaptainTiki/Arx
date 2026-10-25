class_name Enemy
extends CharacterBody3D
## Deliberately dumb melee enemy: walk up, telegraph an overhead smash, swing, stand there being hittable.

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, FLINCH, DEAD }

@export var data: EnemyData
## Who to fight. Falls back to the first node in the "player" group.
@export var target: Player

@export_group("Hit Flash")
## Overlay shared by every body mesh and tinted on hit. Must be local to scene.
@export var flash_material: StandardMaterial3D
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var flash_fade_color: Color = Color(1.0, 0.15, 0.1, 0.55)
@export var flash_time: float = 0.18

@onready var _health: Health = %Health
@onready var _hitbox: MeleeHitbox = %Hitbox
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
var _flash_tween: Tween


func _ready() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Player
	_hitbox.owner_body = self
	_hitbox.hit_landed.connect(_on_hit_landed)
	_health.changed.connect(_on_health_changed)
	_health.died.connect(_on_died)
	_on_health_changed(_health.hp, _health.max_hp)
	_enter(State.IDLE)


func take_hit(hit: HitInfo) -> void:
	if _state == State.DEAD:
		return
	_flash()
	# Super armor through the attack itself: hitting it mid-swing is a trade, not an interrupt.
	var can_flinch: bool = _state != State.WINDUP and _state != State.STRIKE
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
			_face_target(data.windup_turn_speed, delta)
			if _state_time >= data.windup_time:
				_enter(State.STRIKE)
		State.STRIKE:
			if _state_time >= data.strike_time:
				_enter(State.RECOVER)
		State.RECOVER:
			if _state_time >= data.recover_time:
				_enter(State.CHASE)
		State.FLINCH:
			if _state_time >= data.flinch_time:
				_enter(State.CHASE)
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
	_face_target(data.turn_speed, delta)
	var to_target: Vector3 = _flat_to_target()
	var distance: float = to_target.length()
	if distance > data.attack_range:
		_chase_velocity = to_target / distance * data.move_speed
		_play_loop(&"walk")
	elif _cooldown_left > 0.0:
		_play_loop(&"idle")
	else:
		_enter(State.WINDUP)


func _move(delta: float) -> void:
	var horizontal: Vector3 = _knockback
	if _state == State.CHASE:
		horizontal += _chase_velocity
	_knockback = _knockback.move_toward(Vector3.ZERO, data.knockback_decel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	move_and_slide()


func _enter(next: State) -> void:
	var previous: State = _state
	_state = next
	_state_time = 0.0
	if previous == State.RECOVER:
		_cooldown_left = data.attack_cooldown
	if previous == State.STRIKE:
		# The strike animation's method track normally closes the hitbox; this covers interruptions.
		_hitbox.end_swing()
	match next:
		State.IDLE:
			_play_loop(&"idle")
		State.WINDUP:
			_play_timed(&"windup", data.windup_time)
			_tell_flash.visible = true
			_tell_left = data.tell_flash_time
			_grunt_sfx.play()
		State.STRIKE:
			_play_timed(&"strike", data.strike_time)
			_swing_sfx.play()
		State.RECOVER:
			_play_timed(&"recover", data.recover_time)
		State.FLINCH:
			_play_timed(&"flinch", data.flinch_time, 0.03)
		State.DEAD:
			_die()


func _die() -> void:
	_hitbox.end_swing()
	_tell_flash.visible = false
	_body_shape.set_deferred(&"disabled", true)
	_health_bar.visible = false
	velocity = Vector3.ZERO
	_anim.play(&"die", 0.05)
	_death_sfx.play()
	remove_from_group(&"enemies")


func _play_timed(anim_name: StringName, duration: float, blend: float = 0.06) -> void:
	var length: float = _anim.get_animation(anim_name).length
	_anim.play(anim_name, blend, length / maxf(duration, 0.01))


func _play_loop(anim_name: StringName) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.15)


func _face_target(turn_speed: float, delta: float) -> void:
	var to_target: Vector3 = _flat_to_target()
	if to_target.length_squared() < 0.0001:
		return
	var desired_yaw: float = atan2(-to_target.x, -to_target.z)
	rotation.y = rotate_toward(rotation.y, desired_yaw, turn_speed * delta)


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
	flash_material.albedo_color = flash_color
	# Scaled time on purpose: the flash holds at full white through hitstop.
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_material, "albedo_color", flash_fade_color, flash_time * 0.4)
	_flash_tween.tween_property(flash_material, "albedo_color", Color(flash_fade_color, 0.0), flash_time * 0.6)


func _on_hit_landed(body: Node3D) -> void:
	var direction: Vector3 = body.global_position - global_position
	direction.y = 0.0
	body.call(&"take_hit", HitInfo.new(data.damage, self, direction.normalized(), true))


func _on_health_changed(current: int, maximum: int) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current


func _on_died() -> void:
	_enter(State.DEAD)
