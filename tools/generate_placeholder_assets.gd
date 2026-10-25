class_name PlaceholderAssetGenerator
extends SceneTree
## Regenerates the shared palette texture and the placeholder SFX. Deterministic (fixed seed).
## Run from the project root:
##   godot --headless --path . --script res://tools/generate_placeholder_assets.gd

const SAMPLE_RATE: int = 44100
const SWATCH_SIZE: int = 8
const PALETTE_COLUMNS: int = 8
## IconStroke swatch value that clears pixels instead of painting.
const ERASE: int = -1

## Row-major, 8 columns x 4 rows; index = row * 8 + column. The swatch map in NOTES.md mirrors this.
var _palette: Array[Color] = [
	# Row 0: stone / neutrals, dark -> light
	Color("0e0c12"), Color("1b1920"), Color("2a272f"), Color("3b3740"),
	Color("514b55"), Color("6d666e"), Color("958c90"), Color("c9c0b9"),
	# Row 1: earth / wood / burlap
	Color("24170f"), Color("3d2717"), Color("5c3b20"), Color("7f552c"),
	Color("a8763e"), Color("c99a5b"), Color("e2c08a"), Color("f2e2bf"),
	# Row 2: blood / fire
	Color("2a080c"), Color("4f1015"), Color("84191c"), Color("b8291f"),
	Color("e05426"), Color("f58b26"), Color("ffc93d"), Color("fff3c4"),
	# Row 3: metal / cloth / misc
	Color("1a2329"), Color("2e3d45"), Color("4b6068"), Color("7a8e94"),
	Color("aab9bc"), Color("dfe8e6"), Color("3f5a2c"), Color("ffffff"),
]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.seed = 1337
	_write_palette("res://art/palette/palette.png")
	_write_wav("res://audio/sfx/whoosh.wav", _whoosh())
	_write_wav("res://audio/sfx/impact_thud.wav", _thud())
	_write_wav("res://audio/sfx/block_clang.wav", _clang())
	_write_wav("res://audio/sfx/enemy_grunt.wav", _voice(0.42, 90.0, 125.0, 70.0, 650.0, 1100.0, 0.15))
	_write_wav("res://audio/sfx/player_hurt.wav", _voice(0.24, 160.0, 210.0, 120.0, 750.0, 1250.0, 0.25))
	_write_wav("res://audio/sfx/nope.wav", _nope())
	_write_weapons()
	_write_armor()
	print("Placeholder assets written.")
	quit()


## Weapon meshes (grip at origin, long axis +Y, edge toward -X) and their 32×32 icons.
## Swatch numbers index _palette: 9 dark wood, 10/11 wood, 26–29 steel dark -> bright.
func _write_weapons() -> void:
	var sword: Array[MeshPart] = [
		MeshPart.new(Vector3(0.032, 0.16, 0.032), Vector3(0.0, 0.0, 0.0), 9),
		MeshPart.new(Vector3(0.045, 0.03, 0.045), Vector3(0.0, -0.095, 0.0), 26, true),
		MeshPart.new(Vector3(0.18, 0.025, 0.04), Vector3(0.0, 0.0925, 0.0), 26, true),
		MeshPart.new(Vector3(0.05, 0.72, 0.012), Vector3(0.0, 0.465, 0.0), 28, true),
		MeshPart.new(Vector3(0.03, 0.05, 0.014), Vector3(0.012, 0.22, 0.0), 11),
		MeshPart.new(Vector3(0.024, 0.035, 0.014), Vector3(-0.01, 0.56, 0.0), 10),
	]
	var axe: Array[MeshPart] = [
		MeshPart.new(Vector3(0.042, 0.16, 0.042), Vector3(0.0, 0.0, 0.0), 9),
		MeshPart.new(Vector3(0.034, 0.86, 0.034), Vector3(0.0, 0.33, 0.0), 11),
		MeshPart.new(Vector3(0.17, 0.12, 0.026), Vector3(-0.075, 0.68, 0.0), 27, true),
		MeshPart.new(Vector3(0.06, 0.08, 0.04), Vector3(0.03, 0.68, 0.0), 26, true),
		MeshPart.new(Vector3(0.022, 0.18, 0.018), Vector3(-0.165, 0.68, 0.0), 29, true),
		MeshPart.new(Vector3(0.04, 0.03, 0.04), Vector3(0.0, 0.775, 0.0), 26, true),
	]
	var dagger: Array[MeshPart] = [
		MeshPart.new(Vector3(0.028, 0.1, 0.028), Vector3(0.0, 0.0, 0.0), 9),
		MeshPart.new(Vector3(0.036, 0.022, 0.036), Vector3(0.0, -0.061, 0.0), 26, true),
		MeshPart.new(Vector3(0.1, 0.018, 0.03), Vector3(0.0, 0.059, 0.0), 26, true),
		MeshPart.new(Vector3(0.036, 0.28, 0.01), Vector3(0.0, 0.208, 0.0), 27, true),
		MeshPart.new(Vector3(0.022, 0.07, 0.012), Vector3(-0.006, 0.12, 0.0), 11),
		MeshPart.new(Vector3(0.016, 0.04, 0.012), Vector3(0.008, 0.26, 0.0), 10),
	]
	_write_item_mesh("res://weapons/meshes/rusty_sword.res", sword)
	_write_item_mesh("res://weapons/meshes/woodcutters_axe.res", axe)
	_write_item_mesh("res://weapons/meshes/rusted_dagger.res", dagger)

	_write_icon("res://weapons/icons/rusty_sword.png", [
		IconStroke.new(Vector2(10, 22), Vector2(27, 5), 1.7, 28),
		IconStroke.new(Vector2(6, 19), Vector2(13, 26), 1.3, 26),
		IconStroke.new(Vector2(5, 27), Vector2(9, 23), 1.6, 9),
		IconStroke.new(Vector2(4, 28), Vector2(4, 28), 2.0, 26),
		IconStroke.new(Vector2(17, 15), Vector2(18, 14), 1.0, 11),
	])
	_write_icon("res://weapons/icons/woodcutters_axe.png", [
		IconStroke.new(Vector2(5, 28), Vector2(23, 8), 1.3, 11),
		IconStroke.new(Vector2(5, 28), Vector2(9, 24), 1.7, 9),
		IconStroke.new(Vector2(14, 9), Vector2(20, 3), 3.4, 27),
		IconStroke.new(Vector2(11, 7), Vector2(18, 0), 1.3, 29),
		IconStroke.new(Vector2(22, 9), Vector2(24, 7), 1.8, 26),
	])
	_write_icon("res://weapons/icons/rusted_dagger.png", [
		IconStroke.new(Vector2(13, 20), Vector2(23, 10), 1.5, 27),
		IconStroke.new(Vector2(9, 18), Vector2(15, 24), 1.1, 26),
		IconStroke.new(Vector2(9, 25), Vector2(12, 22), 1.6, 9),
		IconStroke.new(Vector2(8, 26), Vector2(8, 26), 1.8, 26),
		IconStroke.new(Vector2(16, 17), Vector2(16, 17), 1.1, 11),
	])


## Armor world meshes and icons. Built in pickup space: +Z is up once Pickup lays the mesh down
## (its Mesh node turns mesh +Y to horizontal and mesh +Z to up). Swatches: 9–12 leather, 26–28 iron.
func _write_armor() -> void:
	var cap: Array[MeshPart] = [
		MeshPart.new(Vector3(0.2, 0.2, 0.11), Vector3(0.0, 0.0, 0.075), 12),
		MeshPart.new(Vector3(0.14, 0.14, 0.03), Vector3(0.0, 0.0, 0.145), 12),
		MeshPart.new(Vector3(0.23, 0.23, 0.03), Vector3(0.0, 0.0, 0.015), 10),
	]
	var vest: Array[MeshPart] = [
		MeshPart.new(Vector3(0.42, 0.5, 0.06), Vector3(0.0, 0.0, 0.03), 12),
		MeshPart.new(Vector3(0.1, 0.08, 0.07), Vector3(0.13, 0.26, 0.035), 10),
		MeshPart.new(Vector3(0.1, 0.08, 0.07), Vector3(-0.13, 0.26, 0.035), 10),
		MeshPart.new(Vector3(0.03, 0.4, 0.065), Vector3(0.0, 0.0, 0.033), 9),
		MeshPart.new(Vector3(0.43, 0.04, 0.065), Vector3(0.0, -0.24, 0.033), 10),
	]
	var gloves: Array[MeshPart] = []
	var boots: Array[MeshPart] = []
	for side: float in [-1.0, 1.0]:
		var x: float = 0.07 * side
		gloves.append(MeshPart.new(Vector3(0.09, 0.14, 0.04), Vector3(x, 0.02, 0.02), 11))
		gloves.append(MeshPart.new(Vector3(0.08, 0.07, 0.03), Vector3(x, 0.12, 0.015), 11))
		gloves.append(MeshPart.new(Vector3(0.1, 0.05, 0.05), Vector3(x, -0.07, 0.025), 10))
		gloves.append(MeshPart.new(Vector3(0.03, 0.05, 0.03), Vector3(x + 0.055 * side, 0.03, 0.015), 11))
		boots.append(MeshPart.new(Vector3(0.09, 0.1, 0.2), Vector3(x, 0.0, 0.12), 11))
		boots.append(MeshPart.new(Vector3(0.09, 0.2, 0.07), Vector3(x, 0.07, 0.045), 11))
		boots.append(MeshPart.new(Vector3(0.095, 0.21, 0.02), Vector3(x, 0.07, 0.01), 9))
	var iron_cap: Array[MeshPart] = [
		MeshPart.new(Vector3(0.22, 0.22, 0.12), Vector3(0.0, 0.0, 0.08), 27, true),
		MeshPart.new(Vector3(0.16, 0.16, 0.03), Vector3(0.0, 0.0, 0.155), 27, true),
		MeshPart.new(Vector3(0.245, 0.245, 0.035), Vector3(0.0, 0.0, 0.0175), 28, true),
		MeshPart.new(Vector3(0.03, 0.02, 0.07), Vector3(0.0, 0.123, 0.02), 26, true),
	]
	_write_item_mesh("res://items/armor/meshes/rawhide_cap.res", cap)
	_write_item_mesh("res://items/armor/meshes/rawhide_vest.res", vest)
	_write_item_mesh("res://items/armor/meshes/rawhide_gloves.res", gloves)
	_write_item_mesh("res://items/armor/meshes/rawhide_boots.res", boots)
	_write_item_mesh("res://items/armor/meshes/iron_cap.res", iron_cap)

	# Caps: a round crown with everything below the brim erased, so it reads as a dome, not a loaf.
	_write_icon("res://items/armor/icons/rawhide_cap.png", [
		IconStroke.new(Vector2(12, 21), Vector2(20, 21), 9.0, 12),
		IconStroke.new(Vector2(0, 29), Vector2(32, 29), 6.0, ERASE),
		IconStroke.new(Vector2(5, 23), Vector2(27, 23), 1.6, 10),
		IconStroke.new(Vector2(13, 15), Vector2(19, 15), 0.8, 13),
	])
	_write_icon("res://items/armor/icons/rawhide_vest.png", [
		IconStroke.new(Vector2(16, 10), Vector2(16, 24), 7.5, 12),
		IconStroke.new(Vector2(9, 7), Vector2(9, 10), 2.0, 10),
		IconStroke.new(Vector2(23, 7), Vector2(23, 10), 2.0, 10),
		IconStroke.new(Vector2(16, 10), Vector2(16, 26), 0.8, 9),
		IconStroke.new(Vector2(10, 27), Vector2(22, 27), 1.2, 10),
	])
	_write_icon("res://items/armor/icons/rawhide_gloves.png", [
		IconStroke.new(Vector2(10, 11), Vector2(10, 22), 3.5, 11),
		IconStroke.new(Vector2(22, 11), Vector2(22, 22), 3.5, 11),
		IconStroke.new(Vector2(5, 16), Vector2(6, 19), 1.6, 11),
		IconStroke.new(Vector2(27, 16), Vector2(26, 19), 1.6, 11),
		IconStroke.new(Vector2(8, 26), Vector2(12, 26), 1.6, 10),
		IconStroke.new(Vector2(20, 26), Vector2(24, 26), 1.6, 10),
	])
	_write_icon("res://items/armor/icons/rawhide_boots.png", [
		IconStroke.new(Vector2(9, 7), Vector2(9, 22), 3.0, 11),
		IconStroke.new(Vector2(9, 24), Vector2(14, 24), 3.0, 11),
		IconStroke.new(Vector2(21, 7), Vector2(21, 22), 3.0, 11),
		IconStroke.new(Vector2(21, 24), Vector2(26, 24), 3.0, 11),
		IconStroke.new(Vector2(6, 28), Vector2(16, 28), 0.8, 9),
		IconStroke.new(Vector2(18, 28), Vector2(28, 28), 0.8, 9),
	])
	_write_icon("res://items/armor/icons/iron_cap.png", [
		IconStroke.new(Vector2(13, 20), Vector2(19, 20), 10.0, 27),
		IconStroke.new(Vector2(0, 28), Vector2(32, 28), 6.0, ERASE),
		IconStroke.new(Vector2(5, 22), Vector2(27, 22), 1.5, 26),
		IconStroke.new(Vector2(16, 22), Vector2(16, 29), 1.3, 28),
		IconStroke.new(Vector2(12, 13), Vector2(18, 11), 0.8, 29),
	])


## Two descending, low, slightly square blips: a dull "nope".
func _nope() -> PackedFloat32Array:
	var count: int = int(0.26 * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / SAMPLE_RATE
		var freq: float = 196.0 if t < 0.11 else 147.0
		var local_t: float = t if t < 0.11 else t - 0.12
		var on: bool = t < 0.09 or (t >= 0.12 and t < 0.24)
		phase += TAU * freq / SAMPLE_RATE
		var env: float = (smoothstep(0.0, 0.006, local_t) * exp(-local_t * 18.0)) if on else 0.0
		low += (tanh(sin(phase) * 3.0) * env - low) * 0.18
		out[i] = low
	return _normalized(out, 0.6)


## Merges boxes into one mesh: a matte surface and a metal surface, both on the shared palette texture.
## Every vertex of a box gets the UV of its swatch's center, so the whole box reads as that one color.
func _write_item_mesh(path: String, parts: Array[MeshPart]) -> void:
	var matte: Material = load("res://art/materials/palette_base.tres") as Material
	var metal: Material = load("res://art/materials/palette_metal.tres") as Material
	var mesh: ArrayMesh = ArrayMesh.new()
	for use_metal: bool in [false, true]:
		var verts: PackedVector3Array = PackedVector3Array()
		var normals: PackedVector3Array = PackedVector3Array()
		var uvs: PackedVector2Array = PackedVector2Array()
		var indices: PackedInt32Array = PackedInt32Array()
		for part: MeshPart in parts:
			if part.metal != use_metal:
				continue
			var box: BoxMesh = BoxMesh.new()
			box.size = part.size
			var arrays: Array = box.get_mesh_arrays()
			var base: int = verts.size()
			var uv: Vector2 = _swatch_uv(part.swatch)
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				verts.append(v + part.position)
				uvs.append(uv)
			normals.append_array(arrays[Mesh.ARRAY_NORMAL])
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
		if verts.is_empty():
			continue
		var surface: Array = []
		surface.resize(Mesh.ARRAY_MAX)
		surface[Mesh.ARRAY_VERTEX] = verts
		surface[Mesh.ARRAY_NORMAL] = normals
		surface[Mesh.ARRAY_TEX_UV] = uvs
		surface[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		mesh.surface_set_material(mesh.get_surface_count() - 1, metal if use_metal else matte)
	_ensure_dir(path)
	var err: Error = ResourceSaver.save(mesh, path)
	assert(err == OK, "Failed to save %s" % path)


## 32×32 icon: each stroke is a thick line segment in one swatch, with a 1 px dark outline under everything.
## A stroke with swatch ERASE clears pixels instead (no outline), for flat cuts like a cap's rim.
func _write_icon(path: String, strokes: Array[IconStroke]) -> void:
	var size: int = 32
	var image: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for outline: bool in [true, false]:
		for stroke: IconStroke in strokes:
			var erase: bool = stroke.swatch == ERASE
			if outline and erase:
				continue
			var radius: float = stroke.radius + (1.0 if outline else 0.0)
			var color: Color = Color(0, 0, 0, 0) if erase else (_palette[0] if outline else _palette[stroke.swatch])
			for y: int in size:
				for x: int in size:
					var p: Vector2 = Vector2(x + 0.5, y + 0.5)
					var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p, stroke.from, stroke.to)
					if p.distance_to(nearest) <= radius:
						image.set_pixel(x, y, color)
	_ensure_dir(path)
	var err: Error = image.save_png(path)
	assert(err == OK, "Failed to save %s" % path)


func _swatch_uv(index: int) -> Vector2:
	var rows: int = ceili(float(_palette.size()) / PALETTE_COLUMNS)
	var column: int = index % PALETTE_COLUMNS
	var row: int = floori(float(index) / PALETTE_COLUMNS)
	return Vector2((column + 0.5) / PALETTE_COLUMNS, (row + 0.5) / rows)


class MeshPart:
	var size: Vector3
	var position: Vector3
	var swatch: int
	var metal: bool

	func _init(p_size: Vector3, p_position: Vector3, p_swatch: int, p_metal: bool = false) -> void:
		size = p_size
		position = p_position
		swatch = p_swatch
		metal = p_metal


class IconStroke:
	var from: Vector2
	var to: Vector2
	var radius: float
	var swatch: int

	func _init(p_from: Vector2, p_to: Vector2, p_radius: float, p_swatch: int) -> void:
		from = p_from
		to = p_to
		radius = p_radius
		swatch = p_swatch


func _write_palette(path: String) -> void:
	var rows: int = ceili(float(_palette.size()) / PALETTE_COLUMNS)
	var image: Image = Image.create_empty(PALETTE_COLUMNS * SWATCH_SIZE, rows * SWATCH_SIZE, false, Image.FORMAT_RGBA8)
	for i: int in _palette.size():
		var column: int = i % PALETTE_COLUMNS
		var row: int = floori(float(i) / PALETTE_COLUMNS)
		image.fill_rect(Rect2i(column * SWATCH_SIZE, row * SWATCH_SIZE, SWATCH_SIZE, SWATCH_SIZE), _palette[i])
	_ensure_dir(path)
	var err: Error = image.save_png(path)
	assert(err == OK, "Failed to save %s" % path)


## Band-passed noise with a rising-then-falling cutoff.
func _whoosh() -> PackedFloat32Array:
	var count: int = int(0.32 * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var low: float = 0.0
	var band: float = 0.0
	for i: int in count:
		var t: float = float(i) / count
		var cutoff: float = lerpf(450.0, 2400.0, sin(t * PI))
		var f: float = 2.0 * sin(PI * cutoff / SAMPLE_RATE)
		low += f * band
		var high: float = _rng.randf_range(-1.0, 1.0) - low - 1.1 * band
		band += f * high
		var env: float = pow(sin(PI * pow(t, 0.7)), 2.0)
		out[i] = band * env
	return _normalized(out, 0.6)


## Pitch-dropping sine body plus a short low-passed noise smack, lightly saturated.
func _thud() -> PackedFloat32Array:
	var count: int = int(0.28 * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var low: float = 0.0
	for i: int in count:
		var t: float = float(i) / SAMPLE_RATE
		var freq: float = 45.0 + 85.0 * exp(-t * 22.0)
		phase += TAU * freq / SAMPLE_RATE
		var body: float = sin(phase) * exp(-t * 14.0)
		low += (_rng.randf_range(-1.0, 1.0) - low) * 0.12
		var smack: float = low * exp(-t * 55.0) * 2.5
		out[i] = tanh((body + smack) * 1.6)
	return _normalized(out, 0.85)


## Inharmonic decaying partials plus a click: reads as metal on metal.
func _clang() -> PackedFloat32Array:
	var count: int = int(0.75 * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	# (frequency Hz, amplitude, decay rate)
	var partials: Array[Vector3] = [
		Vector3(523.0, 1.0, 5.0), Vector3(817.0, 0.35, 6.0), Vector3(1307.0, 0.65, 7.5),
		Vector3(2093.0, 0.45, 9.0), Vector3(2981.0, 0.3, 12.0), Vector3(3797.0, 0.22, 16.0),
	]
	for i: int in count:
		var t: float = float(i) / SAMPLE_RATE
		var sample: float = _rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) * 0.8
		for p: Vector3 in partials:
			sample += sin(TAU * p.x * t) * p.y * exp(-t * p.z)
		out[i] = sample
	return _normalized(out, 0.75)


## Saw "vocal cord" through two formant band-passes. Crude, but reads as a grunt.
func _voice(length: float, f_start: float, f_peak: float, f_end: float, formant_a: float, formant_b: float, breath: float) -> PackedFloat32Array:
	var count: int = int(length * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	var low_a: float = 0.0
	var band_a: float = 0.0
	var low_b: float = 0.0
	var band_b: float = 0.0
	var fa: float = 2.0 * sin(PI * formant_a / SAMPLE_RATE)
	var fb: float = 2.0 * sin(PI * formant_b / SAMPLE_RATE)
	for i: int in count:
		var t: float = float(i) / count
		var f0: float = lerpf(f_start, f_peak, t / 0.3) if t < 0.3 else lerpf(f_peak, f_end, (t - 0.3) / 0.7)
		f0 *= 1.0 + 0.02 * sin(TAU * 7.0 * t * length)
		phase = fmod(phase + f0 / SAMPLE_RATE, 1.0)
		var source: float = phase * 2.0 - 1.0 + _rng.randf_range(-1.0, 1.0) * breath
		low_a += fa * band_a
		band_a += fa * (source - low_a - 0.3 * band_a)
		low_b += fb * band_b
		band_b += fb * (source - low_b - 0.3 * band_b)
		var env: float = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.6, 1.0, t))
		out[i] = (band_a + band_b * 0.6) * env
	return _normalized(out, 0.8)


func _normalized(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest: float = 0.0
	for s: float in samples:
		loudest = maxf(loudest, absf(s))
	if loudest <= 0.0:
		return samples
	var gain: float = peak / loudest
	for i: int in samples.size():
		samples[i] *= gain
	return samples


## 16-bit mono PCM.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	_ensure_dir(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Failed to open %s" % path)
	var data_size: int = samples.size() * 2
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(SAMPLE_RATE)
	file.store_32(SAMPLE_RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	for s: float in samples:
		file.store_16(int(clampf(s, -1.0, 1.0) * 32767.0) & 0xFFFF)
	file.close()


func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
