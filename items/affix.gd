class_name Affix
extends Resource
## One rollable modifier. Authored as a template (a range, which slots it fits, a name part); when
## an item rolls it, a copy with `value` set is stored on that item.

## Word that goes before the base name (prefix) or after it (suffix: "of the Bear").
@export var name_part: String = ""
@export var is_prefix: bool = true
@export var stat: Stat.Kind = Stat.Kind.DAMAGE_PCT
@export var value_min: float = 1.0
@export var value_max: float = 10.0
## Slots this can roll on (ItemData.Slot values). Empty = any.
@export var slots: Array[int] = []
## Relative pick chance among affixes that fit.
@export var weight: float = 1.0
## Lowest loot level that can roll this. (Tiers later: the same affix at higher ranges.)
@export var min_level: int = 1

## The rolled value. 0 on a template.
var value: float = 0.0


func fits(slot: int, level: int) -> bool:
	return level >= min_level and (slots.is_empty() or slots.has(slot))


func describe() -> String:
	return Stat.describe(stat, value)
