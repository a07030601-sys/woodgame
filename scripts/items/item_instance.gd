class_name ItemInstance
extends RefCounted

# 一件實際存在的物品。底材與詞綴的固定資料（名稱、傷害範圍等）不存在這裡，
# 需要時用 id 向 ItemDatabase 查詢。
# 符文也是物品：rune_id 有值、base_id 是空的，佔 1 × 1 格，走同一套背包與地上物品流程。

const QUALITY_NORMAL: String = "normal"
const QUALITY_MAGIC: String = "magic"
const QUALITY_RARE: String = "rare"
const QUALITY_SET: String = "set"
const QUALITIES: Array[String] = [QUALITY_NORMAL, QUALITY_MAGIC, QUALITY_RARE, QUALITY_SET]

const COLOR_NORMAL: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_MAGIC: Color = Color(0.45, 0.55, 1.0, 1.0)
const COLOR_RARE: Color = Color(1.0, 0.95, 0.35, 1.0)
const COLOR_SET: Color = Color(0.3, 0.9, 0.3, 1.0)
# 有孔的普通物品
const COLOR_SOCKETED: Color = Color(0.6, 0.6, 0.6, 1.0)
const COLOR_RUNE: Color = Color(1.0, 0.6, 0.15, 1.0)
# 符文之語：暗金色
const COLOR_RUNEWORD: Color = Color(0.78, 0.66, 0.38, 1.0)

const RUNE_SIZE: Vector2i = Vector2i(1, 1)

var base_id: String = ""
# 符文物品的符文 id，不是符文時為空字串
var rune_id: String = ""
var quality: String = QUALITY_NORMAL
# 孔數，只有普通品質的物品會有
var sockets: int = 0
# 已鑲嵌的符文 id，依鑲嵌順序排列
var socketed_runes: Array[String] = []
# 孔全部插滿且符合配方時記下的符文之語 id，不是符文之語時為空字串
var runeword_id: String = ""
# 套裝品質的物品是哪一件套裝物品（data/set_items.json 的 id），其他品質為空字串
var set_item_id: String = ""
# 每個詞綴是 {"id": 詞綴 id, "modifiers": [已擲好數值的修正值, ...]}，修正值格式見 StatSystem
var affixes: Array = []
# 生成時擲出的防禦值，武器為 0
var defense: int = 0
# 稀有物品生成時擲出的名稱，其他品質為空字串
var rare_name: String = ""


func is_rune() -> bool:
	return not rune_id.is_empty()


# 還有沒插東西的孔，而且對方是符文時才可以插入。符文本身不能被插入。
func can_insert_rune(rune_item: ItemInstance) -> bool:
	if is_rune() or rune_item == null or not rune_item.is_rune():
		return false
	if not ItemDatabase.has_rune(rune_item.rune_id):
		return false
	return socketed_runes.size() < sockets


# 把符文插進下一個空孔，成功時回傳 true。插入後不能取出，呼叫端要自己把那顆符文物品丟掉。
# 孔全部插滿時比對一次符文之語，符合配方就記下 runeword_id。
func insert_rune(rune_item: ItemInstance) -> bool:
	if not can_insert_rune(rune_item):
		return false
	socketed_runes.append(rune_item.rune_id)
	if socketed_runes.size() == sockets:
		runeword_id = RunewordMatcher.find_match(self)
	return true


func is_runeword() -> bool:
	return not runeword_id.is_empty()


func is_set_item() -> bool:
	return not set_item_id.is_empty()


# 這件套裝物品所屬套裝的 id，不是套裝物品時回傳空字串
func get_set_id() -> String:
	if not is_set_item():
		return ""
	return str(ItemDatabase.get_set_item(set_item_id).get("set_id", ""))


# 所屬套裝的名稱，不是套裝物品時回傳空字串
func get_set_name() -> String:
	var set_id: String = get_set_id()
	if set_id.is_empty():
		return ""
	return str(ItemDatabase.get_set(set_id).get("name", set_id))


# 回傳這件物品提供的所有修正值，格式見 StatSystem：
# 底材、詞綴、已插入的符文、符文之語，再加上套裝物品本身固定的修正值（不含套裝的件數加成）。
# 符文各自的效果與符文之語的效果是疊加的。
# 符文本身不提供任何修正值，要插進裝備才有效果。
func get_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if is_rune():
		return modifiers

	var base: Dictionary = ItemDatabase.get_base(base_id)
	if base.has("damage"):
		var damage: Array = base["damage"]
		modifiers.append({"stat": "damage_min", "value": float(damage[0]), "type": "flat"})
		modifiers.append({"stat": "damage_max", "value": float(damage[1]), "type": "flat"})
	if base.has("defense"):
		modifiers.append({"stat": "defense", "value": float(defense), "type": "flat"})

	modifiers.append_array(get_affix_modifiers())
	modifiers.append_array(get_rune_modifiers())
	modifiers.append_array(get_runeword_modifiers())
	modifiers.append_array(get_set_item_modifiers())
	return modifiers


# 只回傳套裝物品本身固定的修正值，不是套裝物品時回傳空陣列。套裝的件數加成不在這裡。
func get_set_item_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if not is_set_item():
		return modifiers

	var set_item: Dictionary = ItemDatabase.get_set_item(set_item_id)
	for modifier: Variant in set_item.get("modifiers", []):
		if typeof(modifier) == TYPE_DICTIONARY:
			# JSON 讀進來的 value 可能是整數，統一轉成 float
			modifiers.append({
				"stat": modifier["stat"],
				"value": float(modifier["value"]),
				"type": modifier["type"],
			})
	return modifiers


# 只回傳符文之語提供的修正值，不是符文之語時回傳空陣列
func get_runeword_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if not is_runeword():
		return modifiers

	var runeword: Dictionary = ItemDatabase.get_runeword(runeword_id)
	for modifier: Variant in runeword.get("modifiers", []):
		if typeof(modifier) == TYPE_DICTIONARY:
			# JSON 讀進來的 value 可能是整數，統一轉成 float
			modifiers.append({
				"stat": modifier["stat"],
				"value": float(modifier["value"]),
				"type": modifier["type"],
			})
	return modifiers


# 只回傳已插入的符文提供的修正值，依插入順序排列。
# 底材的 slot 是 weapon 時用符文的 weapon_mods，其他都用 armor_mods。
func get_rune_modifiers() -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if socketed_runes.is_empty():
		return modifiers

	var mods_field: String = "weapon_mods" if get_slot() == ItemDatabase.SLOT_WEAPON else "armor_mods"
	for socketed_rune_id: String in socketed_runes:
		var rune: Dictionary = ItemDatabase.get_rune(socketed_rune_id)
		for modifier: Variant in rune.get(mods_field, []):
			if typeof(modifier) == TYPE_DICTIONARY:
				# JSON 讀進來的 value 可能是整數，統一轉成 float
				modifiers.append({
					"stat": modifier["stat"],
					"value": float(modifier["value"]),
					"type": modifier["type"],
				})
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
	if is_rune():
		return RUNE_SIZE
	var base: Dictionary = ItemDatabase.get_base(base_id)
	if base.is_empty():
		return Vector2i.ZERO
	var size: Array = base["size"]
	return Vector2i(int(size[0]), int(size[1]))


# 底材的裝備欄位（weapon、helm 等），符文或查不到底材時回傳空字串
func get_slot() -> String:
	if is_rune():
		return ""
	var base: Dictionary = ItemDatabase.get_base(base_id)
	return str(base.get("slot", ""))


# 符文回傳符文名
func get_base_name() -> String:
	if is_rune():
		return str(ItemDatabase.get_rune(rune_id).get("name", rune_id))
	var base: Dictionary = ItemDatabase.get_base(base_id)
	return str(base.get("name", base_id))


# 普通：底材名。魔法：後綴 + 前綴 + 底材名，底材名一律在最後。
# 稀有：生成時擲出的名稱，不含底材名，要顯示底材請另外用 get_base_name()。
# 符文之語：符文之語的名稱，同樣不含底材名。套裝：該件套裝物品的名稱。
func get_display_name() -> String:
	var base_name: String = get_base_name()
	if is_rune():
		return base_name
	if is_runeword():
		return str(ItemDatabase.get_runeword(runeword_id).get("name", base_name))
	if is_set_item():
		return str(ItemDatabase.get_set_item(set_item_id).get("name", base_name))

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
	if quality == QUALITY_SET:
		return COLOR_SET
	return COLOR_NORMAL


# 顯示物品時用的顏色（名稱文字、背包裡的邊框）：
# 符文橘色、符文之語暗金色、有孔的普通物品灰色，其餘是品質顏色
func get_display_color() -> Color:
	if is_rune():
		return COLOR_RUNE
	if is_runeword():
		return COLOR_RUNEWORD
	if quality == QUALITY_NORMAL and sockets > 0:
		return COLOR_SOCKETED
	return get_quality_color()


func to_dict() -> Dictionary:
	return {
		"base_id": base_id,
		"rune_id": rune_id,
		"quality": quality,
		"sockets": sockets,
		"socketed_runes": socketed_runes.duplicate(),
		"runeword_id": runeword_id,
		"set_item_id": set_item_id,
		"affixes": affixes.duplicate(true),
		"defense": defense,
		"rare_name": rare_name,
	}


# 缺少的欄位使用預設值。從 JSON 讀回來的數字是 float，這裡會轉回 int。
static func from_dict(data: Dictionary) -> ItemInstance:
	var item: ItemInstance = ItemInstance.new()
	item.base_id = str(data.get("base_id", ""))
	item.rune_id = str(data.get("rune_id", ""))
	item.runeword_id = str(data.get("runeword_id", ""))
	item.set_item_id = str(data.get("set_item_id", ""))
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
