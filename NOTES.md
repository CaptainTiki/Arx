# Step 1 — One Room, One Enemy, Swing & Block

Open in Godot 4.7, press F5. Main scene: `res://main/Main.tscn`.

**Controls:** WASD move · Shift sprint · LMB swing · RMB block (hold) · R restart · Esc frees the mouse (click to recapture).

The dummy wakes up when you get within 4 m. It walks in, rears back with a red flash and a grunt (0.7 s), smashes, then stands there for 0.8 s plus a 1.5 s cooldown. Block the smash, release, and hit it 4 times.

---

## Tunables: what lives where

### Weapon — `weapons/rusty_sword.tres` (`WeaponData`)

| Field | Value | Notes |
|---|---|---|
| `damage` | 25 | 4 hits kills the 100 HP dummy |
| `stamina_cost` | 10 | ≈10 swings per bar |
| `swing_time` | 0.45 s | The `swing` animation is time-scaled to this |
| `active_start` / `active_end` | 0.12 / 0.28 s | **Written into the swing anim's method-track keys at startup** (`WeaponRig._apply_weapon_timing`). Edit them here; key times edited in the AnimationPlayer get overwritten. |
| `lunge_distance` | 0.6 m | Forward step on swing start |
| `hitstop` | 0.05 s | Real-time freeze on a landed hit |

### Enemy — `enemy/training_dummy.tres` (`EnemyData`)

| Field | Value | Notes |
|---|---|---|
| `move_speed` | 3.0 m/s | |
| `turn_speed` / `windup_turn_speed` | 8.0 / 2.5 rad/s | Slow tracking during windup, so you can sidestep |
| `aggro_range` | 4.0 m | Spawns 5 m away, so you walk up to it |
| `attack_range` | 1.8 m | Center to center |
| `damage` | 15 | |
| `windup_time` | 0.7 s | The tell. Don't shorten it. |
| `tell_flash_time` | 0.15 s | TellFlash light on at windup start |
| `strike_time` | 0.2 s | Hitbox is open for roughly 10%–90% of it (method keys in the `strike` anim) |
| `recover_time` | 0.8 s | Punish window |
| `attack_cooldown` | 1.5 s | Starts when RECOVER ends (or is interrupted by a flinch) |
| `flinch_time` | 0.3 s | Only from IDLE/CHASE/RECOVER. WINDUP and STRIKE have super armor, so a hit there is a trade. |
| `flinch_knockback` / `knockback_decel` | 2.5 m/s / 14 m/s² | |
| `despawn_delay` | 3.0 s | Corpse lifetime |

The enemy animations (`windup`, `strike`, `recover`, `flinch`) are played time-scaled to these durations. Edit **poses** in `Enemy.tscn → AnimationPlayer` and **timing** in the `.tres`.

### Hit points and stamina (nodes)

| Where | Field | Value |
|---|---|---|
| `player/Player.tscn → Health` | `max_hp` | 100 |
| `enemy/Enemy.tscn → Health` | `max_hp` | 100 |
| `player/Player.tscn → Stamina` | `max_stamina` / `regen_per_second` / `regen_delay` | 100 / 25 / 0.6 s |

### Feel — `player/Player.tscn → Head/Camera3D/WeaponRig` (`weapon_rig.gd` exports)

| Group | Field | Value |
|---|---|---|
| Hit Feedback | `hitstop_time_scale` | 0.05 (`Engine.time_scale` during hitstop) |
| | `swing_kick_deg` | (-0.8, 0.9, 1.4) pitch/yaw/roll, on every swing |
| | `hit_kick_deg` | (-2.4, -1.2, -2.2), on a landed hit |
| | `kick_in_time` / `kick_out_time` | 0.035 / 0.2 s |
| | `impact_surface_offset` | 0.3 m (where particles spawn, in front of the target's center) |
| Block Impact | `block_shake_deg` / `block_shake_time` | 0.7° / 0.18 s |
| | `block_hitstop` | 0.035 s (set 0 to disable) |
| Bob & Sway | `bob_amplitude` | (0.01, 0.008) m at walk speed |
| | `bob_frequency` | 1.7 Hz at walk speed (scales with speed) |
| | `sway_per_pixel_speed` / `sway_max_deg` / `sway_smoothing` | 0.0025 °/(px/s) / 3.5° / 12 |
| Input | `attack_buffer_time` | 0.15 s. A click during a swing or block still swings when the rig frees up. 0 disables it. |

### Player — `player/Player.tscn` root (`player.gd` exports)

| Field | Value |
|---|---|
| `walk_speed` / `sprint_speed` / `block_speed` | 5.0 / 7.5 / 2.5 m/s |
| `acceleration` | 45 m/s² |
| `mouse_sensitivity` | 0.0022 rad/px |
| `pitch_limit_deg` | 85 |
| `lunge_duration` | 0.18 s (distance comes from `WeaponData.lunge_distance`) |
| `block_cone_dot` | 0.3 (≈145° cone) |
| `hurt_shake_deg` / `hurt_shake_time` | 1.2° / 0.25 s |
| `death_restart_delay` | 2.5 s |

### Other knobs

| Where | What |
|---|---|
| `Enemy.tscn` root → Hit Flash group | `flash_color` (white), `flash_fade_color` (red), `flash_time` 0.18 s |
| `Player.tscn → HUD` | `damage_flash_alpha` 0.35, `damage_flash_time` 0.35 s |
| `Player.tscn → WeaponRig/Hitbox/CollisionShape3D` | 0.6 × 0.5 × 1.4 m box at z = -0.85, so it reaches 1.55 m. The visible blade tip reaches about 1.3 m mid-swing, so the box is about 20% longer. |
| `Enemy.tscn → Hitbox/CollisionShape3D` | 1.0 × 1.3 × 1.3 m box at z = -1.05 (reaches 1.7 m) |
| `Player.tscn → WeaponRig/AnimationPlayer` | Sword poses for `swing`, `block_raise`, `block_lower`, `block_impact` |
| `Player.tscn → WeaponRig/HitSparks`, `HitSparks/HitPuff` | Particle amount, lifetime, process material |
| SFX nodes | `WhooshSfx` -6 dB, `ImpactSfx` 0 dB, `ClangSfx` -3 dB, `HurtSfx` -4 dB, enemy `SwingSfx` pitch 0.7, `DeathSfx` pitch 0.6 |
| `world/Torch.tscn` root | `light_energy` 2.0, `omni_range` 7.0, `flicker_amount` 0.15, `flicker_speed` 7 |
| `Main.tscn → Room/WorldEnvironment` | ambient 0.6, fog density 0.025 |

---

## How the pieces fit

- **Input:** only `PlayerIntent` touches `Input`. It runs at process and physics priority -1, so it samples before `Player`. Attack and restart are latched from input events, so a click can't be dropped between frames.
- **Damage:** everything goes through `take_hit(hit: HitInfo)`. `Player.take_hit` checks block and cone and only then calls `Health`. `Enemy.take_hit` flashes, applies damage, then decides on a flinch.
- **Hitboxes:** `MeleeHitbox.begin_swing()` / `end_swing()` are called only from AnimationPlayer method tracks. Besides `body_entered` it also sweeps `get_overlapping_bodies()` while active, because a body already inside the box when monitoring turns on doesn't reliably fire `body_entered`.
- **Hit feedback order** (`WeaponRig._on_hit_landed`): `take_hit` → cut the whoosh → thud → sparks and puff → camera kick → hitstop. Kick and shake tweens ignore time scale, so the camera punches during the freeze. The enemy flash runs on scaled time, so it holds at full white through the freeze.
- **Whiff vs hit audio:** the whoosh starts with every swing and is cut on contact, so a hit sounds like a thud and a miss like a whoosh.

### Collision layers

| Layer | Name | Who |
|---|---|---|
| 1 | world | CSG room |
| 2 | player | Player body (mask: world + enemy). Enemy hitbox masks this layer. |
| 3 | enemy | Enemy body (mask: world + player). Player hitbox masks this layer. |

Hitbox areas have no layer of their own.

### Palette

`art/palette/palette.png`: 64×32, 8 × 4 swatches of 8×8 px each. Index = row × 8 + column. It is imported lossless, without mipmaps or VRAM compression (see its `.import`), and every material uses nearest filtering.

The greybox primitives use one material per swatch, with `uv1_scale = 0` and `uv1_offset` set to the swatch center, so every UV lands on that swatch. Swatch center: u = (col + 0.5) / 8, v = (row + 0.5) / 4. For real UV-mapped models, use `art/materials/palette_base.tres` (UV scale 1) and map the UVs onto swatches in the modeling tool.

| Row | Columns 0 → 7 |
|---|---|
| 0 stone | `0e0c12` `1b1920` `2a272f` `3b3740` `514b55` `6d666e` `958c90` `c9c0b9` |
| 1 earth | `24170f` `3d2717` `5c3b20` `7f552c` `a8763e` `c99a5b` `e2c08a` `f2e2bf` |
| 2 fire | `2a080c` `4f1015` `84191c` `b8291f` `e05426` `f58b26` `ffc93d` `fff3c4` |
| 3 metal | `1a2329` `2e3d45` `4b6068` `7a8e94` `aab9bc` `dfe8e6` `3f5a2c` `ffffff` |

---

## Tools

On a fresh clone, open the editor once (or run `godot --headless --path . --import`) so the `class_name` cache exists before running anything headless.

| Command (from the project root) | What it does |
|---|---|
| `godot --headless --path . --script res://tools/generate_placeholder_assets.gd` | Regenerates the palette PNG and the synthesized placeholder SFX (deterministic) |
| `godot --headless --path . --script res://tools/combat_smoke_test.gd` | Drives the real scene with input events: walk in, eat a hit (100 → 85), block the next (stays 85), 4 swings kill the dummy, `time_scale` back to 1, corpse despawns. Exit code 0 means pass. |
| `godot --path . --script res://tools/capture_views.gd -- out.png` | Opens a window and renders a contact sheet of the viewmodel poses, the enemy tell and the hit FX |

---

## Decisions and deviations from the handoff

- **Camera kick goes on `Camera3D`, not `Head`.** Head holds mouse-look pitch, so tweening it would fight the look code. The camera's own rotation is otherwise unused, so kick and shake compose there.
- **`SwordMesh` is the grip.** Its mesh is the handle, with Blade, Guard and Pommel as children, so the animation rotates around the hand instead of the blade's center.
- **The enemy body is a small rig:** `Rig` → `Legs`, `Body` (pelvis) → Torso, Head, Eyes, both arms, Club. The `die` anim tips `Rig` over backward. Every mesh shares one local-to-scene overlay material for the hit flash.
- **Hit particles live on the WeaponRig** as a `top_level` GPUParticles3D that is moved and restarted per hit, so nothing gets instantiated.
- **Enemy stats are in an `EnemyData` resource**, following the content-as-resources rule. The handoff didn't name one.
- **Small additions:** a `walk` loop for the enemy, an R restart, auto-restart on player death, the 0.15 s attack buffer, a 0.035 s hitstop on block impact, and a billboard HP bar.
- **The block is active the moment RMB goes down.** `block_raise` is only cosmetic.
- **`untyped_declaration` is set to Error** in project settings, so the static-typing rule is enforced.

## Known limitations (step 2 candidates)

- The viewmodel is world-scale geometry on the camera, so it clips into the dummy at point-blank range and into walls. Fix with a viewmodel render layer or camera, or a depth-squash shader.
- The impact point is estimated from the camera ray and the target's position, not raycast against the mesh.
- The SFX are synthesized placeholders.
