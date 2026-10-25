class_name WeaponData
extends Resource
## Melee weapon stats. Timings are in seconds of real swing time.

@export var display_name: String = "Rusty Sword"
@export var damage: int = 25
@export var stamina_cost: int = 10
## Total swing length. The `swing` animation is time-scaled to match.
@export var swing_time: float = 0.45
## Hitbox on. Written into the swing animation's method track at startup.
@export var active_start: float = 0.12
## Hitbox off. Written into the swing animation's method track at startup.
@export var active_end: float = 0.28
## Forward step during the swing, in meters.
@export var lunge_distance: float = 0.6
## Freeze-frame length on a landed hit, in real seconds.
@export var hitstop: float = 0.05
