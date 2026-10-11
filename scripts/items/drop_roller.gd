class_name DropRoller
extends RefCounted

# 依掉落表擲骰，決定掉不掉物品、掉什麼。所有隨機都來自傳入的 rng，同一個種子會得到相同的結果。
# 掉落表的格式見 ItemDatabase.get_drop_table()。

const DEFAULT_TABLE_ID: String = "default"


# 用 ItemDatabase 裡的掉落表擲一次。沒有掉落或找不到掉落表時回傳 null。
static func roll(table_id: String, rng: RandomNumberGenerator) -> ItemInstance:
	var table: Dictionary = ItemDatabase.get_drop_table(table_id)
	if table.is_empty():
		return null
	return roll_table(table, rng)


# 用傳入的掉落表擲一次：先擲掉落機率，掉落時再依權重決定是符文還是某個品質的裝備。
# 符文從所有符文裡平均抽一顆，裝備的底材從所有底材裡平均抽一個。
static func roll_table(table: Dictionary, rng: RandomNumberGenerator) -> ItemInstance:
	var drop_chance: float = float(table.get("drop_chance", 0.0))
	# randf() 的範圍包含 0 和 1，機率 0 要另外擋掉才會真的完全不掉
	if drop_chance <= 0.0 or rng.randf() * 100.0 > drop_chance:
		return null

	var quality_weights: Dictionary = table.get("quality_weights", {})
	var rune_weight: float = maxf(float(table.get("rune_weight", 0.0)), 0.0)
	if rune_weight > 0.0:
		var total_weight: float = rune_weight + _get_total_quality_weight(quality_weights)
		if rng.randf() * total_weight < rune_weight:
			return _roll_rune(rng)

	var quality: String = pick_quality(quality_weights, rng)
	var base_ids: Array[String] = ItemDatabase.get_base_ids()
	if quality.is_empty() or base_ids.is_empty():
		return null

	var base_id: String = base_ids[rng.randi_range(0, base_ids.size() - 1)]
	return ItemGenerator.generate(base_id, quality, rng)


# 依權重抽一個品質，權重為 0 或沒列出的品質不會被抽到。所有權重都是 0 時回傳空字串。
static func pick_quality(quality_weights: Dictionary, rng: RandomNumberGenerator) -> String:
	# 依固定順序走訪，結果才不會受 JSON 裡的欄位順序影響
	var candidates: Array[String] = []
	var total_weight: float = 0.0
	for quality: String in ItemInstance.QUALITIES:
		var weight: float = float(quality_weights.get(quality, 0.0))
		if weight > 0.0:
			candidates.append(quality)
			total_weight += weight
	if candidates.is_empty():
		return ""

	var roll_value: float = rng.randf() * total_weight
	for quality: String in candidates:
		roll_value -= float(quality_weights[quality])
		if roll_value < 0.0:
			return quality
	return candidates[candidates.size() - 1]


# 從所有符文裡平均抽一顆，沒有任何符文資料時回傳 null
static func _roll_rune(rng: RandomNumberGenerator) -> ItemInstance:
	var rune_ids: Array[String] = ItemDatabase.get_rune_ids()
	if rune_ids.is_empty():
		return null
	return ItemDatabase.create_rune(rune_ids[rng.randi_range(0, rune_ids.size() - 1)])


static func _get_total_quality_weight(quality_weights: Dictionary) -> float:
	var total_weight: float = 0.0
	for quality: String in ItemInstance.QUALITIES:
		total_weight += maxf(float(quality_weights.get(quality, 0.0)), 0.0)
	return total_weight
