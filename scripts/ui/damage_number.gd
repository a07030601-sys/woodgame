class_name DamageNumber
extends Node2D

const LIFETIME: float = 0.8
const RISE_DISTANCE: float = 40.0
# 生成時的隨機水平偏移範圍，避免連續數字疊在一起
const HORIZONTAL_SPREAD: float = 14.0

var _amount: int = 0
var _color: Color = Color.WHITE

@onready var _label: Label = $Label


func _ready() -> void:
	_apply()
	position.x += randf_range(-HORIZONTAL_SPREAD, HORIZONTAL_SPREAD)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, LIFETIME)
	# 前段保持清楚，後段才快速淡出
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


# 加入場景樹之前或之後呼叫都可以
func setup(amount: int, color: Color) -> void:
	_amount = amount
	_color = color
	if is_node_ready():
		_apply()


func _apply() -> void:
	_label.text = str(_amount)
	_label.add_theme_color_override("font_color", _color)
