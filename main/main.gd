class_name Main
extends Node3D
## Builds a dungeon on start, then lets the player loose. F5 rebuilds it with a fresh seed.

@onready var _generator: DungeonGenerator = %DungeonGenerator
@onready var _player: Player = %Player


func _ready() -> void:
	_generator.generate()
	_player.process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process(_delta: float) -> void:
	if _player.intent.regenerate_pressed:
		_generator.generate()
