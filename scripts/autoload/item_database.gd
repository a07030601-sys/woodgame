extends Node

# 物品資料庫：啟動時讀取 data/ 裡的 JSON，並負責建立物品實例。

const BASES_PATH: String = "res://data/bases.json"
const AFFIXES_PATH: String = "res://data/affixes.json"
const RARE_NAMES_PATH: String = "res://data/rare_names.json"

const SLOT_WEAPON: String = "weapon"
const VALID_SLOTS: Array[String] = ["weapon", "helm", "armor", "gloves", "boots"]
const REQUIRED_BASE_FIELDS: Array[String] = ["id", "name", "type", "slot", "size", "max_sockets"]

const AFFIX_PREFIX: String = "prefix"
const AFFIX_SUFFIX: String = "suffix"
const REQUIRED_AFFIX_FIELDS: Array[String] = [
	"id", "name", "affix_type", "group", "weight", "allowed_types", "modifiers"
]
const REQUIRED_AFFIX_MODIFIER_FIELDS: Array[String] = ["stat", "type", "min", "max"]

# 底材 id -> 底材資料
var _bases: Dictionary = {}
# 詞綴 id -> 詞綴資料
var _affixes: Dictionary = {}
# 稀有物品名稱＝共用的第一段字詞 + 依底材 type 選的第二段字詞
var _rare_first_words: Array[String] = []
# 底材 type -> 第二段字詞的 Array[String]
var _rare_second_words: Dictionary = {}


func _ready() -> void:
	_load_bases()
	_load_affixes()
	_load_rare_names()


# 找不到時警告並回傳空的 Dictionary
func get_base(id: String) -> Dictionary:
	if not _bases.has(id):
		push_warning("ItemDatabase：找不到底材 %s" % id)
		return {}
	return _bases[id]


func has_base(id: String) -> bool:
	return _bases.has(id)


func get_base_count() -> int:
	return _bases.size()


# 所有底材的 id，順序與 bases.json 相同
func get_base_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_bases.keys())
	return ids


# 找不到時警告並回傳空的 Dictionary
func get_affix(id: String) -> Dictionary:
	if not _affixes.has(id):
		push_warning("ItemDatabase：找不到詞綴 %s" % id)
		return {}
	return _affixes[id]


func has_affix(id: String) -> bool:
	return _affixes.has(id)


func get_affix_count() -> int:
	return _affixes.size()


# 回傳可以出現在 base_type 上、類型為 affix_type（prefix 或 suffix）的所有詞綴
func get_affixes_for(base_type: String, affix_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for affix: Dictionary in _affixes.values():
		if affix["affix_type"] == affix_type and affix["allowed_types"].has(base_type):
			result.append(affix)
	return result


func get_rare_first_words() -> Array[String]:
	return _rare_first_words


# 該底材 type 沒有第二段字詞時回傳空陣列
func get_rare_second_words(base_type: String) -> Array[String]:
	var words: Array[String] = []
	if _rare_second_words.has(base_type):
		words.assign(_rare_second_words[base_type])
	return words


# 建立普通品質的物品實例，找不到底材時回傳 null。
# 有傳 rng 時用它擲防禦值，同一個種子會得到相同結果。
func create_item(base_id: String, rng: RandomNumberGenerator = null) -> ItemInstance:
	var base: Dictionary = get_base(base_id)
	if base.is_empty():
		return null

	var item: ItemInstance = ItemInstance.new()
	item.base_id = base_id
	item.quality = ItemInstance.QUALITY_NORMAL
	if base.has("defense"):
		var defense_range: Array = base["defense"]
		var defense_min: int = int(defense_range[0])
		var defense_max: int = int(defense_range[1])
		if rng != null:
			item.defense = rng.randi_range(defense_min, defense_max)
		else:
			item.defense = randi_range(defense_min, defense_max)
	return item


func _load_bases() -> void:
	_bases.clear()
	var data: Variant = _load_json(BASES_PATH, TYPE_ARRAY)
	if data == null:
		return

	for entry: Variant in data:
		if _is_valid_base(entry):
			_bases[entry["id"]] = entry


func _load_affixes() -> void:
	_affixes.clear()
	var data: Variant = _load_json(AFFIXES_PATH, TYPE_ARRAY)
	if data == null:
		return

	for entry: Variant in data:
		if _is_valid_affix(entry):
			_affixes[entry["id"]] = entry


func _load_rare_names() -> void:
	_rare_first_words.clear()
	_rare_second_words.clear()
	var data: Variant = _load_json(RARE_NAMES_PATH, TYPE_DICTIONARY)
	if data == null:
		return

	_rare_first_words = _read_word_list(data.get("first_words"), "first_words")

	var second_words: Variant = data.get("second_words")
	if typeof(second_words) != TYPE_DICTIONARY:
		push_warning("ItemDatabase：%s 的 second_words 必須是「底材 type -> 字詞陣列」" % RARE_NAMES_PATH)
		return
	for base_type: Variant in second_words:
		var words: Array[String] = _read_word_list(
			second_words[base_type], "second_words.%s" % str(base_type)
		)
		if not words.is_empty():
			_rare_second_words[str(base_type)] = words

	# 每種底材 type 都要有第二段字詞，否則該 type 的稀有物品會沒有名稱
	for base: Dictionary in _bases.values():
		if not _rare_second_words.has(base["type"]):
			push_warning(
				"ItemDatabase：%s 的 second_words 沒有 %s（底材 %s 會用到）"
				% [RARE_NAMES_PATH, base["type"], base["id"]]
			)


func _read_word_list(list: Variant, field: String) -> Array[String]:
	var words: Array[String] = []
	if typeof(list) != TYPE_ARRAY:
		push_warning("ItemDatabase：%s 的 %s 必須是陣列" % [RARE_NAMES_PATH, field])
		return words

	for word: Variant in list:
		if typeof(word) != TYPE_STRING or word == "":
			push_warning("ItemDatabase：略過 %s 裡不是文字的項目 %s" % [field, str(word)])
			continue
		words.append(word)
	if words.is_empty():
		push_warning("ItemDatabase：%s 的 %s 沒有任何字詞" % [RARE_NAMES_PATH, field])
	return words


# 讀取並解析 JSON，最外層型別必須是 expected_type。失敗時警告並回傳 null。
func _load_json(path: String, expected_type: int) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("ItemDatabase：找不到 %s" % path)
		return null

	var json: JSON = JSON.new()
	var error: Error = json.parse(FileAccess.get_file_as_string(path))
	if error != OK:
		push_warning(
			"ItemDatabase：%s 第 %d 行解析失敗：%s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return null
	if typeof(json.data) != expected_type:
		push_warning("ItemDatabase：%s 最外層的型別不對" % path)
		return null
	return json.data


# 有問題的底材只警告並略過，不讓遊戲崩潰
func _is_valid_base(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		push_warning("ItemDatabase：略過不是物件的底材 %s" % str(entry))
		return false

	for field: String in REQUIRED_BASE_FIELDS:
		if not entry.has(field):
			push_warning("ItemDatabase：略過缺少 %s 欄位的底材 %s" % [field, str(entry)])
			return false

	var id: Variant = entry["id"]
	if typeof(id) != TYPE_STRING or id == "":
		push_warning("ItemDatabase：略過 id 不合法的底材 %s" % str(entry))
		return false
	if _bases.has(id):
		push_warning("ItemDatabase：略過 id 重複的底材 %s" % id)
		return false

	var slot: Variant = entry["slot"]
	if typeof(slot) != TYPE_STRING or not VALID_SLOTS.has(slot):
		push_warning("ItemDatabase：略過 slot 不合法的底材 %s" % id)
		return false

	if not _is_number_pair(entry["size"]):
		push_warning("ItemDatabase：略過 size 不是 [寬, 高] 的底材 %s" % id)
		return false

	# 武器必須有 damage，防具必須有 defense
	var range_field: String = "damage" if slot == SLOT_WEAPON else "defense"
	if not entry.has(range_field) or not _is_number_pair(entry[range_field]):
		push_warning("ItemDatabase：略過 %s 不是 [最小, 最大] 的底材 %s" % [range_field, id])
		return false

	return true


# 有問題的詞綴只警告並略過，不讓遊戲崩潰
func _is_valid_affix(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		push_warning("ItemDatabase：略過不是物件的詞綴 %s" % str(entry))
		return false

	for field: String in REQUIRED_AFFIX_FIELDS:
		if not entry.has(field):
			push_warning("ItemDatabase：略過缺少 %s 欄位的詞綴 %s" % [field, str(entry)])
			return false

	var id: Variant = entry["id"]
	if typeof(id) != TYPE_STRING or id == "":
		push_warning("ItemDatabase：略過 id 不合法的詞綴 %s" % str(entry))
		return false
	if _affixes.has(id):
		push_warning("ItemDatabase：略過 id 重複的詞綴 %s" % id)
		return false

	if typeof(entry["name"]) != TYPE_STRING or entry["name"] == "":
		push_warning("ItemDatabase：略過 name 不合法的詞綴 %s" % id)
		return false

	var affix_type: Variant = entry["affix_type"]
	if typeof(affix_type) != TYPE_STRING or (affix_type != AFFIX_PREFIX and affix_type != AFFIX_SUFFIX):
		push_warning("ItemDatabase：略過 affix_type 不是 prefix 或 suffix 的詞綴 %s" % id)
		return false

	if typeof(entry["group"]) != TYPE_STRING or entry["group"] == "":
		push_warning("ItemDatabase：略過 group 不合法的詞綴 %s" % id)
		return false

	if not _is_number(entry["weight"]) or entry["weight"] <= 0:
		push_warning("ItemDatabase：略過 weight 不是正數的詞綴 %s" % id)
		return false

	var allowed_types: Variant = entry["allowed_types"]
	if typeof(allowed_types) != TYPE_ARRAY or allowed_types.is_empty():
		push_warning("ItemDatabase：略過 allowed_types 不是非空陣列的詞綴 %s" % id)
		return false
	for allowed_type: Variant in allowed_types:
		if typeof(allowed_type) != TYPE_STRING:
			push_warning("ItemDatabase：略過 allowed_types 含有非文字項目的詞綴 %s" % id)
			return false

	var modifiers: Variant = entry["modifiers"]
	if typeof(modifiers) != TYPE_ARRAY or modifiers.is_empty():
		push_warning("ItemDatabase：略過 modifiers 不是非空陣列的詞綴 %s" % id)
		return false
	for modifier: Variant in modifiers:
		if not _is_valid_affix_modifier(modifier, id):
			return false

	return true


func _is_valid_affix_modifier(modifier: Variant, affix_id: String) -> bool:
	if typeof(modifier) != TYPE_DICTIONARY:
		push_warning("ItemDatabase：略過 modifiers 含有非物件項目的詞綴 %s" % affix_id)
		return false

	for field: String in REQUIRED_AFFIX_MODIFIER_FIELDS:
		if not modifier.has(field):
			push_warning("ItemDatabase：略過修正值缺少 %s 欄位的詞綴 %s" % [field, affix_id])
			return false

	var stat: Variant = modifier["stat"]
	if typeof(stat) != TYPE_STRING or not StatSystem.STAT_NAMES.has(stat):
		push_warning(
			"ItemDatabase：略過詞綴 %s，stat 名稱 %s 不在 StatSystem 的屬性清單內"
			% [affix_id, str(stat)]
		)
		return false

	var modifier_type: Variant = modifier["type"]
	if typeof(modifier_type) != TYPE_STRING or (
		modifier_type != StatSystem.MODIFIER_FLAT and modifier_type != StatSystem.MODIFIER_PERCENT
	):
		push_warning("ItemDatabase：略過修正值 type 不是 flat 或 percent 的詞綴 %s" % affix_id)
		return false

	if not _is_number(modifier["min"]) or not _is_number(modifier["max"]):
		push_warning("ItemDatabase：略過修正值 min 或 max 不是數字的詞綴 %s" % affix_id)
		return false
	if modifier["min"] > modifier["max"]:
		push_warning("ItemDatabase：略過修正值 min 大於 max 的詞綴 %s" % affix_id)
		return false

	return true


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_number_pair(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return false
	for element: Variant in value:
		if not _is_number(element):
			return false
	return true
