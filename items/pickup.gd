class_name Pickup
extends StaticBody3D
## An item lying on the floor. Taking a weapon swaps it in place: this pickup stays put and now
## holds the weapon you had. Nothing is freed or instantiated.

@export var item: ItemData

@onready var _mesh: MeshInstance3D = %Mesh
@onready var _shape: CollisionShape3D = %InteractShape


func _ready() -> void:
	set_item(item)


func interact(player: Player) -> void:
	if item == null:
		return
	if item.slot == ItemData.Slot.WEAPON:
		player.swap_weapon(self)
	else:
		print("Pickup: %s (%s) - non-weapon slots are handled in step 5" % [item.display_name, ItemData.Slot.keys()[item.slot]])


## Swaps the resource and refreshes the mesh. Null empties the pickup (hidden, ray can't hit it).
func set_item(new_item: ItemData) -> void:
	item = new_item
	var has_item: bool = item != null
	visible = has_item
	_shape.set_deferred(&"disabled", not has_item)
	_mesh.mesh = item.world_mesh if has_item else null
	_rest_on_floor()


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
