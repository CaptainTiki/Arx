class_name EnemyData
extends Resource
## Enemy behaviour and timing. Animations are time-scaled to fit these durations.
## Hit points live on the scene's Health node (max_hp).

@export var display_name: String = "Training Dummy"

@export_group("Movement")
@export var move_speed: float = 3.0
## Yaw rate while chasing, in rad/s.
@export var turn_speed: float = 8.0
## Yaw rate while winding up. Low, so sidestepping the tell is possible.
@export var windup_turn_speed: float = 2.5
## Starts chasing once the player is this close.
@export var aggro_range: float = 4.0
## Stops and starts an attack within this distance (center to center).
@export var attack_range: float = 1.8

@export_group("Attack")
@export var damage: int = 15
## The readable tell. Don't shorten without a reason.
@export var windup_time: float = 0.7
## How long TellFlash stays lit at windup start.
@export var tell_flash_time: float = 0.15
## Hitbox window; method keys in the `strike` animation sit just inside it.
@export var strike_time: float = 0.2
## Punish window: no movement, no turning, flinches when hit.
@export var recover_time: float = 0.8
## Delay after RECOVER ends before the next WINDUP can start.
@export var attack_cooldown: float = 1.5

@export_group("Reactions")
@export var flinch_time: float = 0.3
## Push speed on flinch, in m/s, along the hit direction.
@export var flinch_knockback: float = 2.5
## How fast flinch knockback bleeds off, in m/s².
@export var knockback_decel: float = 14.0
## Seconds the corpse stays before queue_free.
@export var despawn_delay: float = 3.0
