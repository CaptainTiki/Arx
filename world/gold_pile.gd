class_name GoldPile
extends Area3D
## Coins on the floor. Walk over them and they're yours: no prompt, a ting, gone. Gold is a counter
## on the Inventory, never a bag item. Dungeon.drop_loot places these from a table row's gold range.

@export var amount: int = 1

@onready var _sfx: AudioStreamPlayer3D = %TingSfx
@onready var _coins: Node3D = %Coins
@onready var _shape: CollisionShape3D = %Shape

var _taken: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Bigger piles are bigger.
	var scale_factor: float = clampf(0.6 + amount / 40.0, 0.6, 1.6)
	_coins.scale = Vector3.ONE * scale_factor


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body is Player:
		return
	_taken = true
	(body as Player).inventory.add_gold(amount)
	_shape.set_deferred(&"disabled", true)
	_coins.visible = false
	_sfx.play()
	_sfx.finished.connect(queue_free)
