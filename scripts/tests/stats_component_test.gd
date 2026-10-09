extends Node

# StatsComponent 的測試：用 F6 執行 scenes/tests/stats_component_test.tscn，結果印在輸出面板。

var _pass_count: int = 0
var _fail_count: int = 0
var _signal_count: int = 0


func _ready() -> void:
	print("===== StatsComponent 測試開始 =====")

	var stats: StatsComponent = StatsComponent.new()
	stats.strength = 10.0
	stats.life = 100.0
	add_child(stats)
	stats.stats_changed.connect(_on_stats_changed)

	_check_value("初始值等於基礎值", stats.get_stat("strength"), 10.0)

	stats.add_source("ring", [{"stat": "strength", "value": 5, "type": "flat"}])
	_check_value("加入來源後數值改變", stats.get_stat("strength"), 15.0)
	_check_true("加入後 has_source 為 true", stats.has_source("ring"))
	_check_value("其他屬性不受影響", stats.get_stat("life"), 100.0)
	_check_value("加入來源時發出 stats_changed", float(_signal_count), 1.0)

	stats.add_source("ring", [{"stat": "strength", "value": 5, "type": "flat"}])
	_check_value("同一來源重複加入是覆蓋而不是疊加", stats.get_stat("strength"), 15.0)

	stats.add_source("ring", [{"stat": "strength", "value": 8, "type": "flat"}])
	_check_value("同一來源換成新的修正值", stats.get_stat("strength"), 18.0)

	stats.add_source("amulet", [{"stat": "strength", "value": 50, "type": "percent"}])
	_check_value("不同來源會疊加", stats.get_stat("strength"), 27.0)

	stats.remove_source("ring")
	_check_value("移除一個來源後只剩另一個", stats.get_stat("strength"), 15.0)
	_check_true("移除後 has_source 為 false", not stats.has_source("ring"))

	stats.remove_source("amulet")
	_check_value("移除所有來源後恢復基礎值", stats.get_stat("strength"), 10.0)

	_signal_count = 0
	stats.remove_source("not_exist")
	_check_value("移除不存在的來源不會出錯也不發訊號", float(_signal_count), 0.0)

	print("===== 測試結束：%d PASS，%d FAIL =====" % [_pass_count, _fail_count])


func _check_value(title: String, actual: float, expected: float) -> void:
	if is_equal_approx(actual, expected):
		_pass_count += 1
		print("PASS  %s" % title)
	else:
		_fail_count += 1
		print("FAIL  %s：預期 %s，實際 %s" % [title, expected, actual])


func _check_true(title: String, condition: bool) -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % title)
	else:
		_fail_count += 1
		print("FAIL  %s" % title)


func _on_stats_changed() -> void:
	_signal_count += 1
