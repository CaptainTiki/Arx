class_name Main
extends Node3D
## The loop. You start at camp. Turning the key at the gate builds a floor behind the door theatre.
## Step past the entrance room and the door shuts behind you, daylight fades to torchlight, and the
## camp is stowed (the gate itself is handed to the dungeon first, so it stays in the wall). Come
## back to the entrance room and it all comes back. The far exit, dying, or walking out and taking
## the key empties the castle. F5 / F6 rebuild from camp for testing (F6 = same seed).

## Seconds the stow waits after the door starts closing, so you hear it shut first.
@export var stow_delay: float = 2.2
## Rooms added per frame while the chains rattle.
@export var rooms_per_frame: int = 6

@onready var _generator: DungeonGenerator = %DungeonGenerator
@onready var _player: Player = %Player
@onready var _dungeon: Dungeon = %Dungeon
@onready var _camp: Camp = %Camp
@onready var _world_env: WorldEnvironment = %WorldEnvironment

var _deep: bool = false
var _stow_timer: SceneTreeTimer
## Frame-time watch while the gate opens: prints the worst frames and when they landed.
var _watching: bool = false
var _watch_start: int = 0
var _watch_frames: Array[Vector2] = []


func _ready() -> void:
	_world_env.environment = _camp.environment
	_player.respawn_requested.connect(_on_respawn)
	_dungeon.player_cell_changed.connect(_on_player_cell)
	_camp.gate.key_turned.connect(_on_key_turned)
	_camp.gate.key_taken.connect(_on_key_taken)
	_player.place_at(_camp.arrival_gate.global_transform)
	_player.process_mode = Node.PROCESS_MODE_INHERIT


func _process(delta: float) -> void:
	if _watching:
		var ms: float = delta * 1000.0
		if ms > 25.0:
			_watch_frames.append(Vector2((Time.get_ticks_usec() - _watch_start) / 1000.0, ms))


func _start_watch() -> void:
	_watching = true
	_watch_start = Time.get_ticks_usec()
	_watch_frames.clear()


func _stop_watch(label: String) -> void:
	_watching = false
	var parts: PackedStringArray = []
	for f: Vector2 in _watch_frames:
		parts.append("%.0fms frame at +%.0fms" % [f.y, f.x])
	print("Frame watch (%s): %s" % [label, ", ".join(parts) if not parts.is_empty() else "no frame over 25 ms"])


func _physics_process(_delta: float) -> void:
	if _player.intent.regenerate_pressed:
		_debug_rebuild(0)
	elif _player.intent.regenerate_same_pressed:
		_debug_rebuild(_generator.last_seed)


## The key goes in: chains start, the floor goes in over frames behind them, then the door opens.
func _on_key_turned() -> void:
	_start_watch()
	_camp.gate.begin_open()
	await _generator.generate_async(0, rooms_per_frame)
	print("  floor ready at +%.0fms" % ((Time.get_ticks_usec() - _watch_start) / 1000.0))
	_camp.gate.finish_open()
	await get_tree().create_timer(4.0).timeout
	_stop_watch("key turn → 4 s")


## The key comes out (only reachable from outside): shut the gate and empty the castle.
func _on_key_taken() -> void:
	_camp.gate.close()
	_generator.clear()


## Past the entrance room = deep: door shuts, light fades, camp stows. Back in it = all undone.
func _on_player_cell(cell: Vector2i) -> void:
	var inside: bool = _dungeon.map != null and _dungeon.map.room_at(cell) != null
	var deep: bool = inside and not _dungeon.player_in_start_room()
	if deep == _deep:
		return
	_deep = deep
	if deep:
		_camp.hand_gate_to(_dungeon)
		_camp.gate.close()
		_stow_timer = get_tree().create_timer(stow_delay)
		_stow_timer.timeout.connect(_finish_stow)
	else:
		_stow_timer = null
		_camp.set_stowed(false)
		_camp.hand_gate_to(_camp)
		_camp.gate.open()


func _finish_stow() -> void:
	if _deep and _stow_timer and _stow_timer.time_left <= 0.0:
		_camp.set_stowed(true)


## The floor is over. From the far exit you come up the garden stairs; otherwise (death) the gate.
func leave_castle(from_far_exit: bool) -> void:
	_deep = false
	_stow_timer = null
	_camp.set_stowed(false)
	_camp.hand_gate_to(_camp)
	_generator.clear()
	_camp.gate.key_in_lock = false
	_camp.gate.close()
	var arrival: Marker3D = _camp.arrival_garden if from_far_exit else _camp.arrival_gate
	_player.place_at(arrival.global_transform)


func _on_respawn() -> void:
	leave_castle(false)
	_player.revive()


func _debug_rebuild(seed_value: int) -> void:
	_camp.gate.key_in_lock = true
	if not _camp.gate.is_open:
		_camp.gate.begin_open()
	await _generator.generate_async(seed_value, rooms_per_frame)
	_camp.gate.finish_open()
