class_name SpawnTable
extends Resource
## Weighted list of what a spawn point can produce. Rolled with the generator's seeded RNG, so a seed
## reproduces the spawns too.

@export var entries: Array[SpawnEntry] = []


## Weighted pick. The entry may have a null payload, meaning "nothing". Null only if the table is empty.
func roll(rng: RandomNumberGenerator) -> SpawnEntry:
	var total: float = total_weight()
	if total <= 0.0:
		return null
	var pick: float = rng.randf() * total
	for entry: SpawnEntry in entries:
		pick -= maxf(entry.weight, 0.0)
		if pick < 0.0:
			return entry
	return entries.back() as SpawnEntry


func total_weight() -> float:
	var total: float = 0.0
	for entry: SpawnEntry in entries:
		if entry:
			total += maxf(entry.weight, 0.0)
	return total
