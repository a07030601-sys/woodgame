class_name ScreenMessage
extends CanvasLayer

# 畫面上方的短暫提示文字，例如「背包已滿」。

const INVENTORY_FULL_MESSAGE: String = "背包已滿"

@onready var _label: Label = $Label
@onready var _timer: Timer = $Timer


func _ready() -> void:
	_label.text = ""
	_timer.timeout.connect(_on_timer_timeout)

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player != null:
		player.inventory_full.connect(_on_inventory_full)


# 顯示一段文字，過一會兒自動消失；還沒消失就再呼叫會重新計時
func show_message(text: String) -> void:
	_label.text = text
	_timer.start()


func get_message() -> String:
	return _label.text


func _on_inventory_full() -> void:
	show_message(INVENTORY_FULL_MESSAGE)


func _on_timer_timeout() -> void:
	_label.text = ""
