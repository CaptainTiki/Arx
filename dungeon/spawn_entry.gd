class_name SpawnEntry
extends Resource
## One row of a SpawnTable. The SpawnPoint's kind decides which payload is read; both empty = spawn nothing.

@export var weight: float = 1.0
## Read by ENEMY spawn points.
@export var enemy: EnemyData
## Read by WEAPON spawn points.
@export var item: ItemData


## What this row spawns for a spawn point of `kind`, or null for "nothing".
func payload_for(kind: SpawnPoint.Kind) -> Resource:
	return enemy if kind == SpawnPoint.Kind.ENEMY else item


## Short name for logs: the payload's display name, or "nothing".
func describe(kind: SpawnPoint.Kind) -> String:
	if kind == SpawnPoint.Kind.ENEMY and enemy:
		return enemy.display_name.to_lower()
	if kind == SpawnPoint.Kind.WEAPON and item:
		return item.display_name.to_lower()
	return "nothing"
