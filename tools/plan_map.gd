extends SceneTree
## Headless plan rasterizer: plans seeds with the real generator and draws each as a cell map.
## godot --headless --path . --script res://tools/plan_map.gd -- out.png seed seed ...

const PX: int = 14
const PAD: int = 1
const COLS: int = 3

var _maps: Array[Image] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0]
	var main: Node = (load("res://main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var gen: DungeonGenerator = main.get_node("DungeonGenerator") as DungeonGenerator
	for i: int in range(1, args.size()):
		var s: int = int(args[i])
		var plan: Array = gen.plan_layout(s)
		var tries: int = 0
		while plan.is_empty() and tries < gen.max_restarts:
			tries += 1
			plan = gen.plan_layout(s + tries * 7919)
		print("seed %d: %s" % [s, DungeonGenerator.describe_plan(plan)])
		_maps.append(_draw(plan, s))
	_sheet(out)
	quit()


func _draw(plan: Array, s: int) -> Image:
	var mn: Vector2i = Vector2i(999, 999)
	var mx: Vector2i = Vector2i(-999, -999)
	for p: DungeonGenerator.Placement in plan:
		for c: Vector2i in p.cells():
			mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
			mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	var size: Vector2i = (mx - mn + Vector2i(3, 3)) * PX
	var img: Image = Image.create_empty(size.x, size.y + 18, false, Image.FORMAT_RGB8)
	img.fill(Color("0e0c12"))
	var off: Vector2i = -mn + Vector2i(1, 1)
	var cell_owner: Dictionary = {}
	for p: DungeonGenerator.Placement in plan:
		var col: Color
		var t: int = p.template.type
		if p.loop:
			col = Color("ffc93d")
		elif t == Room.Type.START:
			col = Color("3f8a3c")
		elif t == Room.Type.EXIT:
			col = Color("e05426")
		elif t == Room.Type.TREASURE:
			col = Color("c99a5b")
		elif p.template.is_connector:
			col = Color("514b55") if p.main_path else Color("3b3740")
		else:
			col = Color("958c90") if p.main_path else Color("6d666e")
		for c: Vector2i in p.cells():
			cell_owner[c] = p
			var at: Vector2i = (c + off) * PX
			img.fill_rect(Rect2i(at + Vector2i(PAD, PAD), Vector2i(PX - 2 * PAD, PX - 2 * PAD)), col)
	# Doors: a bright notch on the edge. Used = white, unused = dark red.
	for p: DungeonGenerator.Placement in plan:
		for i: int in p.template.door_cells.size():
			var c: Vector2i = p.door_cell(i)
			var d: int = p.door_dir(i)
			var o: Vector2i = Door.offset(d)
			var used: bool = i in p.used_doors
			var col: Color = Color("ffffff") if used else Color("84191c")
			var at: Vector2i = (c + off) * PX
			var mid: Vector2i = at + Vector2i(PX / 2, PX / 2) + o * (PX / 2 - 1)
			img.fill_rect(Rect2i(mid - Vector2i(2, 2), Vector2i(4, 4)), col)
	# Label strip.
	var label: String = "seed %d" % s
	_text(img, label, Vector2i(2, size.y + 4))
	return img


func _text(img: Image, text: String, at: Vector2i) -> void:
	# 3x5 digits only; letters drawn as blocks. Good enough for a seed number.
	var glyphs: Dictionary = {
		"0": ["111","101","101","101","111"], "1": ["010","110","010","010","111"],
		"2": ["111","001","111","100","111"], "3": ["111","001","111","001","111"],
		"4": ["101","101","111","001","001"], "5": ["111","100","111","001","111"],
		"6": ["111","100","111","101","111"], "7": ["111","001","001","001","001"],
		"8": ["111","101","111","101","111"], "9": ["111","101","111","001","111"],
		" ": ["000","000","000","000","000"],
	}
	var x: int = at.x
	for ch: String in text:
		if not glyphs.has(ch):
			x += 4
			continue
		var g: Array = glyphs[ch]
		for r: int in 5:
			for cidx: int in 3:
				if g[r][cidx] == "1":
					img.fill_rect(Rect2i(Vector2i(x + cidx * 2, at.y + r * 2), Vector2i(2, 2)), Color("dfe8e6"))
		x += 8


func _sheet(path: String) -> void:
	var w: int = 0
	var h: int = 0
	for m: Image in _maps:
		w = maxi(w, m.get_width())
		h = maxi(h, m.get_height())
	var rows: int = ceili(float(_maps.size()) / COLS)
	var sheet: Image = Image.create_empty(w * COLS + 8 * (COLS + 1), h * rows + 8 * (rows + 1), false, Image.FORMAT_RGB8)
	sheet.fill(Color("1b1920"))
	for i: int in _maps.size():
		var at: Vector2i = Vector2i(8 + (i % COLS) * (w + 8), 8 + (i / COLS) * (h + 8))
		sheet.blit_rect(_maps[i], Rect2i(Vector2i.ZERO, _maps[i].get_size()), at)
	sheet.save_png(path)
	print("Wrote ", path)
