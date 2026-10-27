class_name EnemyData
extends Resource
## Everything that makes one enemy type different from another; enemy.gd reads all its tuning from here.
## Animations are time-scaled to the durations below: poses live in Enemy.tscn, timing lives here.

enum Behavior { MELEE, POUNCE, CHARGE }

@export_group("Body")
@export var display_name: String = "Grunt"
## Applied to the scene's Health node on ready.
@export var max_hp: int = 100
@export var move_speed: float = 3.0
## False = never staggers when hit (bruisers). Still takes damage and flashes.
@export var can_flinch: bool = true
## Light hits it takes before one staggers it (1 = every hit). Heavies always stagger. The count
## resets when it staggers and when it starts an attack, so it's "hits in a row", not a pool.
@export var poise: int = 1
## Uniform size of the whole rig and its collision capsule. Applied on ready.
@export var body_scale: float = 1.0
## Palette material for torso and arms so variants read at a glance. Null = keep the scene's burlap.
@export var body_material: Material
## Pitch of grunt / bark / death sounds, so you can hear which kind spotted you.
@export var voice_pitch: float = 1.0

@export_group("Attack")
## Starts WINDUP inside this distance (center to center).
@export var trigger_range: float = 1.8
## Hitbox length, measured forward from the enemy's center. Longer than trigger_range on purpose.
@export var attack_reach: float = 2.3
@export var damage: int = 15
## The readable tell. Don't shorten without a reason.
@export var windup_time: float = 0.7
## Hitbox window; the method keys in the `strike` animation sit just inside it.
@export var strike_time: float = 0.2
## Punish window: no movement, no turning, flinches when hit.
@export var recover_time: float = 0.8
## Further standstill after RECOVER before the next attack. Also no movement, no turning.
@export var cooldown_time: float = 1.5
## Meters stepped forward along the locked facing during STRIKE.
@export var strike_lunge: float = 1.4

@export_group("Tracking")
## Yaw rate while chasing or alerted, deg/s. High enough to read as "faces you directly".
@export var chase_turn_rate: float = 460.0
## Yaw rate during WINDUP and CROUCH, deg/s. Facing locks when the attack starts.
@export var windup_turn_rate: float = 180.0
## How long TellFlash stays lit at windup start.
@export var tell_flash_time: float = 0.15

@export_group("Perception")
@export var sight_range: float = 12.0
## Full view cone, degrees.
@export var sight_fov: float = 110.0
## Seconds without line of sight in CHASE before it gives up and SEARCHes.
@export var lose_sight_time: float = 3.0
## Multiplier on every noise radius (6c).
@export var hearing: float = 1.0
## Once aware, it senses you inside this distance even outside its cone (still needs line of sight),
## so circling behind an enemy that's fighting you doesn't make it forget you. Unaware enemies only see in the cone.
@export var aware_sense_range: float = 2.5
## The "huh?" beat: turns to the sight/noise and barks before chasing or investigating.
@export var alert_time: float = 0.4
## IDLE look-around: yaw swing either side of its resting facing, and one full sweep's duration.
@export var idle_look_angle: float = 40.0
@export var idle_look_period: float = 4.0
## SEARCH: walk speed as a fraction of move_speed, time spent looking around where you were,
## how close counts as "got there", and how long it tries to reach a spot before moving on.
@export var search_speed_mult: float = 0.6
@export var search_look_time: float = 2.0
@export var search_arrive_distance: float = 0.6
@export var search_give_up_time: float = 6.0

@export_group("Behavior")
## How it opens a fight: MELEE always walks in and swings; POUNCE leaps from mid-range; CHARGE rushes from afar.
@export var behavior: Behavior = Behavior.MELEE

@export_subgroup("Pounce")
@export var pounce_crouch_time: float = 0.4
## A hit or a block while it's in the air knocks it down: it drops where it is and lies in RECOVER.
@export var pounce_swattable: bool = true
## Push speed on a swat, m/s, away from the player.
@export var swat_knockback: float = 3.0
## Launches when within this distance...
@export var pounce_range: float = 5.0
## ...but closer than this it does its normal WINDUP/STRIKE bite instead.
@export var pounce_min_range: float = 2.0
## Horizontal speed of the leap, m/s.
@export var pounce_speed: float = 9.0
## Peak height of the leap, meters.
@export var pounce_arc: float = 1.2
## Rig height while crouched, as a fraction of its standing height.
@export var pounce_squash: float = 0.6

@export_subgroup("Charge")
## Charges if farther than this; closer, it walks in and swipes.
@export var charge_min_range: float = 4.0
@export var charge_windup: float = 0.6
@export var charge_speed: float = 7.0
## Turn rate while charging, deg/s. Slow, so a sidestep works and standing still doesn't.
@export var charge_turn_rate: float = 60.0
@export var charge_max_time: float = 2.5
## Hitbox length while charging. Shorter than attack_reach so the hit lands on contact, not 3 m out.
@export var charge_hit_reach: float = 1.3
## Player speed multiplier and duration applied by a charge that connects (not blocked).
@export var charge_slow_mult: float = 0.5
@export var charge_slow_time: float = 1.5
## Head-on-ness needed to count a wall bump as a wall hit (dot of wall normal and -charge direction).
@export var charge_wall_dot: float = 0.5
## Dazed after running into a wall: the punish window. Hits flinch it but don't end the stun.
@export var wall_stun_time: float = 2.0

@export_group("Noise")
## Radius of the noise it makes when hit (its grunt), before listeners' hearing.
@export var hurt_noise_radius: float = 7.0
## Radius of the roar at charge windup.
@export var roar_noise_radius: float = 12.0

@export_group("Loot")
## Rolled drop_rolls times where it dies (Dungeon.drop_loot). Null = drops nothing.
@export var drop_table: SpawnTable
@export var drop_rolls: int = 1

@export_group("Reactions")
@export var flinch_time: float = 0.3
## Push speed on flinch, m/s, along the hit direction.
@export var flinch_knockback: float = 2.5
## How fast flinch knockback bleeds off, m/s².
@export var knockback_decel: float = 14.0
## Seconds the corpse stays before queue_free.
@export var despawn_delay: float = 3.0

@export_group("Hit Flash")
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var flash_fade_color: Color = Color(1.0, 0.15, 0.1, 0.55)
## Seconds from flash_color to flash_fade_color.
@export var flash_time: float = 0.07
## Seconds from flash_fade_color to transparent.
@export var flash_fade_time: float = 0.11
