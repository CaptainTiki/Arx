# Steps 1–5 — Swing & Block, Pickups, Generated Dungeon, Spawn Tables, Inventory

Open in Godot 4.7, press F5. Main scene: `res://main/Main.tscn`. The step-1 room lives on as `res://tests/CombatArena.tscn`, the fixture for the combat smoke test; you can also open it and F6 it to fight one grunt in a known room.

**Controls:** WASD move · Shift sprint · LMB swing · RMB block (hold) · E take · Tab inventory · R restart · F5 new dungeon · F6 same dungeon again · Esc frees the mouse (click to recapture).

Every Play builds a different floor of about 10 hand-built rooms, from a start room to a glowing exit pad. You start holding the Rusty Sword with an empty bag. Combat and treasure rooms roll what's in them from spawn tables. The output log prints `Dungeon seed N`, followed by one line per spawn point (`room 4 (CombatRoom_B) spawn 1 → skitterer`). Put N in `DungeonGenerator.seed_value`, or press F6, to get that exact floor and those exact spawns again. F5 builds a new one. Look at an item within 2.5 m and press E to put it in your bag; Tab opens the inventory to wear it.

Enemies wake up when you get within 4 m. Each walks in, rears back with a red flash and a grunt (its windup, turning at most its turn rate to follow you), then lunges into the strike. After that it stands still, without turning, through recovery and cooldown. There are three kinds; see Step 4.

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
| `recover_time` | 0.8 | 0.4 | 1.2 |
| `cooldown_time` | 1.5 | 0.6 | 2.0 |
| `strike_lunge` | 0.9 | 1.3 | 0.6 |
| `windup_turn_rate` | 180 | 360 | 90 |
| `body_scale` | 1.0 | 0.7 | 1.4 |
| `body_material` | (scene burlap) | `hide_skitterer.tres`, pale bone `c9c0b9` | `hide_bruiser.tres`, blood red `84191c` |

`body_scale` sizes the whole visual `Rig`, legs included, plus the collision capsule, HP bar height and tell light. Scaling only the `Body` node in this scene would leave the legs grunt-sized. `body_material` goes on torso and arms as a `material_override`; the hit-flash overlay still works on top. Everything else uses the grunt's defaults (aggro 4 m, chase turn 460°/s, flinch 0.3 s, and so on).

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

| Knob | Default | What it does |
|---|---|---|
| `catalog` | `dungeon/catalog.tres` | Room pool: its `rooms` list plus every `.tscn` in `scan_folder` (`res://dungeon/rooms`) |
| `target_rooms` | 10 | Rooms per floor, START and EXIT included. The last two are forced TREASURE, then EXIT. |
| `max_attempts` | 200 | Overlap failures allowed before a layout is abandoned and restarted |
| `seed_value` | 0 | 0 = random every generate. Anything else rebuilds the same floor and spawns (restarts derive from it too). |
| `enemy_scene` / `pickup_scene` | `Enemy.tscn` / `Pickup.tscn` | What a rolled ENEMY row (with its `EnemyData` set) or a WEAPON spawn instantiates |
| `print_spawn_log` | true | One log line per spawn point after the seed line |
| `corridor_chance` | 0.3 | Chance the next normal room is a corridor rather than combat |
| `max_corridor_chain` | 2 | Corridors in a row, at most |
| `recency_bias` | 2.0 | Which open door to grow from: 1 = any (bushy), higher = the newest (snakier, more hallway) |
| `door_retry_limit` | 4 | A door that fails this many placements is given up on and plugged |
| `max_restarts` | 5 | Fresh-seed restarts when no exit was placed, then it errors loudly |

Per room, on the scene root (`Room`): `type`, `weight` (pick chance within its type, default 1) and `footprint`.

### What 1000 seeds look like (`tools/dungeon_tests.gd`)

Your playtest questions, answered over seeds 1–1000 at the defaults:

- **Overlaps:** none.
- **Exit failures:** 98.5% of seeds place an exit first try, and the rest need one restart. None needed more, so "1 in 10" is nowhere close.
- **Dead ends:** about 3.9 doors per floor end up plugged. About 0.4 of the roughly 2.1 corridors per floor run into a plug (about 1 floor in 2.5 has one). That's the "looks stupid" case to watch.
- **Floor or hallway:** the deepest room sits about 6.4 steps from the start of 10, and the exit about 5.4. No floor in the batch was a single chain. The 3- and 4-door combat rooms branch it, so it reads more floor than hallway. Footprint is about 86 cells (about 14 × 15 cells, 56 × 62 m). Raise `recency_bias` for snakier floors, lower it toward 1 for bushier ones.

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
| `dungeon/dungeon_generator.gd` (`DungeonGenerator`) | Plan (pure data) → build (rooms, plugs, spawns) |
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
| `strike_lunge` | 0.9 m | **Fixes hit-and-back-off.** Reach plus lunge covers about 3.2 m from where it stood, so a player retreating at walk speed has to start roughly 0.25 s before the strike to escape. The smoke test checks both the caught case and the escape case. | It skates across the room and ends every strike in your face, which makes the viewmodel clip into it. 0 brings back the backpedal cheese. |
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
| | `strike_lunge` | 0.9 m | Ease-out over `strike_time` along the facing locked at STRIKE start |
| Tracking | `aggro_range` | 4.0 m | Spawns 5 m away, so you walk up to it |
| | `chase_turn_rate` | 460 °/s | |
| | `windup_turn_rate` | 180 °/s | Facing locks at STRIKE start, through RECOVER and COOLDOWN |
| | `tell_flash_time` | 0.15 s | TellFlash light on at windup start |
| Reactions | `flinch_time` | 0.3 s | Only from IDLE, CHASE, RECOVER or COOLDOWN. WINDUP and STRIKE have super armor, so a hit there is a trade. |
| | `flinch_knockback` / `knockback_decel` | 2.5 m/s / 14 m/s² | |
| | `despawn_delay` | 3.0 s | Corpse lifetime |
| Hit Flash | `flash_color` → `flash_fade_color` | white → red | |
| | `flash_time` / `flash_fade_time` | 0.07 / 0.11 s | White to red, then red to clear |

The enemy animations (`windup`, `strike`, `recover`, `flinch`) are played time-scaled to these durations. Edit **poses** in `Enemy.tscn → AnimationPlayer` and **timing** in the `.tres`.

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
- **Enemy states:** IDLE → CHASE → WINDUP (capped tracking) → STRIKE (facing locked, lunge) → RECOVER → COOLDOWN → CHASE. FLINCH returns to COOLDOWN if cooldown time is left, otherwise to CHASE. The lunge is an ease-out displacement over `strike_time`, applied through `velocity` + `move_and_slide()`, so walls and the player's capsule stop it.
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
| `godot --headless --path . --script res://tools/dungeon_tests.gd [-- 1000 20]` | Generator checks. It tests `rotate_cell` against real transforms, every catalog door at every rotation, that the authoring warnings fire on broken rooms, and a batch of seeded layouts (stats as above). It then does real builds, where every connected door must meet its partner, every other door must be plugged, and spawned nodes must match the spawn log, with the player on the start spawn. Finally, **spawn tables**: each table rolled 22,000 times against its weights, each enemy variant's HP, scale, capsule and tint on the real scene, and the same seed built twice giving identical spawn logs. It prints seed 1's log. The arguments are batch size and build count. Exit code 0 means pass. |
| `godot --path . --script res://tools/capture_dungeon.gd -- out.png 1 2 3` | Opens a window and renders a top-down view (ceilings hidden) and the view from spawn for each seed given |
| `godot --headless --path . --script res://tools/combat_smoke_test.gd` | Drives `tests/CombatArena.tscn` (the step-1 room, so it stays deterministic) with input events, in three parts. **Part A (inventory and weapons):** E into the bag (and ignored while blocking); Tab pausing; every drop rule, driven through the slots' own drop handlers with real payloads; the right-click shortcuts; the tooltip and stats. Then drop to world and pick it back up, fists unable to swing, the iron cap turning 15 into 12 (and 2 into 1), the full-bag flip and notice, an equip during a swing waiting for it to end, and a probe per weapon. The probe measures swing length, the hitbox open/close times, lunge distance, stamina spent and damage dealt against that weapon's data. **Part B (fresh scene, grunt):** data applied, strike lunge, block, the windup turn cap, facing and position locked through RECOVER/COOLDOWN, hit-and-back-off caught, an early retreat escaping, and a punish to the kill. **Part C (fresh scene, variants):** the bruiser hits for 35 and doesn't flinch from a sword hit in RECOVER; the skitterer closes faster than your walk, winds up in 0.35 s and hits for 8. Exit code 0 means pass. |
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
- **`EnemyData` has more than the 1.1 spec.** `aggro_range`, `chase_turn_rate`, the flinch, knockback and despawn values, and the hit-flash colors and timings moved in too, so `enemy.gd` has no tuning numbers left.
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

## Known limitations

- One `swing` clip serves every weapon, so the dagger slashes the same arc as the sword, just faster. Camera kicks and SFX are shared too. If the dagger feels like a worse sword, these are the levers. A per-weapon clip or a kick scale in `WeaponData` would be the next step.
- The viewmodel is world-scale geometry on the camera, so it clips into the grunt at point-blank range and into walls. With `strike_lunge` this happens after every strike. Fix with a viewmodel render layer or camera, or a depth-squash shader.
- The hit-puff contact point is the hitbox/body midpoint. Within about 1 m it lands inside the body.
- The SFX are synthesized placeholders.
- Torchlight can bleed through walls into a neighbouring room once a torch's shadow fades out (past 16 m). Out of scope for step 3.
- The graph is a tree: no loops, no locked doors. Roughly 0.4 corridors per floor dead-end into a plug.
- The generated room scenes list every shared resource in their headers, including ones a given room doesn't use. Godot drops the unused ones the first time you save each room in the editor.
