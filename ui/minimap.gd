class_name Minimap
extends Control
## Draws the cells the player has revealed (Dungeon.revealed over Dungeon.map) onto %Canvas.
## One script for both maps: the corner minimap and the M full map are two instances of
## Minimap.tscn with different exports.

## Size of one 4 m cell on screen. The full map shrinks below this if the floor wouldn't fit.
@export var cell_px: int = 10
## Keep the player in the middle (corner map); otherwise frame everything revealed (full map).
@export var centered_on_player: bool = true
## Most redraws per second for walking and turning. A reveal redraws at once.
@export var redraw_hz: float = 10.0
## How far an unexplored doorway's tick pokes out, in cells (0.3 = 3 px at 10 px per cell).
@export var stub_length: float = 0.3

@export_group("Colors")
@export var main_path_color: Color = Color(0.427, 0.4, 0.431, 1.0)
@export var branch_color: Color = Color(0.318, 0.294, 0.333, 1.0)
@export var wall_color: Color = Color(0.106, 0.098, 0.125, 1.0)
@export var stub_color: Color = Color(0.886, 0.753, 0.541, 1.0)
@export var player_color: Color = Color(1.0, 0.953, 0.769, 1.0)
@export var exit_color: Color = Color(0.878, 0.329, 0.149, 1.0)
@export var treasure_color: Color = Color(1.0, 0.788, 0.239, 1.0)

@onready var _canvas: Control = %Canvas

var _dungeon: Dungeon
var _player: Node3D
var _since_redraw: float = 0.0
var _drawn_position: Vector2 = Vector2.INF
var _drawn_yaw: float = 0.0


func _ready() -> void:
	_canvas.draw.connect(_draw_map)
	_canvas.resized.connect(_canvas.queue_redraw)
	visibility_changed.connect(_canvas.queue_redraw)


func bind(dungeon: Dungeon, player: Node3D) -> void:
	_dungeon = dungeon
	_player = player
	if dungeon:
		dungeon.revealed_changed.connect(_canvas.queue_redraw)
	_canvas.queue_redraw()


## Redraws for movement and turning at most redraw_hz times a second, and only when something moved.
func _process(delta: float) -> void:
	if _player == null or not is_visible_in_tree():
		return
	_since_redraw += delta
	if _since_redraw < 1.0 / redraw_hz:
		return
	var moved: bool = _player_cells().distance_to(_drawn_position) > 0.02
	var turned: bool = absf(angle_difference(_player.global_rotation.y, _drawn_yaw)) > deg_to_rad(1.5)
	if moved or turned:
		_canvas.queue_redraw()


func _draw_map() -> void:
	_since_redraw = 0.0
	if _dungeon == null or _dungeon.map == null or _player == null:
		return
	_drawn_position = _player_cells()
	_drawn_yaw = _player.global_rotation.y
	var model: MapModel = _dungeon.map
	var revealed: Dictionary[Vector2i, bool] = _dungeon.revealed
	var px: float = _cell_size()
	var origin: Vector2 = _origin(px)
	var line: float = maxf(1.0, roundf(px / 10.0))
	for room: MapModel.MapRoom in model.rooms:
		if room.map_tile and _is_seen(room):
			_draw_tile(room, origin, px)
	for cell: Vector2i in revealed:
		var room: MapModel.MapRoom = model.room_at(cell)
		if room and not room.map_tile:
			_canvas.draw_rect(Rect2(origin + Vector2(cell) * px, Vector2(px, px)), _floor_color(room))
	# Walls: every revealed cell edge that borders another room or nothing. Neighbouring rooms each
	# draw their own side, so a shared wall reads as a dark seam. A hall or a loop bridge counts as one room.
	for cell: Vector2i in revealed:
		for dir: int in 4:
			if not model.joined(cell, cell + Door.offset(dir)):
				_canvas.draw_rect(_edge_rect(origin, cell, dir, px, line, 0.0, 1.0), wall_color)
	# Doorways: the middle half of the edge (a 2 m door in a 4 m cell) is cut out of the seam. One that
	# leads somewhere not yet seen gets a tick poking out: the "where next" cue.
	for room: MapModel.MapRoom in model.rooms:
		for door: MapModel.MapDoor in room.doors:
			if not door.used or not revealed.has(door.cell):
				continue
			_canvas.draw_rect(_edge_rect(origin, door.cell, door.dir, px, line, 0.25, 0.75), _floor_color(room))
			if not revealed.has(door.outside()):
				var middle: Vector2 = origin + (Vector2(door.cell) + Vector2(0.5, 0.5) + Vector2(Door.offset(door.dir)) * 0.5) * px
				_canvas.draw_line(middle, middle + Vector2(Door.offset(door.dir)) * stub_length * px, stub_color, line * 2.0)
	var icon: float = maxf(2.0, px * 0.3)
	for room: MapModel.MapRoom in model.rooms:
		if not _is_seen(room):
			continue
		var center: Vector2 = origin + room.center() * px
		if room.type == Room.Type.EXIT:
			_canvas.draw_rect(Rect2(center - Vector2(icon, icon), Vector2(icon, icon) * 2.0), exit_color, false, line)
		elif room.type == Room.Type.TREASURE:
			_canvas.draw_circle(center, icon * 0.6, treasure_color)
	_draw_player(origin, px)


func _draw_player(origin: Vector2, px: float) -> void:
	var at: Vector2 = origin + _player_cells() * px
	var yaw: float = _player.global_rotation.y
	# Yaw 0 faces -Z, which is up on the map.
	var forward: Vector2 = Vector2(-sin(yaw), -cos(yaw))
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var size: float = maxf(4.0, px * 0.45)
	var back: Vector2 = at - forward * size * 0.6
	_canvas.draw_colored_polygon(PackedVector2Array([at + forward * size, back + side * size * 0.6, back - side * size * 0.6]), player_color)


## Authored art over the room's footprint, turned with the room (screen rotation is clockwise, like `turns`).
func _draw_tile(room: MapModel.MapRoom, origin: Vector2, px: float) -> void:
	var unturned: Vector2 = Vector2(room.footprint) * px
	_canvas.draw_set_transform(origin + room.center() * px, PI * 0.5 * room.turns)
	_canvas.draw_texture_rect(room.map_tile, Rect2(-unturned * 0.5, unturned), false)
	_canvas.draw_set_transform(Vector2.ZERO)


## A strip along one edge of `cell`, inside it, covering `from`..`to` of the edge's length.
static func _edge_rect(origin: Vector2, cell: Vector2i, dir: int, px: float, thickness: float, from: float, to: float) -> Rect2:
	var corner: Vector2 = origin + Vector2(cell) * px
	var along: float = px * (to - from)
	match dir:
		Door.Dir.NORTH:
			return Rect2(corner + Vector2(px * from, 0.0), Vector2(along, thickness))
		Door.Dir.SOUTH:
			return Rect2(corner + Vector2(px * from, px - thickness), Vector2(along, thickness))
		Door.Dir.WEST:
			return Rect2(corner + Vector2(0.0, px * from), Vector2(thickness, along))
		_:
			return Rect2(corner + Vector2(px - thickness, px * from), Vector2(thickness, along))


func _floor_color(room: MapModel.MapRoom) -> Color:
	return main_path_color if room.main_path else branch_color


func _is_seen(room: MapModel.MapRoom) -> bool:
	for cell: Vector2i in room.cells:
		if _dungeon.revealed.has(cell):
			return true
	return false


## Player position in cells (fractional), in the dungeon's grid.
func _player_cells() -> Vector2:
	var local: Vector3 = _dungeon.to_local(_player.global_position) if _dungeon else _player.global_position
	return Vector2(local.x, local.z) / Room.CELL_SIZE


func _cell_size() -> float:
	if centered_on_player:
		return cell_px
	var bounds: Rect2 = _revealed_bounds()
	var room_for: Vector2 = (_canvas.size - Vector2(2.0, 2.0) * cell_px) / bounds.size
	return clampf(floorf(minf(room_for.x, room_for.y)), 2.0, cell_px)


## Screen position of the grid's (0, 0) corner, whole pixels so cells stay crisp.
func _origin(px: float) -> Vector2:
	var focus: Vector2 = _player_cells() if centered_on_player else _revealed_bounds().get_center()
	return (_canvas.size * 0.5 - focus * px).round()


## Revealed cells' bounding box, in cells; around the player when nothing is revealed yet.
func _revealed_bounds() -> Rect2:
	if _dungeon.revealed.is_empty():
		return Rect2(_player_cells() - Vector2.ONE, Vector2(2.0, 2.0))
	var low: Vector2i = Vector2i.MAX
	var high: Vector2i = Vector2i.MIN
	for cell: Vector2i in _dungeon.revealed:
		low = low.min(cell)
		high = high.max(cell)
	return Rect2(Vector2(low), Vector2(high - low + Vector2i.ONE))
