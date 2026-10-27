class_name Pickup
extends StaticBody3D
## An item lying on the floor. Taking it moves it into the bag and frees this pickup. With a full
## bag it flips in place and says no.

@export var item: ItemData
@export_group("Reject")
## Seconds for the half-turn out and back.
@export var reject_time: float = 0.25
## How high it hops while flipping, in meters.
@export var reject_hop: float = 0.15

@onready var _flip: Node3D = %Flip
@onready var _mesh: MeshInstance3D = %Mesh
@onready var _shape: CollisionShape3D = %InteractShape
@onready var _nope_sfx: AudioStreamPlayer3D = %NopeSfx

var _reject_tween: Tween
var _glow: OmniLight3D


func _ready() -> void:
	set_item(item)


func interact(player: Player) -> void:
	if item == null:
		return
	if player.inventory.try_add(item):
		queue_free()
	else:
		reject()
		player.notify_inventory_full()


## The "bag full" tell: a half turn around Y and back with a little hop, plus a dull nope.
func reject() -> void:
	if _reject_tween:
		_reject_tween.kill()
	_flip.rotation.y = 0.0
	_flip.position.y = 0.0
	var half: float = reject_time * 0.5
	_reject_tween = create_tween()
	_reject_tween.tween_property(_flip, "rotation:y", PI, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.parallel().tween_property(_flip, "position:y", reject_hop, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.tween_property(_flip, "rotation:y", 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_reject_tween.parallel().tween_property(_flip, "position:y", 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_nope_sfx.play()


func is_rejecting() -> bool:
	return _reject_tween != null and _reject_tween.is_running()


## Swaps the resource and refreshes the mesh. Null empties the pickup (hidden, ray can't hit it).
func set_item(new_item: ItemData) -> void:
	item = new_item
	var has_item: bool = item != null
	visible = has_item
	_shape.set_deferred(&"disabled", not has_item)
	_mesh.mesh = item.world_mesh if has_item else null
	_rest_on_floor()
	# Magic and better glow on the floor in their colour, so a drop reads from across the room.
	if has_item and item.is_rolled():
		if _glow == null:
			_glow = OmniLight3D.new()
			_glow.omni_range = 2.2
			_glow.light_energy = 0.9
			_glow.position.y = 0.35
			add_child(_glow)
		_glow.light_color = item.rarity_color()
		_glow.visible = true
	elif _glow:
		_glow.visible = false


func prompt_text() -> String:
	return "Take %s" % item.display_name if item else ""


## Centers the item over the pickup and sits it on the ground, whatever its size.
## The Mesh node's authored rotation lays the upright world_mesh flat.
func _rest_on_floor() -> void:
	if _mesh.mesh == null:
		return
	var bounds: AABB = Transform3D(_mesh.basis, Vector3.ZERO) * _mesh.mesh.get_aabb()
	var center: Vector3 = bounds.get_center()
	_mesh.position = Vector3(-center.x, -bounds.position.y, -center.z)
