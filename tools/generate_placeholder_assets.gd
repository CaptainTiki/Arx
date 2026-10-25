class_name PlaceholderAssetGenerator
extends SceneTree
## Regenerates the shared palette texture and the placeholder SFX. Deterministic (fixed seed).
## Run from the project root:
##   godot --headless --path . --script res://tools/generate_placeholder_assets.gd

const SAMPLE_RATE: int = 44100
const SWATCH_SIZE: int = 8
const PALETTE_COLUMNS: int = 8

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
	print("Placeholder assets written.")
	quit()


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
