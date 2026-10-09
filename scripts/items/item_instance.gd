class_name ItemInstance
extends RefCounted

# 一件實際存在的物品。底材的固定資料（名稱、傷害範圍等）不存在這裡，
# 需要時用 base_id 向 ItemDatabase 查詢。

const QUALITY_NORMAL: String = "normal"

var base_id: String = ""
var quality: String = QUALITY_NORMAL
var sockets: int = 0
# 已鑲嵌的符文 id，依鑲嵌順序排列
var socketed_runes: Array[String] = []
var affixes: Array = []
# 生成時擲出的防禦值，武器為 0
var defense: int = 0


# 回傳這件物品提供的所有修正值，格式見 StatSystem。詞綴和符文之後再加。
func get_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	var base: Dictionary = ItemDatabase.get_base(base_id)
	if base.is_empty():
		return modifiers

	if base.has("damage"):
		var damage: Array = base["damage"]
		modifiers.append({"stat": "damage_min", "value": float(damage[0]), "type": "flat"})
		modifiers.append({"stat": "damage_max", "value": float(damage[1]), "type": "flat"})
	if base.has("defense"):
		modifiers.append({"stat": "defense", "value": float(defense), "type": "flat"})

	return modifiers


func to_dict() -> Dictionary:
	return {
		"base_id": base_id,
		"quality": quality,
		"sockets": sockets,
		"socketed_runes": socketed_runes.duplicate(),
		"affixes": affixes.duplicate(true),
		"defense": defense,
	}


# 缺少的欄位使用預設值。從 JSON 讀回來的數字是 float，這裡會轉回 int。
static func from_dict(data: Dictionary) -> ItemInstance:
	var item: ItemInstance = ItemInstance.new()
	item.base_id = str(data.get("base_id", ""))
	item.quality = str(data.get("quality", QUALITY_NORMAL))
	item.sockets = int(data.get("sockets", 0))
	item.defense = int(data.get("defense", 0))

	var rune_ids: Variant = data.get("socketed_runes", [])
	if typeof(rune_ids) == TYPE_ARRAY:
		for rune_id: Variant in rune_ids:
			item.socketed_runes.append(str(rune_id))

	var affix_list: Variant = data.get("affixes", [])
	if typeof(affix_list) == TYPE_ARRAY:
		item.affixes = affix_list.duplicate(true)

	return item
