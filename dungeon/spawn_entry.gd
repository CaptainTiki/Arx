class_name SpawnEntry
extends Resource
## One row of a SpawnTable. The SpawnPoint's kind decides which payload is read; all empty = spawn nothing.
## Loot drop tables (Dungeon.drop_loot) read `item`, like a WEAPON point.

@export var weight: float = 1.0
## Read by ENEMY spawn points.
@export var enemy: EnemyData
## Read by WEAPON spawn points and by drop tables.
@export var item: ItemData
## Read by BREAKABLE spawn points: a Breakable scene (Crate, Pot, Barrel).
@export var scene: PackedScene
## Read by CHEST spawn points.
@export var chest: ChestData


## What this row spawns for a spawn point of `kind`, or null for "nothing".
func payload_for(kind: SpawnPoint.Kind) -> Resource:
	match kind:
		SpawnPoint.Kind.ENEMY:
			return enemy
		SpawnPoint.Kind.BREAKABLE:
			return scene
		SpawnPoint.Kind.CHEST:
			return chest
		_:
			return item


## Whatever this row carries, read by any kind. Null = a "nothing" row.
func any_payload() -> Resource:
	for payload: Resource in [enemy, item, scene, chest]:
		if payload:
			return payload
	return null


## Short name for logs: the payload's display name (scene or chest: its file name), or "nothing".
func describe(kind: SpawnPoint.Kind) -> String:
	return payload_name(payload_for(kind))


static func payload_name(payload: Resource) -> String:
	if payload is EnemyData:
		return (payload as EnemyData).display_name.to_lower()
	if payload is ItemData:
		return (payload as ItemData).display_name.to_lower()
	if payload == null:
		return "nothing"
	var file: String = payload.resource_path.get_file().get_basename().to_lower()
	# A chest made in code has no file; its display name will do.
	if file.is_empty() and payload is ChestData:
		return (payload as ChestData).display_name.to_lower()
	return file
