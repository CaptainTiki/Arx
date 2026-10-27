class_name Breakable
extends StaticBody3D
## A crate, pot or barrel. Hit it like an enemy: it's on the enemy layer, so the sword's hitbox finds
## it (look down at it: the hitbox hangs off the camera), and the rig's hitstop and camera kick fire
## as for any hit. It's on the world layer too, so enemies and the drop ray stop at it like a wall,
## instead of walking through it or dropping loot inside it. The hit that takes its last hp
## shatters it: the intact Mesh hides, the pre-placed Debris pieces fly away from the swing, a dust
## puff bursts, it cracks, makes noise and drops its loot. The collider goes at once so you can walk
## through the spot; the body frees itself once the pieces have shrunk away.
## Crate, Pot and Barrel are inherited scenes of Breakable.tscn: same nodes, own meshes and table.

@export var drop_table: SpawnTable
@export var drop_rolls: int = 1
## Damage it takes to break. 1 = any hit.
@export var hp: int = 1
@export var break_noise_radius: float = 6.0
## Noise and loot go through here. Set by the generator; null = the Dungeon above it (a breakable
## placed by hand in a room scene).
@export var dungeon: Dungeon

@export_group("Shatter")
## The swing's hit puff turns this colour, and so does the burst at the middle when it breaks.
@export var dust_material: Material
## Seconds each piece is in the air.
@export var fling_time: float = 0.4
## How far each piece lands from where it started, meters, along the swing.
@export var fling_distance_min: float = 0.6
@export var fling_distance_max: float = 1.4
## Height of each piece's arc above a straight line to where it lands.
@export var fling_height: float = 0.5
## Each piece's heading is the swing direction turned up to this many degrees either way.
@export var fling_spread_deg: float = 40.0
## How much a piece also heads outward from the middle (0 = straight along the swing).
@export var fling_outward: float = 0.5
## Seconds the pieces lie on the floor, then how long they take to shrink away.
@export var debris_linger: float = 2.0
@export var debris_fade_time: float = 0.3

@onready var _shape: CollisionShape3D = %CollisionShape3D
@onready var _mesh: Node3D = %Mesh
@onready var _debris: Node3D = %Debris
@onready var _break_sfx: AudioStreamPlayer3D = %BreakSfx

var _broken: bool = false


func _ready() -> void:
	if dungeon == null:
		dungeon = Dungeon.find_above(self)


func take_hit(hit: HitInfo) -> void:
	if _broken:
		return
	hit.puff_material = dust_material
	hp -= hit.damage
	if hp <= 0:
		hit.muffle_thud = true
		_shatter(hit)


func is_broken() -> bool:
	return _broken


func _shatter(hit: HitInfo) -> void:
	_broken = true
	_shape.set_deferred(&"disabled", true)
	var away: Vector3 = Vector3(hit.direction.x, 0.0, hit.direction.z).normalized()
	if away.is_zero_approx():
		away = -global_basis.z
	var center: Vector3 = _shape.global_position
	_mesh.visible = false
	_debris.visible = true
	for child: Node in _debris.get_children():
		_fling(child as Node3D, away, center)
	var player: Player = hit.source as Player
	if player and player.fx:
		player.fx.play_hit_puff(center, away + Vector3.UP * 0.5, dust_material)
	_break_sfx.play()
	if dungeon:
		dungeon.emit_noise(global_position, break_noise_radius)
		dungeon.drop_loot(drop_table, global_position, null, drop_rolls, scene_file_path.get_file().get_basename().to_lower())
	await get_tree().create_timer(fling_time + debris_linger + debris_fade_time).timeout
	queue_free()


## One ballistic hop away from the swing (straight-line flight plus a parabola, so it falls like
## it has weight), tumbling end over end to land flat, then a linger and a shrink.
func _fling(piece: Node3D, away: Vector3, center: Vector3) -> void:
	var from: Vector3 = piece.global_position
	var outward: Vector3 = Vector3(from.x - center.x, 0.0, from.z - center.z)
	var heading: Vector3 = (away + outward.normalized() * fling_outward).normalized()
	heading = heading.rotated(Vector3.UP, deg_to_rad(randf_range(-fling_spread_deg, fling_spread_deg)))
	var to: Vector3 = from + heading * randf_range(fling_distance_min, fling_distance_max)
	to.y = global_position.y + _rest_height(piece)
	# Whole half turns about X and Z, so it ends lying flat whichever way up.
	var spin: Vector3 = Vector3(PI * randi_range(-2, 2), piece.rotation.y + randf_range(-PI, PI), PI * randi_range(-1, 1))
	var tween: Tween = create_tween()
	tween.tween_method(_arc.bind(piece, from, to), 0.0, 1.0, fling_time)
	tween.parallel().tween_property(piece, "rotation", spin, fling_time)
	tween.tween_interval(debris_linger)
	tween.tween_property(piece, "scale", Vector3.ONE * 0.01, debris_fade_time).set_ease(Tween.EASE_IN)
	tween.tween_callback(piece.hide)


func _arc(t: float, piece: Node3D, from: Vector3, to: Vector3) -> void:
	var at: Vector3 = from.lerp(to, t)
	at.y += fling_height * 4.0 * t * (1.0 - t)
	piece.global_position = at


## Half the piece's thickness along its own Y: lying flat, that's how high its middle sits.
static func _rest_height(piece: Node3D) -> float:
	var mesh_instance: MeshInstance3D = piece as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return 0.0
	return mesh_instance.mesh.get_aabb().size.y * 0.5 * piece.scale.y
