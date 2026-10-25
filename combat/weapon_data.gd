class_name WeaponData
extends ItemData
## Melee weapon: everything that makes one weapon feel different. WeaponRig.equip() applies all of it.
## Timings are in seconds of real swing time.

@export_group("Swing")
@export var damage: int = 25
@export var stamina_cost: int = 10
## Total swing length. The normalized 1 s `swing` clip plays at speed 1 / swing_time.
@export var swing_time: float = 0.45
## Hitbox on. Written into the swing clip's method key at active_start / swing_time on equip.
@export var active_start: float = 0.12
## Hitbox off. Written into the swing clip's method key at active_end / swing_time on equip.
@export var active_end: float = 0.28
## Forward step during the swing, in meters. Spread from swing start to the middle of the active window.
@export var lunge_distance: float = 0.6
## Freeze-frame length on a landed hit, in real seconds.
@export var hitstop: float = 0.05
## Hitbox length forward from its authored back edge.
@export var attack_reach: float = 1.4

@export_group("Viewmodel")
## First-person mesh. Origin = grip, long axis +Y.
@export var view_mesh: Mesh
## Per-weapon nudge of the whole viewmodel (rig space, meters). Shifts the entire swing path.
@export var view_offset: Vector3 = Vector3.ZERO
## Per-weapon rotation nudge of the whole viewmodel, in degrees.
@export var view_rotation: Vector3 = Vector3.ZERO


func _init() -> void:
	slot = Slot.WEAPON
