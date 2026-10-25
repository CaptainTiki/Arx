# Step 1 / 1.1 — One Room, One Enemy, Swing & Block

Open in Godot 4.7, press F5. Main scene: `res://main/Main.tscn`.

**Controls:** WASD move · Shift sprint · LMB swing · RMB block (hold) · R restart · Esc frees the mouse (click to recapture).

The grunt wakes up when you get within 4 m. It walks in, rears back with a red flash and a grunt (0.7 s, turning at most 180°/s to follow you), then lunges 0.9 m into the smash. After that it stands still, without turning, for 0.8 s of recovery plus a 1.5 s cooldown. Block the smash, release, and hit it 4 times.

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

### Weapon — `weapons/rusty_sword.tres` (`WeaponData`)

| Field | Value | Notes |
|---|---|---|
| `damage` | 25 | 4 hits kills the 100 HP grunt |
| `stamina_cost` | 10 | ≈10 swings per bar |
| `swing_time` | 0.45 s | The `swing` animation is time-scaled to this |
| `active_start` / `active_end` | 0.12 / 0.28 s | **Written into the swing anim's method-track keys at startup** (`WeaponRig._apply_weapon_timing`). Edit them here; key times edited in the AnimationPlayer get overwritten. |
| `lunge_distance` | 0.6 m | Forward step on swing start |
| `hitstop` | 0.05 s | Real-time freeze on a landed hit |

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
| `fx` | `Main/FX`, set in `Main.tscn`. Leave empty to run Player.tscn alone, without particles. |
| `walk_speed` / `sprint_speed` / `block_speed` | 5.0 / 7.5 / 2.5 m/s |
| `acceleration` | 45 m/s² |
| `mouse_sensitivity` | 0.0022 rad/px |
| `pitch_limit_deg` | 85 |
| `lunge_duration` | 0.18 s (distance comes from `WeaponData.lunge_distance`) |
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
| `Player.tscn → WeaponRig/Hitbox/CollisionShape3D` | 0.6 × 0.5 × 1.4 m box at z = -0.85, so it reaches 1.55 m. The visible blade tip reaches about 1.3 m mid-swing, so the box is about 20% longer. |
| `Player.tscn → WeaponRig/AnimationPlayer` | Sword poses for `swing`, `block_raise`, `block_lower`, `block_impact` |
| SFX nodes | `WhooshSfx` -6 dB, `ImpactSfx` 0 dB, `ClangSfx` -3 dB, `HurtSfx` -4 dB, enemy `SwingSfx` pitch 0.7, `DeathSfx` pitch 0.6 |
| `world/Torch.tscn` root | `light_energy` 2.0, `omni_range` 7.0, `flicker_amount` 0.15, `flicker_speed` 7 |
| `Main.tscn → Room/WorldEnvironment` | ambient 0.6, fog density 0.025 |

---

## How the pieces fit

- **Input:** only `PlayerIntent` touches `Input`. It runs at process and physics priority -1, so it samples before `Player`. Attack and restart are latched from input events, so a click can't be dropped between frames.
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

Hitbox areas have no layer of their own. The enemy hitbox's `BoxShape3D` is `resource_local_to_scene`, so resizing it from `attack_reach` doesn't leak into other enemy instances.

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

---

## Tools

On a fresh clone, open the editor once (or run `godot --headless --path . --import`) so the `class_name` cache exists before running anything headless.

| Command (from the project root) | What it does |
|---|---|
| `godot --headless --path . --script res://tools/generate_placeholder_assets.gd` | Regenerates the palette PNG and the synthesized placeholder SFX (deterministic) |
| `godot --headless --path . --script res://tools/combat_smoke_test.gd` | Drives the real scene with input events. It checks that the data is applied on ready, that you take a hit and the lunge covers `strike_lunge`, a successful block, the windup turn cap, facing and position locked through RECOVER/COOLDOWN, that hit-and-back-off gets caught, that an early retreat escapes, and a punish to the kill with `time_scale` restored. Exit code 0 means pass. |
| `godot --path . --script res://tools/capture_views.gd -- out.png` | Opens a window and renders a contact sheet: viewmodel poses, enemy tell, hit puff and block spark |

---

## Decisions and deviations from the handoffs

- **Camera kick goes on `Camera3D`, not `Head`.** Head holds mouse-look pitch, so tweening it would fight the look code. The camera's own rotation is otherwise unused, so kick and shake compose there.
- **`SwordMesh` is the grip.** Its mesh is the handle, with Blade, Guard and Pommel as children, so the animation rotates around the hand instead of the blade's center.
- **The enemy body is a small rig:** `Rig` → `Legs`, `Body` (pelvis) → Torso, Head, Eyes, both arms, Club. The `die` anim tips `Rig` over backward. Every mesh shares one local-to-scene overlay material for the hit flash.
- **`EnemyData` has more than the 1.1 spec.** `aggro_range`, `chase_turn_rate`, the flinch, knockback and despawn values, and the hit-flash colors and timings moved in too, so `enemy.gd` has no tuning numbers left.
- **COOLDOWN is its own state** rather than a timer inside CHASE. That makes "no tracking, no movement" explicit, and it shows up in `get_state_name()` for debugging.
- **Player owns the `fx` reference** (`@export var fx: FxPool`, wired in `Main.tscn`). WeaponRig reaches it through the player, because a nested node inside an instanced scene can't be wired cleanly from Main.
- **Small additions from step 1:** a `walk` loop for the enemy, an R restart, auto-restart on player death, the 0.15 s attack buffer, a 0.035 s hitstop on block impact, and a billboard HP bar.
- **The block is active the moment RMB goes down.** `block_raise` is only cosmetic.
- **`untyped_declaration` is set to Error** in project settings, so the static-typing rule is enforced.

## Known limitations (step 2 candidates)

- The viewmodel is world-scale geometry on the camera, so it clips into the grunt at point-blank range and into walls. With `strike_lunge` this happens after every strike. Fix with a viewmodel render layer or camera, or a depth-squash shader.
- The hit-puff contact point is the hitbox/body midpoint. Within about 1 m it lands inside the body.
- The SFX are synthesized placeholders.
