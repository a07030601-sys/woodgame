class_name SetBonusCalculator
extends RefCounted

# 套裝的件數加成。只看穿在身上的物品（Equipment），背包裡的不算。
# 加成有兩種，都依「該套穿了幾件」決定是否生效：
# - 套裝的件數加成：data/sets.json 的 bonuses。
# - 單件的件數詞綴：data/set_items.json 每件選填的 set_bonuses，那一件自己也要穿在身上才算。
# 這裡只負責計算，不保存任何角色的資料；把結果交給屬性元件是持有者（玩家）的事。


# 回傳每一套目前的狀態，只包含身上至少有一件的套裝：
# 套裝 id -> {"count": 件數, "modifiers": 目前生效的修正值清單（沒有生效的加成時是空陣列）}
# modifiers 先是套裝的件數加成，接著是身上每一件的單件件數詞綴。
static func calculate(equipment: Equipment) -> Dictionary:
	var result: Dictionary = {}
	var pieces: Dictionary = get_equipped_pieces(equipment)
	for set_id: String in pieces:
		var piece_ids: Array = pieces[set_id]
		var count: int = piece_ids.size()
		var modifiers: Array[Dictionary] = get_bonus_modifiers(set_id, count)
		for set_item_id: String in piece_ids:
			modifiers.append_array(get_item_bonus_modifiers(set_item_id, count))
		result[set_id] = {"count": count, "modifiers": modifiers}
	return result


# 身上每一套穿了幾件：套裝 id -> 件數，只包含至少有一件的套裝
static func count_pieces(equipment: Equipment) -> Dictionary:
	return _to_counts(get_equipped_pieces(equipment))


# 這些物品裡每一套有幾件。同一個 set_item_id 只算一次，不是套裝物品的會略過。
static func count_pieces_in(items: Array[ItemInstance]) -> Dictionary:
	return _to_counts(get_pieces_in(items))


# 身上每一套穿了哪幾件：套裝 id -> 套裝物品 id 清單，只包含至少有一件的套裝
static func get_equipped_pieces(equipment: Equipment) -> Dictionary:
	var items: Array[ItemInstance] = []
	if equipment != null:
		for slot: String in Equipment.SLOTS:
			var item: ItemInstance = equipment.get_item(slot)
			if item != null:
				items.append(item)
	return get_pieces_in(items)


# 這些物品裡每一套有哪幾件：套裝 id -> 套裝物品 id 清單（不重複）。不是套裝物品的會略過。
static func get_pieces_in(items: Array[ItemInstance]) -> Dictionary:
	var pieces: Dictionary = {}
	for item: ItemInstance in items:
		if item == null or not item.is_set_item():
			continue
		var set_id: String = item.get_set_id()
		if set_id.is_empty():
			continue
		if not pieces.has(set_id):
			pieces[set_id] = []
		if not pieces[set_id].has(item.set_item_id):
			pieces[set_id].append(item.set_item_id)
	return pieces


# 這一套穿到 piece_count 件時，套裝的件數加成裡生效的修正值。
# 加成是累加的：bonuses 裡每一個件數門檻只要達到，該門檻的修正值就全部生效，門檻由小到大排列。
static func get_bonus_modifiers(set_id: String, piece_count: int) -> Array[Dictionary]:
	if not ItemDatabase.has_set(set_id):
		var empty: Array[Dictionary] = []
		return empty
	return _get_reached_modifiers(ItemDatabase.get_set(set_id).get("bonuses", {}), piece_count)


# 這一件套裝物品穿在身上、所屬套裝穿到 piece_count 件時，它自己的件數詞綴裡生效的修正值。
# 沒有 set_bonuses 的套裝物品回傳空陣列。
static func get_item_bonus_modifiers(set_item_id: String, piece_count: int) -> Array[Dictionary]:
	if not ItemDatabase.has_set_item(set_item_id):
		var empty: Array[Dictionary] = []
		return empty
	return _get_reached_modifiers(
		ItemDatabase.get_set_item(set_item_id).get("set_bonuses", {}), piece_count
	)


# 「件數 -> 修正值清單」裡的所有門檻，由小到大排列
static func get_thresholds(bonuses: Dictionary) -> Array[int]:
	# JSON 的鍵是文字，轉成數字後排序，結果才不會受資料裡的順序影響
	var thresholds: Array[int] = []
	for key: Variant in bonuses:
		thresholds.append(int(str(key)))
	thresholds.sort()
	return thresholds


# 「件數 -> 修正值清單」裡某一個門檻的修正值，數值統一轉成 float
static func get_threshold_modifiers(bonuses: Dictionary, threshold: int) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	for modifier: Variant in bonuses.get(str(threshold), []):
		if typeof(modifier) == TYPE_DICTIONARY:
			# JSON 讀進來的 value 可能是整數，統一轉成 float
			modifiers.append({
				"stat": modifier["stat"],
				"value": float(modifier["value"]),
				"type": modifier["type"],
			})
	return modifiers


static func _get_reached_modifiers(bonuses: Dictionary, piece_count: int) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	for threshold: int in get_thresholds(bonuses):
		if piece_count >= threshold:
			modifiers.append_array(get_threshold_modifiers(bonuses, threshold))
	return modifiers


static func _to_counts(pieces: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for set_id: String in pieces:
		counts[set_id] = pieces[set_id].size()
	return counts
