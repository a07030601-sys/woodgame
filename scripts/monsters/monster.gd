class_name Monster
extends CharacterBody2D

const FLASH_DURATION: float = 0.15

var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null

@onready var _polygon: Polygon2D = $Polygon2D
@onready var _health: HealthComponent = $HealthComponent
@onready var _health_bar: HealthBar = $HealthBar


func _ready() -> void:
	_base_color = _polygon.color
	_health.health_changed.connect(_health_bar.update_health)
	_health.died.connect(_on_died)
	_health_bar.update_health(_health.current_health, _health.max_health)


func take_damage(amount: int) -> void:
	print("%s 受到 %d 點傷害" % [name, amount])

	# 閃白後漸變回原本的顏色
	if _flash_tween != null:
		_flash_tween.kill()
	_polygon.color = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(_polygon, "color", _base_color, FLASH_DURATION)

	_health.take_damage(amount)


func _on_died() -> void:
	queue_free()
