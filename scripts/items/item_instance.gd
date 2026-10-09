class_name ItemInstance
extends RefCounted

# 一件實際存在的物品。底材與詞綴的固定資料（名稱、傷害範圍等）不存在這裡，
# 需要時用 id 向 ItemDatabase 查詢。

const QUALITY_NORMAL: String = "normal"
const QUALITY_MAGIC: String = "magic"
const QUALITY_RARE: String = "rare"

const COLOR_NORMAL: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_MAGIC: Color = Color(0.45, 0.55, 1.0, 1.0)
const COLOR_RARE: Color = Color(1.0, 0.95, 0.35, 1.0)

var base_id: String = ""
var quality: String = QUALITY_NORMAL
var sockets: int = 0
# 已鑲嵌的符文 id，依鑲嵌順序排列
var socketed_runes: Array[String] = []
# 每個詞綴是 {"id": 詞綴 id, "modifiers": [已擲好數值的修正值, ...]}，修正值格式見 StatSystem
var affixes: Array = []
# 生成時擲出的防禦值，武器為 0
var defense: int = 0
# 稀有物品生成時擲出的名稱，其他品質為空字串
var rare_name: String = ""


# 回傳這件物品提供的所有修正值，格式見 StatSystem。符文之後再加。
func get_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []

	var base: Dictionary = ItemDatabase.get_base(base_id)
	if base.has("damage"):
		var damage: Array = base["damage"]
		modifiers.append({"stat": "damage_min", "value": float(damage[0]), "type": "flat"})
		modifiers.append({"stat": "damage_max", "value": float(damage[1]), "type": "flat"})
	if base.has("defense"):
		modifiers.append({"stat": "defense", "value": float(defense), "type": "flat"})

	modifiers.append_array(get_affix_modifiers())
	return modifiers


# 只回傳詞綴提供的修正值，不含底材本身的傷害或防禦
func get_affix_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	for affix: Variant in affixes:
		if typeof(affix) != TYPE_DICTIONARY:
			continue
		var affix_modifiers: Variant = affix.get("modifiers", [])
		if typeof(affix_modifiers) != TYPE_ARRAY:
			continue
		for modifier: Variant in affix_modifiers:
			if typeof(modifier) == TYPE_DICTIONARY:
				modifiers.append(modifier.duplicate())

	return modifiers


# 背包佔用的格數 [寬, 高]，查不到底材時回傳 Vector2i.ZERO
func get_size() -> Vector2i:
	var base: Dictionary = ItemDatabase.get_base(base_id)
	if base.is_empty():
		return Vector2i.ZERO
	var size: Array = base["size"]
	return Vector2i(int(size[0]), int(size[1]))


# 底材的裝備欄位（weapon、helm 等），查不到底材時回傳空字串
func get_slot() -> String:
	var base: Dictionary = ItemDatabase.get_base(base_id)
	return str(base.get("slot", ""))


func get_base_name() -> String:
	var base: Dictionary = ItemDatabase.get_base(base_id)
	return str(base.get("name", base_id))


# 普通：底材名。魔法：後綴 + 前綴 + 底材名，底材名一律在最後。
# 稀有：生成時擲出的名稱，不含底材名，要顯示底材請另外用 get_base_name()。
func get_display_name() -> String:
	var base_name: String = get_base_name()

	if quality == QUALITY_RARE and not rare_name.is_empty():
		return rare_name
	if quality != QUALITY_MAGIC:
		return base_name

	var prefix_name: String = ""
	var suffix_name: String = ""
	for affix: Variant in affixes:
		if typeof(affix) != TYPE_DICTIONARY:
			continue
		var affix_data: Dictionary = ItemDatabase.get_affix(str(affix.get("id", "")))
		if affix_data.is_empty():
			continue
		if affix_data["affix_type"] == ItemDatabase.AFFIX_PREFIX:
			prefix_name = affix_data["name"]
		else:
			suffix_name = affix_data["name"]
	return suffix_name + prefix_name + base_name


func get_quality_color() -> Color:
	if quality == QUALITY_MAGIC:
		return COLOR_MAGIC
	if quality == QUALITY_RARE:
		return COLOR_RARE
	return COLOR_NORMAL


func to_dict() -> Dictionary:
	return {
		"base_id": base_id,
		"quality": quality,
		"sockets": sockets,
		"socketed_runes": socketed_runes.duplicate(),
		"affixes": affixes.duplicate(true),
		"defense": defense,
		"rare_name": rare_name,
	}


# 缺少的欄位使用預設值。從 JSON 讀回來的數字是 float，這裡會轉回 int。
static func from_dict(data: Dictionary) -> ItemInstance:
	var item: ItemInstance = ItemInstance.new()
	item.base_id = str(data.get("base_id", ""))
	item.quality = str(data.get("quality", QUALITY_NORMAL))
	item.sockets = int(data.get("sockets", 0))
	item.defense = int(data.get("defense", 0))
	item.rare_name = str(data.get("rare_name", ""))

	var rune_ids: Variant = data.get("socketed_runes", [])
	if typeof(rune_ids) == TYPE_ARRAY:
		for rune_id: Variant in rune_ids:
			item.socketed_runes.append(str(rune_id))

	var affix_list: Variant = data.get("affixes", [])
	if typeof(affix_list) == TYPE_ARRAY:
		item.affixes = affix_list.duplicate(true)

	return item
