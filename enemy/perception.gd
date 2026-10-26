class_name Perception
extends Node3D
## The enemy's eyes, placed at eye height. Cheap on purpose: range check, then cone, then one
## raycast to the player's head that must hit the player, not geometry. Each enemy only looks on
## its own slot of a STAGGER-frame cycle, so a room full of them doesn't raycast on the same tick.

## Physics frames per look. can_see holds its last result in between.
const STAGGER: int = 4

## Who it's looking for. Set by the Enemy.
var target: Player
var can_see: bool = false
## Where the target was the last time it was seen (or heard; Enemy writes this too).
var last_known_pos: Vector3

@onready var ray: RayCast3D = %SightRay
@onready var _enemy: Enemy = owner as Enemy

var _phase: int = 0


func _ready() -> void:
	_phase = get_instance_id() % STAGGER


func _physics_process(_delta: float) -> void:
	if Engine.get_physics_frames() % STAGGER != _phase:
		return
	can_see = _look()
	if can_see:
		last_known_pos = target.global_position


func _look() -> bool:
	if not is_instance_valid(target) or target.is_dead() or _enemy.is_dead():
		return false
	var data: EnemyData = _enemy.data
	var eye: Vector3 = global_position
	var head: Vector3 = target.eye_position()
	var to_head: Vector3 = head - eye
	var distance: float = to_head.length()
	if distance > data.sight_range:
		return false
	# Aware enemies feel you behind them up close; unaware ones only see inside the cone.
	var sensed: bool = _enemy.is_aware() and distance <= data.aware_sense_range
	if not sensed:
		var forward: Vector3 = -global_basis.z
		var flat_forward: Vector2 = Vector2(forward.x, forward.z).normalized()
		var flat_to: Vector2 = Vector2(to_head.x, to_head.z).normalized()
		if flat_forward.dot(flat_to) < cos(deg_to_rad(data.sight_fov) * 0.5):
			return false
	ray.target_position = ray.to_local(head)
	ray.force_raycast_update()
	return ray.get_collider() == target
