class_name StatsPanel
extends CanvasLayer

# 屬性的顯示名稱，沒列在這裡的屬性會直接顯示英文名稱
const STAT_LABELS: Dictionary = {
	"strength": "力量",
	"vitality": "體力",
	"life": "生命",
	"damage_min": "最小傷害",
	"damage_max": "最大傷害",
	"attack_speed": "攻擊速度",
	"move_speed": "移動速度",
	"defense": "防禦",
}

var _stats: StatsComponent = null
# 屬性名稱 -> 顯示數值的 Label
var _value_labels: Dictionary = {}

@onready var _grid: GridContainer = $Panel/Margin/VBox/Grid


func _ready() -> void:
	hide()
	_build_rows()

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		push_warning("StatsPanel：找不到 player 群組的玩家")
		return
	_stats = player.get_stats()
	_stats.stats_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_stats_panel"):
		visible = not visible


# 依 StatSystem 的屬性清單建立每一列，新增屬性時面板會自動多一列
func _build_rows() -> void:
	for stat_name: String in StatSystem.STAT_NAMES:
		var name_label: Label = Label.new()
		name_label.text = STAT_LABELS.get(stat_name, stat_name)
		_grid.add_child(name_label)

		var value_label: Label = Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(value_label)
		_value_labels[stat_name] = value_label


func _refresh() -> void:
	for stat_name: String in _value_labels:
		var value_label: Label = _value_labels[stat_name]
		value_label.text = "%.2f" % _stats.get_stat(stat_name)
