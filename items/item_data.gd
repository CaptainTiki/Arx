class_name ItemData
extends Resource
## Base for anything that can lie on the floor and be picked up. Slot decides where it goes when
## taken. A .tres is a template; ItemRoller.roll turns one into a dropped item by duplicating it
## and filling in rarity, affixes and a name. Normal items stay the template itself.

enum Slot { WEAPON, HEAD, CHEST, HANDS, FEET, RING, TRINKET, OFFHAND }
enum Rarity { NORMAL, MAGIC, RARE, UNIQUE }

const RARITY_COLORS: Array[Color] = [
	Color(0.88, 0.88, 0.84),  # normal
	Color(0.42, 0.62, 1.0),   # magic
	Color(1.0, 0.85, 0.3),    # rare
	Color(1.0, 0.55, 0.2),    # unique
]

@export var display_name: String
@export var slot: Slot
## Inventory/paper-doll icon (step 5). Placeholder 32×32 for now.
@export var icon: Texture2D
## How it looks on the floor. Built upright (long axis +Y); Pickup lays it flat and rests it on the ground.
@export var world_mesh: Mesh
## Base sale value in gold at normal rarity; the roller scales it up with rarity and affixes.
@export var value: int = 5

## UNIQUE on a template means hand-authored: the roller leaves it alone. Set by the roller otherwise.
@export var rarity: Rarity = Rarity.NORMAL
## Hand-authored affixes on a unique, or the rolled copies on a dropped item.
@export var affixes: Array[Affix] = []

## The template's display_name, kept when the roller renames a magic or rare item.
var base_name: String = ""
## Loot level it dropped at.
var level: int = 1


func rarity_color() -> Color:
	return RARITY_COLORS[rarity]


func is_rolled() -> bool:
	return rarity != Rarity.NORMAL


## Sum of this item's affixes for one stat.
func stat(kind: Stat.Kind) -> float:
	var total: float = 0.0
	for affix: Affix in affixes:
		if affix.stat == kind:
			total += affix.value
	return total


## Gold the peddler pays. Rarity multiplies, each affix adds.
func sell_value() -> int:
	var mult: float = [1.0, 2.5, 6.0, 15.0][rarity]
	return maxi(1, roundi(value * mult + affixes.size() * 4 * level))
