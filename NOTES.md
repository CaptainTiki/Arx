# Steps 1–11 — Swing & Block, Pickups, Generated Dungeon, Spawn Tables, Inventory, Enemy Perception, Generator v2 & Minimap, Connectors, Aimed Branches, Hub Rooms & Halls, Loot v1, Combat Feel

Open in Godot 4.7, press F5. Main scene: `res://main/Main.tscn`. The step-1 room lives on as `res://tests/CombatArena.tscn`, the fixture for the combat smoke test; you can also open it and F6 it to fight one grunt in a known room.

**Controls:** WASD move · Shift sprint · LMB swing · RMB block (hold) · E take · Tab inventory · M full map · R restart · F5 new dungeon · F6 same dungeon again · Esc frees the mouse (click to recapture).

Every Play builds a different floor: a main path of 12 rooms from a start room to a glowing exit pad, with 4–6 side branches off it, about 36 rooms in all. Rooms never open straight into rooms; a hall of 1–4 corridor pieces always sits between them, and every floor loops back on itself several times. (Step 9 doubled everything on purpose, to tune down from; see Step 9.) You start holding the Rusty Sword with an empty bag. Combat and treasure rooms roll what's in them from spawn tables. The output log prints the floor's shape (`Dungeon seed N: main 12, branches 5/5 (depths 3,6,6,5,6), aimed 5 (closed 1), halls 41 (mean 1.6, 2 extended, 10 capped), loops 8 (len 6, 4, 6, 7, 8, 8, 9, 10), treasure at depths [2, 10], candidates 12`), then one line per spawn point (`room 4 (CombatRoom_B) spawn 1 → skitterer`). Put N in `DungeonGenerator.seed_value`, or press F6, to get that exact floor and those exact spawns again. F5 builds a new one. Look at an item within 2.5 m and press E to put it in your bag; Tab opens the inventory to wear it. The corner map fills in each room as you walk into it; M swaps it for a full-screen map.

Enemies stand watch, sweeping their gaze, until they **see** you (12 m, a 110° cone, a clear line to your head) or **hear** you (a fight, a block, a sprint, a dropped item). Then they bark, turn, and come for you, or go and look if they only heard something. Lose them for 3 s and they search where they last saw you, then walk home. Grunts walk in, rear back with a red flash (the windup, turning at most their turn rate to follow you) and lunge into the strike. Skitterers crouch and leap at you from mid-range. Bruisers roar and charge from afar; sidestep one into a wall and it stands there dazed. After any attack the enemy stands still, without turning, through recovery and cooldown. See Steps 4 and 6.

---

## Step 11: combat feel — poise, charged heavy, shield, guard, openings, room lights

Commits `Combat Feel` → `Cooldown Tracking / Bruiser Tune`. The diagnosis was that every enemy system (telegraph, windup, strike) existed but never ran, because holding LMB flinch-locked a grunt to death and nothing the player did cost anything. The fix was to give the enemy its turn and make the player's turn cost something, not to add juice.

### Player
- **Directional speed** (`player.gd`): forward 1.0, strafe `strafe_speed_mult` 0.7, back `backpedal_speed_mult` 0.6, blended by input direction; applies to sprint. You can't kite a 3 m/s grunt with a 1.4 m lunge at 3 m/s.
- **Every swing fires on release.** Press enters `CHARGE` in `weapon_rig.gd`; after `heavy_pose_dead_time` (0.1 s) the weapon draws back (`heavy_pose_offset`/`heavy_pose_rot_deg` on the rig, applied to `ViewPivot` by `_heavy_blend`). On release, `fraction = held / heavy_charge_time`. Below `WeaponData.heavy_threshold` (0.75) it's a light; at or above, a heavy whose damage, hitstop, kick and swing time lerp from the light's numbers to the heavy's by the fraction. `HitInfo.heavy` is set only for a real heavy. Full charge + `heavy_auto_release` (0.8 s) forces the swing. Click-again mid-swing with the button still down flows into the next charge.
- **Stamina drains during the charge**: `heavy_stamina_cost` spread evenly over `heavy_charge_time` via `Stamina.spend_or_break`; running dry releases on the spot. On release the rig settles the remainder of whichever swing it became. Pool 100, regen 30/s after 0.8 s. Sword 12/30, dagger 6/16, axe 20/45 (light/heavy). Light-light-heavy-breathe sustains; pure spam decays to a swing every ~1.2 s.
- **Charge meter** (`ui/charge_meter.gd`, `%ChargeMeter` under HUD): visible only while charging. Light colour to the white tick at the threshold, heavy colour past it; a thin red bar beneath fills over the auto-release window. `Hud.set_charge` is fed from `Player._physics_process`.
- **Blocks cost stamina**: `block_stamina_per_damage` (1.0) per point absorbed, times `WeaponRig.block_cost_mult()` (the shield's, or 1). If the bar runs dry under a block it's a **guard break**: the hit lands, `WeaponRig.break_guard()` locks the rig in `STAGGER` for `guard_break_time` (0.45 s), low clang, big shake.
- **Shield** (`items/shield_data.gd`, slot `OFFHAND` = 7, paper-doll square bottom-right). Blocks with it bare-handed. `block_cost_mult` 0.4, `block_cone_dot` 0 (whole front half). The view mesh is `%ShieldPivot` in Player.tscn (primitive boxes, palette materials); `ShieldData.rest_*` / `block_*` pose it, lerped by `_shield_blend`. Rest is low-left and edge-on so it covers almost nothing; block is square in front, top around the bottom fifth. A hit while raised shoves it back and returns. `wooden_shield.tres` drops from shieldbearers (weight 3) and treasure rooms (1.5).

### Enemies
- **Poise** (`EnemyData.poise`): light hits in a row before one staggers. Counter resets on stagger and on entering any attack windup. Heavies always stagger. Grunt 3, shieldbearer 2, skitterer 1, bruiser never (`can_flinch` false). Grunt HP 100 → 50: two lights or one heavy.
- **Swat** (`pounce_swattable`, `swat_knockback`): a hit or a held block during `POUNCE` drops the skitterer where it is into `RECOVER` with a shove. Super armour no longer covers the leap.
- **Cooldown tracks**: `COOLDOWN` now turns toward the target at `chase_turn_rate`. `RECOVER` stays facing-locked — that's the earned window. Circling an enemy after its swing no longer buys a second window. Bruiser retuned: HP 250 → 170, windup 1.1 → 0.9 s, cooldown 0.8 → 0.5, `windup_turn_rate` 90 → 220 so you can't walk out of the swing.
- **Openings** (`EnemyData`): `backstab_mult` 1.5 when the attacker is past `backstab_dot` of the facing (−0.3; shieldbearer −0.5), `sneak_mult` 2.0 when it never saw you (unaware, searching, or still in the alert turn). `HitInfo.bonus` carries the multiplier back so the rig scales kick and hitstop with it.
- **Guard** (`EnemyData.guard`, shieldbearer): up in IDLE/ALERT/CHASE/SEARCH/COOLDOWN, covers `guard_cone_dot` of the front (0.1, ~160°). Light from the front → `hit.blocked`, no damage, rig plays clang + sparks and a short jolt. Heavy from the front → damage lands, `GUARD_BROKEN` state for `guard_break_time` (1.5 s, "stunned": reels on hits but stays open), then COOLDOWN. The guard is down from WINDUP through RECOVER. The shield arm (`%ArmL`, not in any clip) is posed from code by `_pose_shield_arm`: up / down / broken, exports on the Enemy scene. Shieldbearer: 100 HP, 20 dmg, 0.9 s windup, 1.1 s recover, weight 2.5 in `combat_enemy.tres`; bruiser weight 1 → 2.

### Room lights
- The Compatibility renderer caps lights per mesh (`max_lights_per_object`, now 16) and globally (`max_renderable_lights`, 32 → 256); the old symptom was whole rooms going dark as the in-view count crossed 32.
- `Dungeon.light_reach` (2): torches are lit by map group — the player's group plus everything within that many used doorways. Others are doused (no light, no flame, 0.35 s fade; `Torch.set_lit`). `_collect_torches` runs in `set_plan` (rooms are already children), files torches by the group of their cell, and builds group adjacency from used doors. `_relight` on every `player_cell` change. Torches outside a dungeon stay lit.

## Step 10: loot v1 — breakables, chests, per-source drop tables

Commit `Loot v1`. Crates, pots and barrels (`world/Breakable.tscn` + inherited scenes) on the enemy layer so the sword finds them; shatter into pre-placed debris flung along the swing, dust, crack SFX, noise, and a roll on their drop table. Chests (`world/Chest.tscn`, `ChestData` common/rich) open once on E, lid animates, loot spills in front via `Dungeon.drop_loot`. `data/tables/drops/` holds one table per source (barrel, crate, pot, chest, chest_rich, each enemy).

## Step 9: hub rooms, adaptive halls, doubled floors

Rooms are now hubs with doors on several sides, the halls between them are chains of 1–4 connector pieces that bend round whatever is in the way, and every shape knob is doubled ("deliberately too big; we tune down from the maps"). Vocabulary: a **room** is content, a **hall** is the chain of connector pieces between two rooms, and a **corridor** is one piece.

**The maps:** `docs/plans_step9.png`, seeds 1–12 at the defaults, from `tools/plan_map.gd`. `docs/plans_step8.png` is the same seeds on the step-8.1 generator, for comparison. Light grey is the main path, dark grey branches, darker strips halls, yellow loop bridges, green START, orange EXIT, tan treasure. White notches are used doors and red ones plugged.

### Hub rooms — `res://dungeon/rooms/` (greybox CSG, all COMBAT)

| Scene | Footprint | Doors | Spawns | Weight | What's in it |
|---|---|---|---|---|---|
| `Hall_4x8` | 4×8 | W and E, each at z = 1 and z = 6 | ENEMY ×3, WEAPON ×1 | 1 | Five pillars down the middle, 4 torches |
| `Crossroads_3x3` | 3×3 | N, E, S, W, centred | ENEMY ×1 | 2 | One central pillar, 2 torches |
| `Hub_5x5` | 5×5 | N, E, S, W centred, plus a second S at x = 0 | ENEMY ×3 (one on the platform), WEAPON ×1 (on the platform) | 1 | An 8×8 m platform 0.5 m up, with a 2 m ramp on each side facing the centred doors. The ring round it, where the doors are, stays at floor level. 4 torches |
| `Gallery_2x6` | 2×6 | N at x = 0, S at x = 1, W and E at z = 2 | ENEMY ×2 | 2 | Plain and narrow, 2 torches |
| `Barracks_4x4` | 4×4 | N (x = 1), E (z = 2), S (x = 2) | ENEMY ×2, WEAPON ×1 | 2 | Four wooden bunks along the blank west wall and two 1.2 m stone low walls as cover, 3 torches |

Every ENEMY point is on `combat_enemy.tres` and every WEAPON point on `combat_weapon.tres`, and the room warnings are clean on all five. The existing combat rooms keep their weight of 1. A room 2 or 4 cells wide has no centred cell, so the Gallery's end doors are offset diagonally (its long run jogs), and the Barracks' N and S sit one cell either side of the middle.

### Halls — `DungeonGenerator._grow_link()`

```
grow_link(door, type): lay 1 or 2 connectors (by weight; every template and entry door tried until one fits with a way on)
  loop: try every allowed room of `type` (weighted order) at every entry door on the hall's end; one fits? done
        the hall is max_hall_pieces long? give up
        else extend by one piece in hall_extend_order (L, Straight, T, Corridor_4, Corridor_2): the first that fits
  give up: _unplace() every piece, newest first, and cap the door (never grown from again; plugged unless a bridge ends there)
main path: the current room tries its free doors until a link takes; none take = restart. A branch does the same; none = it ends.
```

- **`_unplace()`** is the exact reverse of `_place()`: cells freed, the parent's door free again, the piece dropped from the plan, the room and template counts undone. The test turns on `verify_unplace`, which copies the layout before every link and compares it after every failed one. Over 1000 seeds, restarts' tries included, that's 6,028 failed links and none changed anything.
- A T in a hall carries on through one of its two exits (picked at random, or toward an aimed branch's target), and the other stays free. Main-path T's are branch starts like the main-path rooms, and any T exit can end a loop bridge.
- **Capped doors still take loop bridges.** A capped door had no room for a hall plus a room, but a 1-cell-wide bridge may fit. Branch starts and links skip them.
- Every link is room → hall → room, and the connector rule is gone. `_next_type`, `_grow_one` and `door_retry_limit` went with it. Loop bridges are untouched. Separation still counts rooms only, so a whole hall is free.
- On the map, a hall's pieces join into one corridor with no seams, like a bridge's (`MapModel` groups them).

### Knobs — doubled

| Knob | Was | Now | Notes |
|---|---|---|---|
| `main_path_length` | 6 | **12** | |
| `branch_count_min` / `max` | 2 / 3 | **4 / 6** | |
| `max_branch_depth` | 3 | **6** | |
| `max_loop_length` (the handoff's `bridge_max_len`) | 5 | **10** | Kept its name |
| `max_rooms` | 24 | **64** | Never binds (0 of 1000 floors). A floor can't pass 52 rooms: 14 on the spine, 6 branches of 6, 2 treasure rooms off the main path. |
| `max_hall_pieces` | (new) | **4** | |
| `hall_extend_order` | (new) | L, Straight, T, Corridor_4, Corridor_2 | Connectors not listed come after, in catalog order |
| `loop_min_separation` | 3 | 3 | |
| `max_attempts` | 200 | **2500** | Every template and entry door a hall or room tries counts now. A floor spends 425 on average and 1,240 at worst, so 200 cut almost every floor short (silently: the branch pass just stops). 2500 is twice the worst. |
| `max_restarts` | 5 | **10** | 78.8% of seeds plan first time; the worst of 1000 needed 5 restarts |
| `door_retry_limit` | 4 | (gone) | Halls and rooms try every template and entry door instead of 4 random ones |

Step 8's knob table below is kept as history; its defaults are the old ones.

### What 1000 seeds look like (defaults)

| | Step 8.1 | Step 9 |
|---|---|---|
| Rooms per floor | 13.7 | **36.0** |
| Floor footprint | 192 cells | **696 cells** (bounding box 54 × 54 cells, 214 × 216 m) |
| Main path, START to EXIT | 108 cells | **256 cells** (1,022 m of floor to walk through; the exit is 144 m from START as the crow flies) |
| Doors per room | 2.62 | **3.40** |
| Share of room doors used | 74% | **64%** |
| Share of all doors used (connectors included) | 84% | 84% |
| Floors with a loop (separation 3) | 32% | **100%** (5.05 per floor, mean 6.2 cells) |
| Treasure per floor / floors with none | 0.49 / 59% | **1.70 / 6%** |
| Floors short of their rolled branch count | 6% | 1.9% |

- **Halls:** 35.0 per floor, 1.56 pieces each. By pieces: 1: 48.1%, 2: 48.5%, 3: 2.7%, 4: 0.7%. 54.6 connector pieces per floor.
- **Extends:** 5.8% of halls needed one past their first 1–2 pieces. Of the links that extended, 53% then found a room.
- **Caps:** links are tried 40.6 times per floor and 13.8% cap their door. A third of those had extended first.
- **The share of room doors used went down, not up.** The hubs carry 4–5 doors and use 2–3 of them. Used doors per room did rise (1.94 → 2.18), and 49 doors per floor are plugged.
- **Aimed branches:** 5.17 per floor, always with a target. Of 5,169:
  - 32% closed a loop (was 11%);
  - 22% reached `max_branch_depth`;
  - 46% found nothing that fit;
  - none ran into `max_rooms` or a one-door room.
- **Leftover loop pass:** 9.7 candidates per floor, none within 10 cells on 2% of floors.
- **Bridge lengths:** 22% are 9–10 cells. These are hallways, not shortcuts.

### Loop table at the defaults — share of floors with a loop (loops per floor, mean bridge cells), 300 seeds per cell

| separation ≥ | cap 5 | cap 10 |
|---|---|---|
| 1 | 99% (4.86, 3.6) | 100% (10.68, 6.2) |
| 2 | 98% (3.57, 3.6) | 100% (6.65, 6.1) |
| **3** | 93% (2.69, 3.6) | **100% (4.90, 6.2)** |

At step 9's size, loops no longer need the long cap: cap 5 still loops 93% of floors, with bridges half as long.

### Main path length — one-off sweep, 300 seeds each, everything else at the defaults

| `main_path_length` | First try | Main path | Exit from START | Floor | Rooms | Loops |
|---|---|---|---|---|---|---|
| 8 | 89% | 178 cells (710 m) | 113 m | 583 cells | 30.4 | 4.27 |
| 10 | 86% | 217 cells (866 m) | 126 m | 649 cells | 33.8 | 4.47 |
| **12** | 81% | 255 cells (1,022 m) | 140 m | 693 cells | 35.8 | 4.90 |

Shortening the main path shortens the walk but hardly the floor: the 4–6 branches of up to 6 rooms are most of it.

### Reading the maps (the handoff's three questions)

1. **A place or a line?** The middle of most floors is a web now: hubs with 3–5 doors, short halls, rooms on several sides of each other (seeds 1, 3, 8, 9). But the main path still often runs out as a line at one end. Seed 7's last six rooms to the exit are a straight row, and seed 6 has a long tail too. Branches bunch where the main path left space.
2. **Do branches meet the spine?** Yes. Every floor has loops, and a third of aimed branches close. The bridges that do it are long, though: at cap 10 they read as extra corridors snaking between clusters.
3. **12 main rooms: a floor or a marathon?** A marathon: 1 km of rooms and halls between START and EXIT. 8 would be 710 m, and the table above has what each length costs.

---

## Step 8 (with 8.1): aimed branches and branch knobs

### Floor shape — `Main.tscn → DungeonGenerator`, Shape group

| Knob | Default | Meaning |
|---|---|---|
| `main_path_length` | 6 | Rooms (not connectors) between START and EXIT. The spine is always this + 2 rooms. |
| `branch_count_min` / `branch_count_max` | 2 / 3 | Each floor rolls how many branches it wants, between these two, from the plan's RNG. Branches keep starting off the main path's spare doors until that many have each placed at least one room. A branch that places nothing (no fit, or it closed a loop straight from its start door) doesn't count, and the next spare door gets a turn. |
| `max_branch_depth` | 3 | Rooms (not connectors) per branch, at most |
| `max_rooms` | 24 | Hard ceiling on rooms, START and EXIT included: a safety stop for bigger presets. At 2–3 branches a floor tops out at 8 + 3×3 = 17 plus any side treasure rooms, so it never binds (the test checks it). At 4–6 it can bind (1% of floors). |
| `aimed_branch_chance` | 0.6 | Share of branches that aim for a loop (below) |
| `aim_strength` | 1.0 | How hard an aimed branch steers (0 = it picks a target but doesn't steer) |
| `loop_min_separation` | 3 | Fewest rooms between a bridge's two ends; also the aimed branch's target filter |
| `max_loop_length` | 5 | Longest bridge in cells, the aimed branch's closing bridge included |

`target_rooms` is gone (8.1). It was a single room budget shared by every branch, and it starved them (below).

### Aimed branches — `DungeonGenerator._plan_branches()`

Each branch that starts from a main-path door is **aimed** with probability `aimed_branch_chance`:

1. **Target** (`_pick_target`): of every free door on a room (not a connector) at least `loop_min_separation` rooms from the branch's start room, along the layout as it stands, take the one nearest the start door. Distance is Manhattan, between the cells outside the two doors, and the target's outside cell must be empty so a bridge can end there. Ties go to placement order, then door order. With no such door, the branch grows normally.
2. **Steer:** each growth step weights frontier doors and entry doors by `dot(door_out_dir, (target_cell - door_cell).normalized())`, at `1 + aim_strength × score`, clamped to at least 0.1. This is the curl code, generalized to steer toward any point (`_grow_one`'s `bias` and `toward`).
3. **No dead ends (8.1):** an aimed branch never picks a one-door room. Its templates need at least 2 doors, and a TREASURE roll becomes COMBAT, because a treasure room would end the branch on the spot. Normal branches still get treasure rooms.
4. **Close** (`_close_aimed`): before the first piece, and after every piece, each of the branch's free doors is tried against the target, the start door included until something attaches to it. Any door whose routed bridge fits in `max_loop_length` cells, between rooms still at least `loop_min_separation` apart, qualifies, and the shortest is laid with the normal bridge pieces. The branch ends there.
5. **Give up quietly:** a branch that reaches `max_branch_depth` or can't fit anything is just a normal branch. Nothing is undone.

Aimed branches use `_grow_one`, so the connector rule and the placement rules apply. Normal branches are unchanged, and the leftover loop pass still runs last. At chance 0 there's no roll at all.

### Final numbers (defaults, 1000 seeds)

- **Loops on 32% of floors** (0.38 per floor) at separation 3, cap 5. Confirmed at 31.8% on a separate 1000-seed run, so the 30% bar is cleared, but narrowly. Bridges average 3.8 cells.
- **Shape:** 13.7 rooms and 13.4 connectors per floor, 192 cells (107 × 115 m), 2.42 branches of 2.49 rolled, the deepest 2.8 rooms deep. The main path is 108 cells long.
- **Door supply:** 6% of floors got fewer branches than they rolled, because the main path's spare doors ran out. At 3–5 that's 29% and at 4–6, 48%; that's the number that says the room set needs more doors.
- **Aimed branches:** 1.64 per floor (plus 239 rolls in all with no far door to aim at). Of 1,643:
  - 186 (11%) closed a loop;
  - 719 (44%) reached `max_branch_depth` first;
  - 738 (45%) found nothing that fit;
  - none ran into `max_rooms` or ended in a one-door room.

  They place 3.9 pieces before ending.
- **Treasure fell to 0.49 per floor, and 59% of floors have none.** Fewer branch rooms means fewer treasure rolls, and aimed branches can't roll treasure at all. That's step 9's to fix.

### Branch-count table — separation 3, cap 5, 300 seeds each

| branches | loops | cells | rooms | branches placed | short of roll | `max_rooms` hit |
|---|---|---|---|---|---|---|
| **2–3 (default)** | **32% (0.36)** | 193 | 13.6 | 2.39 | 5% | 0% |
| 3–5 | 45% (0.58) | 229 | 16.0 | 3.46 | 29% | 0% |
| 4–6 | 48% (0.66) | 246 | 17.1 | 3.98 | 48% | 1% |

**Decision (the handoff's rule, adapted to min/max pairs):** the smallest pair with separation-3 loops on 30%+ of floors is 2–3. 3–5 buys 13 more points of loops for 19% more floor, and 4–6 adds little over 3–5 because the door supply runs out. That's the content limit showing.

### Loop table at the defaults — share of floors with a loop (loops per floor), 300 seeds per cell

| separation ≥ | cap 4 | cap 5 | cap 6 |
|---|---|---|---|
| 1 | 48% (0.61) | 61% (0.83) | 74% (1.13) |
| 2 | 35% (0.41) | 44% (0.53) | 49% (0.61) |
| **3** | 25% (0.27) | **32% (0.36)** | 38% (0.43) |

### Before 8.1 (step 8 alone, with `target_rooms` 12)

Aimed branches on their own took separation 3, cap 5 from 13% to 19% at chance 0.6, and 22% at chance 1.0. Adding `max_branch_depth` 4 didn't help (18%). Of 1,331 aimed branches:
- 6% closed;
- 32% ran out of the shared `target_rooms` budget;
- 14% dead-ended in a treasure room;
- 29% found nothing that fit;
- 19% reached their depth.

Those two starvation causes, the shared budget and the treasure dead ends, are what 8.1 removed.

### Why loops were hard (read before trying curl again)

The generator grows a tree outward from START, so rooms that end up near each other in space are almost always near each other in the layout. A loop between them is a pointless circle, which the separation rule rightly refuses. Every passive lever has been tried and measured:
- **Straight one-cell bridges:** 1% of floors.
- **Routed bridges up to 5 cells:** 10%.
- **Longer caps:** they help little, because separation binds, not length.
- **Main-path curl:** it folds the path into contact with itself, not into bridgeable gaps; it also costs restarts and made loops *worse* every time it was measured (13% → 12% in 7.1, 32% → 28% at 8.1's defaults).
- **The connector rule:** it pushes rooms (where most free doors are) apart, and loops fell from 19% to 13%.

What moved the rate:
1. **A free door in the middle of the layout:** the T junction, 10% → 19% before connectors.
2. **Branches that aim for a far room:** 13% → 19%.
3. **The room budget, the last generator lever:** `target_rooms` 12 gave all branches about 4 rooms to share. Replacing it with a per-floor branch count, and keeping aimed branches out of dead ends, took loops from 19% to 32% (2–3 branches) or 45% (3–5).

The generator levers are spent. From here, loops come from content: rooms with three or four doors, which the door-supply number above already asks for at 3+ branches.

---

## Step 7.1: connectors, T junction, main-path curl

Three pieces, measured after each with `dungeon_tests.gd`'s loop table. Nothing is committed; the per-piece numbers below are what each piece measured as it went in.

### The connector rule — rooms never touch rooms

Every link in the layout is room → connector → room. `Room.is_connector` (on for every CORRIDOR; the room's authoring check flags a CORRIDOR without it) marks connectors. `_pick_template` enforces the rule for every placement that `_grow_one` makes: a door on a connector only takes a room, and a door on a room only takes a connector. `_next_type()` follows from it: after a room comes a CORRIDOR, after a connector a room (TREASURE at `treasure_chance` under the cap, else COMBAT). `corridor_chance`, `max_corridor_chain` and `Placement.corridor_chain` are gone.

The main path is START → C → R → C → R … → C → EXIT. `main_path_length` and every room count (depth, `target_rooms`, branch depth, loop separation) count rooms, never connectors. Branches alternate the same way: from a room's spare door they start with a connector, and from a T's spare door with a room. Loop bridges are unchanged. Their pieces are connectors, so a bridge never puts a room against a room; it can join a room to a T's side door.

**Why:** a room → corridor → room cadence. Every fight room is entered through a corridor, and corridors carry the torches and the cubby loot.

### Connectors — `res://dungeon/rooms/`

| Scene | Footprint | Doors | Dressing | Weight |
|---|---|---|---|---|
| `Corridor_Stub` | 1×1 | N, S | none | 0 (loop bridges only) |
| `Corridor_Corner` | 1×1 | N, E | none | 0 (loop bridges only) |
| `Corridor_2` | 1×2 | N, S | 1 torch | **4** |
| `Corridor_Straight` | 1×3 | N, S | 1 torch | 2 |
| `Corridor_4` | 1×4 | N, S | 2 torches, cubby | 1 |
| `Corridor_L` | 2×2 | N, E | 1 torch | 2 |
| `Corridor_T` | 3×1 | W, E, N (middle cell) | 1 torch at the junction, on the wall facing the side opening | 1 |

Short ones are weighted high so the floor doesn't balloon. If the main path feels like a hallway sim, lower `Corridor_4`'s weight first, then `Corridor_Straight`'s.

**The cubby (`Corridor_4`):**
- **Shape:** a niche 2 m wide, 1.5 m deep and 2.2 m tall at floor level in the east wall, with a `WEAPON` spawn inside rolling `combat_weapon.tres` (62% nothing). It's a notch, not a room: no door marker.
- **Construction:** corridor walls are only 0.3 m thick, and the cell next door may hold another room, so a 1.5 m cut through the wall would open into the neighbour or the void. Instead, a wall mass (`CubbyMass`, 4 m long, 1.5 m deep) is added on the inside of the east wall, and the niche (`Cubby`, a Subtraction box of the given size) is cut out of it.
- **How it reads:** two 1 m pilasters frame the niche, with a lintel above. The corridor narrows to 1.9 m alongside it.
- **Lighting:** the torches sit on the west wall at the 4 m and 12 m marks, so the niche is lit from across the corridor, dimly. The pickup's own glint helps.

### Main-path curl — `DungeonGenerator.main_path_curl`

Only the main path curls. For each frontier door, a score is computed: `score = dot(door_out_dir, (start_center - door_cell).normalized())` (+1 = facing straight back at START). The door order is then a weighted draw with `weight = max(0.1, 1 + curl × score)`, using the plan's RNG. The candidate room's entry door is weighted the same way: each entry is scored by the best of the room's *other* doors, as they'd end up placed, at pointing back toward START. At curl 0 the old shuffle and random entry run unchanged, so curl 0 builds exactly the floors piece 2 built.

Measured over 300 seeds each, cap 5:

| curl | EXIT from START | main path | first try | loops, separation 3 | loops, separation 2 |
|---|---|---|---|---|---|
| **0 (default)** | 23.4 cells (94 m) | 108.5 cells | 75% | 13% (0.13 per floor) | 16% (0.17) |
| 0.5 | 18.0 cells (72 m) | 107.9 cells | 59% | 12% (0.12) | 19% (0.20) |
| 1.0 | 13.4 cells (53 m) | 101.6 cells | 41% | 10% (0.11) | 15% (0.16) |

Curl does what it says to the shape (the exit comes 40% closer at 1.0) but **not to loops**, and it costs reliability: at 0.5, 16 of 3000 seeds fail all 5 restarts, which means an error and no floor. 10 restarts brings that to 0 of 3000. Folding the path back packs it against itself (first-try success falls with it). It creates contact, not the one-to-five-cell gaps with facing doors that a bridge needs.

**Default 0.** By the handoff's decision rule, 12% at curl 0.5 and separation 3 is under 15%. Trying curl 1.0 gives 15% at separation 2, which doesn't clear 15%, so: stop and report. Curl ships off, the knob stays, separation stays 3, cap stays 5. To try curl anyway, set it to 0.5 and `max_restarts` to 10.

### Loop table after each piece

Share of floors with a loop (loops per floor) over 300 seeds per cell, at each piece's defaults:

| After | separation ≥ | cap 4 | cap 5 | cap 6 |
|---|---|---|---|---|
| Step 7 (start) | 1 | 31% (0.36) | 35% (0.45) | 54% (0.77) |
| | 2 | 15% (0.15) | 22% (0.25) | 31% (0.37) |
| | 3 | 7% (0.07) | 10% (0.11) | 16% (0.18) |
| 1. `Corridor_T` | 1 | 39% (0.47) | 45% (0.58) | 59% (0.89) |
| | 2 | 22% (0.23) | 30% (0.33) | 36% (0.42) |
| | 3 | 13% (0.13) | **19% (0.20)** | 24% (0.27) |
| 2. Connector rule | 1 | 25% (0.28) | 32% (0.36) | 45% (0.57) |
| | 2 | 11% (0.12) | 16% (0.17) | 22% (0.24) |
| | 3 | 10% (0.10) | **13% (0.13)** | 17% (0.18) |
| 3. Curl at 0.5 | 1 | 23% (0.25) | 32% (0.37) | 42% (0.54) |
| | 2 | 14% (0.14) | 19% (0.20) | 24% (0.27) |
| | 3 | 8% (0.08) | 12% (0.12) | 17% (0.17) |

**Final defaults (curl 0) = the connector-rule rows: 13% of floors at separation 3, cap 5.**

The T alone nearly doubled loops (10% → 19%): its side door is a free door in the middle of the layout, and connectors cost nothing in the separation count. The connector rule took most of that back. A corridor now sits between every two rooms, which pushes rooms, where most unused doors are, further apart than a 5-cell bridge reaches.

### The rest of the floor, per piece (1000 seeds)

| | Step 7 | + T | + connector rule | + curl 0.5 |
|---|---|---|---|---|
| Cells occupied (bounding box) | 142 (80 × 84 m) | 141 (80 × 84 m) | 163 (102 × 109 m) | 163 (100 × 103 m) |
| Corridors / connectors per floor | 3.7 | 3.7 | 11.2 | 11.2 |
| Main path, cells | | | 108 (434 m) | 108 |
| First-try success | 84% | 86% | 74% | 59% (3 seeds failed) |
| Treasure per floor (floors with none) | 0.87 (35%) | 0.89 (36%) | 0.66 (47%) | 0.64 (49%) |

- **The footprint grew 16%,** not the expected 30–50%. The short connectors are weighted up, and the room count didn't change.
- **Treasure fell** because a main-path treasure room needs a connector with a door to spare (only the T has one), so most main-path treasure rolls now become combat rooms. Raising `treasure_chance` is the lever (Step 7's table).
- **Restarts went up** with the connector rule: 2 of 1000 seeds needed all 5, and none failed in 3000.

---

## Step 7: generator v2 (main path, branches, loops) and minimap

Step 7.1 changed two things this section describes. Corridors are no longer rolled at `corridor_chance`; they alternate with rooms under the connector rule. The numbers in "Shape knobs" and "What 1000 seeds look like" were measured before connectors; current ones are in Step 7.1.

### How a floor is planned — `DungeonGenerator._plan()`

Three passes over one seeded RNG, all on data, before anything is built:

1. **Main path.** START, then a chain of `main_path_length` rooms, then EXIT. Each room rolls CORRIDOR at `corridor_chance` (within `max_corridor_chain`), else TREASURE at `treasure_chance` (while under `max_treasure_per_floor`), else COMBAT. Corridors don't count, so the exit is always exactly `main_path_length + 1` rooms deep. If the chain boxes itself in, the seed restarts (`max_restarts`).
2. **Branches.** The main path's unused doors, shuffled, each grow a chain of up to `max_branch_depth` rooms (corridors free again, same roll), until the floor has `target_rooms` non-corridor rooms or the doors run out. A branch carries on through whichever of its newest room's other doors fits first.
3. **Loops** (routed bridges, replacing the brief's one-cell rule 5 with your approval):
   - **Candidates:** every pair of unused doors whose rooms are at least `loop_min_separation` (3) apart, with a route through empty cells no longer than `max_loop_length` (5) between the cells outside the two doors. Separation counts the non-corridor rooms you'd walk through on the layout as it stands; corridors are free.
   - **Order:** shortest route first. Ties go to placement order (the door list is built placement by placement, door by door), and the route search tries neighbours N, E, S, W, so a seed always reproduces its floor.
   - **Rolling:** each candidate is re-checked (doors still free, route still clear, still far enough apart after earlier bridges), then rolled at `loop_chance`.
   - **Building:** a bridge is one 1×1 piece per route cell, `Corridor_Stub` where it runs straight and `Corridor_Corner` where it turns. Each piece goes through the normal `_place`, so both ends and every joint are real used doors.

Depth (`Placement.depth`) counts rooms from START, not corridors. Each placement also records `main_path` and `visited` (the last for the map). Bridge pieces record `loop`, their `bridge_id`, and on the last piece `bridge_end`, the room it opens into. `Room` has two placement-rule exports for later room types, both 0 (off) on every room today: `min_depth_from_start` and `max_per_floor`. `_pick_template` skips any template that would break either; the dungeon test proves it by setting them on the pillar room in memory.

### Shape knobs — `Main.tscn → DungeonGenerator`

Measured over 300–1000 seeds (`tools/dungeon_tests.gd` and a one-off sweep).

| Knob | Default | What it does | Pushed too far |
|---|---|---|---|
| `main_path_length` | 6 | Rooms between START and EXIT. The exit is always this + 1 deep. | The chain boxes itself in more: first-try success drops from 85% to 72% at 9 and 56% at 12, and the odd seed fails all 5 restarts (an error, no floor). The main path ignores `target_rooms`, so 12 gives about 15 rooms. |
| `max_branch_depth` | 3 | Rooms per branch | At 1, branches are single side rooms off the path; at the default most stop at 2–3 anyway (deepest averages 2.6). Raise it with `target_rooms` or it changes little. |
| `target_rooms` | (gone) | Replaced in 8.1 by `branch_count_min` / `branch_count_max` and the `max_rooms` ceiling; see Step 8. | |
| `treasure_chance` | 0.15 | Per normal slot, after the corridor roll | At 0.15, 36% of floors have no treasure (0.87 per floor). 0.25 gives 1.29 per floor with 17% empty; 0.35 gives 1.62 with 6% empty, and most floors hit the cap of 2. |
| `max_treasure_per_floor` | 2 | Cap on treasure rooms | Higher only matters once `treasure_chance` is up. |
| `loop_chance` | 0.6 | Per loop candidate, shortest first | A door with several candidates gets several rolls, so the real rate per door is a bit higher. At today's candidate counts it matters less than the two knobs below. |
| `max_loop_length` | 5 | Longest bridge, in cells. Shortcuts, not hallways. | Started at 4 as you asked; loops landed on only 7% of floors there, so it's at 5 per your "bump to 5 first" (10–11%). 6 gives 15%. Past that, bridges stop reading as shortcuts. |
| `loop_min_separation` | 3 | Fewest rooms between a bridge's two ends, along the layout before the bridge. 1 = neighbours. | This is the real limiter, not length: at length 5, separation 2 gives loops on 21% of floors and 1 on 35%. At 1, "loops" are pointless circles between adjacent rooms. |
| `main_path_curl` (7.1) | 0 | Main path prefers doors and room turns that face back toward START | See Step 7.1: pulls the exit in, doesn't add loops, costs restarts. |
| `aimed_branch_chance` / `aim_strength` (8) | 0.6 / 1.0 | Branches that aim for a far room's door and close a loop | See Step 8. |
| `door_retry_limit`, `max_attempts`, `max_restarts`, `seed_value` | 4, 200, 5, 0 | As before | |

`corridor_chance` and `max_corridor_chain` are gone (7.1); the connector rule decides where corridors go.

`recency_bias` is gone; growing the main path first makes it moot.

### What 1000 seeds look like (defaults)

- **Always:** exit depth exactly 7, main path exactly 6 rooms, no branch deeper than 3, at most 2 treasure rooms, at most 12 rooms, every bridge at most 5 cells between rooms at least 3 apart, no overlaps, same seed → same plan. 84% place first try; every seed is done within 3 restarts.
- **Shape:** 11.9 rooms and 3.7 corridors per floor, 2.3 branches, about 142 cells in a 20 × 21-cell box (80 × 84 m). 8.0 plugged doors per floor; 0.19 corridors per floor dead-end into a plug.
- **Treasure is flat, not back-loaded:** by depth, 2: 131 · 3: 166 · 4: 149 · 5: 140 · 6: 135 · 7: 90 · 8: 40 · 9: 15 (the tail thins because only branches reach past the exit's depth). 540 of 866 sit straight off the main path. On average 0.87 per floor, and 35% of floors have none at the default chance.
- **Loops: 0.11 per floor, on 11% of floors.**
  - **Candidates:** 0.20 per floor.
  - **Bridge lengths** over the 1000 floors: 1 cell ×3, 2 ×20, 3 ×23, 4 ×28, 5 ×40.
  - **Cap as limiter:** 84% of floors have no candidate at all within 5 cells. For 64 of those, a 6-cell cap would give one; for 184, an 8-cell cap.
  - **Separation is the binding rule.** Measured over 500 floors, the share with a loop:

    | separation ≥ | ≤ 4 cells | ≤ 5 | ≤ 6 |
    |---|---|---|---|
    | 1 | 30% | 35% | 52% |
    | 2 | 14% | 21% | 30% |
    | **3** | **7%** | **10%** | 15% |

    The generator grows outward, so doors near each other in space almost always belong to rooms near each other in the layout. Far-apart rooms seldom end up side by side.
  - **History:** the brief's original one-cell, straight-across rule found a loop on 1% of floors (0.01 per floor). Two doors on fixed edge positions rarely line up.

### The treasure room is a dead end, so on the main path it's a side room

`TreasureRoom` has one door, so it can't be a link in the chain: nothing could follow it. When the main path rolls TREASURE, the treasure room goes on one of the current room's *other* doors, as a one-room side pocket (`main_path` false, depth = path depth + 1), and the path carries on through a door it kept. That slot doesn't count toward `main_path_length`. With only one free door the roll becomes COMBAT. Since 7.1 a room slot always follows a connector, and only `Corridor_T` has a door to spare, so main-path treasure is rarer (see Step 7.1). Give a treasure room two doors and it becomes a normal chain link automatically: the rule is "no dead ends on the chain", not "no treasure". This is how treasure lands at depth 2.

### Minimap — data flow

1. **Plan → MapModel:** after each build the generator calls `Dungeon.set_plan(plan)`, which flattens it into a `MapModel` (`dungeon/map_model.gd`): per room its cells, doors (cell, side, used), type, `main_path`, `map_tile` and `turns`. It also clears `revealed`.
2. **Player → revealed:** every physics frame the Player sets `Dungeon.player_cell` (4 m grid cell under it). On a change, `_reveal_at()` finds the room there and, on its first visit, marks the placement `visited`, adds each of its cells to `revealed` and emits `revealed_changed`. Reveal is per cell, so a radius brush later only touches `_reveal_at()`.
3. **revealed → _draw:** `ui/minimap.gd` (`Minimap`) draws on its `%Canvas`. It redraws on `revealed_changed` at once, and for walking or turning at most `redraw_hz` (10) times a second, only when something moved.
4. **What's drawn:**
   - Revealed cells; main-path rooms one stone step lighter than branches.
   - A dark seam on every edge between rooms, with each used doorway cut out of it. A loop bridge's pieces share a group in `MapModel`, so a bridge draws as one corridor with no seams inside it.
   - A tick poking out of every doorway that leads somewhere not yet revealed: the "where next" cue.
   - An outlined square for the exit and a dot for treasure, once seen.
   - A triangle for you, turned to your yaw.

   The corner map (`HUD/Minimap`, 160 × 160 below the hint line, 10 px per cell) stays centered on you. M shows `HUD/FullMap`: a dim layer and a second `Minimap.tscn` instance at 24 px per cell, framed on everything revealed (shrinking to fit), without pausing.

**`Room.map_tile` is the authored-art hook.** No room sets it yet. When one does, the map draws that texture over the room's footprint, authored unrotated and turned with the room, instead of plain cells. Seams, doorways and ticks still draw on top.

Knobs on `Minimap`: `cell_px`, `centered_on_player`, `redraw_hz`, `stub_length` (tick length in cells; 0.3 = 3 px on the corner map, the first thing to raise if the ticks don't read), and the colour group (all palette swatches).

### Bruiser retune — `enemy/bruiser.tres`

`wall_stun_time` 2.0 → **1.2**, `recover_time` 1.2 → **0.5**, `cooldown_time` 2.0 → **0.8**, `charge_min_range` 4.0 → **3.0**. The smoke test now gets exactly 3 sword hits in during a wall stun (it asks for 3), and a landed charge leaves 0.5 + 0.8 = 1.3 s before he swings again.

---

## Step 6: enemy v2 — perception, behaviours, noise

### States

All of this lives in the one `enemy/enemy.gd`. The opener an enemy picks is a `match data.behavior` in `_try_attack()`.

- **IDLE**: stands at its spawn, sweeping its facing ±`idle_look_angle` (40°) over `idle_look_period` (4 s). Each spawn spot gets its own phase, so neighbours don't sweep in lockstep.
  - → **ALERT** when it sees you or hears a noise.
  - When hit: → **FLINCH** if it can flinch (grunt, skitterer), otherwise → **ALERT** (bruiser).
- **ALERT** (`alert_time` 0.4 s): barks and turns toward `last_known_pos` at the chase turn rate.
  - → **CHASE** if it can see you, or if a hit woke it.
  - → **SEARCH** otherwise (it only heard something).
- **CHASE**: walks at you while it can see you, and at `last_known_pos` while it can't.
  - → **SEARCH** after `lose_sight_time` (3 s) without seeing you.
  - In range: → the opener for its behaviour (below).
- **SEARCH**: three legs, each with a `search_give_up_time` (6 s) limit:
  - GOTO: walks to `last_known_pos` at `search_speed_mult` (0.6) × move speed.
  - LOOK: looks around for `search_look_time` (2 s).
  - RETURN: walks home, then → **IDLE** facing its old way.
  - Sees you at any point: bark, → **CHASE**. Hears a noise: → **ALERT** toward it.
- **MELEE opener** (grunt, and every type at close range): within `trigger_range`, **WINDUP** (capped turn) → **STRIKE** (facing locked, lunge) → **RECOVER** → **COOLDOWN** → **CHASE**.
- **POUNCE opener** (skitterer, between `pounce_min_range` 2 m and `pounce_range` 5 m): **CROUCH** (`pounce_crouch_time` 0.4 s). It squashes to `pounce_squash` (0.6) height, the TellFlash lights, it chitters, and it tracks you at the windup turn rate. The landing spot locks when the crouch ends.
  - → **POUNCE**: a ballistic leap with the hitbox live for the whole flight, so you can block it.
  - → **RECOVER** on landing (or after 2 s) → **COOLDOWN**. Under 2 m it bites with a normal WINDUP instead.
- **CHARGE opener** (bruiser, beyond `charge_min_range` 3 m since step 7): **CHARGE_WINDUP** (`charge_windup` 0.6 s). It roars (a 12 m noise), holds the TellFlash and turns at the chase rate. Then **CHARGING**: `charge_speed` 7 m/s, turning at `charge_turn_rate` 60°/s, with a `charge_hit_reach` 1.3 m hitbox. A charge ends one of three ways:
  - **Hits you:** 35 damage, `player.effects.apply_slow(0.5, 1.5)`, → **RECOVER**. Blocked: no damage and no slow, but it still stops, → **RECOVER**.
  - **Hits a wall head-on** (`charge_wall_dot` 0.5): → **WALL_STUN** (`wall_stun_time` 1.2 s since step 7) → **COOLDOWN**.
  - **`charge_max_time` (2.5 s) runs out:** → **RECOVER**.
- **FLINCH** (0.3 s): from a hit outside an attack, if `can_flinch`. Then → **COOLDOWN** if cooldown time is left, otherwise → **CHASE**.
- **WALL_STUN**: counts as `can_flinch` for every type. Each hit plays the flinch and knocks it back, but the stun runs its full `wall_stun_time`.
- **Super armour** in WINDUP, STRIKE, CROUCH, POUNCE, CHARGE_WINDUP and CHARGING: a hit there is a trade, not an interrupt.
- **DEAD**: leaves the `enemies` group, so noise no longer reaches it.

### Perception — `enemy/perception.gd` (`Perception`, a node at eye height in `Enemy.tscn`)

Each look is a range check, then the cone, then one `SightRay` (masks world + player) to `Player.eye_position()`, which must hit the player. Enemies look on 1 physics frame in 4, each on its own phase, so a full room never raycasts on the same tick. Reaction time is therefore up to 4 frames: the smoke test measures ALERT 0.03–0.07 s after you step into view. The node's height scales with `body_scale`.

| `EnemyData` → Perception | grunt | skitterer | bruiser | Notes |
|---|---|---|---|---|
| `sight_range` | 12 m | 12 m | 12 m | |
| `sight_fov` | 110° | 110° | 110° | Full cone |
| `lose_sight_time` | 3 s | 3 s | 3 s | CHASE → SEARCH |
| `hearing` | 1.0 | 1.0 | 1.0 | Multiplies every noise radius it hears |
| `aware_sense_range` | 2.5 m | 2.5 m | 2.5 m | Once aware, it senses you outside its cone this close (still needs line of sight). Not in the handoff; see Decisions. |
| `alert_time` | 0.4 s | 0.4 s | 0.4 s | |
| `idle_look_angle` / `idle_look_period` | 40° / 4 s | 40° / 4 s | 40° / 4 s | |
| `search_speed_mult` / `search_look_time` | 0.6 / 2 s | 0.6 / 2 s | 0.6 / 2 s | |
| `search_arrive_distance` / `search_give_up_time` | 0.6 m / 6 s | 0.6 m / 6 s | 0.6 m / 6 s | Give-up is per leg, because there's no pathfinding (see Known limitations) |

No variant overrides perception yet; they all use the `EnemyData` defaults. If you want a difference, the obvious first candidates are a skitterer `hearing` of 1.5 and a bruiser `sight_fov` of 90.

### Behaviour — `EnemyData` → Behavior

| | grunt | skitterer | bruiser |
|---|---|---|---|
| `behavior` | MELEE | POUNCE | CHARGE |
| `strike_lunge` | **1.4** (was 0.9) | 1.3 | 0.6 |
| `voice_pitch` | 1.0 | 1.5 | 0.65 |

| Pounce (skitterer) | Value | | Charge (bruiser) | Value |
|---|---|---|---|---|
| `pounce_crouch_time` | 0.4 s | | `charge_min_range` | 3 m (4 in step 6) |
| `pounce_range` | 5 m | | `charge_windup` | 0.6 s |
| `pounce_min_range` | 2 m | | `charge_speed` | 7 m/s |
| `pounce_speed` | 9 m/s horizontal | | `charge_turn_rate` | 60 °/s |
| `pounce_arc` | 1.2 m peak | | `charge_max_time` | 2.5 s |
| `pounce_squash` | 0.6 | | `charge_hit_reach` | 1.3 m (restored to `attack_reach` afterwards) |
| | | | `charge_slow_mult` / `charge_slow_time` | 0.5 / 1.5 s |
| | | | `charge_wall_dot` | 0.5 |
| | | | `wall_stun_time` | 1.2 s (2 in step 6) |

`voice_pitch` (not in the handoff) pitches the grunt, bark and death sounds, so you can hear which kind spotted you. The skitterer's crouch has its own chitter and the bruiser's charge its own roar (`audio/sfx/enemy_chitter.wav`, `enemy_roar.wav`, `enemy_bark.wav`, all from the asset generator).

**Measured by the smoke test:**
- **Pounce:** crouched at 5.0 m for 0.41 s, peaked at 1.24 m, landed on you for 8, then RECOVER. A block eats it.
- **Charge:** from 7 m it roared and charged, hit for 35 and slowed you to 2.5 m/s, which wore off after 1.5 s. Blocked, it stopped with no damage and no slow. Sidestepped into a wall, it stayed dazed through 3 sword hits and came out after 1.2 s (4 hits and 2.0 s before the step 7 retune).

### Noise — `dungeon/dungeon.gd` (`Dungeon.emit_noise(pos, radius)`)

Every living enemy in the `enemies` group within `radius × its hearing` gets `hear(pos)`. Only IDLE and SEARCH enemies react: they go ALERT with `last_known_pos = pos`, investigate, and chase only once they actually see you. ALERT, CHASE and attacking enemies ignore noise. There's no occlusion, so noise carries through walls into the next room.

| Noise | Radius | Where it lives |
|---|---|---|
| Your hit lands (any weapon) | 9 m | `Player.noise_sword_hit`, made in `WeaponRig._on_hit_landed` |
| You block a hit | 9 m | `Player.noise_block` |
| An enemy takes a hit (its grunt) | 7 m | `EnemyData.hurt_noise_radius`, per variant |
| Your swing whiffs | 3 m | `Player.noise_whiff`, at swing end if nothing was hit |
| Sprint footstep | 5 m every 0.3 s | `Player.noise_sprint_step`, `sprint_step_interval`. Only while actually moving faster than walk speed. |
| Walking | 0 | Silent; nothing is emitted |
| Dropping an item | 4 m | `Player.noise_drop` |
| Bruiser roar (charge windup) | 12 m | `EnemyData.roar_noise_radius` |

A landed hit makes two noises: yours (9 m) and the victim's grunt (7 m, made after its own state change so it doesn't hear itself). `Player.dungeon` and `Enemy.dungeon` are the references: `Main.tscn` wires the player's, and the generator hands its own `dungeon` to every enemy it spawns. Leave it empty and that body is silent.

**Measured:** sneaking up behind two grunts woke neither. Hitting one alerted the other, which turned toward the fight, saw you, and chased. Walking past 3.5–4 m behind one: nothing. Sprinting past on the same line: heard.

### PlayerEffects — `player/player_effects.gd` (`Player.tscn → Effects`)

A deliberately minimal stub with one effect. `apply_slow(mult, duration)` keeps the stronger slow and refreshes the time, and `speed_mult` feeds `Player._max_speed()`. While you're slowed, the HUD tints the stamina bar grey (`Hud.slowed_tint`). Reach it with `player.effects`.

---

## Step 5: paper doll and grid inventory

### The model — `player/inventory.gd` (`Inventory`, on the Player)

`bag` holds 6 × 4 = 24 squares (null = empty) and `equipped` maps each `ItemData.Slot` to its item. Every change emits `changed`, and the screen redraws from the model; slots never hold items of their own. `equip()` is the only route into `WeaponRig.equip()`; `unequip(WEAPON)` sends null, which means fists. RING and TRINKET can be worn but do nothing yet. The player starts with the sword equipped and an empty bag.

**`armour` is a stand-in.** `ArmorData.armour` is a flat per-hit reduction, summed over what you wear: `Player.take_hit` applies `max(1, damage - total_armour())`. A block still zeroes the hit. This will be replaced by a real armour model. The iron cap (3) turns a grunt's 15 into 12. The HUD now prints HP on the health bar (`88 / 100`), so you can read that off the screen.

### Armour pieces — `items/armor/*.tres` (`ArmorData`)

| Item | Slot | armour |
|---|---|---|
| Rawhide Cap | HEAD | 1 |
| Rawhide Vest | CHEST | 2 |
| Rawhide Gloves | HANDS | 1 |
| Rawhide Boots | FEET | 1 |
| Iron Cap | HEAD | 3 |

Every item now has a 32 × 32 palette icon, and the armour pieces have floor meshes. Both come from `tools/generate_placeholder_assets.gd` (`_write_armor()`). All five pieces are in **`data/tables/treasure_loot.tres`** (renamed from `treasure_weapon.tres`) at weight 1 each, alongside sword, axe and dagger at 2 each and nothing at 1. Each of the two treasure points rolls roughly a 50% weapon, 42% armour, 8% nothing.

### Pickups

- **E puts the item in the first free square** and the pickup frees itself. The step-2 swap-in-place rule is retired, and the start room's spare sword is gone.
- **Bag full:** the pickup does a half turn around Y and back with a 0.15 m hop over 0.25 s, plays a dull "nope", and the prompt line reads `Inventory full` (orange) for 1 s. Knobs: `Pickup.reject_time` / `reject_hop`, `Player.inventory_full_text` / `notice_time`.

### The screen — `ui/InventoryScreen.tscn`, instanced in `Player.tscn`

Tab opens it over a paused game (`get_tree().paused`, mouse visible); Tab closes it. The paper doll has HEAD on top, WEAPON left of CHEST, RING and TRINKET on the right, and HANDS and FEET below. To its right is the 6 × 4 bag, then the stats (Armour, Weapon dmg, HP, Stamina), and a tooltip that follows the cursor over any filled slot (name, slot, damage or armour). All 24 bag squares (`ui/BagSlot.tscn`, `index` 0–23) and 7 doll slots (`ui/EquipSlot.tscn`, `slot`) are authored instances in the scene; nothing is generated.

`PlayerIntent` runs while paused so Tab can close the screen, but ignores every other input then. The screen polls it (`consume_inventory_toggle()`) and asks it to free or capture the mouse, so `Input` is still only read in one place.

### Drop rules

Drag uses Godot's built-in drag and drop. The payload is `{ "item", "from_bag": index or -1, "from_slot": slot or -1 }`, and the preview is the item's icon. When a drop isn't allowed, `_can_drop_data` returns false and the cursor shows "no" before you let go.

| From → to | Rule |
|---|---|
| Bag → bag | Always allowed. The target's item goes back to the source square (a swap; onto an empty square it's a move). |
| Bag → equip slot | Only if `item.slot` matches the slot. The previous occupant goes into the source square. |
| Equip slot → bag | Onto an empty square: unequip it there. Onto an item that fits the source slot: they trade places. Onto anything else: refused. |
| Equip → equip | Refused for now (RING ↔ RING once there are two ring slots). |
| Anything → background | Drop it in the world, 1 m in front of you (see below). |
| Right-click a bag item | Equip it; whatever was worn takes its square. |
| Right-click an equipped item | Unequip to the first free square; refused (with the nope) if the bag is full. |

Weapon changes made while paused are already in your hand when you unpause. The rig only queues an equip while a swing is in progress, which can't happen while paused, so a swap never lands mid-swing.

### Drop to world

Dropping on the screen background takes the item out of the bag or slot and spawns a `Pickup.tscn` 1 m in front of you on the floor, under `Dungeon/Spawned`. A short ray (0.5 m up, world layer) pulls the drop back 0.4 m from any wall in the way, so it can't vanish into stone. Knobs: `Player.drop_distance`, `drop_probe_height`, `drop_wall_margin`, `drop_wall_mask`, `drop_parent`, `pickup_scene`. Dropping your weapon leaves you with fists: no mesh, no swing, no block. Pick it up again with E and wear it from the bag. Dropped items are cleared on F5/F6 along with everything else in `Spawned`.

---

## Step 4: spawn tables

### The rule

`SpawnPoint` checks **its table first, then its fixed fallback**. With a `table` set, the table is rolled; a "nothing" row places nothing. With no table, the step-3 `fixed_scene` / `fixed_item` is used. START (just the player since step 5) and EXIT stay fixed. Combat and treasure spawn points now point at tables; they keep their old fixed values as the fallback if you clear the table.

Rolls use the generator's own `RandomNumberGenerator`. The RNG that planned the layout carries straight on into the spawn loop, in build order, so a seed reproduces the layout and every spawn. Step-3 seeds still give the same layouts.

### Tables — `res://data/tables/` (`SpawnTable` of `SpawnEntry` rows)

| Table | Rows (weight → share) | Used by |
|---|---|---|
| `combat_enemy.tres` | grunt 5 (45%), skitterer 3 (27%), bruiser 1 (9%), nothing 2 (18%) | Every ENEMY point in a COMBAT room: CombatRoom_A ×1, CombatRoom_B ×2, CombatRoom_Pillars ×2 |
| `combat_weapon.tres` | sword 1, axe 1, dagger 1 (12.5% each), nothing 5 (62.5%) | CombatRoom_Pillars' WEAPON point |
| `treasure_loot.tres` | sword 2, axe 2, dagger 2 (16.7% each); rawhide cap, vest, gloves, boots and iron cap 1 each (8.3% each); nothing 1 (8.3%) | Both TreasureRoom WEAPON points (the kind name is historical; they roll armour too) |

A row's `enemy` is read by ENEMY points and its `item` by WEAPON points; a row with neither is "nothing". The room's editor warnings flag a table carrying the wrong kind of row, which would silently spawn nothing. An average 2-point combat room holds about 1.6 enemies, and one bruiser in a pillar room is the spike. `tools/dungeon_tests.gd` rolls each table 22,000 times and checks the shares match the weights (they're within 0.4%).

### Enemy variants — `enemy/*.tres` (`EnemyData`)

| | grunt | skitterer | bruiser |
|---|---|---|---|
| `max_hp` | 100 | 40 | 250 |
| `move_speed` | 3.0 | 5.5 (faster than your 5.0 walk) | 2.2 |
| `can_flinch` | true | true | **false** |
| `trigger_range` | 1.8 | 1.4 | 2.2 |
| `attack_reach` | 2.3 | 1.6 | 2.8 |
| `damage` | 15 | 8 | 35 (kills you in 3) |
| `windup_time` | 0.7 | **0.35** | 1.1 |
| `strike_time` | 0.2 | 0.15 | 0.3 |
| `recover_time` | 0.8 | 0.4 | 0.5 (1.2 before step 7) |
| `cooldown_time` | 1.5 | 0.6 | 0.8 (2.0 before step 7) |
| `strike_lunge` | 1.4 (0.9 before step 6) | 1.3 | 0.6 |
| `windup_turn_rate` | 180 | 360 | 90 |
| `body_scale` | 1.0 | 0.7 | 1.4 |
| `body_material` | (scene burlap) | `hide_skitterer.tres`, pale bone `c9c0b9` | `hide_bruiser.tres`, blood red `84191c` |

`body_scale` sizes the whole visual `Rig`, legs included, plus the collision capsule, HP bar height and tell light. Scaling only the `Body` node in this scene would leave the legs grunt-sized. `body_material` goes on torso and arms as a `material_override`; the hit-flash overlay still works on top. Everything else uses the grunt's defaults (chase turn 460°/s, flinch 0.3 s, and so on). Step 6 added each variant's behaviour, perception and voice; see there.

**Tuning order from the handoff:**
- **Skitterer:** a nuisance means raise `damage`; unfair means raise `windup_time` before touching anything else.
- **Bruiser:** a sponge means lower `max_hp` and raise `damage`. It should kill you in 3.
- **Dagger vs bruiser:** `can_flinch = false` means no stunlock, by design.

### Debug

- **Spawn log** (`DungeonGenerator.print_spawn_log`, on by default): one line per spawn point after the seed line. Lines read `→ grunt`, `→ nothing`, `→ fixed rusty sword` or `→ player`. The current floor's lines are also kept in `last_spawn_log`.
- **F6** rebuilds from `last_seed`; F5 rolls a new seed. To diff two runs, copy the log lines from both. The dungeon test does exactly that for four seeds and requires them identical.

---

## Step 3: dungeon

### Generator tunables — `Main.tscn → DungeonGenerator`

The shape knobs are in **Step 7** and **Step 8** (main path, branches, treasure, loops, retries); step 7 replaced this step's single growth loop and removed `recency_bias` and the forced treasure-then-exit ending. The rest:

| Knob | Default | What it does |
|---|---|---|
| `catalog` | `dungeon/catalog.tres` | Room pool: its `rooms` list plus every `.tscn` in `scan_folder` (`res://dungeon/rooms`) |
| `max_attempts` | 200 | Overlap failures allowed before a layout is abandoned and restarted |
| `seed_value` | 0 | 0 = random every generate. Anything else rebuilds the same floor and spawns (restarts derive from it too). |
| `enemy_scene` / `pickup_scene` | `Enemy.tscn` / `Pickup.tscn` | What a rolled ENEMY row (with its `EnemyData` set) or a WEAPON spawn instantiates |
| `print_spawn_log` | true | One log line per spawn point after the seed line |

Per room, on the scene root (`Room`): `type`, `weight` (pick chance within its type, default 1; 0 = never rolled, like the loop pieces), `footprint`, and since step 7 `min_depth_from_start`, `max_per_floor` and `map_tile`.

Step 3's 1000-seed numbers (10 rooms, 98.5% first try, 3.9 plugged doors) described the old generator; the current ones are under Step 7.

### Rotation convention

`turns` = **clockwise** quarter turns seen from above, with −Z as north. A placed room gets `rotation_degrees.y = -90 × turns`, and its node is offset so the rotated footprint's min corner lands on `grid_origin`. One turn sends doors N → E → S → W, so a door's `dir` is also its clockwise turns from north. A `(w, h)` footprint becomes `(h, w)`, and cell `(x, z)` becomes `(h-1-z, x)`; see `DungeonGenerator.rotate_cell()`. The test checks `rotate_cell` against the actual `Transform3D` for every cell of every footprint up to 5 × 5 at every turn, and checks every catalog door at every rotation.

Grid: 4 m cells; cell `(x, z)` sits at world `(4x, 0, 4z)`. A door's marker sits on the footprint boundary at the center of a cell edge; `Door.cell` is the footprint cell it belongs to. Connecting door D to candidate door E picks the one rotation that makes E face D's opposite, then sets `grid_origin` so E's cell is the cell across D's edge. That's the only connectivity rule: no loops, no extra connections.

### Authoring a new room

1. **Duplicate** any scene in `res://dungeon/rooms/` and set `type` / `weight` / `footprint` on its root. Anything in that folder is in the catalog automatically.
2. **Move CSG boxes** under `Geometry`. `Floor` and `Ceiling` cover the footprint. Walls sit *inside* the footprint edge, 0.3 m thick, so neighbours end up back to back. Each door needs a 2 × 3 m subtraction box (`operation = Subtraction`) through its wall; the existing `Doorway*` boxes are ready to move.
3. **Move markers.** A `Door` goes on the footprint edge at a cell-edge center: one coordinate on the boundary (0 or 4 × cells), the other at 4k + 2. Set its `dir`; the marker turns itself to face out. `SpawnPoint`s go anywhere inside the footprint. Each `ENEMY` or `WEAPON` point needs a `table` (from `res://data/tables/`) or a fixed fallback (`fixed_scene` / `fixed_item`), and START needs exactly one `PLAYER`.

The Room root shows editor warnings, refreshed as you drag markers. It warns when a door is off an edge center, a door has no doorway cutter within 0.5 m, a spawn is outside the footprint, a spawn has neither a table nor a fixed value, a table holds the wrong kind of row, or a START room has no player spawn. The generator skips any room with warnings and logs why.

**Doorway size:** the handoff says "2-cell-wide opening". Cells are 4 m and doors sit at the center of a single cell edge, so I read that as **2 m** wide, 3 m tall. Corridors use the same 2 m doorway rather than a fully open end, so one shared `DoorPlug.tscn` (2.1 × 3.05 m) fits every unused door.

### Building blocks

| File | Role |
|---|---|
| `dungeon/room.gd` (`Room`, @tool) | Room contract, `get_doors()`, `get_spawn_points()`, authoring checks |
| `dungeon/door.gd` (`Door`, @tool) | `dir`, `plug_scene`, `cell`, `used`, `opposite()`, plus direction/offset/edge helpers |
| `dungeon/spawn_point.gd` (`SpawnPoint`, @tool) | `kind`, `table` (rolled first), `fixed_scene`, `fixed_item` (fallback) |
| `dungeon/spawn_table.gd` / `spawn_entry.gd` | `SpawnTable.roll(rng)`; `SpawnEntry` rows with `weight`, `enemy`, `item` |
| `dungeon/room_catalog.gd` (`RoomCatalog`) | `rooms` plus `scan_folder` |
| `dungeon/dungeon_generator.gd` (`DungeonGenerator`) | Plan (pure data: main path → branches → loops) → build (rooms, plugs, spawns) → hand the plan to `Dungeon` |
| `dungeon/dungeon.gd` (`Dungeon`, on `Main/Dungeon`) | Floor root; noise hub; owns the map (`map`, `revealed`, `player_cell`) |
| `dungeon/map_model.gd` (`MapModel`) | The plan flattened for drawing: rooms' cells, doors, type, main path, tile |
| `dungeon/rooms/Corridor_*.tscn` | The connectors (Step 7.1): `Corridor_2`, `Corridor_Straight`, `Corridor_4` (with the cubby), `Corridor_L`, `Corridor_T`, plus the two 1×1 loop-bridge pieces `Corridor_Stub` (straight, N/S) and `Corridor_Corner` (N/E), weight 0 and unlit, that only the loop pass places. |
| `ui/Minimap.tscn` + `ui/minimap.gd` (`Minimap`) | Draws the revealed map; instanced twice in the HUD |
| `dungeon/DoorPlug.tscn` | Default wall chunk, added as a child of each unused door marker |
| `dungeon/exit_trigger.gd` (`ExitTrigger`) | Prints `exit reached` |

---

## Step 2: weapons

### Per-weapon tunables — `weapons/*.tres` (`WeaponData`, extends `ItemData`)

| Field | Rusty Sword | Woodcutter's Axe | Rusted Dagger | What it drives |
|---|---|---|---|---|
| `damage` | 25 | 45 | 12 | Hits to kill the 100 HP grunt: 4 / **3** / 9 |
| `stamina_cost` | 10 | 20 | 5 | Swings per full bar: 10 / 5 / 20 |
| `swing_time` | 0.45 | 0.75 | 0.25 | Length of the swing; the clip plays at speed 1 / swing_time |
| `active_start` – `active_end` | 0.12–0.28 | 0.25–0.45 | 0.06–0.14 | Hitbox window (real seconds into the swing) |
| `lunge_distance` | 0.6 | 0.8 | 0.4 | Forward step, spread over swing start → middle of the active window (0.20 / 0.35 / 0.10 s) |
| `hitstop` | 0.05 | 0.08 | 0.03 | Freeze on a landed hit |
| `attack_reach` | 1.4 | 1.5 | 1.0 | Hitbox length forward from its authored near edge (0.15 m in front of the camera) |
| `view_mesh` / `world_mesh` | `meshes/rusty_sword.res` | `meshes/woodcutters_axe.res` | `meshes/rusted_dagger.res` | Same mesh for both; Pickup lays the world one flat |
| `view_offset` | (0, 0, 0) | (0.09, 0.01, 0) | (-0.05, 0.06, -0.05) | Rig-space nudge of the whole swing path, meters |
| `view_rotation` | (0, 0, 0) | (0, 0, -14) | (6, 4, 0) | Rig-space rotation nudge, degrees. The axe rolls upright, the dagger tilts up and inward. |
| `icon` | `icons/rusty_sword.png` | `icons/woodcutters_axe.png` | `icons/rusted_dagger.png` | 32×32 placeholder for step 5 |

**Axe math:** the handoff says the axe two-shots the grunt, but 45 × 2 = 90 < 100 HP, so as written it's a three-shot. Change one number to make it a two-shot: axe `damage` ≥ 50, or grunt `max_hp` ≤ 90 in `enemy/grunt.tres`. Lowering grunt HP leaves the sword at 4 hits and makes the dagger 8.

**Still shared by every weapon** (these are the levers if the dagger reads as a worse sword): the one `swing` clip's poses, the camera kicks (`swing_kick_deg`, `hit_kick_deg` on WeaponRig), the whoosh/thud SFX, the 0.3 s `equip` clip, and the block poses. Everything in the table above is per weapon, and the smoke test measures each value in play.

### How the normalized swing clip maps to `swing_time`

The `swing` clip in `Player.tscn → WeaponRig/AnimationPlayer` is authored at **1.0 s**. Its pose keys are at normalized times, and the blade crosses screen center at 0.444. On every `equip()`:

- **Playback:** `play("swing", blend, 1.0 / swing_time)`, so the clip lasts exactly `swing_time`. It's a per-play speed rather than `AnimationPlayer.speed_scale`, because speed_scale would also stretch `block_*` and `equip`.
- **Hitbox keys:** the two method keys move to `active_start / swing_time` and `active_end / swing_time`. For the axe that's 0.333 / 0.600; for the dagger 0.24 / 0.56.
- **Lunge:** the step runs from swing start to `(active_start + active_end) / 2` real seconds, so it carries the body into the hit for every weapon. With the old fixed 0.18 s, the axe finished stepping before its active window even opened. The lunge is now an exact ease-out displacement per tick; the old per-tick decay came up about 0.05 m short on every swing.

Edit pose keys in the editor freely. Don't hand-move the two method keys; `equip()` overwrites them from the data.

### Equip

`WeaponRig.equip(weapon)` swaps `SwordMesh.mesh`, sets `ViewPivot` from `view_offset` / `view_rotation`, resizes the hitbox from `attack_reach`, rewrites swing timing, then plays `equip` (0.3 s, rises from below; you can't swing or block until it ends). Since step 5 only `Inventory` calls it. Called mid-swing, it queues and applies when the swing ends, so it never swaps during active frames. During a block or another equip it applies at once, which is what makes paused inventory swaps instant. `equip(null)` means fists: no mesh, no swing, no block, and the rig drops straight back to IDLE. `Player.starting_weapon` is equipped (through the Inventory) on ready.

### Pickups and interact

| Where | Knob | Value | Notes |
|---|---|---|---|
| `Player.tscn → Head/Camera3D/InteractRay` | `target_position` | (0, 0, -2.5) | Reach. Masks layer 4 only. |
| `items/Pickup.tscn → InteractShape` | box | 0.45 × 0.25 × 1.0 m | What the ray hits. It's on layer 4, which nothing physical collides with. |
| `items/Pickup.tscn → Glint` + `AnimationPlayer` | energy / range | 0.1 → 0.35 pulse over 2.4 s, 0.7 m | Palette `fff3c4`. Set the Glint invisible to drop it. |
| `Player.tscn → HUD` | `prompt_format` | `"[E] %s"` | `%s` is `prompt_text()`, e.g. "Take Woodcutter's Axe" |

- **Swap-in-place (retired in step 5):** E now puts the item in the bag and the pickup frees itself; see Step 5. `set_item` still re-centers any item's mesh over the pickup and rests it on the floor, which drops and loot rely on.
- **Blocked while busy:** while swinging, blocking or equipping there's no target and no prompt, so you can't vacuum loot with block held.
- **Where it lives:** the target is cached in `Player._update_interact()`, and the HUD only updates when the target or its prompt text changes. The press is handled before the refresh, so the prompt reflects the result in the same frame.

---

## New in 1.1: what each knob fixes, and what breaks if you push it

All of these live in `enemy/grunt.tres` (`EnemyData`) unless noted.

| Tunable | Default | What it does / fixes | Pushed too far |
|---|---|---|---|
| `max_hp` | 100 | HP now belongs to the enemy type and is written into `Health` on ready. | High with `can_flinch` on means very long stunlocks. High with it off makes a damage sponge. |
| `can_flinch` | true | Lets heavy types (bruisers) ignore stagger. They still take damage and flash. | Off, every hit outside RECOVER/COOLDOWN is a trade, and the punish window is the only safe damage. |
| `trigger_range` | 1.8 m | Distance at which it commits to WINDUP. | Above about 1.9 it swings from outside your sword reach (1.55 m + its 0.4 m body), so you can never answer a windup. Too low and it walks into your face first. |
| `attack_reach` | 2.3 m | Hitbox length forward from its center (resized on ready). Longer than `trigger_range`, so one step back doesn't dodge. | Much longer and hits land when the club is visibly nowhere near you. Below `trigger_range` + 0.35 it whiffs against a player standing still. |
| `strike_lunge` | 0.9 m (1.4 since step 6) | **Fixes hit-and-back-off.** Reach plus lunge covered about 3.2 m from where it stood at 0.9 (3.7 m at 1.4), so a retreating player has to start backing off early to escape. The smoke test checks both the caught case and the escape case. Since step 6 the lunge ends when it touches you. | It skates across the room and ends every strike in your face, which makes the viewmodel clip into it. 0 brings back the backpedal cheese. |
| `windup_turn_rate` | 180 °/s | Capped tracking during WINDUP, about 126° over the full tell. A strafe gets partly behind it; a full sprint-circle doesn't. | High and it tracks perfectly, so block is the only defense. Low and circle-strafing trivializes it. |
| `cooldown_time` | 1.5 s | Now a true standstill after RECOVER: no movement, no turning. It used to chase and track during cooldown. | Long gives free kills. Short leaves RECOVER as the only window, and attacks chain back to back. |
| `chase_turn_rate` | 460 °/s | Was `turn_speed` (8 rad/s). Same behavior, now in deg/s like the windup rate. | Low and you can walk around it while it chases. |
| `fx/HitPuff.tscn` | 5 particles, 0.25 s, 0.05–0.1 m, dark red, shaded | **Fixes** the big spark firing on every landed hit and drowning out the flinch and material flash. It sprays along `HitInfo.direction` from the hitbox/body midpoint. | More, bigger or brighter competes with the flash again. At point-blank the midpoint sits inside the body and hides it. |
| `fx/BlockSpark.tscn` | 12 particles, 0.25 s, 6–11 m/s radial, yellow-white, unshaded | **Fixes** blocking having no visual of its own. It spawns at the blade, about 0.45 m from the camera. | It already fills much of the screen. More or longer streaks start covering the enemy's next tell. |
| `Main.tscn → FX/HitPuffs`, `FX/BlockSparks` | 4 each | Pool size. Instances are cycled with `restart()`, nothing is instantiated. | Too few (1) and a second effect restarts the first mid-flight. More than 4 is wasted at current attack rates. |

"Unshaded" is the palette's version of emissive: full-bright, no glow pass.

---

## Tunables: what lives where

### Weapons

See **Step 2: weapons** above for every per-weapon field.

### Enemy — `enemy/grunt.tres` (`EnemyData`)

`enemy.gd` reads every tuning number from here. The only literals left in it are animation crossfade constants and math guards.

| Group | Field | Value | Notes |
|---|---|---|---|
| Body | `display_name` | "Grunt" | |
| | `max_hp` | 100 | Overrides `Enemy.tscn → Health.max_hp` on ready |
| | `move_speed` | 3.0 m/s | |
| | `can_flinch` | true | |
| Attack | `trigger_range` | 1.8 m | Center to center |
| | `attack_reach` | 2.3 m | Sets the hitbox box length and offset on ready. Width, height and height offset stay in `Enemy.tscn → Hitbox/HitboxShape`. |
| | `damage` | 15 | |
| | `windup_time` | 0.7 s | The tell. Don't shorten it. |
| | `strike_time` | 0.2 s | Hitbox open for roughly 10%–90% of it (method keys in the `strike` anim) |
| | `recover_time` | 0.8 s | Punish window |
| | `cooldown_time` | 1.5 s | Starts when RECOVER ends or a flinch interrupts it |
| | `strike_lunge` | 1.4 m | Ease-out over `strike_time` along the facing locked at STRIKE start. Walls stop it, and touching you ends it. |
| Tracking | `chase_turn_rate` | 460 °/s | Also ALERT, SEARCH and CHARGE_WINDUP turns |
| | `windup_turn_rate` | 180 °/s | Facing locks at STRIKE start, through RECOVER and COOLDOWN |
| | `tell_flash_time` | 0.15 s | TellFlash light on at windup start |
| Reactions | `flinch_time` | 0.3 s | Only from IDLE, CHASE, RECOVER or COOLDOWN. WINDUP and STRIKE have super armor, so a hit there is a trade. |
| | `flinch_knockback` / `knockback_decel` | 2.5 m/s / 14 m/s² | |
| | `despawn_delay` | 3.0 s | Corpse lifetime |
| Hit Flash | `flash_color` → `flash_fade_color` | white → red | |
| | `flash_time` / `flash_fade_time` | 0.07 / 0.11 s | White to red, then red to clear |

Body also holds `body_scale`, `body_material` and `voice_pitch`; the Perception, Behavior (Pounce, Charge) and Noise groups are listed under **Step 6**. `aggro_range` is gone, replaced by perception.

The enemy animations `windup`, `strike`, `recover`, `flinch`, `alert` and `crouch` are played time-scaled to these durations; `pounce`, `charge` and `stun` loop. Edit **poses** in `Enemy.tscn → AnimationPlayer` and **timing** in the `.tres`.

### Hit points and stamina (nodes)

| Where | Field | Value |
|---|---|---|
| `player/Player.tscn → Health` | `max_hp` | 100 |
| `player/Player.tscn → Stamina` | `max_stamina` / `regen_per_second` / `regen_delay` | 100 / 25 / 0.6 s |

### Feel — `player/Player.tscn → Head/Camera3D/WeaponRig` (`weapon_rig.gd` exports)

| Group | Field | Value |
|---|---|---|
| Hit Feedback | `hitstop_time_scale` | 0.05 (`Engine.time_scale` during hitstop) |
| | `swing_kick_deg` | (-0.8, 0.9, 1.4) pitch/yaw/roll, on every swing |
| | `hit_kick_deg` | (-2.4, -1.2, -2.2), on a landed hit |
| | `kick_in_time` / `kick_out_time` | 0.035 / 0.2 s |
| Block Impact | `block_shake_deg` / `block_shake_time` | 0.7° / 0.18 s |
| | `block_hitstop` | 0.035 s (set 0 to disable) |
| Bob & Sway | `bob_amplitude` | (0.01, 0.008) m at walk speed |
| | `bob_frequency` | 1.7 Hz at walk speed (scales with speed) |
| | `sway_per_pixel_speed` / `sway_max_deg` / `sway_smoothing` | 0.0025 °/(px/s) / 3.5° / 12 |
| Input | `attack_buffer_time` | 0.15 s. A click during a swing or block still swings when the rig frees up. 0 disables it. |

### Player — `player/Player.tscn` root (`player.gd` exports)

| Field | Value |
|---|---|
| `starting_weapon` | `weapons/rusty_sword.tres`, equipped on ready |
| `fx` | `Main/FX`, set in `Main.tscn`. Leave empty to run Player.tscn alone, without particles. |
| `walk_speed` / `sprint_speed` / `block_speed` | 5.0 / 7.5 / 2.5 m/s |
| `acceleration` | 45 m/s² |
| `mouse_sensitivity` | 0.0022 rad/px |
| `pitch_limit_deg` | 85 |
| `block_cone_dot` | 0.3 (≈145° cone) |
| `hurt_shake_deg` / `hurt_shake_time` | 1.2° / 0.25 s |
| `death_restart_delay` | 2.5 s |
| `dungeon` | `Main/Dungeon`, set in `Main.tscn`; where noise goes. Empty = you make no noise. |
| Noise group | `noise_sword_hit` 9, `noise_block` 9, `noise_whiff` 3, `noise_sprint_step` 5 every `sprint_step_interval` 0.3 s, `noise_drop` 4 (meters; see Step 6) |

### FX — `fx/`

| Scene | Fields worth touching |
|---|---|
| `HitPuff.tscn` | root `amount` 5, `lifetime` 0.25. Process material: `direction` (0, 0.6, -1) local (the pool aims local -Z along `HitInfo.direction`), `spread` 35°, velocity 1–2 m/s, gravity -6. Box 0.07 m × scale 0.7–1.4. Material `art/materials/fx_blood.tres`. |
| `BlockSpark.tscn` | root `amount` 12, `lifetime` 0.25. Process material: `spread` 180° (radial), velocity 6–11 m/s, damping 2–4. Streak box 0.02 × 0.14 m, aligned to velocity, holds full size for 60% of its life. Material `art/materials/fx_spark.tres`. |

### Other knobs

| Where | What |
|---|---|
| `Enemy.tscn` root | `flash_material`, the shared, local-to-scene overlay. Its colors and timing come from `EnemyData`. |
| `Player.tscn → HUD` | `damage_flash_alpha` 0.35, `damage_flash_time` 0.35 s |
| `Player.tscn → WeaponRig/Hitbox/HitboxShape` | Width 0.6 and height 0.5 are authored here, as is the near edge 0.15 m in front of the camera. Length comes from `attack_reach` on equip. The sword reaches 1.55 m against a visible tip of about 1.3 m. |
| `Player.tscn → WeaponRig/AnimationPlayer` | Viewmodel poses for `swing` (normalized 1 s), `block_raise`, `block_lower`, `block_impact`, `equip` (0.3 s). Tracks drive `ViewPivot/SwordMesh`. |
| SFX nodes | `WhooshSfx` -6 dB, `ImpactSfx` 0 dB, `ClangSfx` -3 dB, `HurtSfx` -4 dB, enemy `SwingSfx` pitch 0.7, `DeathSfx` pitch 0.6 |
| `world/Torch.tscn` root | `light_energy` 2.0, `omni_range` 7.0, `flicker_amount` 0.15, `flicker_speed` 7. `distance_fade` begin 24 m (shadows off past 16 m), so a floor full of torches stays cheap. |
| `Main.tscn → WorldEnvironment` | ambient 0.6, fog density 0.025 (same in `tests/CombatArena.tscn`) |

---

## How the pieces fit

- **Input:** only `PlayerIntent` touches `Input`. It runs at process and physics priority -1, so it samples before `Player`. Attack, interact and restart are latched from input events, so a press can't be dropped between frames.
- **Damage:** everything goes through `take_hit(hit: HitInfo)`. `Player.take_hit` checks block and cone and only then calls `Health`. `Enemy.take_hit` flashes, applies damage, then decides on a flinch (only if `data.can_flinch`, and never in WINDUP or STRIKE).
- **Hitboxes:** `MeleeHitbox.begin_swing()` / `end_swing()` are called only from AnimationPlayer method tracks. Besides `body_entered` it also sweeps `get_overlapping_bodies()` while active, because a body already inside the box when monitoring turns on doesn't reliably fire `body_entered`. `overlap_point(body)` returns the midpoint between the hitbox shape and the body's shape, used as the FX contact point.
- **Enemy states:** the full list is in **Step 6 → States**. The melee core is CHASE → WINDUP (capped tracking) → STRIKE (facing locked, lunge) → RECOVER → COOLDOWN → CHASE. FLINCH returns to COOLDOWN if cooldown time is left, otherwise to CHASE. The lunge is an ease-out displacement over `strike_time`, applied through `velocity` + `move_and_slide()`. Walls stop it, and the rest of it is dropped the moment it touches you. Your own swing step stops on touching an enemy the same way. Without that, `move_and_slide` turns any off-centre contact into a slide round the other capsule.
- **Perception and noise:** `Enemy` owns a `Perception` node and reads `can_see` / `last_known_pos`; no signals. Noise is a direct call to `Dungeon.emit_noise()`, which calls `Enemy.hear()` on the `enemies` group. There's no global bus.
- **Map:** the generator hands each plan to `Dungeon.set_plan()`. The Player writes `Dungeon.player_cell` every physics frame. Both minimaps hold the `Dungeon` (bound through `Hud.bind_map()` from `Player._ready()`) and redraw on its `revealed_changed` signal, the one signal in the chain, because the draw is cheaper to skip than to poll.
- **Hit feedback order** (`WeaponRig._on_hit_landed`): `take_hit` → cut the whoosh → thud → `fx.play_hit_puff` → camera kick → hitstop. Block impact (`WeaponRig.play_block_impact`): recoil animation → `fx.play_block_spark` at the blade → clang → shake → short hitstop. Kick and shake tweens ignore time scale, so the camera punches during the freeze. The enemy flash runs on scaled time, so it holds at full white through the freeze.
- **FX pool** (`fx/fx_pool.gd` on `Main/FX`): `play_hit_puff(pos, dir)` and `play_block_spark(pos)` move the next pooled instance and call `restart()`. Pools are the children of `%HitPuffs` and `%BlockSparks`; add children to grow them.
- **Whiff vs hit audio:** the whoosh starts with every swing and is cut on contact, so a hit sounds like a thud and a miss like a whoosh.

### Collision layers

| Layer | Name | Who |
|---|---|---|
| 1 | world | CSG room |
| 2 | player | Player body (mask: world + enemy). Enemy hitbox masks this layer. |
| 3 | enemy | Enemy body (mask: world + player). Player hitbox masks this layer. |
| 4 | interactable | Pickups (`StaticBody3D`, mask none). Only `InteractRay` masks this layer; bodies walk through them. |

Hitbox areas and the exit room's `ExitTrigger` (which masks the player layer) have no layer of their own. Room geometry, including door plugs, is on layer 1. The enemy hitbox's `BoxShape3D` is `resource_local_to_scene`, so resizing it from `attack_reach` doesn't leak into other enemy instances.

### Palette

`art/palette/palette.png`: 64×32, 8 × 4 swatches of 8×8 px each. Index = row × 8 + column. It is imported lossless, without mipmaps or VRAM compression (see its `.import`), and every material uses nearest filtering.

The greybox primitives use one material per swatch, with `uv1_scale = 0` and `uv1_offset` set to the swatch center, so every UV lands on that swatch. Swatch center: u = (col + 0.5) / 8, v = (row + 0.5) / 4. For real UV-mapped models, use `art/materials/palette_base.tres` (UV scale 1) and map the UVs onto swatches in the modeling tool.

| Row | Columns 0 → 7 |
|---|---|
| 0 stone | `0e0c12` `1b1920` `2a272f` `3b3740` `514b55` `6d666e` `958c90` `c9c0b9` |
| 1 earth | `24170f` `3d2717` `5c3b20` `7f552c` `a8763e` `c99a5b` `e2c08a` `f2e2bf` |
| 2 fire | `2a080c` `4f1015` `84191c` `b8291f` `e05426` `f58b26` `ffc93d` `fff3c4` |
| 3 metal | `1a2329` `2e3d45` `4b6068` `7a8e94` `aab9bc` `dfe8e6` `3f5a2c` `ffffff` |

FX swatches: `fx_blood` = row 2 col 2 (`84191c`, shaded); `fx_spark` = row 2 col 7 (`fff3c4`, unshaded).

**Weapon meshes** are the first real use of palette UVs. Each is one `ArrayMesh` built from boxes by the asset generator, and every box's UVs point at its swatch center. There are two surfaces: matte (`palette_base.tres`) and metal (`palette_metal.tres`, metallic 0.2). Both sample the same palette. To change a weapon's shape or colors, edit its parts list in `tools/generate_placeholder_assets.gd → _write_weapons()` and rerun the generator. Each part is a size, a position (grip at origin, long axis +Y, edge toward -X), a swatch index and whether it's metal.

---

## Tools

On a fresh clone, open the editor once (or run `godot --headless --path . --import`) so the `class_name` cache exists before running anything headless.

| Command (from the project root) | What it does |
|---|---|
| `godot --headless --path . --script res://tools/generate_placeholder_assets.gd` | Regenerates the palette PNG, the synthesized placeholder SFX, the weapon meshes and the 32×32 weapon icons (deterministic) |
| `godot --headless --path . --script res://tools/dungeon_tests.gd [-- 1000 20 20 300]` | Generator checks.<br>• `rotate_cell` against real transforms, every catalog door at every rotation, and the authoring warnings firing on broken rooms.<br>• A batch of seeded layouts, printing the shape line for the first seeds (`seed 1: main 12, branches 5/5 (depths 3,6,6,5,6), aimed 5 (closed 1), halls 41 (mean 1.6, 2 extended, 10 capped), loops 8 (len 6, 4, 6, 7, 8, 8, 9, 10), treasure at depths [2, 10], candidates 12`). Every seed must have exit depth `main_path_length + 1`, exactly `main_path_length` main rooms (a spine of `main_path_length + 2`), a branch count rolled within `branch_count_min`..`max` with no more branches than rolled, `max_rooms` and `max_attempts` never binding, no branch over `max_branch_depth`, treasure within the cap, rooms within `max_rooms`, every link room ↔ hall ↔ room (no room hangs off a room, every hall piece leads on), every hall 1–`max_hall_pieces` pieces, every failed link (with `verify_unplace` on) leaving the occupied cells, placements, counts and its door exactly as it found them, and no overlaps. Every loop bridge must be 1×1 pieces with both doors used, at most `max_loop_length` long, and join rooms at least `loop_min_separation` apart, recomputed independently over the layout as it was just before that bridge. It reports restarts, placement tries, rooms, branches, halls (pieces per hall, extends, caps), doors per room and the share used, the treasure depth spread, loops with their lengths, candidates per floor, how many candidate-less floors a longer cap would rescue, plugs, how often the door supply ran out before the rolled branch count, aimed-branch outcomes (closed, gave up at depth, hit `max_rooms`, dead end, nothing fit, no target) and their mean length, mean bridge length, the main path's length in cells, the exit's distance from START, and size, plus an ASCII map of seed 1.<br>• The **loop table**: share of floors with a loop, loops per floor and mean bridge length, for separation 1/2/3 × cap 5/10 at the defaults. (The step-8.1 branch table and step-7.1 curl table are gone; their numbers are in those sections.)<br>• Same seed twice giving the same plan, and the placement rules honoured.<br>• Real builds, plus the first 3 seeds that have a loop (at least one with a corner piece): every connected door (bridge pieces included) meets its partner, every other door is plugged, spawned nodes match the spawn log, and the player lands on the start spawn.<br>• **Map:** a rebuild clears it, `MapModel` matches the built rooms, spawning reveals only the start room, walking in reveals the next room whole with one signal, revisiting changes nothing, and M swaps the maps without pausing.<br>• **Spawn tables:** each table rolled 22,000 times against its weights, each enemy variant's HP, scale, capsule and tint on the real scene, and the same seed built twice giving identical spawn logs. It prints seed 1's log.<br>The arguments are batch size, build count, per-seed lines and seeds per table cell. About 135 s with `-- 1000 20 12 300`. Exit code 0 means pass. |
| `godot --headless --path . --script res://tools/plan_map.gd -- out.png 1 2 3` | Headless, no GPU. Plans each seed with the real generator (restarting like `generate()`) and draws it as a cell map on one sheet, three per row. Rooms are light grey on the main path and dark grey on branches; halls are darker strips; yellow is a loop bridge, green START, orange EXIT and tan treasure. White notches are used doors and red ones plugged. Each seed's shape line is printed. `docs/plans_step9.png` is seeds 1–12. |
| `godot --path . --script res://tools/capture_map.gd -- out.png 10 40` | Opens a window. Per seed it walks the floor, room by room, except the last two branch rooms, ending in the exit. It grabs the corner map (doubled) and the M full map, one row per seed. Seed 40 has a 5-cell L-shaped loop bridge. |
| `godot --path . --script res://tools/capture_dungeon.gd -- out.png 1 2 3` | Opens a window and renders a top-down view (ceilings hidden) and the view from spawn for each seed given |
| `godot --headless --path . --script res://tools/combat_smoke_test.gd` | Drives `tests/CombatArena.tscn` (the step-1 room, so it stays deterministic) with input events, in four parts.<br>**Part A (inventory and weapons):**<br>• E into the bag (and ignored while blocking); Tab pausing; every drop rule, driven through the slots' own drop handlers with real payloads; the right-click shortcuts; the tooltip and stats.<br>• Drop to world and pick it back up; fists unable to swing; the iron cap turning 15 into 12 (and 2 into 1); the full-bag flip and notice; an equip during a swing waiting for it to end.<br>• A probe per weapon, measuring swing length, the hitbox open/close times, lunge distance and stamina spent against that weapon's data.<br>• Against a frozen grunt: damage per weapon, a swing from touching distance, and a swing step that glances off the grunt and must stop instead of sliding round it.<br>**Part B (fresh scene, grunt):** data applied, strike lunge, block, the windup turn cap, facing and position locked through RECOVER/COOLDOWN, hit-and-back-off caught, an early retreat escaping, a lunge that glances off you staying on its line, and a punish to the kill.<br>**Part C (fresh scene, behaviours):**<br>• Skitterer: spots you and out-runs your walk; crouches at 5 m and pounces for 8; a block eats the pounce; point-blank it bites.<br>• Bruiser: roars and charges from 7 m, hitting for 35 and slowing you to half speed for 1.5 s; a blocked charge does nothing but still stops; sidestepped into the arena wall it's dazed through exactly 3 sword hits, then COOLDOWN.<br>**Part D (fresh scene, perception and noise):** unseen 4 m behind it and seen 4 m in front; losing sight → SEARCH → walks to the spot → home to IDLE; the arena's `Pillar` blocking line of sight; a sneak hit waking a second grunt by noise; walking past silent, sprinting past heard.<br>Exit code 0 means pass. |
| `godot --path . --script res://tools/capture_views.gd -- out.png` | Opens a window and renders a contact sheet: pickups on the floor with the prompt, each weapon at rest, mid-swing and blocking, the hit puff and block spark, a skitterer / grunt / bruiser lineup, the inventory screen with a tooltip, and a pickup mid-flip off a full bag |

---

## Decisions and deviations from the handoffs

- **Camera kick goes on `Camera3D`, not `Head`.** Head holds mouse-look pitch, so tweening it would fight the look code. The camera's own rotation is otherwise unused, so kick and shake compose there.
- **`SwordMesh` is the hand.** Its origin is the grip, so swings rotate around the hand. Since step 2 it holds a single generated `view_mesh` per weapon instead of child boxes. It sits under a new `ViewPivot` node that carries `view_offset` / `view_rotation`. The AnimationPlayer owns `SwordMesh`'s transform, so the nudge needs its own node.
- **No `AnimationPlayer.speed_scale`.** Swing speed is passed per `play()`, so `block_*` and `equip` keep their authored timing.
- **The lunge duration comes from the weapon** (swing start → middle of the active window) instead of the removed `Player.lunge_duration`. A fixed 0.18 s had the axe finish its step before the hit.
- **EQUIP is a fourth rig state** (with IDLE, SWING, BLOCK). While equipping you can't swing, block or interact. Only SWING queues an equip (step 5 narrowed this from "anything but IDLE"); the inventory pauses the game, so an equip raise could otherwise never finish and would hold later swaps hostage.
- **The inventory screen is instanced inside `Player.tscn`**, next to the HUD, so it reaches the player's `%Inventory` directly. `Player` exposes read-only `inventory`, `health`, `stamina` and `intent` for it.
- **The drag preview is a tiny scene** (`ui/DragPreview.tscn`), instantiated per drag. `set_drag_preview()` takes ownership of the control and frees it when the drag ends, so a pre-placed node can't be reused. Together with the dropped Pickup, these are the only runtime instantiations outside the generator.
- **Background drops go to the world only over the true background.** The paper-doll panel and the bag grid stop the mouse and refuse drops, so a drag that misses a square by a few pixels shows "no" instead of dumping the item on the floor.
- **Drops are pulled back from walls** by a short ray, so an item dropped while facing a wall stays reachable.
- **The HUD prints HP on the health bar**, so the armour check ("12, not 15") is readable without the inventory open.
- **The enemy body is a small rig:** `Rig` → `Legs`, `Body` (pelvis) → Torso, Head, Eyes, both arms, Club. The `die` anim tips `Rig` over backward. Every mesh shares one local-to-scene overlay material for the hit flash.
- **`EnemyData` has more than the 1.1 spec.** `aggro_range` (removed in step 6), `chase_turn_rate`, the flinch, knockback and despawn values, and the hit-flash colors and timings moved in too, so `enemy.gd` has no tuning numbers left.
- **COOLDOWN is its own state** rather than a timer inside CHASE. That makes "no tracking, no movement" explicit, and it shows up in `get_state_name()` for debugging.
- **Player owns the `fx` reference** (`@export var fx: FxPool`, wired in `Main.tscn`). WeaponRig reaches it through the player, because a nested node inside an instanced scene can't be wired cleanly from Main.
- **Small additions from step 1:** a `walk` loop for the enemy, an R restart, auto-restart on player death, the 0.15 s attack buffer, a 0.035 s hitstop on block impact, and a billboard HP bar.
- **The block is active the moment RMB goes down.** `block_raise` is only cosmetic.
- **`untyped_declaration` is set to Error** in project settings, so the static-typing rule is enforced.
- **The generator plans first, then builds.** The algorithm is the handoff's, but it runs on data (`plan_layout(seed)`); only the finished plan is instantiated. Restarts cost nothing, and the batch test can run thousands of seeds without building anything. The one off-tree instance per catalog room (read for metadata, then freed) is the only node it creates and doesn't place.
- **Extra pruning on open doors:** a door whose neighbour cell is already taken is dropped immediately (it can never connect). A door that fails `door_retry_limit` placements is also dropped. Both end up plugged. Restart seeds are `seed + n × 7919`, so a fixed `seed_value` reproduces the restarts too.
- **The catalog also scans a folder** (`scan_folder`), so authoring a room is just "duplicate a scene" with no data file to touch. The explicit `rooms` list still works for rooms kept elsewhere.
- **Door markers rotate themselves** from `dir` (−Z out through the doorway). Plugs are added as children of the unused door marker, so they sit at its exact transform and are freed with the room.
- **`Spawned` is pre-authored** under `Dungeon` in `Main.tscn` (nodes aren't created at runtime). Regenerating frees every other `Dungeon` child and empties `Spawned`.
- **The HUD stays inside `Player.tscn`** rather than becoming a `Main` child. Player drives it through `%HUD`, and moving it would only add wiring.
- **The Player starts disabled** (`process_mode` Disabled in `Main.tscn`). `Main._ready()` generates the floor, places the player, then enables it. F5 goes through `PlayerIntent.regenerate_pressed`, read by `Main` via `Player.intent`, so `Input` is still only touched in one place. F6 (`regenerate_same_pressed`) works the same way.
- **Rolled enemies use the generator's `enemy_scene`** with the row's `EnemyData` set before the node enters the tree. `fixed_scene` is only read by the no-table fallback, as in step 3.
- **`body_scale` scales the `Rig`, not just `Body`.** In this scene `Body` is the pelvis and upper body, so scaling it alone would leave grunt-sized legs. The capsule shape is local to scene and resized, not node-scaled, because physics doesn't like scaled shapes.
- **Tints are two palette materials** (`hide_skitterer`, `hide_bruiser`) set from `EnemyData.body_material`, per the handoff's "three greybox materials is fine". The grunt keeps the scene's burlap.
- **`aggro_range` is gone.** Perception replaced it outright; nothing reads a plain distance any more.
- **A hit on an unaware enemy:** the handoff says it goes ALERT. Flinching types (grunt, skitterer) go to FLINCH instead, and the flinch is their startle beat. FLINCH ends in CHASE, and `last_known_pos` is already set to whoever hit them. A bruiser can't flinch, so it does go ALERT, and an ALERT that a hit started always ends in CHASE, even without line of sight. A hit while already in CHASE changes nothing beyond the usual flinch.
- **`aware_sense_range` (2.5 m) is an addition.** Without it, an enemy fighting you loses you the moment you circle out of its 110° cone, which turns every fight into a strafe-reset. Unaware enemies still only see inside the cone, so sneaking up from behind works (the test does it).
- **WALL_STUN hits flinch without ending the stun.** The handoff says to treat `can_flinch` as true while stunned. A full FLINCH would end the punish window on the first hit, so a stunned hit plays the flinch and knockback but stays in WALL_STUN.
- **SEARCH walks home** after its look-around instead of going IDLE where it stands, so a floor doesn't slowly drift toward wherever you last fought. Each leg has a 6 s give-up, because there's no pathfinding and a straight-line walk can be stopped by a wall.
- **The pounce arc is literal:** 9 m/s horizontal and a 1.2 m peak is about 1 s of flight, so a skitterer whose target sidesteps lands about 9 m from where it jumped. It lands in RECOVER wherever that is. That's either the punish window or a skitterer that ends up behind you; see the playtest questions.
- **The charge shortens the hitbox** to `charge_hit_reach` (1.3 m) for the charge, so it hits on contact rather than 2.8 m out, then restores `attack_reach`. **`HitInfo.blocked`** is set by the receiver (`Player.take_hit`), so the charge knows not to apply the slow after a block.
- **Lunges stop on contact.** At step 6's 1.4 m grunt lunge, a strike that met you even slightly off-centre had `move_and_slide` carry the rest of it round your capsule. The grunt ended up beside you, and sometimes past you. Your own swing step did the same to the grunt, so a point-blank swing could whiff. Both now drop the rest of the move once they touch the other body, and the smoke test checks a glancing lunge and a glancing step (0.30 m and 0.16 m of sideways slide before, about 0.01 m now). This surfaced as a flaky axe damage probe. I first blamed the hitbox and tried a shape query in `MeleeHitbox`. That turned out to be wrong, so it's reverted, and `melee_hitbox.gd` is unchanged from step 5.
- **Perception staggers the whole look** (range, cone and ray), not just the ray, at 1 frame in 4 with a phase from the instance id. `can_see` holds between looks.
- **`Main.tscn`'s `Dungeon` node now carries `dungeon.gd`.** It was already the floor's root, so noise lives where the enemies do. `tests/CombatArena.tscn` gained a `Dungeon` node (for noise) and a `Pillar` (for the line-of-sight test).
- **Part A's damage probes freeze the grunt** (`DISABLE_MODE_KEEP_ACTIVE`, so it stays in the physics space). Since step 6 it sees you instantly, and a live grunt struck back mid-probe.
- **Step 7: the generator keeps the brief's algorithm,** with these calls of mine:
  - **Treasure on the main path becomes a side room**, because the treasure room is a dead end (see Step 7).
  - **`_place` returns the placement**, and corridors no longer add depth; everything else in it, and `_fits`, `_build`, `_spawn`, `rotate_cell` and `placement_transform`, is untouched. `_pick_template` gained the placement rules plus "weight 0 is never picked" (before, a 0-weight template could win on an exact 0.0 roll), and returns null when nothing qualifies.
  - **A branch continues through whichever of its newest room's doors fits first**, not one picked blind, so fewer branches die on a wall.
  - **Shuffles use the plan's own RNG** (`_shuffle`), because `Array.shuffle()` uses the global one and would break same-seed floors.
- **The generator's seed line now prints the floor's shape**, the same `describe_plan()` line the test prints, so a playtest log says how deep the treasure was.
- **Doorways on the map are the real doorway width**, the middle half of the cell edge (a 2 m door in a 4 m cell; 5 px on the corner map), not a fixed 2 px, so it scales with both maps (5 px on the corner, 12 on the full one) and matches the doorways you walk through.
- **The player triangle sits at your exact position**, not your cell's center, so the centered corner map scrolls smoothly instead of jumping 4 m at a time. Position and yaw changes share the 10 Hz redraw throttle.
- **The corner map sits under the controls hint line**, since the hint already held the top-left corner. M also hides the corner map while the full one is up. M does nothing while paused (inventory open), like every other key but Tab.
- **The full map frames what you've revealed**, not the whole floor, so it never gives away the floor's size. It drops below 24 px per cell when the revealed area wouldn't fit.
- **Step 9, my calls:**
  - **"Shuffled by rng" is a weighted shuffle.** A hall's room tries every allowed template in a random order drawn by weight (and its first 1–2 pieces likewise), so weights still mean something. Entry doors are a plain shuffle, or steered for an aimed branch.
  - **A connector only "fits" with a way on:** at least one of its other doors must open onto an empty cell. Otherwise the hall would end in a wall no room can attach to.
  - **One null doesn't end the main path or a branch.** Each tries every free door of its current room, as `_grow_one` did, and only gives up (restart, or branch over) when none links. Every door that failed is capped.
  - **A hall is never 0 pieces.** If not even the first piece fits, the link fails, because a room straight on the door would touch a room.
  - **Capped doors still take loop bridges and aimed targets**, since a 1-cell bridge needs far less room than a hall plus a room.
  - **Treasure on the main path** hangs off the current room on a hall of its own: one try, only when the room keeps another free door, and the slot stays COMBAT. It used to hang off a connector's side door.
  - **`bridge_max_len` is `max_loop_length`**, renamed nowhere.
  - **`max_attempts` 2500 and `max_restarts` 10.** The search tries every template and entry door now, so tries per floor went from tens to hundreds. 200 would have cut almost every floor's branches short without a word.
  - **Hub doors on 2- and 4-wide sides:** there's no centred cell, so I picked offsets (Gallery N at x = 0 and S at x = 1; Barracks N at x = 1 and S at x = 2).
  - **Halls draw as one corridor on the map** (`MapModel` groups a hall's pieces like a bridge's). Not asked for, but at 1–4 pieces a hall drawn piece by piece is a row of seams.
  - **`tools/plan_map.gd` is as attached**, except its restart loop uses the generator's `max_restarts` (it had 5).
  - **`docs/` holds the map sheets**, with a `.gdignore` so Godot doesn't import them. `plans_step8.png` is the 8.1 generator on the same seeds, for comparison.
  - **`verify_unplace`** is a plain var (not exported) for the tests. It copies the layout before each link, so it stays off in the game.
- **Step 8.1, my calls:**
  - **Branch count is rolled per floor** (`randi_range(min, max)`, inclusive, from the plan's RNG, before the spare doors are shuffled), per your amendment. The decision rule became "smallest pair over 30%", and "set 4" if none got there would have been 3–5.
  - **A branch only counts once it places a room**, so an aimed branch that closes straight from its start door, with no rooms, makes a loop but doesn't use up a branch.
  - **Aimed branches skip one-door rooms** by asking `_grow_one` for templates with 2+ doors, and turning a TREASURE roll into COMBAT when no 2-door treasure room exists.
  - **`max_rooms` binding is checked**, not assumed: `PlanStats.hit_max_rooms`, which the test requires to stay false at the defaults.
- **Step 8, my calls:**
  - **Chance 0 skips the roll entirely,** so it builds exactly the step 7.1 floors (that's the chance-0 row of the loop table).
  - **Grid distance for the target** is Manhattan, between the cells outside the doors (where a bridge would start and end). A target whose outside cell is already occupied is skipped, since no bridge could ever reach it.
  - **The start door counts as one of the branch's doors** until something attaches to it, so a target already in bridge range closes with no branch rooms at all.
  - **Closing re-checks separation** over the layout as it stands; the independent check in the test passes for every bridge (closest 3). The link graph is rebuilt from parent links plus bridge ends whenever it's needed, because aimed bridges now appear mid-plan.
  - **A main-path spare door an aimed bridge used** is skipped when its turn to start a branch comes.
  - **`PlanStats`** (`DungeonGenerator.last_stats`) replaces `last_loop_candidates`; it carries the loop candidates and every aimed-branch outcome.
- **Step 7.1, my calls:**
  - **Straight corridor weight:** the handoff says it was already 2, but every corridor was at the default 1. I set it to 2 in piece 1, as the handoff intended.
  - **Connector rule:** the rule lives in `_pick_template` (via the placement it attaches to), so `_grow_one` and every caller get it. Depth, room counts, branch depth and loop separation now key off `is_connector` instead of the CORRIDOR type; today they're the same set.
  - **Cubby:** it's a wall mass with the niche cut out of it, not a cut through the 0.3 m wall (see Step 7.1).
  - **Curl ships at 0** (Step 7.1's decision). At 0 it runs the old code path exactly, so curl 0 floors are piece 2's floors byte for byte.
  - **Curl's entry-door score** is the best of the room's other doors, not their average, so one door pointing home is enough to favour that turn.

## Known limitations

- One `swing` clip serves every weapon, so the dagger slashes the same arc as the sword, just faster. Camera kicks and SFX are shared too. If the dagger feels like a worse sword, these are the levers. A per-weapon clip or a kick scale in `WeaponData` would be the next step.
- The viewmodel is world-scale geometry on the camera, so it clips into the grunt at point-blank range and into walls. With `strike_lunge` this happens after every strike. Fix with a viewmodel render layer or camera, or a depth-squash shader.
- The hit-puff contact point is the hitbox/body midpoint. Within about 1 m it lands inside the body.
- The SFX are synthesized placeholders.
- Torchlight can bleed through walls into a neighbouring room once a torch's shadow fades out (past 16 m). Out of scope for step 3.
- Every floor loops at the step-9 defaults (4.9 bridges per floor at separation 3), but at cap 10, 22% of bridges are 9–10 cells: long unlit corridors more than shortcuts. Cap 5 still loops 93% of floors at this size. No locked doors.
- Loop bridges are unlit (no torch in the 1×1 pieces), so they read as dark passages between lit rooms.
- Treasure is still a dice roll, not a guarantee. At step 9's size it's 1.7 per floor, and 6% of floors have none.
- Branches only start from main-path doors (rooms and hall T's), so asking for many branches falls short when those run out. That happens on 1.9% of floors at step 9's 4–6 branches; at step 8.1's size it was 48%.
- About 1 seed in 5 restarts because the 12-room main path boxed itself in (a restart is free, about 30 ms). A hall never re-rolls its first pieces, only extends from the end, so a hall that starts into a pocket fails even where another first piece would have led out.
- A step-9 floor builds 100–170 scenes with 120–180 torches. It builds in about 0.1 s headless. Torches are lit by room (step 11), so only 10–30 are live at once; a whole floor can stay built.
- `Hub_5x5`'s platform is only reached by its four ramps; its 0.5 m edge is a wall. Enemies don't pathfind, so one chasing you across the hub can get stuck against that edge.
- The generated room scenes list every shared resource in their headers, including ones a given room doesn't use. Godot drops the unused ones the first time you save each room in the editor.
- No pathfinding. CHASE and SEARCH walk straight at their goal, so an enemy that lost you round a corner walks into the wall until SEARCH's 6 s give-up moves it on. A `NavigationRegion3D` baked per room would be the fix.
- Noise ignores walls: a fight in one room wakes enemies within 9 m in the next. Cheap occlusion would be a ray per listener with a radius penalty when it's blocked.
- Enemies don't alert each other by sight, only through the noise of a fight.
