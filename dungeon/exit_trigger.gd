class_name ExitTrigger
extends Area3D
## The far exit. Stepping on it ends the floor: Main empties the castle and puts the player in the
## garden outside the wall. Exit-only; there's no way back in but the gate.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		var main: Main = get_tree().get_first_node_in_group(&"main") as Main
		if main:
			# Deferred: tearing the castle down inside a physics callback is not allowed.
			main.leave_castle.call_deferred(true)
		else:
			print("exit reached")
