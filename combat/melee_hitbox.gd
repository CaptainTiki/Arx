class_name MeleeHitbox
extends Area3D
## Weapon/attack volume shared by player and enemy. Off until begin_swing(); each body is hit at most once per swing.

signal hit_landed(target: Node3D)

## Set by the parent so a swing never hits its own wielder.
var owner_body: Node3D

var _hit_this_swing: Array[Node3D] = []
var _active: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = false
	body_entered.connect(_on_body_entered)
	set_physics_process(false)


func begin_swing() -> void:
	_hit_this_swing.clear()
	_active = true
	set_deferred(&"monitoring", true)
	set_physics_process(true)


func end_swing() -> void:
	_active = false
	set_deferred(&"monitoring", false)
	set_physics_process(false)


## Rough contact point for FX: midpoint between this hitbox's shape and the body's shape.
func overlap_point(body: Node3D) -> Vector3:
	return _shape_center(self).lerp(_shape_center(body), 0.5)


func _physics_process(_delta: float) -> void:
	# A body already inside the box when monitoring turns on doesn't reliably fire
	# body_entered, so sweep current overlaps too. _hit_this_swing dedupes.
	if not monitoring:
		return
	for body: Node3D in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node3D) -> void:
	if not _active or body == owner_body or body in _hit_this_swing:
		return
	if body.has_method(&"take_hit"):
		_hit_this_swing.append(body)
		hit_landed.emit(body)


## Global position of the node's first collision shape, or the node itself if it has none.
static func _shape_center(node: Node3D) -> Vector3:
	var collider: CollisionObject3D = node as CollisionObject3D
	if collider:
		for owner_id: int in collider.get_shape_owners():
			var shape_node: Node3D = collider.shape_owner_get_owner(owner_id) as Node3D
			if shape_node:
				return shape_node.global_position
	return node.global_position
