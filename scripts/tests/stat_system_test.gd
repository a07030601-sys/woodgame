extends Node

# StatSystem 的測試：用 F6 執行 scenes/tests/stat_system_test.tscn，結果印在輸出面板。
# 「被忽略」的幾組會故意觸發 push_warning，除錯器出現黃色警告是預期行為。

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("===== StatSystem 測試開始 =====")

	_check(
		"只有 flat",
		{"strength": 10},
		[{"stat": "strength", "value": 5, "type": "flat"}],
		{"strength": 15.0}
	)
	_check(
		"只有 percent",
		{"life": 100},
		[{"stat": "life", "value": 20, "type": "percent"}],
		{"life": 120.0}
	)
	_check(
		"flat 加 percent 混合",
		{"damage_min": 10},
		[
			{"stat": "damage_min", "value": 5, "type": "flat"},
			{"stat": "damage_min", "value": 20, "type": "percent"},
		],
		{"damage_min": 18.0}
	)
	_check(
		"多筆同屬性疊加",
		{"life": 100},
		[
			{"stat": "life", "value": 10, "type": "flat"},
			{"stat": "life", "value": 20, "type": "flat"},
			{"stat": "life", "value": 10, "type": "percent"},
			{"stat": "life", "value": 15, "type": "percent"},
		],
		{"life": 162.5}
	)
	_check(
		"不同屬性互不影響",
		{"strength": 10, "move_speed": 200},
		[
			{"stat": "strength", "value": 50, "type": "percent"},
			{"stat": "move_speed", "value": 20, "type": "flat"},
		],
		{"strength": 15.0, "move_speed": 220.0}
	)
	_check(
		"負值修正",
		{"move_speed": 200},
		[{"stat": "move_speed", "value": -25, "type": "percent"}],
		{"move_speed": 150.0}
	)
	_check(
		"沒有修正值時等於基礎值，未提供的屬性為 0",
		{"vitality": 12},
		[],
		{"vitality": 12.0, "strength": 0.0}
	)
	_check(
		"錯誤屬性名稱被忽略",
		{"strength": 10},
		[
			{"stat": "luck", "value": 99, "type": "flat"},
			{"stat": "strength", "value": 5, "type": "flat"},
		],
		{"strength": 15.0}
	)
	_check(
		"錯誤 type 被忽略",
		{"strength": 10},
		[{"stat": "strength", "value": 99, "type": "multiply"}],
		{"strength": 10.0}
	)
	_check(
		"缺少欄位被忽略",
		{"strength": 10},
		[
			{"stat": "strength", "type": "flat"},
			{"value": 99, "type": "flat"},
			{"stat": "strength", "value": 99},
		],
		{"strength": 10.0}
	)

	_check(
		"10 點力量讓傷害變為 1.1 倍",
		{"strength": 10, "damage_min": 10, "damage_max": 20},
		[],
		{"damage_min": 11.0, "damage_max": 22.0}
	)
	_check(
		"10 點體力讓生命 +30",
		{"vitality": 10, "life": 100},
		[],
		{"life": 130.0}
	)
	_check(
		"力量的 percent 與裝備的 percent 相加而不是相乘",
		{"strength": 10, "damage_min": 10},
		[{"stat": "damage_min", "value": 20, "type": "percent"}],
		{"damage_min": 13.0}
	)
	_check(
		"衍生效果用的是力量的最終值",
		{"strength": 5, "damage_min": 10},
		[
			{"stat": "strength", "value": 5, "type": "flat"},
			{"stat": "strength", "value": 100, "type": "percent"},
		],
		{"strength": 20.0, "damage_min": 12.0}
	)
	_check(
		"體力給的生命併入 flat，再乘上生命的 percent",
		{"vitality": 10, "life": 100},
		[{"stat": "life", "value": 10, "type": "percent"}],
		{"life": 143.0}
	)

	print("===== 測試結束：%d PASS，%d FAIL =====" % [_pass_count, _fail_count])


# 只比對 expected 列出的屬性
func _check(title: String, base_stats: Dictionary, modifiers: Array, expected: Dictionary) -> void:
	var result: Dictionary = StatSystem.calculate(base_stats, modifiers)

	var errors: Array[String] = []
	for stat_name: String in expected:
		var expected_value: float = expected[stat_name]
		if not result.has(stat_name):
			errors.append("%s 不在結果中" % stat_name)
		elif not is_equal_approx(float(result[stat_name]), expected_value):
			errors.append("%s 預期 %s，實際 %s" % [stat_name, expected_value, result[stat_name]])

	if errors.is_empty():
		_pass_count += 1
		print("PASS  %s" % title)
	else:
		_fail_count += 1
		print("FAIL  %s：%s" % [title, "；".join(errors)])
