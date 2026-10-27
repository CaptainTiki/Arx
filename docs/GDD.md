# Arx — Game Design Document

## Concept
First-person haunted-castle dungeon crawler with Diablo-style combat, loot and progression. You camp outside the walls. A key opens the castle; every turn of the key builds a new castle behind the door. The key is the run, the build and the progression: find them, grind them, upgrade them, keep the good ones.

Ordinary enemies are easy until an encounter gets dangerous. Exploration and combat are both central. Power fantasy, not punishment.

## The loop
1. At camp, pick a key from the rack and put it in the gate.
2. Turn it. Chains, the portcullis lifts, the door opens onto the entrance hall. Behind the theatre the generator has built the floor from the key.
3. Romp. Fight, loot, break things, open chests. Fill the bag.
4. Leave: walk back out the entrance, use a portal stone (bought with gold), or find the far exit — an exit-only room at the end of the floor, a small reward for finishing it.
5. Back at camp: sell to the peddler, grind or upgrade the key, pick a key, go again.

The key stays in the lock while you're inside and comes back out with you.

## Combat
First-person melee with lights, charged heavies and blocking. Every swing fires on release; holding draws the weapon back and the longer the hold the more of the heavy you get (a charge meter under the crosshair shows the light/heavy line and the forced-swing window). Stamina drains while charging and pays for blocks; running the bar dry under a block breaks your guard.

Enemies telegraph, have poise (several lights to stagger, a heavy always does), and give their turn: recovery after a swing is the opening, cooldown turns them back toward you. Hits from behind land harder; hits they never saw land harder still. A shield-bearing enemy clangs lights off its front and opens to a heavy, a flank, or patience.

Enemies: grunt (easy, poise 3), skitterer (pounces, swattable mid-air), bruiser (charges, eats walls, can't be flinched), shieldbearer (guard). Elites and champions later.

Movement is forward-biased: full speed forward, 70% strafe, 60% back. You block or step; you don't kite.

## The key
A key is an item like any other: rarity, affixes, level, name. Its affixes mean generator things:
- 1.5× loot · 3× loot & 1.5× enemy difficulty · 2× enemy difficulty · 2× chests · 2× gold · 2× enemy health · dense spawns · rarer drops · bigger floor.
- Level scales enemy stats and loot tiers.
- The layout seed lives on the key: a key is *that castle*, every time. Spawns, loot and chests reseed on every turn, so the same castle never holds the same loot. The minimap's memory lives on the key too — your grind key is a castle you know; a new key is dark.

### Camp stations
- **Gate** — portcullis and door in the castle wall; the key goes here. The exterior stows once you're inside.
- **Grinder** — hold E: the key on the left with its stats, spin the wheel to regrind it (gold per spin, scaling with level; rolls dull / magic / rare / unique like any item). Rename it here. Pay gold plus a rare drop to raise its level without rerolling. Later: a small chance a grind cracks the key (−1 level), so buying fresh keys matters.
- **Peddler** — buy and sell. Sells fresh keys and portal stones. Gold is a counter, not a bag item.
- **Key rack** — where owned keys live. Slots are a later upgrade.
- **Campfire.** Camp may grow into a town; it starts as a camp.

## Death
Difficulty is one setting:
- **Easy** — respawn at camp with everything.
- **Normal (default)** — respawn at camp; the bag drops where you fell as a tombstone, equipped gear stays. The key is still in the lock, so turn it: same castle, new monsters between you and your loot. Possibly a gold tithe.
- **Hard** — permadeath.

## Items and rarity
Gear is base + rolled instance (Diablo / PoE):
- `ItemData` is the static base. An `ItemInstance` is base + rarity + affixes + name, and is what lives in bags, slots and on the floor.
- Rarity: white (nothing), magic (1–2 affixes, blue), rare (3–4, yellow), unique (hand-authored, orange). Rarity weight rises with key level.
- Affixes are resources: a stat, a range, a tier, which slots they roll on, prefix or suffix. Around fifteen to start.
- Stats are one flat list — damage, armour, HP, stamina, regen, move speed, heavy damage, backstab, poise damage, gold find — summed from equipped gear on a character sheet (a tab of the inventory). Player code reads stats, not constants.
- Prototype visuals: rarity tints the pickup and the icon border; the name carries the rest. Reskins and `.tres`, no new asset pipeline yet.

## Dungeons
Procedurally assembled from handcrafted `.tscn` rooms and halls; room metadata and door markers drive selection, rotation and alignment; overlaps are rejected and unused doors sealed. Size is counted in rooms. Rooms carry spawn points with randomised enemy and item rolls from spawn tables. A full floor builds in ~0.1 s, so floors are built whole behind the door theatre — no streaming until floors are much larger. Torches light by room (the player's room and its neighbours), which keeps the renderer happy and makes unexplored rooms dark.

Two new rooms for the loop: an **entrance hall** (inside face of the gate; the exterior scene stows once you're in) and an **exit-only room** (a way out at the end of the floor — stairs up into the garden, or a side door by the gate — that can't be entered from outside).

## Build order (vertical slice)
1. Loop skeleton — camp scene, gate, generate behind the door, far exit, death to camp. Plain hard-coded key.
2. Items v2 — instances, rarity, affixes, stats, character sheet, gold. The key becomes an item here.
3. Peddler and grinder — both are the inventory UI with a second panel.
4. Key altar depth — sockets, levels, map memory per key.
5. Streaming, only if a measurement ever says so.

## Development
- Engine: Godot 4 (Compatibility renderer).
- Repository: https://github.com/CaptainTiki/Arx
- `NOTES.md` is the engineering handbook: what each step built, where the tunables live, what's known to be limited.
