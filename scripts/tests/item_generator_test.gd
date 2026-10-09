extends Node

# ItemGenerator 的測試：用 F6 執行 scenes/tests/item_generator_test.tscn，結果印在輸出面板。
# 使用固定種子，每次執行的結果都相同。

const TEST_SEED: int = 20261010
const ITEMS_PER_QUALITY: int = 1000
const SAMPLE_COUNT: int = 5
# data/affixes.json 裡的詞綴數量，新增詞綴時要一起更新
const EXPECTED_AFFIX_COUNT: int = 12
const NAME_FORMAT_CHECK: String = "名稱格式"
const BASE_IDS: Array[String] = [
	"short_sword", "hand_axe", "leather_cap", "leather_armor", "leather_gloves", "leather_boots"
]

var _pass_count: int = 0
var _fail_count: int = 0
# 檢查項目 -> 第一個出錯的說明；沒出錯的項目不會出現在裡面
var _failures: Dictionary = {}


func _ready() -> void:
	print("===== ItemGenerator 測試開始（種子 %d）=====" % TEST_SEED)

	_test_data_loaded()
	_test_normal()
	_test_quality(ItemInstance.QUALITY_MAGIC, "魔法", 1, 2, 1, "名稱是「後綴 + 前綴 + 底材名」，以底材名結尾")
	_test_quality(ItemInstance.QUALITY_RARE, "稀有", 3, 4, 2, "名稱的第二段符合底材 type，且不含底材名")
	_test_magic_combinations()
	_test_same_seed_is_reproducible()
	_test_quality_colors()

	print("===== 測試結束：%d PASS，%d FAIL =====" % [_pass_count, _fail_count])

	_print_samples(ItemInstance.QUALITY_MAGIC, "魔法")
	_print_samples(ItemInstance.QUALITY_RARE, "稀有")


func _test_data_loaded() -> void:
	_check(
		"詞綴載入數量正確",
		ItemDatabase.get_affix_count() == EXPECTED_AFFIX_COUNT,
		"預期 %d，實際 %d" % [EXPECTED_AFFIX_COUNT, ItemDatabase.get_affix_count()]
	)
	_check(
		"稀有名稱的兩組字詞都有載入",
		not ItemDatabase.get_rare_first_words().is_empty()
		and not ItemDatabase.get_rare_second_words("sword").is_empty(),
		""
	)


func _test_normal() -> void:
	var rng: RandomNumberGenerator = _new_rng()
	var all_ok: bool = true
	for base_id: String in BASE_IDS:
		var item: ItemInstance = ItemGenerator.generate(base_id, ItemInstance.QUALITY_NORMAL, rng)
		var base_name: String = ItemDatabase.get_base(base_id)["name"]
		if not item.affixes.is_empty() or item.get_display_name() != base_name or item.get_base_name() != base_name:
			all_ok = false
	_check("普通物品沒有詞綴，名稱等於底材名", all_ok, "")


# 生成 ITEMS_PER_QUALITY 件物品逐一檢查，每個檢查項目最後各印一行 PASS 或 FAIL
func _test_quality(
	quality: String,
	label: String,
	min_affixes: int,
	max_affixes: int,
	max_per_type: int,
	name_check_title: String
) -> void:
	var rng: RandomNumberGenerator = _new_rng()
	_failures.clear()

	for i: int in ITEMS_PER_QUALITY:
		var base_id: String = BASE_IDS[i % BASE_IDS.size()]
		var item: ItemInstance = ItemGenerator.generate(base_id, quality, rng)
		_inspect_item(item, min_affixes, max_affixes, max_per_type)

	for check_name: String in [
		"詞綴數量與前後綴上限",
		"沒有重複 group",
		"詞綴都符合底材 type",
		"擲出的數值在範圍內且為整數",
		"get_modifiers 包含底材與所有詞綴的修正值",
		"名稱不為空",
		"to_dict 還原後內容相同",
		"經過 JSON 文字再還原後內容相同",
	]:
		_check(
			"%s %d 件：%s" % [label, ITEMS_PER_QUALITY, check_name],
			not _failures.has(check_name),
			str(_failures.get(check_name, ""))
		)
	# 名稱格式依品質不同，標題由呼叫端指定
	_check(
		"%s %d 件：%s" % [label, ITEMS_PER_QUALITY, name_check_title],
		not _failures.has(NAME_FORMAT_CHECK),
		str(_failures.get(NAME_FORMAT_CHECK, ""))
	)


func _inspect_item(item: ItemInstance, min_affixes: int, max_affixes: int, max_per_type: int) -> void:
	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	var prefix_count: int = 0
	var suffix_count: int = 0
	var prefix_name: String = ""
	var suffix_name: String = ""
	var groups: Array[String] = []
	var affix_modifier_count: int = 0

	for affix: Dictionary in item.affixes:
		var data: Dictionary = ItemDatabase.get_affix(affix["id"])
		if data["affix_type"] == ItemDatabase.AFFIX_PREFIX:
			prefix_count += 1
			prefix_name = data["name"]
		else:
			suffix_count += 1
			suffix_name = data["name"]

		if groups.has(data["group"]):
			_fail("沒有重複 group", "%s 重複了 group %s" % [item.base_id, data["group"]])
		groups.append(data["group"])

		if not data["allowed_types"].has(base["type"]):
			_fail("詞綴都符合底材 type", "%s 出現在 %s 上" % [affix["id"], item.base_id])

		var rolled: Array = affix["modifiers"]
		var definitions: Array = data["modifiers"]
		affix_modifier_count += rolled.size()
		if rolled.size() != definitions.size():
			_fail("擲出的數值在範圍內且為整數", "%s 的修正值數量不對" % affix["id"])
			continue
		for index: int in rolled.size():
			var modifier: Dictionary = rolled[index]
			var definition: Dictionary = definitions[index]
			var value: float = modifier["value"]
			if (
				modifier["stat"] != definition["stat"]
				or modifier["type"] != definition["type"]
				or value < definition["min"]
				or value > definition["max"]
				or not is_equal_approx(value, roundf(value))
			):
				_fail("擲出的數值在範圍內且為整數", "%s 擲出 %s" % [affix["id"], str(modifier)])

	var total: int = prefix_count + suffix_count
	if total < min_affixes or total > max_affixes or prefix_count > max_per_type or suffix_count > max_per_type:
		_fail(
			"詞綴數量與前後綴上限",
			"%s 有 %d 個前綴、%d 個後綴" % [item.base_id, prefix_count, suffix_count]
		)

	# 武器的底材提供 2 筆修正值，防具提供 1 筆
	var base_modifier_count: int = 2 if base.has("damage") else 1
	if item.get_modifiers().size() != base_modifier_count + affix_modifier_count:
		_fail("get_modifiers 包含底材與所有詞綴的修正值", "實際 %s" % str(item.get_modifiers()))

	if item.get_display_name().is_empty():
		_fail("名稱不為空", "%s 的名稱是空的" % item.base_id)
	if item.quality == ItemInstance.QUALITY_RARE and item.rare_name.is_empty():
		_fail("名稱不為空", "%s 沒有稀有名稱" % item.base_id)

	var display_name: String = item.get_display_name()
	var base_name: String = base["name"]
	if item.get_base_name() != base_name:
		_fail(NAME_FORMAT_CHECK, "%s 的 get_base_name 是 %s" % [item.base_id, item.get_base_name()])
	if item.quality == ItemInstance.QUALITY_MAGIC:
		if not display_name.ends_with(base_name) or display_name != suffix_name + prefix_name + base_name:
			_fail(NAME_FORMAT_CHECK, "%s 的名稱是 %s" % [item.base_id, display_name])
	elif item.quality == ItemInstance.QUALITY_RARE:
		if display_name != item.rare_name or display_name.contains(base_name):
			_fail(NAME_FORMAT_CHECK, "%s 的名稱是 %s" % [item.base_id, display_name])
		elif not _is_rare_name_for_type(display_name, base["type"]):
			_fail(NAME_FORMAT_CHECK, "%s（%s）的名稱是 %s" % [item.base_id, base["type"], display_name])

	var saved: Dictionary = item.to_dict()
	var restored: ItemInstance = ItemInstance.from_dict(saved)
	if (
		restored.to_dict() != saved
		or restored.get_display_name() != item.get_display_name()
		or restored.get_modifiers() != item.get_modifiers()
	):
		_fail("to_dict 還原後內容相同", "原本 %s，還原後 %s" % [str(saved), str(restored.to_dict())])

	var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(saved)))
	if from_json.to_dict() != saved or from_json.get_modifiers() != item.get_modifiers():
		_fail(
			"經過 JSON 文字再還原後內容相同",
			"原本 %s，還原後 %s" % [str(saved), str(from_json.to_dict())]
		)


# 稀有名稱必須是「共用的第一段 + 該底材 type 的第二段」
func _is_rare_name_for_type(rare_name: String, base_type: String) -> bool:
	for second_word: String in ItemDatabase.get_rare_second_words(base_type):
		if rare_name.ends_with(second_word):
			var first_word: String = rare_name.trim_suffix(second_word)
			if ItemDatabase.get_rare_first_words().has(first_word):
				return true
	return false


func _test_magic_combinations() -> void:
	var rng: RandomNumberGenerator = _new_rng()
	var seen_prefix_only: bool = false
	var seen_suffix_only: bool = false
	var seen_both: bool = false

	for i: int in ITEMS_PER_QUALITY:
		var item: ItemInstance = ItemGenerator.generate(
			BASE_IDS[i % BASE_IDS.size()], ItemInstance.QUALITY_MAGIC, rng
		)
		var has_prefix: bool = false
		var has_suffix: bool = false
		for affix: Dictionary in item.affixes:
			if ItemDatabase.get_affix(affix["id"])["affix_type"] == ItemDatabase.AFFIX_PREFIX:
				has_prefix = true
			else:
				has_suffix = true
		if has_prefix and has_suffix:
			seen_both = true
		elif has_prefix:
			seen_prefix_only = true
		elif has_suffix:
			seen_suffix_only = true

	_check(
		"魔法物品出現過只有前綴、只有後綴、兩者都有三種組合",
		seen_prefix_only and seen_suffix_only and seen_both,
		"只有前綴 %s、只有後綴 %s、兩者都有 %s" % [seen_prefix_only, seen_suffix_only, seen_both]
	)


func _test_same_seed_is_reproducible() -> void:
	var first: Array[Dictionary] = _generate_batch()
	var second: Array[Dictionary] = _generate_batch()
	_check("相同種子生成的物品完全相同", first == second, "")


func _generate_batch() -> Array[Dictionary]:
	var rng: RandomNumberGenerator = _new_rng()
	var batch: Array[Dictionary] = []
	for i: int in 60:
		var quality: String = ItemInstance.QUALITY_MAGIC if i % 2 == 0 else ItemInstance.QUALITY_RARE
		batch.append(ItemGenerator.generate(BASE_IDS[i % BASE_IDS.size()], quality, rng).to_dict())
	return batch


func _test_quality_colors() -> void:
	var rng: RandomNumberGenerator = _new_rng()
	var normal: Color = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_NORMAL, rng).get_quality_color()
	var magic: Color = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_MAGIC, rng).get_quality_color()
	var rare: Color = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_RARE, rng).get_quality_color()
	_check(
		"品質顏色：普通白、魔法偏藍、稀有偏黃",
		normal == Color.WHITE and magic.b > magic.r and rare.r > rare.b and rare.g > rare.b,
		"普通 %s、魔法 %s、稀有 %s" % [normal, magic, rare]
	)


func _print_samples(quality: String, label: String) -> void:
	print("")
	print("----- %s物品範例 -----" % label)
	var rng: RandomNumberGenerator = _new_rng()
	for i: int in SAMPLE_COUNT:
		# 跳著選底材，讓範例裡武器和防具都看得到
		var base_id: String = BASE_IDS[(i * 5 + 1) % BASE_IDS.size()]
		var item: ItemInstance = ItemGenerator.generate(base_id, quality, rng)
		print("%s（%s）" % [item.get_display_name(), item.get_base_name()])
		for modifier: Dictionary in item.get_modifiers():
			var suffix: String = "%" if modifier["type"] == "percent" else ""
			print("    %s %+d%s" % [modifier["stat"], int(modifier["value"]), suffix])


func _new_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	return rng


# 記下某個檢查項目第一次出錯的說明
func _fail(check_name: String, detail: String) -> void:
	if not _failures.has(check_name):
		_failures[check_name] = detail


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
