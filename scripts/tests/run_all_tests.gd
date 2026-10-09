extends Node

# 依序執行 scenes/tests/ 裡所有檔名以 _test.tscn 結尾的場景，印出各自與總計的結果。
# 全部通過時以結束碼 0 結束，有任何 FAIL（或找不到測試）時以結束碼 1 結束。
# 命令列執行方式：
#   C:\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/tests/run_all_tests.tscn

const TESTS_DIR: String = "res://scenes/tests/"
const TEST_SCENE_SUFFIX: String = "_test.tscn"

var _total_pass: int = 0
var _total_fail: int = 0
# 每個測試一行的結果，最後一起印出
var _summary_lines: Array[String] = []


func _ready() -> void:
	var scene_files: Array[String] = _find_test_scenes()
	if scene_files.is_empty():
		print("FAIL  在 %s 找不到任何 *%s" % [TESTS_DIR, TEST_SCENE_SUFFIX])
		get_tree().quit(1)
		return

	for scene_file: String in scene_files:
		await _run_test_scene(scene_file)
		print("")

	print("===== 全部測試結果 =====")
	for line: String in _summary_lines:
		print(line)
	print("總計：%d PASS，%d FAIL" % [_total_pass, _total_fail])

	get_tree().quit(0 if _total_fail == 0 else 1)


func _find_test_scenes() -> Array[String]:
	var scene_files: Array[String] = []
	for file_name: String in DirAccess.get_files_at(TESTS_DIR):
		if file_name.ends_with(TEST_SCENE_SUFFIX):
			scene_files.append(file_name)
	scene_files.sort()
	return scene_files


func _run_test_scene(scene_file: String) -> void:
	var scene: PackedScene = load(TESTS_DIR + scene_file) as PackedScene
	if scene == null:
		_record(scene_file, 0, 1, "場景載入失敗")
		return

	var instance: Node = scene.instantiate()
	var test: TestBase = instance as TestBase
	if test == null:
		instance.free()
		_record(scene_file, 0, 1, "根節點的腳本沒有繼承 TestBase")
		return

	# 加入場景樹時測試就會開始跑；大多數測試在這一行結束時就已經跑完
	add_child(test)
	if not test.is_finished:
		await test.finished

	if test.pass_count + test.fail_count == 0:
		_record(scene_file, 0, 1, "沒有執行任何 check()")
	else:
		_record(scene_file, test.pass_count, test.fail_count, "")
	test.queue_free()


func _record(scene_file: String, pass_count: int, fail_count: int, problem: String) -> void:
	_total_pass += pass_count
	_total_fail += fail_count
	var line: String = "%s：%d PASS，%d FAIL" % [scene_file, pass_count, fail_count]
	if not problem.is_empty():
		line += "（%s）" % problem
		print("FAIL  %s：%s" % [scene_file, problem])
	_summary_lines.append(line)
