class_name HealthBar
extends Node2D

@onready var _fill: Polygon2D = $Fill


# 參數與 HealthComponent.health_changed 訊號相同，可直接連接
func update_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		_fill.scale.x = 0.0
		return
	_fill.scale.x = clampf(float(current) / float(maximum), 0.0, 1.0)
