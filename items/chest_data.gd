class_name ChestData
extends Resource
## What one kind of chest holds. Opening it rolls drop_table a random drop_rolls_min..max times
## (Dungeon.drop_loot) and spills the lot on the floor in front of it.

@export var display_name: String = "Chest"
## Rolls with no "nothing" row, so every roll is an item.
@export var drop_table: SpawnTable
@export var drop_rolls_min: int = 1
@export var drop_rolls_max: int = 3
## Put on the lid. Null = the scene's wood. For tinting by rarity later.
@export var lid_material: Material


## Average number of rolls, for the loot report.
func mean_rolls() -> float:
	return (drop_rolls_min + maxi(drop_rolls_min, drop_rolls_max)) * 0.5
