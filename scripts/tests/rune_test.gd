extends TestBase

# 符文資料與孔數的測試：runes.json、符文物品、生成時的孔數、說明框的內容。
# 插入符文與符文之語還沒做，這裡不測。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const HELD_ITEM_SCENE: PackedScene = preload("res://scenes/ui/held_item.tscn")
const TEST_SEED: int = 20261012
const ITEMS_PER_BASE: int = 1000
# data/runes.json 裡的符文數量，新增符文時要一起更新
const EXPECTED_RUNE_COUNT: int = 6
# 暗黑 2 的符文名（小寫），自創的符文不能撞名
const FORBIDDEN_RUNE_IDS: Array[String] = [
	"el", "eld", "tir", "nef", "eth", "ith", "tal", "ral", "ort", "thul", "amn", "sol",
	"shael", "dol", "hel", "io", "lum", "ko", "fal", "lem", "pul", "um", "mal", "ist",
	"gul", "vex", "ohm", "lo", "sur", "ber", "jah", "cham", "zod",
]


func _get_test_name() -> String:
	return "符文與孔數"


func _get_header_note() -> String:
	return "（種子 %d）" % TEST_SEED


func _run_tests() -> void:
	_test_rune_data()
	_test_rune_item()
	_test_rune_serialization()
	_test_magic_and_rare_have_no_sockets()
	_test_normal_sockets()
	_test_socketed_item_serialization()
	_test_rune_in_inventory()
	_test_rune_on_ground()
	_test_tooltip_sockets()
	_test_tooltip_rune()


func _test_rune_data() -> void:
	check(
		"符文載入數量正確",
		ItemDatabase.get_rune_count() == EXPECTED_RUNE_COUNT,
		"預期 %d，實際 %d" % [EXPECTED_RUNE_COUNT, ItemDatabase.get_rune_count()]
	)

	var missing_mods: Array[String] = []
	var bad_modifiers: Array[String] = []
	var forbidden: Array[String] = []
	var names: Array[String] = []
	for rune_id: String in ItemDatabase.get_rune_ids():
		var rune: Dictionary = ItemDatabase.get_rune(rune_id)
		names.append(str(rune.get("name", "")))
		if FORBIDDEN_RUNE_IDS.has(rune_id.to_lower()):
			forbidden.append(rune_id)
		for field: String in ItemDatabase.RUNE_MODS_FIELDS:
			var modifiers: Variant = rune.get(field)
			if typeof(modifiers) != TYPE_ARRAY or modifiers.is_empty():
				missing_mods.append("%s.%s" % [rune_id, field])
				continue
			for modifier: Variant in modifiers:
				if not _is_valid_modifier(modifier):
					bad_modifiers.append("%s.%s" % [rune_id, field])

	check("每顆符文都有武器與防具兩種修正值", missing_mods.is_empty(), "、".join(missing_mods))
	check(
		"符文的修正值都是 StatSystem 認得的格式",
		bad_modifiers.is_empty(),
		"、".join(bad_modifiers)
	)
	check("符文的 id 沒有沿用暗黑 2 的符文名", forbidden.is_empty(), "、".join(forbidden))

	var unique_names: Dictionary = {}
	for rune_name: String in names:
		unique_names[rune_name] = true
	check(
		"符文名稱都不是空的，也沒有重複",
		not unique_names.has("") and unique_names.size() == names.size(),
		"、".join(names)
	)
	check("孔的機率來自 item_settings.json", is_equal_approx(ItemDatabase.get_socket_chance(), 50.0))
	check("不存在的符文建立不出物品", ItemDatabase.create_rune("not_exist") == null)


func _test_rune_item() -> void:
	var rune: ItemInstance = ItemDatabase.create_rune("flint")
	check(
		"符文是佔 1 × 1 格的物品",
		rune != null and rune.is_rune() and rune.get_size() == Vector2i(1, 1)
	)
	check(
		"符文的名稱來自 runes.json",
		rune.get_display_name() == "燧紋" and rune.get_base_name() == "燧紋",
		rune.get_display_name()
	)
	check(
		"符文沒有裝備欄位、沒有孔，本身也不提供修正值",
		rune.get_slot().is_empty() and rune.sockets == 0 and rune.get_modifiers().is_empty()
	)
	check(
		"符文的顯示顏色與三種品質、有孔物品都不同",
		rune.get_display_color() == ItemInstance.COLOR_RUNE
		and rune.get_display_color() != ItemInstance.COLOR_NORMAL
		and rune.get_display_color() != ItemInstance.COLOR_MAGIC
		and rune.get_display_color() != ItemInstance.COLOR_RARE
		and rune.get_display_color() != ItemInstance.COLOR_SOCKETED
	)
	check("一般裝備不是符文", not ItemDatabase.create_item("short_sword").is_rune())


func _test_rune_serialization() -> void:
	var all_same: bool = true
	var detail: String = ""
	for rune_id: String in ItemDatabase.get_rune_ids():
		var rune: ItemInstance = ItemDatabase.create_rune(rune_id)
		var data: Dictionary = rune.to_dict()
		var restored: ItemInstance = ItemInstance.from_dict(data)
		var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(data)))
		for copy: ItemInstance in [restored, from_json]:
			if (
				not copy.is_rune()
				or copy.rune_id != rune_id
				or copy.get_display_name() != rune.get_display_name()
				or copy.get_size() != Vector2i(1, 1)
				or copy.to_dict() != data
			):
				all_same = false
				detail = rune_id
	check("每顆符文 to_dict 還原（含經過 JSON 文字）後內容相同", all_same, detail)

	var item_data: Dictionary = ItemDatabase.create_item("short_sword").to_dict()
	check("一般裝備的 to_dict 裡 rune_id 是空的", item_data.get("rune_id") == "")
	item_data.erase("rune_id")
	check("舊資料沒有 rune_id 時還原出來不是符文", not ItemInstance.from_dict(item_data).is_rune())


func _test_magic_and_rare_have_no_sockets() -> void:
	var rng: RandomNumberGenerator = _make_rng()
	for quality: String in [ItemInstance.QUALITY_MAGIC, ItemInstance.QUALITY_RARE]:
		var socketed_count: int = 0
		for base_id: String in ItemDatabase.get_base_ids():
			for i: int in ITEMS_PER_BASE:
				var item: ItemInstance = ItemGenerator.generate(base_id, quality, rng)
				if item.sockets != 0 or not item.socketed_runes.is_empty():
					socketed_count += 1
		check(
			"%s品質每種底材各 %d 件：孔數一定是 0" % [_quality_label(quality), ITEMS_PER_BASE],
			socketed_count == 0,
			"有 %d 件有孔" % socketed_count
		)


func _test_normal_sockets() -> void:
	var rng: RandomNumberGenerator = _make_rng()
	var over_max: Array[String] = []
	var wrong_distribution: Array[String] = []
	var not_empty: Array[String] = []
	var socketed_total: int = 0
	var socketable_total: int = 0

	for base_id: String in ItemDatabase.get_base_ids():
		var max_sockets: int = int(ItemDatabase.get_base(base_id)["max_sockets"])
		# 孔數 -> 出現次數
		var counts: Dictionary = {}
		for i: int in ITEMS_PER_BASE:
			var item: ItemInstance = ItemGenerator.generate(base_id, ItemInstance.QUALITY_NORMAL, rng)
			counts[item.sockets] = int(counts.get(item.sockets, 0)) + 1
			if item.sockets < 0 or item.sockets > max_sockets:
				over_max.append("%s 出現 %d 孔" % [base_id, item.sockets])
			if not item.socketed_runes.is_empty():
				not_empty.append(base_id)

		# 0 孔與 1～max_sockets 的每一種孔數都要出現過，不能有其他孔數
		for sockets: int in range(max_sockets + 1):
			if not counts.has(sockets):
				wrong_distribution.append("%s 沒有出現 %d 孔" % [base_id, sockets])
		if max_sockets > 0:
			socketable_total += ITEMS_PER_BASE
			socketed_total += ITEMS_PER_BASE - int(counts.get(0, 0))

	check("普通品質每種底材各 %d 件：孔數不超過 max_sockets" % ITEMS_PER_BASE, over_max.is_empty(), _first(over_max))
	check(
		"可以有孔的底材，0 孔與 1～max_sockets 每種孔數都出現過",
		wrong_distribution.is_empty(),
		_first(wrong_distribution)
	)
	check("生成時已插入的符文清單是空的", not_empty.is_empty(), _first(not_empty))
	check(
		"可以有孔的底材，有孔的比例接近 50%",
		socketed_total > socketable_total * 0.45 and socketed_total < socketable_total * 0.55,
		"%d 件裡 %d 件有孔" % [socketable_total, socketed_total]
	)

	var gloves_ok: bool = true
	for base_id: String in ["leather_gloves", "leather_boots"]:
		for i: int in ITEMS_PER_BASE:
			if ItemGenerator.generate(base_id, ItemInstance.QUALITY_NORMAL, rng).sockets != 0:
				gloves_ok = false
	check("max_sockets 為 0 的手套與靴子一定沒有孔", gloves_ok)
	check("create_item 建立的普通物品沒有孔", ItemDatabase.create_item("leather_armor").sockets == 0)


func _test_socketed_item_serialization() -> void:
	var item: ItemInstance = _generate_socketed("leather_armor")
	check("測試準備：生成出有孔的皮甲", item != null and item.sockets > 0)
	if item == null:
		return

	var data: Dictionary = item.to_dict()
	check(
		"有孔物品的 to_dict 包含孔數與空的符文清單",
		data.get("sockets") == item.sockets and data.get("socketed_runes") == []
	)
	var restored: ItemInstance = ItemInstance.from_dict(data)
	check(
		"有孔物品 to_dict 還原後孔數與內容相同",
		restored.sockets == item.sockets
		and restored.socketed_runes.is_empty()
		and restored.defense == item.defense
		and restored.to_dict() == data
	)
	var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(data)))
	check(
		"有孔物品經過 JSON 文字再還原後孔數與內容相同",
		from_json.sockets == item.sockets and from_json.to_dict() == data
	)

	# 之後插入符文時清單也要能存下來
	item.socketed_runes.append("flint")
	var with_rune: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(item.to_dict())))
	var expected_runes: Array[String] = ["flint"]
	check("已插入的符文清單也會被還原", with_rune.socketed_runes == expected_runes)


# 符文沿用現有的背包流程：放入、只佔一格、互換、不能穿在身上
func _test_rune_in_inventory() -> void:
	var inventory: Inventory = Inventory.new()
	var flint: ItemInstance = ItemDatabase.create_rune("flint")
	var gale: ItemInstance = ItemDatabase.create_rune("gale")

	check("符文可以自動放進背包", inventory.add_item_auto(flint) and inventory.has_item(flint))
	check(
		"符文只佔一格",
		inventory.get_item_at(0, 0) == flint
		and inventory.get_item_at(1, 0) == null
		and inventory.get_item_at(0, 1) == null
	)
	check(
		"符文可以放在右下角那一格",
		inventory.place(flint, inventory.width - 1, inventory.height - 1)
	)

	var result: Dictionary = inventory.place_or_swap(gale, inventory.width - 1, inventory.height - 1)
	check(
		"符文壓到另一顆符文時互換",
		result["success"]
		and result["swapped_item"] == flint
		and inventory.has_item(gale)
		and not inventory.has_item(flint)
	)

	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	inventory.place(sword, 0, 0)
	result = inventory.place_or_swap(flint, 0, 1)
	check(
		"符文壓到裝備時也會互換",
		result["success"] and result["swapped_item"] == sword and inventory.get_item_at(0, 1) == flint
	)

	var restored: Inventory = Inventory.from_dict(JSON.parse_string(JSON.stringify(inventory.to_dict())))
	var restored_rune: ItemInstance = restored.get_item_at(0, 1)
	check(
		"背包存檔還原後符文還在原位",
		restored_rune != null and restored_rune.rune_id == "flint" and restored.get_items().size() == 2
	)

	var equipment: Equipment = Equipment.new()
	var can_equip_any: bool = false
	for slot: String in Equipment.SLOTS:
		if equipment.can_equip(flint, slot) or equipment.equip(flint, slot)["success"]:
			can_equip_any = true
	check("符文不能穿在任何裝備欄", not can_equip_any)


# 符文沿用現有的地上物品流程：顯示名稱、撿起、從手上丟到地上
func _test_rune_on_ground() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.starting_equipment.clear()
	add_child(player)
	var held_layer: CanvasLayer = HELD_ITEM_SCENE.instantiate() as CanvasLayer
	add_child(held_layer)
	var held: HeldItem = held_layer.get_node("HeldItem") as HeldItem

	var rune: ItemInstance = ItemDatabase.create_rune("spring")
	var ground_item: GroundItem = GroundItem.spawn(self, rune, Vector2(40.0, 0.0))
	var label: Label = ground_item.get_node("Label") as Label
	check(
		"地上的符文顯示符文名與符文的顏色",
		label.text == "泉紋" and label.get_theme_color("font_color") == ItemInstance.COLOR_RUNE,
		label.text
	)
	check(
		"符文可以從地上撿起來放進背包",
		player.pick_up(ground_item) and player.get_inventory().has_item(rune)
	)

	player.get_inventory().remove(rune)
	held.hold(rune)
	check("符文可以拿在手上，大小是一格", held.size == Vector2.ONE * InventoryGrid.CELL_SIZE)
	var dropped: GroundItem = player.drop_held_item()
	check(
		"手上的符文可以丟到地上",
		dropped != null and dropped.item == rune and not held.is_holding()
	)

	if dropped != null:
		dropped.get_parent().remove_child(dropped)
		dropped.free()
	remove_child(held_layer)
	held_layer.free()
	remove_child(player)
	player.free()


func _test_tooltip_sockets() -> void:
	var item: ItemInstance = _generate_socketed("short_sword")
	check("測試準備：生成出有孔的短劍", item != null and item.sockets > 0)
	if item == null:
		return

	var lines: Array[Dictionary] = ItemTooltip.build_lines(item)
	check(
		"有孔物品的說明：灰色名稱、傷害、插槽 (0/N)",
		lines.size() == 3
		and lines[0]["text"] == "短劍"
		and lines[0]["color"] == ItemInstance.COLOR_SOCKETED
		and lines[1]["text"] == "傷害：2–5"
		and lines[2]["text"] == "插槽 (0/%d)" % item.sockets,
		_join_lines(lines)
	)
	check(
		"有孔物品的灰色與沒孔的普通物品不同",
		item.get_display_color() != ItemDatabase.create_item("short_sword").get_display_color()
		and item.get_quality_color() == ItemInstance.COLOR_NORMAL
	)

	var plain: ItemInstance = ItemDatabase.create_item("short_sword")
	lines = ItemTooltip.build_lines(plain)
	var has_socket_line: bool = false
	for line: Dictionary in lines:
		if str(line["text"]).begins_with("插槽"):
			has_socket_line = true
	check(
		"沒有孔的物品不顯示插槽，名稱是白色",
		not has_socket_line and lines[0]["color"] == ItemInstance.COLOR_NORMAL,
		_join_lines(lines)
	)

	var rng: RandomNumberGenerator = _make_rng()
	var magic: ItemInstance = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_MAGIC, rng)
	check("魔法物品的名稱仍是品質顏色", ItemTooltip.build_lines(magic)[0]["color"] == ItemInstance.COLOR_MAGIC)


func _test_tooltip_rune() -> void:
	# 鋒紋：武器 2 條、防具 1 條
	var rune: ItemInstance = ItemDatabase.create_rune("edge")
	var lines: Array[Dictionary] = ItemTooltip.build_lines(rune)
	var expected: Array[String] = [
		"鋒紋", "符文", "武器：", "+1 最小傷害", "+1 最大傷害", "", "防具：", "+1 力量"
	]
	var data: Dictionary = ItemDatabase.get_rune("edge")
	# 修正值文字以 StatSystem.format_modifier 為準，屬性的中文名稱改了這裡也會跟著變
	expected[3] = StatSystem.format_modifier(data["weapon_mods"][0])
	expected[4] = StatSystem.format_modifier(data["weapon_mods"][1])
	expected[7] = StatSystem.format_modifier(data["armor_mods"][0])

	var texts: Array[String] = []
	for line: Dictionary in lines:
		texts.append(line["text"])
	check("符文的說明分成「武器：」與「防具：」兩段", texts == expected, _join_lines(lines))
	check("符文說明的名稱是符文的顏色", lines[0]["color"] == ItemInstance.COLOR_RUNE)

	var all_have_sections: bool = true
	for rune_id: String in ItemDatabase.get_rune_ids():
		var rune_data: Dictionary = ItemDatabase.get_rune(rune_id)
		texts.clear()
		for line: Dictionary in ItemTooltip.build_lines(ItemDatabase.create_rune(rune_id)):
			texts.append(line["text"])
		var weapon_index: int = texts.find("武器：")
		var armor_index: int = texts.find("防具：")
		# 兩段的行數要剛好等於各自的修正值數量（中間還有一行空行）
		if (
			weapon_index < 0
			or armor_index - weapon_index != rune_data["weapon_mods"].size() + 2
			or texts.size() - armor_index != rune_data["armor_mods"].size() + 1
		):
			all_have_sections = false
	check("每顆符文的說明都列出兩段各自的全部修正值", all_have_sections)


func _make_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	return rng


# 重複生成普通品質的物品直到出現有孔的，找不到時回傳 null
func _generate_socketed(base_id: String) -> ItemInstance:
	var rng: RandomNumberGenerator = _make_rng()
	for i: int in 200:
		var item: ItemInstance = ItemGenerator.generate(base_id, ItemInstance.QUALITY_NORMAL, rng)
		if item.sockets > 0:
			return item
	return null


func _is_valid_modifier(modifier: Variant) -> bool:
	if typeof(modifier) != TYPE_DICTIONARY:
		return false
	var modifier_type: Variant = modifier.get("type")
	return (
		StatSystem.STAT_NAMES.has(modifier.get("stat"))
		and (modifier_type == StatSystem.MODIFIER_FLAT or modifier_type == StatSystem.MODIFIER_PERCENT)
		and (typeof(modifier.get("value")) == TYPE_INT or typeof(modifier.get("value")) == TYPE_FLOAT)
	)


func _quality_label(quality: String) -> String:
	return "魔法" if quality == ItemInstance.QUALITY_MAGIC else "稀有"


func _first(messages: Array[String]) -> String:
	return "" if messages.is_empty() else messages[0]


func _join_lines(lines: Array[Dictionary]) -> String:
	var texts: Array[String] = []
	for line: Dictionary in lines:
		texts.append(line["text"])
	return " / ".join(texts)
