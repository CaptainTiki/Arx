class_name Main
extends Node3D
## The loop. You start at camp. Turning the key at the gate builds a floor behind the door theatre;
## walking in and past the entrance room stows the camp; the far exit (or dying, or walking back
## out) puts you in the yard again and empties the castle. F5 / F6 still rebuild from camp for
## testing (F6 = same seed).

@onready var _generator: DungeonGenerator = %DungeonGenerator
@onready var _player: Player = %Player
@onready var _dungeon: Dungeon = %Dungeon
@onready var _camp: Camp = %Camp
@onready var _world_env: WorldEnvironment = %WorldEnvironment

var _dungeon_env: Environment
var _camp_shown: bool = true


func _ready() -> void:
	_dungeon_env = _world_env.environment
	_player.respawn_requested.connect(_on_respawn)
	_dungeon.player_cell_changed.connect(_on_player_cell)
	_camp.gate.key_turned.connect(_on_key_turned)
	_camp.gate.key_taken.connect(_on_key_taken)
	_show_camp(true)
	_player.place_at(_camp.arrival_gate.global_transform)
	_player.process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process(_delta: float) -> void:
	if _player.intent.regenerate_pressed:
		_debug_rebuild(0)
	elif _player.intent.regenerate_same_pressed:
		_debug_rebuild(_generator.last_seed)


## The key goes in: build the floor, then the chains and the door.
func _on_key_turned() -> void:
	_generator.generate()
	_camp.gate.open()


## The key comes out (only reachable from outside): shut the gate and empty the castle.
func _on_key_taken() -> void:
	_camp.gate.close()
	_generator.clear()


## Camp is up while you're outside or still in the entrance room; stowed once you're deeper.
func _on_player_cell(cell: Vector2i) -> void:
	var inside: bool = _dungeon.map != null and _dungeon.map.room_at(cell) != null
	var deep: bool = inside and not _dungeon.player_in_start_room()
	if deep and _camp_shown:
		_show_camp(false)
	elif not deep and not _camp_shown:
		_show_camp(true)
		_camp.gate.open(true)


## The floor is over. From the far exit you come up the garden stairs; otherwise (death) the gate.
func leave_castle(from_far_exit: bool) -> void:
	_generator.clear()
	_show_camp(true)
	_camp.gate.key_in_lock = false
	_camp.gate.close()
	var arrival: Marker3D = _camp.arrival_garden if from_far_exit else _camp.arrival_gate
	_player.place_at(arrival.global_transform)


func _on_respawn() -> void:
	leave_castle(false)
	_player.revive()


func _show_camp(shown: bool) -> void:
	_camp_shown = shown
	_camp.set_stowed(not shown)
	_world_env.environment = _camp.environment if shown else _dungeon_env


func _debug_rebuild(seed_value: int) -> void:
	_generator.generate(seed_value)
	_camp.gate.key_in_lock = true
	if not _camp.gate.is_open:
		_camp.gate.open()
