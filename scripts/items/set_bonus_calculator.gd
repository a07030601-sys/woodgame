class_name SetBonusCalculator
extends RefCounted

# 套裝的件數加成。只看穿在身上的物品（Equipment），背包裡的不算。
# 套裝與加成的資料在 data/sets.json，由 ItemDatabase 讀取。
# 這裡只負責計算，不保存任何角色的資料；把結果交給屬性元件是持有者（玩家）的事。


# 回傳每一套目前的狀態，只包含身上至少有一件的套裝：
# 套裝 id -> {"count": 件數, "modifiers": 目前生效的修正值清單（沒有生效的加成時是空陣列）}
static func calculate(equipment: Equipment) -> Dictionary:
	var result: Dictionary = {}
	var counts: Dictionary = count_pieces(equipment)
	for set_id: String in counts:
		result[set_id] = {
			"count": counts[set_id],
			"modifiers": get_bonus_modifiers(set_id, counts[set_id]),
		}
	return result


# 身上每一套穿了幾件：套裝 id -> 件數，只包含至少有一件的套裝
static func count_pieces(equipment: Equipment) -> Dictionary:
	var items: Array[ItemInstance] = []
	if equipment != null:
		for slot: String in Equipment.SLOTS:
			var item: ItemInstance = equipment.get_item(slot)
			if item != null:
				items.append(item)
	return count_pieces_in(items)


# 這些物品裡每一套有幾件。同一個 set_item_id 只算一次，不是套裝物品的會略過。
static func count_pieces_in(items: Array[ItemInstance]) -> Dictionary:
	# 套裝 id -> {套裝物品 id: true}
	var pieces: Dictionary = {}
	for item: ItemInstance in items:
		if item == null or not item.is_set_item():
			continue
		var set_id: String = item.get_set_id()
		if set_id.is_empty():
			continue
		if not pieces.has(set_id):
			pieces[set_id] = {}
		pieces[set_id][item.set_item_id] = true

	var counts: Dictionary = {}
	for set_id: String in pieces:
		counts[set_id] = pieces[set_id].size()
	return counts


# 這一套穿到 piece_count 件時生效的修正值。
# 加成是累加的：bonuses 裡每一個件數門檻只要達到，該門檻的修正值就全部生效，門檻由小到大排列。
static func get_bonus_modifiers(set_id: String, piece_count: int) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	if not ItemDatabase.has_set(set_id):
		return modifiers

	var bonuses: Dictionary = ItemDatabase.get_set(set_id).get("bonuses", {})
	# JSON 的鍵是文字，轉成數字後排序，結果才不會受資料裡的順序影響
	var thresholds: Array[int] = []
	for key: Variant in bonuses:
		thresholds.append(int(str(key)))
	thresholds.sort()

	for threshold: int in thresholds:
		if piece_count < threshold:
			continue
		for modifier: Variant in bonuses[str(threshold)]:
			if typeof(modifier) == TYPE_DICTIONARY:
				# JSON 讀進來的 value 可能是整數，統一轉成 float
				modifiers.append({
					"stat": modifier["stat"],
					"value": float(modifier["value"]),
					"type": modifier["type"],
				})
	return modifiers
