class_name AffixPool
extends Resource
## Every affix that can roll, in one place. The Dungeon points at one; keys may add their own later.

@export var affixes: Array[Affix] = []


func fitting(slot: int, level: int) -> Array[Affix]:
	var out: Array[Affix] = []
	for affix: Affix in affixes:
		if affix.fits(slot, level):
			out.append(affix)
	return out
