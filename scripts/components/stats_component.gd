class_name StatsComponent
extends Node

signal stats_changed

@export var strength: float = 0.0
@export var vitality: float = 0.0
@export var life: float = 100.0
@export var damage_min: float = 1.0
@export var damage_max: float = 1.0
# 每秒攻擊次數，攻擊間隔 = 1 ÷ attack_speed
@export var attack_speed: float = 1.0
@export var move_speed: float = 100.0

# source_id -> 該來源的修正值 Array，格式見 StatSystem
var _sources: Dictionary = {}
var _final_stats: Dictionary = {}


func _ready() -> void:
	_recalculate()


# 同一個 source_id 再次加入時直接覆蓋原本的修正值
func add_source(source_id: String, modifiers: Array) -> void:
	_sources[source_id] = modifiers.duplicate(true)
	_recalculate()


func remove_source(source_id: String) -> void:
	if not _sources.has(source_id):
		return
	_sources.erase(source_id)
	_recalculate()


func has_source(source_id: String) -> bool:
	return _sources.has(source_id)


func get_stat(stat_name: String) -> float:
	if _final_stats.is_empty():
		_recalculate()
	if not _final_stats.has(stat_name):
		push_warning("StatsComponent：沒有名為 %s 的屬性" % stat_name)
		return 0.0
	return _final_stats[stat_name]


func _recalculate() -> void:
	var modifiers: Array = []
	for source_modifiers: Array in _sources.values():
		modifiers.append_array(source_modifiers)

	_final_stats = StatSystem.calculate(_get_base_stats(), modifiers)
	stats_changed.emit()


func _get_base_stats() -> Dictionary:
	return {
		"strength": strength,
		"vitality": vitality,
		"life": life,
		"damage_min": damage_min,
		"damage_max": damage_max,
		"attack_speed": attack_speed,
		"move_speed": move_speed,
	}
