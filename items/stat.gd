class_name Stat
## The one flat list of things gear can change. Affixes carry a Kind and a value; the player sums
## them across equipped items (Inventory.stat_total) and reads the totals instead of constants.
## PCT kinds are percentages (12 = +12%); the rest are flat.

enum Kind {
	DAMAGE_PCT,
	HEAVY_DAMAGE_PCT,
	BACKSTAB_PCT,
	ARMOUR,
	MAX_HP,
	MAX_STAMINA,
	STAMINA_REGEN,
	MOVE_SPEED_PCT,
	POISE_DAMAGE,
	GOLD_FIND_PCT,
}


static func is_percent(kind: Kind) -> bool:
	return kind in [Kind.DAMAGE_PCT, Kind.HEAVY_DAMAGE_PCT, Kind.BACKSTAB_PCT, Kind.MOVE_SPEED_PCT, Kind.GOLD_FIND_PCT]


static func label(kind: Kind) -> String:
	match kind:
		Kind.DAMAGE_PCT: return "damage"
		Kind.HEAVY_DAMAGE_PCT: return "heavy damage"
		Kind.BACKSTAB_PCT: return "backstab damage"
		Kind.ARMOUR: return "armour"
		Kind.MAX_HP: return "max HP"
		Kind.MAX_STAMINA: return "max stamina"
		Kind.STAMINA_REGEN: return "stamina regen"
		Kind.MOVE_SPEED_PCT: return "move speed"
		Kind.POISE_DAMAGE: return "poise damage"
		Kind.GOLD_FIND_PCT: return "gold find"
	return str(Kind.keys()[kind])


## "+12% damage" / "+3 armour".
static func describe(kind: Kind, value: float) -> String:
	var sign: String = "+" if value >= 0.0 else ""
	if is_percent(kind):
		return "%s%d%% %s" % [sign, roundi(value), label(kind)]
	return "%s%d %s" % [sign, roundi(value), label(kind)]
