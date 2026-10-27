class_name Chest
extends StaticBody3D
## A chest on the floor. E opens it, once: the lid swings up, the glint dies, and with the lid up
## the loot spills onto the floor in front of it (Dungeon.drop_loot). No loot window. It stays where
## it is, lid open, as a landmark. Its front is -Z, so point its CHEST spawn marker into the room.
## Opening goes through Player's interact, so the step-2 rule holds: not mid-swing, not blocking.

@export var data: ChestData
## Where the loot goes and what rolls it. Set by the generator; null = the Dungeon above it (a chest
## placed by hand in a room scene).
@export var dungeon: Dungeon
## Loot lands this far in front of the chest's middle, then scatters. 0.9 keeps the widest scatter
## (Dungeon.drop_scatter_max) clear of its 0.29 m front face.
@export var spill_distance: float = 0.9
## Seconds after the lid is fully up before the loot spills. Raise it (0.2) if the spill comes too
## fast to see the lid open.
@export var spill_delay: float = 0.0

var opened: bool = false

@onready var _lid_mesh: MeshInstance3D = %LidMesh
@onready var _anim: AnimationPlayer = %AnimationPlayer
@onready var _open_sfx: AudioStreamPlayer3D = %OpenSfx


func _ready() -> void:
	if dungeon == null:
		dungeon = Dungeon.find_above(self)
	if data and data.lid_material:
		_lid_mesh.material_override = data.lid_material


func interact(_player: Player) -> void:
	if opened:
		return
	opened = true
	_anim.play(&"open")
	_open_sfx.play()
	await _anim.animation_finished
	if spill_delay > 0.0:
		await get_tree().create_timer(spill_delay).timeout
	_spill()


func prompt_text() -> String:
	return "" if opened or data == null else "Open %s" % data.display_name


func _spill() -> void:
	if dungeon == null or data == null:
		return
	var rolls: int = dungeon.loot_rng.randi_range(data.drop_rolls_min, maxi(data.drop_rolls_min, data.drop_rolls_max))
	var front: Vector3 = -global_basis.z
	front.y = 0.0
	dungeon.drop_loot(data.drop_table, global_position + front.normalized() * spill_distance, null, rolls, SpawnEntry.payload_name(data))
