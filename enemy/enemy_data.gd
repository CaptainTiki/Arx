class_name EnemyData
extends Resource
## Everything that makes one enemy type different from another; enemy.gd reads all its tuning from here.
## Animations are time-scaled to the durations below: poses live in Enemy.tscn, timing lives here.

@export_group("Body")
@export var display_name: String = "Grunt"
## Applied to the scene's Health node on ready.
@export var max_hp: int = 100
@export var move_speed: float = 3.0
## False = never staggers when hit (bruisers). Still takes damage and flashes.
@export var can_flinch: bool = true
## Uniform size of the whole rig and its collision capsule. Applied on ready.
@export var body_scale: float = 1.0
## Palette material for torso and arms so variants read at a glance. Null = keep the scene's burlap.
@export var body_material: Material

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
## Further standstill after RECOVER before the next WINDUP. Also no movement, no turning.
@export var cooldown_time: float = 1.5
## Meters stepped forward along the locked facing during STRIKE.
@export var strike_lunge: float = 0.9

@export_group("Tracking")
## Wakes up and starts chasing once the player is this close.
@export var aggro_range: float = 4.0
## Yaw rate while chasing, deg/s. High enough to read as "faces you directly".
@export var chase_turn_rate: float = 460.0
## Yaw rate during WINDUP, deg/s. Facing locks at STRIKE start.
@export var windup_turn_rate: float = 180.0
## How long TellFlash stays lit at windup start.
@export var tell_flash_time: float = 0.15

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
