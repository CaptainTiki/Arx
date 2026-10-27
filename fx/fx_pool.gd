class_name FxPool
extends Node3D
## Pre-placed one-shot particle pools. Each play_* call moves the next instance in its pool and
## restarts it, so nothing is instantiated at runtime. Grow a pool by adding children in Main.tscn.

@onready var _hit_puff_root: Node3D = %HitPuffs
@onready var _block_spark_root: Node3D = %BlockSparks

var _hit_puffs: Array[GPUParticles3D] = []
var _block_sparks: Array[GPUParticles3D] = []
var _next_hit_puff: int = 0
var _next_block_spark: int = 0


func _ready() -> void:
	_hit_puffs.assign(_hit_puff_root.get_children())
	_block_sparks.assign(_block_spark_root.get_children())


## Quiet debris where a blade connects, sprayed along the hit direction. `material` recolours it
## (fx_dust for a breakable); null = the scene's blood.
func play_hit_puff(pos: Vector3, dir: Vector3, material: Material = null) -> void:
	var puff: GPUParticles3D = _hit_puffs[_next_hit_puff]
	_next_hit_puff = (_next_hit_puff + 1) % _hit_puffs.size()
	puff.material_override = material
	puff.global_position = pos
	# look_at can't build a basis looking straight up or down; keep the last facing then.
	if dir.length_squared() > 0.0001 and absf(dir.normalized().y) < 0.99:
		puff.look_at(pos + dir, Vector3.UP)
	puff.restart()


## Big radial burst for an enemy strike landing on a raised block.
func play_block_spark(pos: Vector3) -> void:
	var spark: GPUParticles3D = _block_sparks[_next_block_spark]
	_next_block_spark = (_next_block_spark + 1) % _block_sparks.size()
	spark.global_position = pos
	spark.restart()
