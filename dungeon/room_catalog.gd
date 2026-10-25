class_name RoomCatalog
extends Resource
## Every room scene the generator may use. Type, weight and footprint come from each scene's Room root.

## Rooms listed explicitly (e.g. ones kept outside scan_folder).
@export var rooms: Array[PackedScene] = []
## Every .tscn in this folder is included too, so a duplicated room needs no catalog edit. Empty = off.
@export_dir var scan_folder: String = ""


## `rooms` plus everything found in scan_folder, each scene once.
func get_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	var seen: Dictionary[String, bool] = {}
	for scene: PackedScene in rooms:
		if scene and not seen.has(scene.resource_path):
			seen[scene.resource_path] = true
			scenes.append(scene)
	if scan_folder.is_empty():
		return scenes
	var files: PackedStringArray = DirAccess.get_files_at(scan_folder)
	files.sort()
	for file: String in files:
		# Exported builds list scenes as "Name.tscn.remap".
		var file_name: String = file.trim_suffix(".remap")
		var path: String = scan_folder.path_join(file_name)
		if file_name.get_extension() != "tscn" or seen.has(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene:
			seen[path] = true
			scenes.append(scene)
	return scenes
