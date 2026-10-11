extends TestBase

# 套裝資料與套裝物品的測試：sets.json、set_items.json、套裝物品的固定內容、存檔還原、掉落、說明框、
# 穿上後的屬性、除錯用的開場道具。套裝的件數加成在 set_bonus_test，這裡只確認加成的資料有讀進來。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const TEST_SEED: int = 20261013
const ROLL_COUNT: int = 500
# data/sets.json 與 data/set_items.json 裡的數量，新增時要一起更新
const EXPECTED_SET_COUNT: int = 2
const EXPECTED_SET_ITEM_COUNT: int = 5


func _get_test_name() -> String:
	return "套裝資料與套裝物品"


func _run_tests() -> void:
	_test_set_item_data()
	_test_set_data()
	_test_fixed_content()
	_test_no_sockets()
	_test_serialization()
	_test_drop()
	_test_equipped_stats()
	_test_tooltip()
	_test_inventory_and_ground()
	_test_debug_kit()


func _test_set_item_data() -> void:
	check(
		"套裝物品載入數量正確",
		ItemDatabase.get_set_item_count() == EXPECTED_SET_ITEM_COUNT,
		"預期 %d，實際 %d" % [EXPECTED_SET_ITEM_COUNT, ItemDatabase.get_set_item_count()]
	)

	var missing_base: Array[String] = []
	var missing_set: Array[String] = []
	var not_listed: Array[String] = []
	var bad_modifiers: Array[String] = []
	var names: Dictionary = {}
	for set_item_id: String in ItemDatabase.get_set_item_ids():
		var set_item: Dictionary = ItemDatabase.get_set_item(set_item_id)
		names[set_item["name"]] = true
		if not ItemDatabase.has_base(set_item["base"]):
			missing_base.append("%s -> %s" % [set_item_id, set_item["base"]])
		if not ItemDatabase.has_set(set_item["set_id"]):
			missing_set.append("%s -> %s" % [set_item_id, set_item["set_id"]])
		elif not ItemDatabase.get_set(set_item["set_id"])["items"].has(set_item_id):
			not_listed.append(set_item_id)
		if set_item["modifiers"].is_empty():
			bad_modifiers.append(set_item_id)
		for modifier: Variant in set_item["modifiers"]:
			if not _is_valid_modifier(modifier):
				bad_modifiers.append(set_item_id)

	check("每件套裝物品的 base 都在 bases.json 裡", missing_base.is_empty(), "、".join(missing_base))
	check("每件套裝物品的 set_id 都在 sets.json 裡", missing_set.is_empty(), "、".join(missing_set))
	check("每件套裝物品都列在所屬套裝的 items 裡", not_listed.is_empty(), "、".join(not_listed))
	check("每件套裝物品都有 StatSystem 認得的修正值", bad_modifiers.is_empty(), "、".join(bad_modifiers))
	check("套裝物品的名稱沒有重複", names.size() == ItemDatabase.get_set_item_count())
	check("不存在的套裝物品建立不出物品", ItemDatabase.create_set_item("not_exist") == null)


func _test_set_data() -> void:
	check(
		"套裝載入數量正確",
		ItemDatabase.get_set_count() == EXPECTED_SET_COUNT,
		"預期 %d，實際 %d" % [EXPECTED_SET_COUNT, ItemDatabase.get_set_count()]
	)

	var missing_items: Array[String] = []
	var wrong_owner: Array[String] = []
	var bad_bonuses: Array[String] = []
	var duplicate_slots: Array[String] = []
	for set_id: String in ItemDatabase.get_set_ids():
		var set_data: Dictionary = ItemDatabase.get_set(set_id)
		# 欄位名 -> true，同一套裡不能有兩件穿在同一個欄位
		var slots: Dictionary = {}
		for set_item_id: Variant in set_data["items"]:
			if not ItemDatabase.has_set_item(str(set_item_id)):
				missing_items.append("%s -> %s" % [set_id, str(set_item_id)])
				continue
			var set_item: Dictionary = ItemDatabase.get_set_item(set_item_id)
			if set_item["set_id"] != set_id:
				wrong_owner.append(str(set_item_id))
			var slot: String = ItemDatabase.get_base(set_item["base"])["slot"]
			if slots.has(slot):
				duplicate_slots.append("%s 的 %s" % [set_id, slot])
			slots[slot] = true

		var bonuses: Dictionary = set_data["bonuses"]
		if bonuses.is_empty():
			bad_bonuses.append("%s 沒有加成" % set_id)
		for piece_count: Variant in bonuses:
			var count: int = int(str(piece_count))
			if count < 2 or count > set_data["items"].size():
				bad_bonuses.append("%s 的 %s 件" % [set_id, str(piece_count)])
			for modifier: Variant in bonuses[piece_count]:
				if not _is_valid_modifier(modifier):
					bad_bonuses.append("%s 的 %s 件" % [set_id, str(piece_count)])

	check("sets.json 的 items 都在 set_items.json 裡", missing_items.is_empty(), "、".join(missing_items))
	check("items 裡的套裝物品都屬於這一套", wrong_owner.is_empty(), "、".join(wrong_owner))
	check("同一套的每一件都穿在不同的欄位", duplicate_slots.is_empty(), "、".join(duplicate_slots))
	check("bonuses 有讀進來，件數不超過該套的件數，修正值格式正確", bad_bonuses.is_empty(), "、".join(bad_bonuses))

	check(
		"A 套是 3 件：頭盔、身體護甲、手套，有 2 件與 3 件的加成",
		_get_set_slots("mistwood") == _sorted(["helm", "armor", "gloves"])
		and _sorted(ItemDatabase.get_set("mistwood")["bonuses"].keys()) == _sorted(["2", "3"])
	)
	check(
		"B 套是 2 件：武器、靴子，有 2 件的加成",
		_get_set_slots("starchase") == _sorted(["weapon", "boots"])
		and ItemDatabase.get_set("starchase")["bonuses"].keys() == ["2"]
	)


func _test_fixed_content() -> void:
	var all_same: bool = true
	var all_fixed: bool = true
	var detail: String = ""
	for set_item_id: String in ItemDatabase.get_set_item_ids():
		var set_item: Dictionary = ItemDatabase.get_set_item(set_item_id)
		var first: ItemInstance = ItemDatabase.create_set_item(set_item_id)
		var second: ItemInstance = ItemDatabase.create_set_item(set_item_id)
		if first.to_dict() != second.to_dict() or first.get_modifiers() != second.get_modifiers():
			all_same = false
			detail = set_item_id

		# 套裝物品本身的修正值就是資料裡那幾條，沒有詞綴
		var expected: Array[Dictionary] = []
		for modifier: Dictionary in set_item["modifiers"]:
			expected.append(
				{"stat": modifier["stat"], "value": float(modifier["value"]), "type": modifier["type"]}
			)
		if (
			first.get_set_item_modifiers() != expected
			or not first.affixes.is_empty()
			or first.quality != ItemInstance.QUALITY_SET
			or first.base_id != set_item["base"]
			or first.get_display_name() != set_item["name"]
		):
			all_fixed = false
			detail = set_item_id
	check("每件套裝物品生成兩次的內容與修正值完全相同", all_same, detail)
	check("套裝物品是 set 品質、沒有隨機詞綴，修正值就是資料裡固定的那幾條", all_fixed, detail)

	# 底材的修正值也要在 get_modifiers 裡
	var blade: ItemInstance = ItemDatabase.create_set_item("starchase_blade")
	var expected_blade: Array[Dictionary] = [
		{"stat": "damage_min", "value": 2.0, "type": "flat"},
		{"stat": "damage_max", "value": 5.0, "type": "flat"},
		{"stat": "damage_min", "value": 2.0, "type": "flat"},
		{"stat": "damage_max", "value": 4.0, "type": "flat"},
		{"stat": "attack_speed", "value": 6.0, "type": "percent"},
	]
	check(
		"get_modifiers 是底材的修正值加上該件固定的修正值",
		blade.get_modifiers() == expected_blade,
		str(blade.get_modifiers())
	)

	var hood: ItemInstance = ItemDatabase.create_set_item("mistwood_hood")
	check(
		"套裝防具的防禦值固定是底材的最大值",
		hood.defense == int(ItemDatabase.get_base("leather_cap")["defense"][1])
	)
	check(
		"套裝物品的名稱、底材名、套裝名稱與顏色",
		hood.get_display_name() == "霧林兜帽"
		and hood.get_base_name() == "皮帽"
		and hood.get_set_id() == "mistwood"
		and hood.get_set_name() == "霧林獵裝"
		and hood.get_quality_color() == ItemInstance.COLOR_SET
		and hood.get_display_color() == ItemInstance.COLOR_SET
	)
	var plain: ItemInstance = ItemDatabase.create_item("leather_cap")
	check(
		"一般物品不是套裝物品",
		not plain.is_set_item() and plain.get_set_id().is_empty() and plain.get_set_item_modifiers().is_empty()
	)


func _test_no_sockets() -> void:
	var all_zero: bool = true
	var cannot_insert: bool = true
	var rune: ItemInstance = ItemDatabase.create_rune("flint")
	for set_item_id: String in ItemDatabase.get_set_item_ids():
		var item: ItemInstance = ItemDatabase.create_set_item(set_item_id)
		if item.sockets != 0 or not item.socketed_runes.is_empty():
			all_zero = false
		if item.can_insert_rune(rune) or item.insert_rune(rune):
			cannot_insert = false
	check("每件套裝物品的孔數都是 0", all_zero)
	check("套裝物品不能插符文", cannot_insert)

	# 從掉落擲出來的套裝物品也一樣
	var rng: RandomNumberGenerator = _make_rng()
	var table: Dictionary = {"drop_chance": 100, "quality_weights": {"set": 1}}
	var dropped_zero: bool = true
	for i: int in ROLL_COUNT:
		var item: ItemInstance = DropRoller.roll_table(table, rng)
		if item == null or item.sockets != 0 or not item.affixes.is_empty():
			dropped_zero = false
	check("掉落的套裝物品孔數也都是 0，沒有詞綴", dropped_zero)


func _test_serialization() -> void:
	var all_same: bool = true
	var detail: String = ""
	for set_item_id: String in ItemDatabase.get_set_item_ids():
		var item: ItemInstance = ItemDatabase.create_set_item(set_item_id)
		var data: Dictionary = item.to_dict()
		var restored: ItemInstance = ItemInstance.from_dict(data)
		var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(data)))
		for copy: ItemInstance in [restored, from_json]:
			if (
				not copy.is_set_item()
				or copy.set_item_id != set_item_id
				or copy.quality != ItemInstance.QUALITY_SET
				or copy.get_display_name() != item.get_display_name()
				or copy.get_modifiers() != item.get_modifiers()
				or copy.to_dict() != data
			):
				all_same = false
				detail = set_item_id
	check("每件套裝物品 to_dict 還原（含經過 JSON 文字）後仍是同一件套裝物品", all_same, detail)

	var data: Dictionary = ItemDatabase.create_set_item("mistwood_grips").to_dict()
	check("to_dict 包含 set_item_id", data.get("set_item_id") == "mistwood_grips" and data.get("quality") == "set")

	var plain_data: Dictionary = ItemDatabase.create_item("leather_gloves").to_dict()
	check("一般物品的 to_dict 裡 set_item_id 是空的", plain_data.get("set_item_id") == "")
	plain_data.erase("set_item_id")
	check("舊資料沒有 set_item_id 時還原出來不是套裝物品", not ItemInstance.from_dict(plain_data).is_set_item())

	var inventory: Inventory = Inventory.new()
	inventory.place(ItemDatabase.create_set_item("starchase_treads"), 6, 2)
	var restored_inventory: Inventory = Inventory.from_dict(
		JSON.parse_string(JSON.stringify(inventory.to_dict()))
	)
	var restored_item: ItemInstance = restored_inventory.get_item_at(6, 2)
	check(
		"背包存檔還原後仍是同一件套裝物品",
		restored_item != null and restored_item.set_item_id == "starchase_treads"
	)


func _test_drop() -> void:
	var rng: RandomNumberGenerator = _make_rng()
	var table: Dictionary = {"drop_chance": 100, "quality_weights": {"set": 1}}
	# 套裝物品 id -> 出現次數
	var counts: Dictionary = {}
	for i: int in ROLL_COUNT:
		var item: ItemInstance = DropRoller.roll_table(table, rng)
		if item != null and item.is_set_item():
			counts[item.set_item_id] = int(counts.get(item.set_item_id, 0)) + 1
	check(
		"擲到 set 時，每一件套裝物品都有機會出現",
		counts.size() == ItemDatabase.get_set_item_count(),
		str(counts)
	)

	var weights: Dictionary = ItemDatabase.get_drop_table(DropRoller.DEFAULT_TABLE_ID)["quality_weights"]
	check(
		"default 表有 set 的權重，而且比稀有低",
		float(weights.get("set", 0.0)) > 0.0 and float(weights["set"]) < float(weights["rare"]),
		str(weights)
	)

	var first: Array[Dictionary] = []
	var second: Array[Dictionary] = []
	for results: Array[Dictionary] in [first, second]:
		var seeded: RandomNumberGenerator = _make_rng()
		for i: int in 50:
			results.append(DropRoller.roll_table(table, seeded).to_dict())
	check("相同種子擲出的套裝物品順序相同", first == second)


func _test_equipped_stats() -> void:
	var player: Player = _create_player()
	var stats: StatsComponent = player.get_stats()
	var equipment: Equipment = player.get_equipment()
	var base_min: float = stats.get_stat("damage_min")
	var base_max: float = stats.get_stat("damage_max")
	var base_attack_speed: float = stats.get_stat("attack_speed")
	var base_life: float = stats.get_stat("life")
	var base_defense: float = stats.get_stat("defense")
	var base_move_speed: float = stats.get_stat("move_speed")

	# 逐星之刃：短劍 2～5，再 +2 最小傷害、+4 最大傷害、+6% 攻擊速度
	var blade: ItemInstance = ItemDatabase.create_set_item("starchase_blade")
	check("套裝武器可以穿在武器欄", equipment.equip(blade, "weapon")["success"])
	check(
		"穿上套裝武器後，傷害與攻擊速度照固定的修正值增加",
		is_equal_approx(stats.get_stat("damage_min"), base_min + 2.0 + 2.0)
		and is_equal_approx(stats.get_stat("damage_max"), base_max + 5.0 + 4.0)
		and is_equal_approx(stats.get_stat("attack_speed"), base_attack_speed * 1.06),
		"傷害 %s～%s，攻速 %s" % [
			stats.get_stat("damage_min"), stats.get_stat("damage_max"), stats.get_stat("attack_speed")
		]
	)

	# 霧林兜帽：皮帽防禦 4（底材最大值），再 +12 生命、+3 防禦
	var hood: ItemInstance = ItemDatabase.create_set_item("mistwood_hood")
	equipment.equip(hood, "helm")
	check(
		"穿上套裝頭盔後，生命與防禦照固定的修正值增加",
		is_equal_approx(stats.get_stat("life"), base_life + 12.0)
		and is_equal_approx(stats.get_stat("defense"), base_defense + float(hood.defense) + 3.0),
		"生命 %s、防禦 %s" % [stats.get_stat("life"), stats.get_stat("defense")]
	)

	# 這裡兩套各只穿一件，沒有件數加成；件數加成的測試在 set_bonus_test
	for slot: String in Equipment.SLOTS:
		equipment.unequip(slot)
	check(
		"全部脫下後屬性回到基礎值",
		is_equal_approx(stats.get_stat("damage_max"), base_max)
		and is_equal_approx(stats.get_stat("life"), base_life)
		and is_equal_approx(stats.get_stat("defense"), base_defense)
		and is_equal_approx(stats.get_stat("move_speed"), base_move_speed)
	)
	_free_player(player)


func _test_tooltip() -> void:
	var blade: ItemInstance = ItemDatabase.create_set_item("starchase_blade")
	var lines: Array[Dictionary] = ItemTooltip.build_lines(blade)
	# 這裡只看開頭的固定內容；件數詞綴、套裝成員與件數加成那幾行在 set_tooltip_test
	var expected: Array[String] = ["逐星之刃", "短劍", "傷害：2–5"]
	for modifier: Dictionary in blade.get_set_item_modifiers():
		expected.append(StatSystem.format_modifier(modifier))
	check(
		"套裝武器的說明開頭：名稱、底材名、傷害、固定修正值",
		expected.size() == 3 + 3 and _texts(lines).slice(0, expected.size()) == expected,
		_join(lines)
	)
	check(
		"名稱是綠色，底材名不是，說明裡有套裝名稱",
		lines[0]["color"] == ItemInstance.COLOR_SET
		and lines[1]["color"] == ItemTooltip.BASE_NAME_COLOR
		and _texts(lines).has("逐星行裝")
	)
	check(
		"綠色和其他名稱顏色都不同",
		ItemInstance.COLOR_SET != ItemInstance.COLOR_NORMAL
		and ItemInstance.COLOR_SET != ItemInstance.COLOR_MAGIC
		and ItemInstance.COLOR_SET != ItemInstance.COLOR_RARE
		and ItemInstance.COLOR_SET != ItemInstance.COLOR_RUNEWORD
	)

	var jerkin: ItemInstance = ItemDatabase.create_set_item("mistwood_jerkin")
	lines = ItemTooltip.build_lines(jerkin)
	check(
		"套裝防具的說明開頭：名稱、底材名、防禦，說明裡有套裝名稱",
		lines[0]["text"] == "霧林獵衣"
		and lines[1]["text"] == "皮甲"
		and lines[2]["text"] == "防禦：%d" % jerkin.defense
		and _texts(lines).has("霧林獵裝"),
		_join(lines)
	)
	var has_socket_line: bool = false
	for line: Dictionary in lines:
		if str(line["text"]).begins_with("插槽"):
			has_socket_line = true
	check("套裝物品的說明沒有插槽", not has_socket_line)


# 套裝物品沿用現有的背包與地上物品流程
func _test_inventory_and_ground() -> void:
	var player: Player = _create_player()
	var treads: ItemInstance = ItemDatabase.create_set_item("starchase_treads")
	check("套裝物品的大小來自底材", treads.get_size() == Vector2i(2, 2))

	var ground_item: GroundItem = GroundItem.spawn(self, treads, Vector2(40.0, 0.0))
	var label: Label = ground_item.get_node("Label") as Label
	check(
		"地上的套裝物品顯示該件的名稱，顏色是綠色",
		label.text == "逐星之履" and label.get_theme_color("font_color") == ItemInstance.COLOR_SET,
		label.text
	)
	check(
		"套裝物品可以從地上撿起來放進背包",
		player.pick_up(ground_item) and player.get_inventory().has_item(treads)
	)
	check(
		"套裝物品只能穿在底材的欄位",
		player.get_equipment().can_equip(treads, "boots") and not player.get_equipment().can_equip(treads, "helm")
	)
	_free_player(player)


func _test_debug_kit() -> void:
	var player: Player = _create_player()
	check(
		"debug_set_kit 預設關閉，背包是空的",
		not player.debug_set_kit and player.get_inventory().get_items().is_empty()
	)
	_free_player(player)

	player = PLAYER_SCENE.instantiate() as Player
	player.starting_equipment.clear()
	player.debug_set_kit = true
	add_child(player)
	var found: Array[String] = []
	for item: ItemInstance in player.get_inventory().get_items():
		found.append(item.set_item_id)
	check(
		"開啟後背包裡剛好是兩套全部的套裝物品，每件一件",
		_sorted(found) == _sorted(ItemDatabase.get_set_item_ids()),
		str(found)
	)
	_free_player(player)


# 這一套每一件穿的欄位，排序過
func _get_set_slots(set_id: String) -> Array:
	var slots: Array = []
	for set_item_id: String in ItemDatabase.get_set(set_id)["items"]:
		slots.append(ItemDatabase.get_base(ItemDatabase.get_set_item(set_item_id)["base"])["slot"])
	return _sorted(slots)


func _sorted(values: Array) -> Array:
	var sorted_values: Array = []
	sorted_values.assign(values)
	sorted_values.sort()
	return sorted_values


func _make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	return rng


func _is_valid_modifier(modifier: Variant) -> bool:
	if typeof(modifier) != TYPE_DICTIONARY:
		return false
	var modifier_type: Variant = modifier.get("type")
	return (
		StatSystem.STAT_NAMES.has(modifier.get("stat"))
		and (modifier_type == StatSystem.MODIFIER_FLAT or modifier_type == StatSystem.MODIFIER_PERCENT)
		and (typeof(modifier.get("value")) == TYPE_INT or typeof(modifier.get("value")) == TYPE_FLOAT)
	)


# 沒有起始裝備、背包是空的玩家
func _create_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.starting_equipment.clear()
	add_child(player)
	return player


func _free_player(player: Player) -> void:
	remove_child(player)
	player.free()


func _texts(lines: Array[Dictionary]) -> Array[String]:
	var texts: Array[String] = []
	for line: Dictionary in lines:
		texts.append(line["text"])
	return texts


func _join(lines: Array[Dictionary]) -> String:
	return " / ".join(_texts(lines))
