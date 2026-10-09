extends Node

# 物品資料庫：啟動時讀取 data/ 裡的 JSON，並負責建立物品實例。

const BASES_PATH: String = "res://data/bases.json"
const SLOT_WEAPON: String = "weapon"
const VALID_SLOTS: Array[String] = ["weapon", "helm", "armor", "gloves", "boots"]
const REQUIRED_BASE_FIELDS: Array[String] = ["id", "name", "type", "slot", "size", "max_sockets"]

# 底材 id -> 底材資料
var _bases: Dictionary = {}


func _ready() -> void:
	_load_bases()


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


# 建立普通品質的物品實例，找不到底材時回傳 null
func create_item(base_id: String) -> ItemInstance:
	var base: Dictionary = get_base(base_id)
	if base.is_empty():
		return null

	var item: ItemInstance = ItemInstance.new()
	item.base_id = base_id
	item.quality = ItemInstance.QUALITY_NORMAL
	if base.has("defense"):
		var defense_range: Array = base["defense"]
		item.defense = randi_range(int(defense_range[0]), int(defense_range[1]))
	return item


func _load_bases() -> void:
	_bases.clear()

	if not FileAccess.file_exists(BASES_PATH):
		push_warning("ItemDatabase：找不到 %s" % BASES_PATH)
		return

	var json: JSON = JSON.new()
	var error: Error = json.parse(FileAccess.get_file_as_string(BASES_PATH))
	if error != OK:
		push_warning(
			"ItemDatabase：%s 第 %d 行解析失敗：%s"
			% [BASES_PATH, json.get_error_line(), json.get_error_message()]
		)
		return
	if typeof(json.data) != TYPE_ARRAY:
		push_warning("ItemDatabase：%s 最外層必須是陣列" % BASES_PATH)
		return

	for entry: Variant in json.data:
		if not _is_valid_base(entry):
			continue
		_bases[entry["id"]] = entry


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


func _is_number_pair(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 2:
		return false
	for element: Variant in value:
		if typeof(element) != TYPE_INT and typeof(element) != TYPE_FLOAT:
			return false
	return true
