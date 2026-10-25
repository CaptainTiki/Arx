class_name ExitTrigger
extends Area3D
## End of the floor. Step 3 only reports it.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		print("exit reached")
