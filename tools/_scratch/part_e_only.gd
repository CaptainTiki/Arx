extends CombatSmokeTest


func _run() -> void:
	var main: Node = (load("res://tests/CombatArena.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _seconds(0.5)
	await _part_loot(main)
	await _seconds(1.0)
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
