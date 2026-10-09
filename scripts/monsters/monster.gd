class_name Monster
extends CharacterBody2D

const FLASH_DURATION: float = 0.15
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/ui/damage_number.tscn")
const DAMAGE_NUMBER_OFFSET: Vector2 = Vector2(0.0, -38.0)
const DAMAGE_NUMBER_COLOR: Color = Color.WHITE

var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null

@onready var _polygon: Polygon2D = $Polygon2D
@onready var _health: HealthComponent = $HealthComponent
@onready var _health_bar: HealthBar = $HealthBar


func _ready() -> void:
	_base_color = _polygon.color
	_health.health_changed.connect(_health_bar.update_health)
	_health.damage_taken.connect(_on_damage_taken)
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


# 數字加到主場景而不是自己底下，被擊殺移除時最後一擊的數字才不會跟著消失
func _on_damage_taken(amount: int) -> void:
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	number.setup(amount, DAMAGE_NUMBER_COLOR)
	number.position = global_position + DAMAGE_NUMBER_OFFSET
	get_tree().current_scene.add_child(number)


func _on_died() -> void:
	queue_free()
