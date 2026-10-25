class_name BagSlot
extends ItemSlotBase
## One of the 24 bag squares.

@export var index: int


func get_item() -> ItemData:
	return inventory.bag[index] if inventory else null


func make_payload() -> Dictionary:
	return {"item": get_item(), "from_bag": index, "from_slot": -1}


## Bag → bag always swaps. Equip → bag works onto an empty square, or onto an item that fits the
## slot it came from (then the two trade places); anything else is refused.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not is_payload(data) or inventory == null:
		return false
	var payload: Dictionary = data
	if int(payload["from_bag"]) >= 0:
		return true
	var occupant: ItemData = get_item()
	return occupant == null or occupant.slot == int(payload["from_slot"])


func _drop_data(_at: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	var from_bag: int = payload["from_bag"]
	if from_bag >= 0:
		if from_bag == index:
			return
		var moving: ItemData = inventory.take_from_bag(from_bag)
		var displaced: ItemData = inventory.put_in_bag(index, moving)
		if displaced:
			inventory.put_in_bag(from_bag, displaced)
		return
	var unequipped: ItemData = inventory.unequip(int(payload["from_slot"]) as ItemData.Slot)
	var swapped_in: ItemData = inventory.put_in_bag(index, unequipped)
	if swapped_in:
		inventory.equip(swapped_in)


## Right-click: wear it. Whatever was in that slot takes its square.
func quick_action() -> void:
	var item: ItemData = inventory.take_from_bag(index)
	var previous: ItemData = inventory.equip(item)
	if previous:
		inventory.put_in_bag(index, previous)
