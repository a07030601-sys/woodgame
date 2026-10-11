class_name ItemGenerator
extends RefCounted

# 依品質生成物品：魔法與稀有帶詞綴，普通可能有孔。所有隨機都來自傳入的 rng，同一個種子會生成相同的物品。

const RARE_MIN_AFFIXES: int = 3
const RARE_MAX_AFFIXES: int = 4
# 稀有物品的前綴與後綴各自的上限
const RARE_MAX_PER_AFFIX_TYPE: int = 2


# 找不到底材時回傳 null；quality 不認得時警告並當成普通品質
static func generate(base_id: String, quality: String, rng: RandomNumberGenerator) -> ItemInstance:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var item: ItemInstance = ItemDatabase.create_item(base_id, rng)
	if item == null:
		return null
	var base: Dictionary = ItemDatabase.get_base(base_id)
	var base_type: String = base["type"]

	if quality == ItemInstance.QUALITY_MAGIC:
		item.quality = quality
		_add_magic_affixes(item, base_type, rng)
	elif quality == ItemInstance.QUALITY_RARE:
		item.quality = quality
		_add_rare_affixes(item, base_type, rng)
		item.rare_name = _roll_rare_name(base_type, rng)
	elif quality != ItemInstance.QUALITY_NORMAL:
		push_warning("ItemGenerator：不認得的品質 %s，當成普通品質" % quality)

	# 只有普通品質的物品會有孔，魔法與稀有一律 0 孔
	if item.quality == ItemInstance.QUALITY_NORMAL:
		item.sockets = _roll_sockets(base, rng)

	return item


# 依 ItemDatabase 的 socket_chance 決定有沒有孔，有孔時孔數在 1 到底材的 max_sockets 之間
static func _roll_sockets(base: Dictionary, rng: RandomNumberGenerator) -> int:
	var max_sockets: int = int(base.get("max_sockets", 0))
	var socket_chance: float = ItemDatabase.get_socket_chance()
	# randf() 的範圍包含 0 和 1，機率 0 要另外擋掉才會真的完全沒有孔
	if max_sockets <= 0 or socket_chance <= 0.0 or rng.randf() * 100.0 > socket_chance:
		return 0
	return rng.randi_range(1, max_sockets)


# 魔法：最多 1 個前綴加 1 個後綴，至少 1 個
static func _add_magic_affixes(
	item: ItemInstance, base_type: String, rng: RandomNumberGenerator
) -> void:
	var used_groups: Array[String] = []
	# 0：只有前綴，1：只有後綴，2：兩個都有
	var roll: int = rng.randi_range(0, 2)
	var added_count: int = 0

	if roll != 1 and _try_add_affix(item, base_type, ItemDatabase.AFFIX_PREFIX, used_groups, rng):
		added_count += 1
	if roll != 0 and _try_add_affix(item, base_type, ItemDatabase.AFFIX_SUFFIX, used_groups, rng):
		added_count += 1

	# 想要的那種剛好沒有可用詞綴時，改用另一種補足至少 1 個
	if added_count == 0:
		if not _try_add_affix(item, base_type, ItemDatabase.AFFIX_PREFIX, used_groups, rng):
			_try_add_affix(item, base_type, ItemDatabase.AFFIX_SUFFIX, used_groups, rng)


# 稀有：3～4 個詞綴，前綴與後綴各最多 2 個
static func _add_rare_affixes(
	item: ItemInstance, base_type: String, rng: RandomNumberGenerator
) -> void:
	var used_groups: Array[String] = []
	var target_count: int = rng.randi_range(RARE_MIN_AFFIXES, RARE_MAX_AFFIXES)
	var prefix_count: int = 0
	var suffix_count: int = 0

	while prefix_count + suffix_count < target_count:
		var can_prefix: bool = prefix_count < RARE_MAX_PER_AFFIX_TYPE
		var can_suffix: bool = suffix_count < RARE_MAX_PER_AFFIX_TYPE
		# 兩種都還能加時隨機決定先試哪一種，試不到再換另一種
		var prefix_first: bool = can_prefix and (not can_suffix or rng.randi_range(0, 1) == 0)

		var added_type: String = ""
		if prefix_first:
			if _try_add_affix(item, base_type, ItemDatabase.AFFIX_PREFIX, used_groups, rng):
				added_type = ItemDatabase.AFFIX_PREFIX
			elif can_suffix and _try_add_affix(
				item, base_type, ItemDatabase.AFFIX_SUFFIX, used_groups, rng
			):
				added_type = ItemDatabase.AFFIX_SUFFIX
		else:
			if can_suffix and _try_add_affix(
				item, base_type, ItemDatabase.AFFIX_SUFFIX, used_groups, rng
			):
				added_type = ItemDatabase.AFFIX_SUFFIX
			elif can_prefix and _try_add_affix(
				item, base_type, ItemDatabase.AFFIX_PREFIX, used_groups, rng
			):
				added_type = ItemDatabase.AFFIX_PREFIX

		if added_type == ItemDatabase.AFFIX_PREFIX:
			prefix_count += 1
		elif added_type == ItemDatabase.AFFIX_SUFFIX:
			suffix_count += 1
		else:
			# 已經沒有可用的詞綴，資料不足時寧可少給也不要卡住
			break


# 從符合底材 type、group 還沒用過的詞綴裡依 weight 抽一個加到物品上。沒有可用詞綴時回傳 false。
static func _try_add_affix(
	item: ItemInstance,
	base_type: String,
	affix_type: String,
	used_groups: Array[String],
	rng: RandomNumberGenerator
) -> bool:
	var candidates: Array[Dictionary] = []
	for affix: Dictionary in ItemDatabase.get_affixes_for(base_type, affix_type):
		if not used_groups.has(affix["group"]):
			candidates.append(affix)
	if candidates.is_empty():
		return false

	var picked: Dictionary = _pick_weighted(candidates, rng)
	used_groups.append(picked["group"])

	# 每條修正值在 min 到 max 之間擲出整數，存成正式的修正值格式
	var rolled_modifiers: Array = []
	for modifier: Dictionary in picked["modifiers"]:
		var value: int = rng.randi_range(int(modifier["min"]), int(modifier["max"]))
		rolled_modifiers.append(
			{"stat": modifier["stat"], "value": float(value), "type": modifier["type"]}
		)
	item.affixes.append({"id": picked["id"], "modifiers": rolled_modifiers})
	return true


static func _pick_weighted(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: float = 0.0
	for candidate: Dictionary in candidates:
		total_weight += float(candidate["weight"])

	var roll: float = rng.randf() * total_weight
	for candidate: Dictionary in candidates:
		roll -= float(candidate["weight"])
		if roll < 0.0:
			return candidate
	return candidates[candidates.size() - 1]


# 第一段是共用的氣氛字詞，第二段依底材 type 選。字詞不足時回傳空字串。
static func _roll_rare_name(base_type: String, rng: RandomNumberGenerator) -> String:
	var first_words: Array[String] = ItemDatabase.get_rare_first_words()
	var second_words: Array[String] = ItemDatabase.get_rare_second_words(base_type)
	if first_words.is_empty() or second_words.is_empty():
		return ""
	return (
		first_words[rng.randi_range(0, first_words.size() - 1)]
		+ second_words[rng.randi_range(0, second_words.size() - 1)]
	)
