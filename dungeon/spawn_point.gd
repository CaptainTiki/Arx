@tool
class_name SpawnPoint
extends Marker3D
## Where something appears when the dungeon is built. The marker's transform becomes the spawn's.

enum Kind { ENEMY, WEAPON, PLAYER }

@export var kind: Kind
## Step 3: exactly what gets placed (ENEMY). Step 4 swaps this for a table.
@export var fixed_scene: PackedScene
## WEAPON kind: the pickup is given this item.
@export var fixed_item: ItemData


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint() and is_inside_tree():
		var room: Room = Room.owning_room(self)
		if room:
			room.update_configuration_warnings()
