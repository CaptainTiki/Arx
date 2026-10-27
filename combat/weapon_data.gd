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

@export_group("Heavy")
## Every swing fires on release. Hold and the weapon draws back; the longer the hold (up to
## heavy_charge_time), the more of the heavy you get. Below heavy_threshold of a full charge it's
## just a light. From the threshold up, damage, hitstop, kick and swing time scale from the light's
## values to the full heavy's with the charge fraction, and it staggers through poise.
@export var heavy_damage_mult: float = 2.5
@export var heavy_stamina_cost: int = 30
## Seconds of hold for a full charge.
@export var heavy_charge_time: float = 0.6
## Fraction of a full charge below which the release is a light.
@export_range(0.0, 1.0) var heavy_threshold: float = 0.75
## Held this long past a full charge, it lets go on its own.
@export var heavy_auto_release: float = 0.8
## The heavy swing plays this much slower than the light: a slower, bigger arc.
@export var heavy_swing_time_mult: float = 1.2
@export var heavy_hitstop: float = 0.11

@export_group("Viewmodel")
## First-person mesh. Origin = grip, long axis +Y.
@export var view_mesh: Mesh
## Per-weapon nudge of the whole viewmodel (rig space, meters). Shifts the entire swing path.
@export var view_offset: Vector3 = Vector3.ZERO
## Per-weapon rotation nudge of the whole viewmodel, in degrees.
@export var view_rotation: Vector3 = Vector3.ZERO


func _init() -> void:
	slot = Slot.WEAPON
