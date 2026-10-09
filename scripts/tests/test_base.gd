class_name TestBase
extends Node

# 所有測試共用的基底。測試腳本繼承它，覆寫 _get_test_name() 與 _run_tests()，
# 在 _run_tests() 裡用 check() 記錄每一項結果。
# 場景檔名以 _test.tscn 結尾並放在 scenes/tests/，run_all_tests 就會自動執行它。
# 單獨用 F6 執行測試場景也可以，結果一樣印在輸出面板。

signal finished

var pass_count: int = 0
var fail_count: int = 0
var is_finished: bool = false


func _ready() -> void:
	print("===== %s 測試開始%s =====" % [_get_test_name(), _get_header_note()])
	await _run_tests()
	print("===== 測試結束：%d PASS，%d FAIL =====" % [pass_count, fail_count])
	_after_tests()
	is_finished = true
	finished.emit()


# 記錄一項測試結果。detail 只在 FAIL 時印出，用來說明預期與實際的差異。
func check(title: String, condition: bool, detail: String = "") -> void:
	if condition:
		pass_count += 1
		print("PASS  %s" % title)
	elif detail.is_empty():
		fail_count += 1
		print("FAIL  %s" % title)
	else:
		fail_count += 1
		print("FAIL  %s：%s" % [title, detail])


# 顯示在開頭那一行的測試名稱
func _get_test_name() -> String:
	return name


# 接在開頭那一行「測試開始」後面的補充說明，例如使用的種子
func _get_header_note() -> String:
	return ""


# 子類別在這裡呼叫 check()
func _run_tests() -> void:
	pass


# 總結行之後要額外印出的內容，例如範例資料
func _after_tests() -> void:
	pass
