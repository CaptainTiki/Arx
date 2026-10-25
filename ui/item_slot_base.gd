class_name ItemSlotBase
extends PanelContainer
## One square of the inventory screen. Holds no item state: it shows the Inventory model and edits
## it through drag & drop (Godot's built-in) and right-click shortcuts.
## Drag payload: { "item": ItemData, "from_bag": int or -1, "from_slot": ItemData.Slot or -1 }.

signal hovered(slot: ItemSlotBase)
signal unhovered(slot: ItemSlotBase)
## A right-click shortcut couldn't happen (e.g. unequip with a full bag).
signal refused

const DRAG_PREVIEW: PackedScene = preload("res://ui/DragPreview.tscn")

## Injected by InventoryScreen on ready.
var inventory: Inventory

@onready var _icon: TextureRect = %Icon


func _ready() -> void:
	mouse_entered.connect(func() -> void: hovered.emit(self))
	mouse_exited.connect(func() -> void: unhovered.emit(self))


func get_item() -> ItemData:
	return null


func refresh() -> void:
	var item: ItemData = get_item()
	_icon.texture = item.icon if item else null


## This slot's item as a drag payload (also what _get_drag_data returns).
func make_payload() -> Dictionary:
	return {"item": get_item(), "from_bag": -1, "from_slot": -1}


static func is_payload(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("item") and (data as Dictionary)["item"] is ItemData


func _get_drag_data(_at: Vector2) -> Variant:
	var item: ItemData = get_item()
	if item == null or inventory == null:
		return null
	# The preview is handed to the viewport and freed when the drag ends, so it has to be a fresh instance.
	var preview: Control = DRAG_PREVIEW.instantiate() as Control
	(preview.get_node(^"%Icon") as TextureRect).texture = item.icon
	set_drag_preview(preview)
	return make_payload()


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT and get_item() and inventory:
		quick_action()
		accept_event()


## Right-click shortcut. Overridden by BagSlot (equip) and EquipSlot (unequip).
func quick_action() -> void:
	pass
