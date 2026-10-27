class_name Gate
extends StaticBody3D
## The castle gate: portcullis and a wooden door in the wall. Interact once to turn the key (Main
## builds the floor; this plays the theatre: chains, the portcullis lifts, the door swings in).
## Interact again from outside to take the key back, which shuts everything and empties the castle.
## The key itself is a plain flag until items v2 makes it an item.

signal key_turned
signal key_taken

@export var portcullis_lift: float = 3.6
@export var portcullis_time: float = 2.4
@export var door_open_deg: float = -105.0
@export var door_time: float = 1.1
## Seconds between chain clanks while the portcullis moves.
@export var chain_interval: float = 0.28

var key_in_lock: bool = false
var is_open: bool = false

@onready var _portcullis: Node3D = %Portcullis
@onready var _door_hinge: Node3D = %DoorHinge
@onready var _chain_sfx: AudioStreamPlayer3D = %ChainSfx
@onready var _door_sfx: AudioStreamPlayer3D = %DoorSfx
@onready var _thud_sfx: AudioStreamPlayer3D = %ThudSfx

var _tween: Tween


func prompt_text() -> String:
	return "Take the key" if key_in_lock else "Turn the key"


func interact(_player: Player) -> void:
	if key_in_lock:
		key_in_lock = false
		key_taken.emit()
	else:
		key_in_lock = true
		key_turned.emit()


## Chains, portcullis up, then the door creaks inward. `instant` snaps (used when the camp is
## re-shown with the gate already open). Main does this in two halves around the floor build:
## begin_open (chains) → build → finish_open (door), so the door never opens on an unfinished floor.
func open(instant: bool = false) -> void:
	if instant:
		is_open = true
		_kill()
		_portcullis.position.y = portcullis_lift
		_door_hinge.rotation_degrees.y = door_open_deg
		return
	begin_open()
	finish_open()


## Chains and the portcullis. Returns at once; the lift runs on its own tween.
func begin_open() -> void:
	is_open = true
	_kill()
	_tween = create_tween()
	_tween.tween_property(_portcullis, ^"position:y", portcullis_lift, portcullis_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var clanks: int = maxi(1, int(portcullis_time / chain_interval))
	for i: int in clanks:
		_tween.parallel().tween_callback(_clank).set_delay(chain_interval * (i + 1))


## The door, once the portcullis is up (waits for it if it's still rising).
func finish_open() -> void:
	if _tween and _tween.is_running():
		await _tween.finished
	if not is_open:
		return  # Closed again while we waited.
	_tween = create_tween()
	_tween.tween_callback(_door_sfx.play)
	_tween.tween_property(_door_hinge, ^"rotation_degrees:y", door_open_deg, door_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Door shuts, then the portcullis drops with a thud.
func close(instant: bool = false) -> void:
	is_open = false
	_kill()
	if instant:
		_portcullis.position.y = 0.0
		_door_hinge.rotation_degrees.y = 0.0
		return
	_tween = create_tween()
	_tween.tween_callback(_door_sfx.play)
	_tween.tween_property(_door_hinge, ^"rotation_degrees:y", 0.0, door_time * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_portcullis, ^"position:y", 0.0, portcullis_time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_thud_sfx.play)


func _clank() -> void:
	_chain_sfx.pitch_scale = randf_range(0.5, 0.65)
	_chain_sfx.play()


func _kill() -> void:
	if _tween:
		_tween.kill()
