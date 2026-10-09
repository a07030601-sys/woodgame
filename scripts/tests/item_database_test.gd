extends Node

# ItemDatabase 與 ItemInstance 的測試：用 F6 執行 scenes/tests/item_database_test.tscn。
# 最後一組會故意查詢不存在的底材，除錯器出現 2 則黃色警告是預期行為。

# data/bases.json 裡的底材數量，新增底材時要一起更新
const EXPECTED_BASE_COUNT: int = 6
const DEFENSE_ROLL_COUNT: int = 100

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("===== ItemDatabase 測試開始 =====")

	_test_loading()
	_test_weapon_modifiers()
	_test_armor_modifiers()
	_test_serialization()
	_test_missing_base()

	print("===== 測試結束：%d PASS，%d FAIL =====" % [_pass_count, _fail_count])


func _test_loading() -> void:
	_check(
		"資料載入數量正確",
		ItemDatabase.get_base_count() == EXPECTED_BASE_COUNT,
		"預期 %d，實際 %d" % [EXPECTED_BASE_COUNT, ItemDatabase.get_base_count()]
	)

	var all_found: bool = true
	for base_id: String in [
		"short_sword", "hand_axe", "leather_cap", "leather_armor", "leather_gloves", "leather_boots"
	]:
		if not ItemDatabase.has_base(base_id):
			all_found = false
	_check("六個底材都查得到", all_found, "有底材查不到")

	var sword: Dictionary = ItemDatabase.get_base("short_sword")
	_check(
		"底材欄位內容正確",
		sword.get("name") == "短劍" and sword.get("slot") == "weapon" and sword.get("type") == "sword",
		"短劍的資料是 %s" % str(sword)
	)


func _test_weapon_modifiers() -> void:
	var base: Dictionary = ItemDatabase.get_base("short_sword")
	var item: ItemInstance = ItemDatabase.create_item("short_sword")
	var modifiers: Array[Dictionary] = item.get_modifiers()
	var damage: Array = base["damage"]

	var expected: Array[Dictionary] = [
		{"stat": "damage_min", "value": float(damage[0]), "type": "flat"},
		{"stat": "damage_max", "value": float(damage[1]), "type": "flat"},
	]
	_check("武器的 get_modifiers 結果正確", modifiers == expected, "實際 %s" % str(modifiers))
	_check("武器是普通品質且沒有防禦值", item.quality == "normal" and item.defense == 0, "")

	var stats: Dictionary = StatSystem.calculate({"damage_min": 1, "damage_max": 2}, modifiers)
	_check(
		"武器的修正值可以交給 StatSystem 計算",
		is_equal_approx(stats["damage_min"], 1.0 + float(damage[0]))
		and is_equal_approx(stats["damage_max"], 2.0 + float(damage[1])),
		"實際 %s 到 %s" % [stats["damage_min"], stats["damage_max"]]
	)


func _test_armor_modifiers() -> void:
	var base: Dictionary = ItemDatabase.get_base("leather_armor")
	var defense_range: Array = base["defense"]
	var item: ItemInstance = ItemDatabase.create_item("leather_armor")
	var modifiers: Array[Dictionary] = item.get_modifiers()

	var expected: Array[Dictionary] = [
		{"stat": "defense", "value": float(item.defense), "type": "flat"},
	]
	_check("防具的 get_modifiers 結果正確", modifiers == expected, "實際 %s" % str(modifiers))

	var all_in_range: bool = true
	for i: int in DEFENSE_ROLL_COUNT:
		var rolled: ItemInstance = ItemDatabase.create_item("leather_armor")
		if rolled.defense < int(defense_range[0]) or rolled.defense > int(defense_range[1]):
			all_in_range = false
	_check("防具的防禦值都在底材的範圍內", all_in_range, "擲出範圍外的防禦值")

	var stats: Dictionary = StatSystem.calculate({}, modifiers)
	_check(
		"防具的修正值可以交給 StatSystem 計算",
		is_equal_approx(stats["defense"], float(item.defense)),
		"預期 %d，實際 %s" % [item.defense, stats["defense"]]
	)


func _test_serialization() -> void:
	var item: ItemInstance = ItemDatabase.create_item("leather_cap")
	item.quality = "magic"
	item.sockets = 2
	item.socketed_runes.append("test_rune")
	item.affixes.append({"id": "test_affix", "value": 5.0})

	var saved: Dictionary = item.to_dict()
	var restored: ItemInstance = ItemInstance.from_dict(saved)
	_check(
		"to_dict 後 from_dict 還原的物品內容與原本相同",
		restored.base_id == item.base_id
		and restored.quality == item.quality
		and restored.sockets == item.sockets
		and restored.defense == item.defense
		and restored.socketed_runes == item.socketed_runes
		and restored.affixes == item.affixes,
		"還原後是 %s" % str(restored.to_dict())
	)
	_check("還原後再 to_dict 的結果相同", restored.to_dict() == saved, "")
	_check(
		"還原後的 get_modifiers 相同",
		restored.get_modifiers() == item.get_modifiers(),
		"實際 %s" % str(restored.get_modifiers())
	)

	restored.socketed_runes.append("another_rune")
	_check("還原的物品與原本的物品互不影響", item.socketed_runes.size() == 1, "")

	# 存檔會經過 JSON，數字讀回來都是 float
	var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(
		"經過 JSON 文字再還原仍然相同",
		from_json.base_id == item.base_id
		and from_json.quality == item.quality
		and from_json.sockets == item.sockets
		and from_json.defense == item.defense
		and from_json.socketed_runes == item.socketed_runes,
		"還原後是 %s" % str(from_json.to_dict())
	)


func _test_missing_base() -> void:
	_check("不存在的 base_id 用 get_base 回傳空值", ItemDatabase.get_base("not_exist").is_empty(), "")
	_check("不存在的 base_id 用 create_item 回傳 null", ItemDatabase.create_item("not_exist") == null, "")


func _check(title: String, condition: bool, detail: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS  %s" % title)
	elif detail.is_empty():
		_fail_count += 1
		print("FAIL  %s" % title)
	else:
		_fail_count += 1
		print("FAIL  %s：%s" % [title, detail])
