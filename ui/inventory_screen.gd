class_name InventoryScreen
extends CanvasLayer
## Tab screen: paper doll + 6×4 bag over a paused game. Redraws from the Inventory on `changed` and
## holds no item state of its own. Dropping a drag on the background (not a slot) drops the item
## at the player's feet.

@onready var _root: Control = %Root
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_label: Label = %TooltipLabel
@onready var _armour_label: Label = %ArmourLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _hp_label: Label = %HPLabel
@onready var _stamina_label: Label = %StaminaLabel
@onready var _nope_sfx: AudioStreamPlayer = %NopeSfx

## Pixels between the cursor and the tooltip's corner.
@export var tooltip_offset: Vector2 = Vector2(18, 18)

var _player: Player
var _inventory: Inventory
var _slots: Array[ItemSlotBase] = []
var _hovered: ItemSlotBase


func _ready() -> void:
	visible = false
	_tooltip.visible = false
	_root.set_drag_forwarding(Callable(), _can_drop_on_background, _drop_on_background)


func _exit_tree() -> void:
	# Never leave the game paused behind a screen that's gone (e.g. a scene reload).
	if visible and is_inside_tree():
		get_tree().paused = false


## Wires the authored slots to the player's inventory. Called by Player on ready.
func bind(player: Player) -> void:
	_player = player
	_inventory = player.inventory
	_slots.clear()
	_collect_slots(_root)
	for slot: ItemSlotBase in _slots:
		slot.inventory = _inventory
		slot.hovered.connect(_on_slot_hovered)
		slot.unhovered.connect(_on_slot_unhovered)
		slot.refused.connect(_nope_sfx.play)
	_inventory.changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	if open == visible or (open and _player.is_dead()):
		return
	visible = open
	get_tree().paused = open
	if open:
		_player.intent.release_mouse()
		_refresh()
	else:
		_player.intent.capture_mouse()
		_hovered = null
		_tooltip.visible = false


func _process(_delta: float) -> void:
	if _player and _player.intent.consume_inventory_toggle():
		set_open(not visible)
	if not visible:
		return
	if get_viewport().gui_is_dragging():
		_tooltip.visible = false
	elif _tooltip.visible:
		var room: Vector2 = _root.size - _tooltip.size
		_tooltip.position = (_root.get_local_mouse_position() + tooltip_offset).clamp(Vector2.ZERO, room)


func _refresh() -> void:
	for slot: ItemSlotBase in _slots:
		slot.refresh()
	var weapon: WeaponData = _inventory.get_equipped(ItemData.Slot.WEAPON) as WeaponData
	_armour_label.text = "Armour: %d" % _inventory.total_armour()
	_weapon_label.text = "Weapon dmg: %s" % (str(weapon.damage) if weapon else "- (fists)")
	_hp_label.text = "HP: %d / %d" % [_player.health.hp, _player.health.max_hp]
	_stamina_label.text = "Stamina: %d / %d" % [roundi(_player.stamina.current), roundi(_player.stamina.max_stamina)]
	_update_tooltip()


func _on_slot_hovered(slot: ItemSlotBase) -> void:
	_hovered = slot
	_update_tooltip()


func _on_slot_unhovered(slot: ItemSlotBase) -> void:
	if _hovered == slot:
		_hovered = null
	_update_tooltip()


func _update_tooltip() -> void:
	var item: ItemData = _hovered.get_item() if _hovered else null
	_tooltip.visible = item != null and visible
	if item:
		_tooltip_label.text = describe(item)
		_tooltip_label.add_theme_color_override(&"font_color", item.rarity_color())
		_tooltip.reset_size()


## Tooltip text: name (and base name when renamed), rarity + slot, damage or armour, then one
## line per affix.
static func describe(item: ItemData) -> String:
	var lines: PackedStringArray = [item.display_name]
	if item.is_rolled() and not item.base_name.is_empty() and item.base_name != item.display_name:
		lines.append(item.base_name)
	var kind: String = str(ItemData.Slot.keys()[item.slot]).capitalize()
	if item.is_rolled():
		kind = "%s %s" % [str(ItemData.Rarity.keys()[item.rarity]).capitalize(), kind]
	lines.append(kind)
	var weapon: WeaponData = item as WeaponData
	var armor: ArmorData = item as ArmorData
	if weapon:
		lines.append("Damage %d" % weapon.damage)
	elif armor:
		lines.append("Armour %d" % armor.armour)
	for affix: Affix in item.affixes:
		lines.append(affix.describe())
	return "\n".join(lines)


func _can_drop_on_background(_at: Vector2, data: Variant) -> bool:
	return ItemSlotBase.is_payload(data)


## Removes the dragged item from wherever it came from and puts it on the floor in front of you.
func _drop_on_background(_at: Vector2, data: Variant) -> void:
	drop_to_world(data as Dictionary)


func drop_to_world(payload: Dictionary) -> void:
	var from_bag: int = payload["from_bag"]
	var item: ItemData = _inventory.take_from_bag(from_bag) if from_bag >= 0 else _inventory.unequip(int(payload["from_slot"]) as ItemData.Slot)
	if item:
		_player.drop_item(item)


func _collect_slots(node: Node) -> void:
	for child: Node in node.get_children():
		if child is ItemSlotBase:
			_slots.append(child as ItemSlotBase)
		_collect_slots(child)
