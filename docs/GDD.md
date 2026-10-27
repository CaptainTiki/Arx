# Arx | Game Design Document

## Concept
First-person fantasy dungeon crawler inspired by Diablo 1, set around a **haunted castle**. Exploration, loot, and approachable melee combat are central. Ordinary enemies should be easy, until encounters become dangerous.

## Core Loop
- At camp/town, manage gear and prepare a castle key.
- Use the key to open the castle gate and enter its dungeon.
- Explore, fight enemies, and collect loot.
- Death returns the player to camp/town. A summoned portal allows a return to town to sell gear.

## Castle Keys
- **Each crafted key receives a permanent dungeon layout seed.** Using the same key returns to the same castle layout; crafting another key creates a new seed/layout.
- Players can keep and reuse keys.
- Items found during exploration can be used to craft/enchant keys, including modifying rewards or difficulty and unlocking deeper floors.
- Dungeon modifiers may be beneficial, detrimental, or mixed. Previously discussed examples: increased loot, enemy difficulty/health, chests, or gold.
- Enchantment permanence, replacement, and consumption rules are not yet decided.

## Dungeons
- Procedurally assembled from handcrafted Godot `.tscn` rooms and corridors, using room metadata and aligned doorway connectors.
- Overlapping modules are rejected; unused doorways are sealed.
- **Dungeon size counts rooms, not corridors** (design intent).
- Room spawn points roll enemies and items.
- Planned: keep a key's structural layout while refreshing encounters and loot between instances; preserve explored map areas.
- Previously discussed: an instance remains available for approximately 20 minutes after the last player leaves.

## Combat and Equipment
- First-person melee attacks and blocking, with impact, block, and enemy reaction feedback.
- Three enemy types implemented.
- Weapon/gear pickups and inventory implemented; equipment and loot support progression.

## Development
- Engine: Godot.
- Repository: https://github.com/CaptainTiki/Arx
- Current prototype includes dungeon generation, randomized spawns, combat, enemies, pickups, and inventory.
