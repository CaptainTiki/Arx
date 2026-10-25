class_name Hud
extends CanvasLayer
## Player HUD: bars, crosshair, damage flash, death text.

@export var damage_flash_alpha: float = 0.35
@export var damage_flash_time: float = 0.35

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _damage_flash: ColorRect = %DamageFlash
@onready var _death_label: Label = %DeathLabel

var _flash_tween: Tween


func bind(health: Health, stamina: Stamina) -> void:
	health.changed.connect(_on_health_changed)
	stamina.changed.connect(_on_stamina_changed)
	_on_health_changed(health.hp, health.max_hp)
	_on_stamina_changed(stamina.current, stamina.max_stamina)


func flash_damage() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_damage_flash.color.a = damage_flash_alpha
	_flash_tween = create_tween().set_ignore_time_scale(true)
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, damage_flash_time).set_ease(Tween.EASE_OUT)


func show_death() -> void:
	_death_label.visible = true


func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_stamina_changed(value: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = value
