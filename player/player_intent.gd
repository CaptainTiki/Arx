class_name PlayerIntent
extends Node
## The only node that reads Input. Everything else reads these fields.
## Runs at process/physics priority -1 (set in Player.tscn) so it samples before Player.

var move: Vector2 = Vector2.ZERO
## Mouse delta since last rendered frame, in pixels. Consumed by Player._process.
var look: Vector2 = Vector2.ZERO
## LMB went down since the last physics frame.
var attack_pressed: bool = false
var block_held: bool = false
var sprint_held: bool = false
var restart_pressed: bool = false

var _look_accum: Vector2 = Vector2.ZERO
var _attack_latched: bool = false
var _restart_latched: bool = false
var _mouse_released: bool = false


func _ready() -> void:
	_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_release_mouse()
		return
	if _mouse_released:
		# The click that recaptures the mouse shouldn't also swing.
		if event is InputEventMouseButton and event.is_pressed():
			_capture_mouse()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_look_accum += (event as InputEventMouseMotion).relative
	elif event.is_action_pressed(&"attack"):
		_attack_latched = true
	elif event.is_action_pressed(&"restart"):
		_restart_latched = true


func _process(_delta: float) -> void:
	look = _look_accum
	_look_accum = Vector2.ZERO


func _physics_process(_delta: float) -> void:
	var active: bool = not _mouse_released
	move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if active else Vector2.ZERO
	block_held = active and Input.is_action_pressed(&"block")
	sprint_held = active and Input.is_action_pressed(&"sprint")
	attack_pressed = _attack_latched
	_attack_latched = false
	restart_pressed = _restart_latched
	_restart_latched = false


func _capture_mouse() -> void:
	_mouse_released = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	_mouse_released = true
	_look_accum = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
