class_name ChargeMeter
extends Control
## Heavy-attack charge readout under the crosshair. One bar: fills in the light colour up to the
## heavy line, past it in the heavy colour. A thin second bar below fills while an overcharged hold
## counts down to the forced swing. Hidden when nothing is charging.

@export var light_color: Color = Color(0.85, 0.85, 0.8, 0.9)
@export var heavy_color: Color = Color(1.0, 0.62, 0.2, 1.0)
@export var force_color: Color = Color(0.9, 0.25, 0.15, 1.0)
@export var track_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var bar_size: Vector2 = Vector2(96.0, 6.0)
@export var force_bar_height: float = 3.0
@export var gap: float = 3.0

var _charging: bool = false
var _fraction: float = 0.0
var _overcharge: float = 0.0
var _threshold: float = 0.75


func update_charge(charging: bool, fraction: float, overcharge: float, threshold: float) -> void:
	_charging = charging
	_fraction = clampf(fraction, 0.0, 1.0)
	_overcharge = clampf(overcharge, 0.0, 1.0)
	_threshold = clampf(threshold, 0.0, 1.0)
	visible = charging
	if charging:
		queue_redraw()


func _draw() -> void:
	if not _charging:
		return
	var origin: Vector2 = (size - bar_size) * 0.5
	draw_rect(Rect2(origin, bar_size), track_color)
	var fill_w: float = bar_size.x * _fraction
	var fill_color: Color = heavy_color if _fraction >= _threshold else light_color
	draw_rect(Rect2(origin, Vector2(fill_w, bar_size.y)), fill_color)
	var line_x: float = origin.x + bar_size.x * _threshold
	draw_line(Vector2(line_x, origin.y - 2.0), Vector2(line_x, origin.y + bar_size.y + 2.0), line_color, 1.0)
	if _overcharge > 0.0:
		var force_origin: Vector2 = origin + Vector2(0.0, bar_size.y + gap)
		var force_size: Vector2 = Vector2(bar_size.x, force_bar_height)
		draw_rect(Rect2(force_origin, force_size), track_color)
		draw_rect(Rect2(force_origin, Vector2(bar_size.x * _overcharge, force_bar_height)), force_color)
