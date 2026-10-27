class_name ItemData
extends Resource
## Base for anything that can lie on the floor and be picked up. Slot decides where it goes when taken.

enum Slot { WEAPON, HEAD, CHEST, HANDS, FEET, RING, TRINKET, OFFHAND }

@export var display_name: String
@export var slot: Slot
## Inventory/paper-doll icon (step 5). Placeholder 32×32 for now.
@export var icon: Texture2D
## How it looks on the floor. Built upright (long axis +Y); Pickup lays it flat and rests it on the ground.
@export var world_mesh: Mesh
