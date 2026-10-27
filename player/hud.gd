class_name Hud
extends CanvasLayer
## Player HUD: bars, crosshair, interact prompt, damage flash, death text, corner map and full map.

@export var damage_flash_alpha: float = 0.35
@export var damage_flash_time: float = 0.35
## %s is the interactable's prompt_text().
@export var prompt_format: String = "[E] %s"
## Tint for notices (e.g. "Inventory full") shown in the prompt line.
@export var notice_color: Color = Color(0.878, 0.329, 0.149, 1.0)
## Stamina bar tint while slowed (bruiser charge).
@export var slowed_tint: Color = Color(0.55, 0.55, 0.6, 1.0)

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_text: Label = %HealthText
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _charge_meter: ChargeMeter = %ChargeMeter
@onready var _gold_label: Label = %GoldLabel
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _death_label: Label = %DeathLabel
@onready var _prompt_label: Label = %PromptLabel
@onready var _minimap: Minimap = %Minimap
@onready var _full_map: Control = %FullMap
@onready var _full_map_view: Minimap = %FullMapView

var _flash_tween: Tween
var _notice_tween: Tween
var _prompt_text: String = ""
var _prompt_wanted: bool = false
var _notice_active: bool = false
var _prompt_color: Color
var _has_map: bool = false


func _ready() -> void:
	_prompt_color = _prompt_label.get_theme_color(&"font_color")


func bind(health: Health, stamina: Stamina) -> void:
	health.changed.connect(_on_health_changed)
	stamina.changed.connect(_on_stamina_changed)
	_on_health_changed(health.hp, health.max_hp)
	_on_stamina_changed(stamina.current, stamina.max_stamina)


## Both maps read the dungeon's reveal state and follow `player`. No dungeon = no corner map.
func set_gold(gold: int) -> void:
	_gold_label.text = "%d gold" % gold


## Heavy charge readout; Player feeds it every physics frame.
func set_charge(charging: bool, fraction: float, overcharge: float, threshold: float) -> void:
	_charge_meter.update_charge(charging, fraction, overcharge, threshold)


func bind_map(dungeon: Dungeon, player: Node3D) -> void:
	_minimap.bind(dungeon, player)
	_full_map_view.bind(dungeon, player)
	_has_map = dungeon != null
	_minimap.visible = _has_map


## M: the full map over a dim screen (the game keeps running), or back to the corner map.
func toggle_full_map() -> void:
	if not _has_map:
		return
	_full_map.visible = not _full_map.visible
	_minimap.visible = not _full_map.visible


func is_full_map_open() -> bool:
	return _full_map.visible


func flash_damage() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_damage_flash.color.a = damage_flash_alpha
	_flash_tween = create_tween().set_ignore_time_scale(true)
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, damage_flash_time).set_ease(Tween.EASE_OUT)


func show_death() -> void:
	_death_label.visible = true


func hide_death() -> void:
	_death_label.visible = false


func show_prompt(text: String) -> void:
	_prompt_text = prompt_format % text
	_prompt_wanted = true
	_apply_prompt()


func hide_prompt() -> void:
	_prompt_wanted = false
	_apply_prompt()


## Takes over the prompt line for `duration` seconds; the normal prompt comes back afterwards.
func show_notice(text: String, duration: float) -> void:
	if _notice_tween:
		_notice_tween.kill()
	_notice_active = true
	_prompt_label.text = text
	_prompt_label.add_theme_color_override(&"font_color", notice_color)
	_prompt_label.visible = true
	_notice_tween = create_tween()
	_notice_tween.tween_interval(duration)
	_notice_tween.tween_callback(_end_notice)


func set_slowed(slowed: bool) -> void:
	_stamina_bar.modulate = slowed_tint if slowed else Color.WHITE


func is_notice_showing() -> bool:
	return _notice_active


func prompt_text_shown() -> String:
	return _prompt_label.text if _prompt_label.visible else ""


func _end_notice() -> void:
	_notice_active = false
	_prompt_label.add_theme_color_override(&"font_color", _prompt_color)
	_apply_prompt()


func _apply_prompt() -> void:
	if _notice_active:
		return
	_prompt_label.text = _prompt_text
	_prompt_label.visible = _prompt_wanted


func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_text.text = "%d / %d" % [current, maximum]


func _on_stamina_changed(value: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = value
