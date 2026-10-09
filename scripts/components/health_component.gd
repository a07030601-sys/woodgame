class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal damage_taken(amount: int)
signal died

@export var max_health: int = 100

var current_health: int = 0

var _is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func is_dead() -> bool:
	return _is_dead


func take_damage(amount: int) -> void:
	if _is_dead or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	damage_taken.emit(amount)

	if current_health == 0:
		_is_dead = true
		died.emit()
