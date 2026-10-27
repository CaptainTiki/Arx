class_name Pickup
extends StaticBody3D
## An item lying on the floor. Taking it moves it into the bag and frees this pickup. With a full
## bag it flips in place and says no.

@export var item: ItemData
@export_group("Reject")
## Seconds for the half-turn out and back.
@export var reject_time: float = 0.25
## How high it hops while flipping, in meters.
@export var reject_hop: float = 0.15

@onready var _flip: Node3D = %Flip
@onready var _mesh: MeshInstance3D = %Mesh
@onready var _shape: CollisionShape3D = %InteractShape
@onready var _nope_sfx: AudioStreamPlayer3D = %NopeSfx

var _reject_tween: Tween
var _glow: OmniLight3D
var _sparkles: CPUParticles3D

## Sparkle count and opacity per rarity: louder the rarer. Colour alone doesn't read for everyone.
const SPARKLE_COUNT: Array[int] = [0, 10, 24, 48]
const SPARKLE_ALPHA: Array[float] = [0.0, 0.45, 0.8, 1.0]
const GLOW_ENERGY: Array[float] = [0.0, 0.35, 0.5, 0.7]


func _ready() -> void:
	set_item(item)


func interact(player: Player) -> void:
	if item == null:
		return
	if player.inventory.try_add(item):
		queue_free()
	else:
		reject()
		player.notify_inventory_full()


## The "bag full" tell: a half turn around Y and back with a little hop, plus a dull nope.
func reject() -> void:
	if _reject_tween:
		_reject_tween.kill()
	_flip.rotation.y = 0.0
	_flip.position.y = 0.0
	var half: float = reject_time * 0.5
	_reject_tween = create_tween()
	_reject_tween.tween_property(_flip, "rotation:y", PI, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.parallel().tween_property(_flip, "position:y", reject_hop, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.tween_property(_flip, "rotation:y", 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_reject_tween.parallel().tween_property(_flip, "position:y", 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_nope_sfx.play()


func is_rejecting() -> bool:
	return _reject_tween != null and _reject_tween.is_running()


## Swaps the resource and refreshes the mesh. Null empties the pickup (hidden, ray can't hit it).
func set_item(new_item: ItemData) -> void:
	item = new_item
	var has_item: bool = item != null
	visible = has_item
	_shape.set_deferred(&"disabled", not has_item)
	_mesh.mesh = item.world_mesh if has_item else null
	_rest_on_floor()
	# Magic and better: a soft coloured light plus sparkles rising off it; more and brighter the
	# rarer, so the tier reads from the motion even if the colour doesn't.
	if has_item and item.is_rolled():
		if _glow == null:
			_glow = OmniLight3D.new()
			_glow.omni_range = 1.8
			_glow.position.y = 0.3
			add_child(_glow)
		_glow.light_color = item.rarity_color()
		_glow.light_energy = GLOW_ENERGY[item.rarity]
		_glow.visible = true
		if _sparkles == null:
			_sparkles = _make_sparkles()
			add_child(_sparkles)
		_sparkles.amount = SPARKLE_COUNT[item.rarity]
		var tint: Color = item.rarity_color()
		tint.a = SPARKLE_ALPHA[item.rarity]
		_sparkles.color = tint
		_sparkles.emitting = true
		_sparkles.visible = true
	else:
		if _glow:
			_glow.visible = false
		if _sparkles:
			_sparkles.emitting = false
			_sparkles.visible = false


func _make_sparkles() -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.035, 0.035, 0.035)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	p.lifetime = 1.4
	p.one_shot = false
	p.explosiveness = 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0.0, 0.25, 0.0)
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.position.y = 0.05
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return p


func prompt_text() -> String:
	return "Take %s" % item.display_name if item else ""


## Centers the item over the pickup and sits it on the ground, whatever its size.
## The Mesh node's authored rotation lays the upright world_mesh flat.
func _rest_on_floor() -> void:
	if _mesh.mesh == null:
		return
	var bounds: AABB = Transform3D(_mesh.basis, Vector3.ZERO) * _mesh.mesh.get_aabb()
	var center: Vector3 = bounds.get_center()
	_mesh.position = Vector3(-center.x, -bounds.position.y, -center.z)
