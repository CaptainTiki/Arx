@tool
class_name SpawnPoint
extends Marker3D
## Where something appears when the dungeon is built. The marker's transform becomes the spawn's.
## Table first: if `table` is set it's rolled (a "nothing" row places nothing). Otherwise the fixed
## fallback is used, exactly as in step 3. CHEST has no fallback; it needs a table.
## A chest faces the marker's -Z and spills its loot that way, so point it into the room.

## New kinds go on the end: scenes store the number.
enum Kind { ENEMY, WEAPON, PLAYER, BREAKABLE, CHEST }

@export var kind: Kind
## Rolled if set. ENEMY reads each row's `enemy`, WEAPON its `item`, BREAKABLE its `scene`, CHEST its `chest`.
@export var table: SpawnTable
## Fallback when there's no table: the scene placed for ENEMY or BREAKABLE.
@export var fixed_scene: PackedScene
## Fallback when there's no table: the item a WEAPON pickup gets.
@export var fixed_item: ItemData


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint() and is_inside_tree():
		var room: Room = Room.owning_room(self)
		if room:
			room.update_configuration_warnings()
