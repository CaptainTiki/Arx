class_name ShieldData
extends ItemData
## Offhand shield. Rests low and to the side so it covers almost none of the screen; right-click
## brings it up in front, top edge around the bottom fifth. The view mesh is the ShieldPivot
## authored in Player.tscn (one look for now); these numbers pose it and price the block.

@export_group("Block")
## Stamina a shielded block spends per point of damage, as a fraction of the bare-weapon cost.
@export var block_cost_mult: float = 0.4
## Facing dot above which a hit is covered. Lower = wider than a weapon's parry cone.
@export var block_cone_dot: float = 0.0

@export_group("View")
## Rig-space pose at rest (m / deg): low left, turned mostly edge-on.
@export var rest_offset: Vector3 = Vector3(-0.42, -0.5, -0.45)
@export var rest_rotation: Vector3 = Vector3(-5.0, 70.0, 15.0)
## Pose while blocking: square in front, low.
@export var block_offset: Vector3 = Vector3(0.0, -0.5, -0.5)
@export var block_rotation: Vector3 = Vector3(10.0, 0.0, 0.0)
@export var raise_time: float = 0.12
@export var lower_time: float = 0.18
