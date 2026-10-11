class_name RunewordMatcher
extends RefCounted

# 符文之語的配方比對。配方資料在 data/runewords.json，由 ItemDatabase 讀取。
# 物品的孔全部插滿時由 ItemInstance.insert_rune() 呼叫一次。


# 回傳 item 符合的符文之語 id，沒有任何配方符合時回傳空字串
static func find_match(item: ItemInstance) -> String:
	if item == null:
		return ""
	for runeword_id: String in ItemDatabase.get_runeword_ids():
		if matches(item, ItemDatabase.get_runeword(runeword_id)):
			return runeword_id
	return ""


# 全部符合才算成功：
# - 物品是普通品質（符文本身不算）
# - 物品的孔數等於配方的符文數量，而且全部插滿
# - 已插入的符文與配方的順序完全一致
# - 底材的 type 在配方的 allowed_bases 裡
static func matches(item: ItemInstance, runeword: Dictionary) -> bool:
	if item == null or item.is_rune() or item.quality != ItemInstance.QUALITY_NORMAL:
		return false

	var runes: Array = runeword.get("runes", [])
	if runes.is_empty() or item.sockets != runes.size() or item.socketed_runes.size() != runes.size():
		return false
	for index: int in runes.size():
		if item.socketed_runes[index] != runes[index]:
			return false

	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	var allowed_bases: Array = runeword.get("allowed_bases", [])
	return allowed_bases.has(base.get("type", ""))
