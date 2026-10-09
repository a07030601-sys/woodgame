extends Node

# 屬性計算核心：只負責計算，不保存任何角色的資料。
# 修正值格式：{"stat": String, "value": float, "type": "flat" 或 "percent"}
# percent 的 value 以百分比表示，20 代表 +20%。
# 公式：（基礎值 + 所有 flat 總和）×（1 + 所有 percent 總和 ÷ 100）

const MODIFIER_FLAT: String = "flat"
const MODIFIER_PERCENT: String = "percent"

const STAT_NAMES: Array[String] = [
	"strength",
	"vitality",
	"life",
	"damage_min",
	"damage_max",
	"attack_speed",
	"move_speed",
]


# 回傳的 Dictionary 包含 STAT_NAMES 的每個屬性，值為 float 且不四捨五入。
# base_stats 沒提供的屬性視為 0。
func calculate(base_stats: Dictionary, modifiers: Array) -> Dictionary:
	var flat_totals: Dictionary = {}
	var percent_totals: Dictionary = {}
	for stat_name: String in STAT_NAMES:
		flat_totals[stat_name] = 0.0
		percent_totals[stat_name] = 0.0

	for modifier: Variant in modifiers:
		if not _is_valid_modifier(modifier):
			continue
		var stat_name: String = modifier["stat"]
		var value: float = float(modifier["value"])
		if modifier["type"] == MODIFIER_FLAT:
			flat_totals[stat_name] += value
		else:
			percent_totals[stat_name] += value

	for key: Variant in base_stats:
		if typeof(key) != TYPE_STRING or not STAT_NAMES.has(key):
			push_warning("StatSystem：忽略不支援的基礎屬性 %s" % str(key))

	var final_stats: Dictionary = {}
	for stat_name: String in STAT_NAMES:
		var base_value: float = _get_base_value(base_stats, stat_name)
		var flat_total: float = flat_totals[stat_name]
		var percent_total: float = percent_totals[stat_name]
		final_stats[stat_name] = (base_value + flat_total) * (1.0 + percent_total / 100.0)
	return final_stats


func _get_base_value(base_stats: Dictionary, stat_name: String) -> float:
	if not base_stats.has(stat_name):
		return 0.0
	var value: Variant = base_stats[stat_name]
	if not _is_number(value):
		push_warning("StatSystem：基礎屬性 %s 的值不是數字，視為 0" % stat_name)
		return 0.0
	return float(value)


# 格式不對的修正值只警告並忽略，不讓遊戲崩潰
func _is_valid_modifier(modifier: Variant) -> bool:
	if typeof(modifier) != TYPE_DICTIONARY:
		push_warning("StatSystem：忽略不是 Dictionary 的修正值 %s" % str(modifier))
		return false

	for field: String in ["stat", "value", "type"]:
		if not modifier.has(field):
			push_warning("StatSystem：忽略缺少 %s 欄位的修正值 %s" % [field, str(modifier)])
			return false

	if typeof(modifier["stat"]) != TYPE_STRING or not STAT_NAMES.has(modifier["stat"]):
		push_warning("StatSystem：忽略屬性名稱不在清單內的修正值 %s" % str(modifier))
		return false

	if not _is_number(modifier["value"]):
		push_warning("StatSystem：忽略 value 不是數字的修正值 %s" % str(modifier))
		return false

	var modifier_type: Variant = modifier["type"]
	if typeof(modifier_type) != TYPE_STRING or (modifier_type != MODIFIER_FLAT and modifier_type != MODIFIER_PERCENT):
		push_warning("StatSystem：忽略 type 不是 flat 或 percent 的修正值 %s" % str(modifier))
		return false

	return true


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
