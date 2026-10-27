class_name PlayerIntent
extends Node
## The only node that reads Input. Everything else reads these fields.
## Runs at process/physics priority -1 (set in Player.tscn) so it samples before Player.
## Process mode is Always so Tab can close the inventory while the tree is paused; every other
## input is ignored while paused.

var move: Vector2 = Vector2.ZERO
## Mouse delta since last rendered frame, in pixels. Consumed by Player._process.
var look: Vector2 = Vector2.ZERO
## LMB went down since the last physics frame.
var attack_pressed: bool = false
## LMB is down right now (held through a light = heavy charge).
var attack_held: bool = false
var block_held: bool = false
var sprint_held: bool = false
## E went down since the last physics frame.
var interact_pressed: bool = false
var restart_pressed: bool = false
## Debug: F5 rebuilds the dungeon with a new seed.
var regenerate_pressed: bool = false
## Debug: F6 rebuilds the dungeon with the same seed.
var regenerate_same_pressed: bool = false
## M went down since the last physics frame: open or close the full map.
var map_pressed: bool = false

var _look_accum: Vector2 = Vector2.ZERO
var _regenerate_latched: bool = false
var _regenerate_same_latched: bool = false
var _map_latched: bool = false
var _attack_latched: bool = false
var _interact_latched: bool = false
var _restart_latched: bool = false
var _inventory_latched: bool = false
var _mouse_released: bool = false


func _ready() -> void:
	capture_mouse()


## True once per Tab press (paused or not). Polled by the InventoryScreen.
func consume_inventory_toggle() -> bool:
	var pressed: bool = _inventory_latched
	_inventory_latched = false
	return pressed


func capture_mouse() -> void:
	_mouse_released = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	_mouse_released = true
	_look_accum = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		_inventory_latched = true
		return
	if get_tree().paused:
		return
	if event.is_action_pressed(&"ui_cancel"):
		release_mouse()
		return
	if _mouse_released:
		# The click that recaptures the mouse shouldn't also swing.
		if event is InputEventMouseButton and event.is_pressed():
			capture_mouse()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_look_accum += (event as InputEventMouseMotion).relative
	elif event.is_action_pressed(&"attack"):
		_attack_latched = true
	elif event.is_action_pressed(&"interact"):
		_interact_latched = true
	elif event.is_action_pressed(&"restart"):
		_restart_latched = true
	elif event.is_action_pressed(&"regenerate"):
		_regenerate_latched = true
	elif event.is_action_pressed(&"regenerate_same"):
		_regenerate_same_latched = true
	elif event.is_action_pressed(&"toggle_map"):
		_map_latched = true


func _process(_delta: float) -> void:
	look = Vector2.ZERO if get_tree().paused else _look_accum
	_look_accum = Vector2.ZERO


func _physics_process(_delta: float) -> void:
	var active: bool = not _mouse_released and not get_tree().paused
	move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if active else Vector2.ZERO
	block_held = active and Input.is_action_pressed(&"block")
	attack_held = active and Input.is_action_pressed(&"attack")
	sprint_held = active and Input.is_action_pressed(&"sprint")
	attack_pressed = _attack_latched
	_attack_latched = false
	interact_pressed = _interact_latched
	_interact_latched = false
	restart_pressed = _restart_latched
	_restart_latched = false
	regenerate_pressed = _regenerate_latched
	_regenerate_latched = false
	regenerate_same_pressed = _regenerate_same_latched
	_regenerate_same_latched = false
	map_pressed = _map_latched
	_map_latched = false
