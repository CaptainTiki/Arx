class_name Inventory
extends Node
## Everything the player carries (6×4 bag) and wears (one item per slot). The only home of item
## state: the UI redraws from here on `changed` and never keeps items of its own.
## The WEAPON slot is mirrored into the WeaponRig; nothing else equips the rig.

signal changed

const COLS: int = 6
const ROWS: int = 4

## COLS * ROWS squares, row-major; null = empty.
var bag: Array[ItemData] = []
## ItemData.Slot -> ItemData, null if empty. Every slot has a key.
var equipped: Dictionary[int, ItemData] = {}

@onready var _weapon_rig: WeaponRig = %WeaponRig


func _init() -> void:
	bag.resize(COLS * ROWS)
	for slot: int in ItemData.Slot.values():
		equipped[slot] = null


## Puts `item` in the first free square. False if the bag is full.
func try_add(item: ItemData) -> bool:
	var index: int = first_free_index()
	if item == null or index < 0:
		return false
	bag[index] = item
	changed.emit()
	return true


## Returns and clears the item at `index`.
func take_from_bag(index: int) -> ItemData:
	var item: ItemData = bag[index]
	if item:
		bag[index] = null
		changed.emit()
	return item


## Puts `item` at `index` and returns what was there (for swaps).
func put_in_bag(index: int, item: ItemData) -> ItemData:
	var previous: ItemData = bag[index]
	bag[index] = item
	changed.emit()
	return previous


## Wears `item` in its own slot and returns the previous occupant. WEAPON goes to the rig;
## RING and TRINKET are stored but do nothing yet.
func equip(item: ItemData) -> ItemData:
	if item == null:
		return null
	var previous: ItemData = equipped[item.slot]
	equipped[item.slot] = item
	if item.slot == ItemData.Slot.WEAPON:
		_sync_weapon()
	changed.emit()
	return previous


## Empties `slot` and returns what was in it. An empty WEAPON slot means fists.
func unequip(slot: ItemData.Slot) -> ItemData:
	var previous: ItemData = equipped[slot]
	if previous == null:
		return null
	equipped[slot] = null
	if slot == ItemData.Slot.WEAPON:
		_sync_weapon()
	changed.emit()
	return previous


func get_equipped(slot: ItemData.Slot) -> ItemData:
	return equipped[slot]


## PLACEHOLDER armour: flat sum across worn ArmorData.
func total_armour() -> int:
	var total: int = 0
	for item: ItemData in equipped.values():
		var armor: ArmorData = item as ArmorData
		if armor:
			total += armor.armour
	return total


func first_free_index() -> int:
	return bag.find(null)


func _sync_weapon() -> void:
	_weapon_rig.equip(equipped[ItemData.Slot.WEAPON] as WeaponData)
