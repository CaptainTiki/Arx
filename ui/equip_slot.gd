class_name EquipSlot
extends ItemSlotBase
## One paper-doll slot. Shows its slot name while empty.

@export var slot: ItemData.Slot

@onready var _hint: Label = %Hint


func _ready() -> void:
	super()
	_hint.text = str(ItemData.Slot.keys()[slot]).capitalize()


func get_item() -> ItemData:
	return inventory.get_equipped(slot) if inventory else null


func refresh() -> void:
	super()
	_hint.visible = get_item() == null


func make_payload() -> Dictionary:
	return {"item": get_item(), "from_bag": -1, "from_slot": slot}


## Only from the bag, and only an item made for this slot. Equip → equip is refused for now
## (it becomes RING ↔ RING once there are two ring slots).
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not is_payload(data) or inventory == null:
		return false
	var payload: Dictionary = data
	return int(payload["from_bag"]) >= 0 and (payload["item"] as ItemData).slot == slot


func _drop_data(_at: Vector2, data: Variant) -> void:
	var from_bag: int = (data as Dictionary)["from_bag"]
	var item: ItemData = inventory.take_from_bag(from_bag)
	var previous: ItemData = inventory.equip(item)
	if previous:
		inventory.put_in_bag(from_bag, previous)


## Right-click: take it off into the first free square; refused if the bag is full.
func quick_action() -> void:
	var free: int = inventory.first_free_index()
	if free < 0:
		refused.emit()
		return
	inventory.put_in_bag(free, inventory.unequip(slot))
