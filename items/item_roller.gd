class_name ItemRoller
## Turns a base item (.tres template) into a dropped item: a duplicate with a rarity, rolled affixes
## and a name. Normal items come back as the template itself, untouched: a Rusty Sword is a Rusty
## Sword. Anything magic or better is a fresh resource that belongs to that drop alone.

const RARE_FIRST: PackedStringArray = ["Dread", "Grim", "Pale", "Bitter", "Wolf", "Raven", "Ember", "Storm", "Bone", "Iron", "Night", "Gallows"]
const RARE_SECOND: PackedStringArray = ["Fang", "Bite", "Song", "Mark", "Grasp", "Edge", "Ward", "Oath", "Call", "Shroud", "Brand", "Thorn"]


## Rarity weights at `level`: normal shrinks, magic and rare grow. Unique isn't rolled yet.
static func rarity_weights(level: int) -> Array[float]:
	var l: float = float(maxi(level, 1) - 1)
	return [
		maxf(60.0 - 4.0 * l, 15.0),  # NORMAL
		30.0 + 2.5 * l,              # MAGIC
		8.0 + 1.5 * l,               # RARE
		0.0,                         # UNIQUE
	]


static func roll(base: ItemData, level: int, rng: RandomNumberGenerator, pool: AffixPool) -> ItemData:
	if base == null or pool == null or base.rarity == ItemData.Rarity.UNIQUE:
		return base
	var rarity: int = _weighted(rng, rarity_weights(level))
	if rarity == ItemData.Rarity.NORMAL:
		return base
	var affix_count: int
	match rarity:
		ItemData.Rarity.MAGIC: affix_count = 1 if rng.randf() < 0.6 else 2
		_: affix_count = 3 if rng.randf() < 0.6 else 4
	var candidates: Array[Affix] = pool.fitting(base.slot, level)
	if candidates.is_empty():
		return base
	var item: ItemData = base.duplicate() as ItemData
	item.base_name = base.display_name
	item.rarity = rarity as ItemData.Rarity
	item.level = level
	item.affixes = []
	var used_stats: Array[int] = []
	for i: int in affix_count:
		var options: Array[Affix] = []
		var weights: Array[float] = []
		for affix: Affix in candidates:
			if used_stats.has(affix.stat):
				continue
			options.append(affix)
			weights.append(affix.weight)
		if options.is_empty():
			break
		var template: Affix = options[_weighted(rng, weights)]
		var rolled: Affix = template.duplicate() as Affix
		rolled.value = rng.randf_range(template.value_min, template.value_max)
		if not Stat.is_percent(rolled.stat):
			rolled.value = roundf(rolled.value)
		item.affixes.append(rolled)
		used_stats.append(rolled.stat)
	item.display_name = _name_for(item, rng)
	return item


static func _name_for(item: ItemData, rng: RandomNumberGenerator) -> String:
	if item.rarity == ItemData.Rarity.RARE:
		return "%s %s" % [RARE_FIRST[rng.randi() % RARE_FIRST.size()], RARE_SECOND[rng.randi() % RARE_SECOND.size()]]
	var prefix: String = ""
	var suffix: String = ""
	for affix: Affix in item.affixes:
		if affix.is_prefix and prefix.is_empty():
			prefix = affix.name_part
		elif not affix.is_prefix and suffix.is_empty():
			suffix = affix.name_part
	var parts: PackedStringArray = []
	if not prefix.is_empty():
		parts.append(prefix)
	parts.append(item.base_name)
	if not suffix.is_empty():
		parts.append(suffix)
	return " ".join(parts)


static func _weighted(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	var total: float = 0.0
	for w: float in weights:
		total += w
	var pick: float = rng.randf() * total
	for i: int in weights.size():
		pick -= weights[i]
		if pick <= 0.0:
			return i
	return weights.size() - 1
