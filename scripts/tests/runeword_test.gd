extends TestBase

# 符文之語的測試：runewords.json、配方比對、修正值、存檔還原、說明框、穿上後的屬性、除錯用的開場道具。
# 說明框的顏色與實際在背包裡插符文的操作，要在編輯器裡確認。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const SCREEN_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const HELD_ITEM_SCENE: PackedScene = preload("res://scenes/ui/held_item.tscn")
# data/runewords.json 裡的配方數量，新增配方時要一起更新
const EXPECTED_RUNEWORD_COUNT: int = 3
# 暗黑 2 的符文之語常見中文譯名，自創的名稱不能撞名
const FORBIDDEN_NAMES: Array[String] = [
	"鋼鐵", "怨恨", "隱密", "知識", "天底", "力量", "葉子", "西風", "煙霧", "精神", "眼光", "謎團",
	"白色", "榮耀", "忠誠", "悔恨", "無限", "悲傷", "死神", "信心", "橡樹之心", "執法者", "荊棘",
]


func _get_test_name() -> String:
	return "符文之語"


func _run_tests() -> void:
	_test_data()
	_test_correct_order()
	_test_reversed_order()
	_test_too_many_sockets()
	_test_wrong_base()
	_test_quality()
	_test_modifiers()
	_test_serialization()
	_test_equipped_stats()
	_test_tooltip()
	_test_grid_insert()
	_test_debug_kit()


func _test_data() -> void:
	check(
		"符文之語載入數量正確",
		ItemDatabase.get_runeword_count() == EXPECTED_RUNEWORD_COUNT,
		"預期 %d，實際 %d" % [EXPECTED_RUNEWORD_COUNT, ItemDatabase.get_runeword_count()]
	)

	var base_types: Dictionary = {}
	for base_id: String in ItemDatabase.get_base_ids():
		base_types[ItemDatabase.get_base(base_id)["type"]] = true

	var problems: Array[String] = []
	var names: Dictionary = {}
	var rune_orders: Dictionary = {}
	for runeword_id: String in ItemDatabase.get_runeword_ids():
		var runeword: Dictionary = ItemDatabase.get_runeword(runeword_id)
		var runeword_name: String = str(runeword.get("name", ""))
		if runeword_name.is_empty() or names.has(runeword_name) or FORBIDDEN_NAMES.has(runeword_name):
			problems.append("%s 的名稱 %s 不合格" % [runeword_id, runeword_name])
		names[runeword_name] = true

		for rune_id: Variant in runeword["runes"]:
			if not ItemDatabase.has_rune(str(rune_id)):
				problems.append("%s 用了不存在的符文 %s" % [runeword_id, str(rune_id)])
		for base_type: Variant in runeword["allowed_bases"]:
			if not base_types.has(base_type):
				problems.append("%s 用了不存在的底材類型 %s" % [runeword_id, str(base_type)])
		if runeword["modifiers"].is_empty():
			problems.append("%s 沒有修正值" % runeword_id)
		if _find_base_for(runeword).is_empty():
			problems.append("%s 沒有任何孔數夠的底材可以做" % runeword_id)

		# 符文順序加上底材類型不能和別的配方重複，否則會比對到兩組
		for base_type: Variant in runeword["allowed_bases"]:
			var key: String = "%s@%s" % [",".join(PackedStringArray(runeword["runes"])), str(base_type)]
			if rune_orders.has(key):
				problems.append("%s 與 %s 的配方重複" % [runeword_id, rune_orders[key]])
			rune_orders[key] = runeword_id
	check(
		"每組配方的名稱、符文、底材類型、修正值都合格，而且做得出來",
		problems.is_empty(),
		"；".join(problems)
	)
	check("不存在的符文之語查不到資料", ItemDatabase.get_runeword("not_exist").is_empty())


func _test_correct_order() -> void:
	var all_ok: bool = true
	var detail: String = ""
	for runeword_id: String in ItemDatabase.get_runeword_ids():
		var runeword: Dictionary = ItemDatabase.get_runeword(runeword_id)
		var item: ItemInstance = _socketed(_find_base_for(runeword), runeword["runes"].size())
		var runes: Array = runeword["runes"]
		for index: int in runes.size():
			# 還沒插滿之前不會變成符文之語
			if item.is_runeword():
				all_ok = false
				detail = "%s 還沒插滿就成功了" % runeword_id
			item.insert_rune(ItemDatabase.create_rune(runes[index]))
		if item.runeword_id != runeword_id or item.get_display_name() != runeword["name"]:
			all_ok = false
			detail = "%s 插滿後是 %s" % [runeword_id, item.runeword_id]
	check("每組配方照正確順序插滿都會成功，名稱變成符文之語的名稱", all_ok, detail)

	var sword: ItemInstance = _make("short_sword", 2, ["flint", "edge"])
	var axe: ItemInstance = _make("hand_axe", 2, ["flint", "edge"])
	check(
		"allowed_bases 裡的每種底材類型都可以（短劍與手斧都能做裂曉）",
		sword.runeword_id == "dawnrend" and axe.runeword_id == "dawnrend"
	)
	check(
		"符文之語的顯示顏色是暗金色，底材名不變",
		sword.get_display_color() == ItemInstance.COLOR_RUNEWORD and sword.get_base_name() == "短劍"
	)
	check(
		"RunewordMatcher.find_match 回傳配方 id，沒插符文的物品回傳空字串",
		RunewordMatcher.find_match(sword) == "dawnrend"
		and RunewordMatcher.find_match(_socketed("short_sword", 2)).is_empty()
		and RunewordMatcher.find_match(null).is_empty()
	)


func _test_reversed_order() -> void:
	var all_failed: bool = true
	for runeword_id: String in ItemDatabase.get_runeword_ids():
		var runeword: Dictionary = ItemDatabase.get_runeword(runeword_id)
		var reversed_runes: Array = runeword["runes"].duplicate()
		reversed_runes.reverse()
		var item: ItemInstance = _make(_find_base_for(runeword), reversed_runes.size(), reversed_runes)
		if item.is_runeword() or item.socketed_runes.size() != reversed_runes.size():
			all_failed = false
	check("每組配方順序相反時都失敗，符文照樣插進去", all_failed)

	var armor: ItemInstance = _make("leather_armor", 3, ["flint", "crag", "ruin"])
	check("三顆符文只對調前兩顆也失敗", not armor.is_runeword())
	check(
		"失敗的物品名稱與顏色維持有孔的普通物品",
		armor.get_display_name() == "皮甲" and armor.get_display_color() == ItemInstance.COLOR_SOCKETED
	)


func _test_too_many_sockets() -> void:
	# 靜泉是 2 顆（泉紋、岩紋），皮帽有 3 孔時前兩顆照配方插也不會成功
	var cap: ItemInstance = _socketed("leather_cap", 3)
	cap.insert_rune(ItemDatabase.create_rune("spring"))
	cap.insert_rune(ItemDatabase.create_rune("crag"))
	check("孔數比配方多，插完配方的符文但還沒插滿時不成功", not cap.is_runeword())
	cap.insert_rune(ItemDatabase.create_rune("flint"))
	check(
		"孔數比配方多，插滿後也失敗",
		not cap.is_runeword() and cap.socketed_runes.size() == 3
	)

	var sword: ItemInstance = _make("short_sword", 3, ["flint", "edge", "flint"])
	check("3 孔的短劍插了裂曉的兩顆再多一顆也失敗", not sword.is_runeword())

	# 孔數比配方少：磐嶽要 3 顆，2 孔的皮甲只插得下前兩顆
	var armor: ItemInstance = _make("leather_armor", 2, ["crag", "flint"])
	check("孔數比配方少時插滿也失敗", not armor.is_runeword())


func _test_wrong_base() -> void:
	var cap: ItemInstance = _make("leather_cap", 2, ["flint", "edge"])
	check("裂曉只能做在劍與斧上，同樣的符文插在皮帽上失敗", not cap.is_runeword())

	var sword: ItemInstance = _make("short_sword", 2, ["spring", "crag"])
	check("靜泉只能做在頭盔上，插在短劍上失敗", not sword.is_runeword())

	var helm_ok: ItemInstance = _make("leather_cap", 2, ["spring", "crag"])
	check("同樣的符文插在皮帽上就成功", helm_ok.runeword_id == "stillspring")


func _test_quality() -> void:
	for quality: String in [ItemInstance.QUALITY_MAGIC, ItemInstance.QUALITY_RARE]:
		var item: ItemInstance = _socketed("short_sword", 2)
		item.quality = quality
		item.insert_rune(ItemDatabase.create_rune("flint"))
		item.insert_rune(ItemDatabase.create_rune("edge"))
		check(
			"%s品質的物品就算有孔、符文順序正確也不會成功" % ("魔法" if quality == "magic" else "稀有"),
			not item.is_runeword()
		)


func _test_modifiers() -> void:
	var plain: ItemInstance = ItemDatabase.create_item("short_sword")
	var sword: ItemInstance = _make("short_sword", 2, ["flint", "edge"])
	var runeword: Dictionary = ItemDatabase.get_runeword("dawnrend")

	# 底材 2～5；燧紋 +2 最大傷害；鋒紋最小、最大各 +1；裂曉 +2 最小、+4 最大、+10% 攻擊速度
	var expected: Array[Dictionary] = plain.get_modifiers()
	expected.append({"stat": "damage_max", "value": 2.0, "type": "flat"})
	expected.append({"stat": "damage_min", "value": 1.0, "type": "flat"})
	expected.append({"stat": "damage_max", "value": 1.0, "type": "flat"})
	for modifier: Dictionary in runeword["modifiers"]:
		expected.append(
			{"stat": modifier["stat"], "value": float(modifier["value"]), "type": modifier["type"]}
		)
	check(
		"成功後 get_modifiers 同時包含底材、符文與符文之語的修正值",
		sword.get_modifiers() == expected,
		str(sword.get_modifiers())
	)
	check(
		"符文的效果與符文之語的效果分開取得，兩者都不是空的",
		sword.get_rune_modifiers().size() == 3
		and sword.get_runeword_modifiers().size() == runeword["modifiers"].size()
	)

	var stats: Dictionary = StatSystem.calculate({"attack_speed": 1.0}, sword.get_modifiers())
	check(
		"符文與符文之語的加成是疊加的",
		is_equal_approx(stats["damage_min"], 2.0 + 1.0 + 2.0)
		and is_equal_approx(stats["damage_max"], 5.0 + 2.0 + 1.0 + 4.0)
		and is_equal_approx(stats["attack_speed"], 1.1),
		"%s～%s，攻速 %s" % [stats["damage_min"], stats["damage_max"], stats["attack_speed"]]
	)

	var failed: ItemInstance = _make("short_sword", 2, ["edge", "flint"])
	check(
		"比對失敗的物品只有符文的效果，沒有符文之語的修正值",
		failed.get_runeword_modifiers().is_empty()
		and failed.get_modifiers().size() == plain.get_modifiers().size() + 3
	)

	var modifiers: Array[Dictionary] = sword.get_runeword_modifiers()
	modifiers[0]["value"] = 999.0
	check(
		"改動回傳的修正值不會影響符文之語資料",
		is_equal_approx(float(ItemDatabase.get_runeword("dawnrend")["modifiers"][0]["value"]), 2.0)
	)


func _test_serialization() -> void:
	var armor: ItemInstance = _make("leather_armor", 3, ["crag", "flint", "ruin"])
	check("測試準備：皮甲做成磐嶽", armor.runeword_id == "bedrock")

	var data: Dictionary = armor.to_dict()
	check("to_dict 包含 runeword_id", data.get("runeword_id") == "bedrock")

	var restored: ItemInstance = ItemInstance.from_dict(data)
	var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(data)))
	check(
		"to_dict 還原後仍是符文之語，內容相同",
		restored.is_runeword()
		and restored.runeword_id == "bedrock"
		and restored.get_display_name() == "磐嶽"
		and restored.to_dict() == data
		and restored.get_modifiers() == armor.get_modifiers()
	)
	check(
		"經過 JSON 文字再還原後仍是符文之語，內容相同",
		from_json.is_runeword()
		and from_json.to_dict() == data
		and from_json.get_modifiers() == armor.get_modifiers()
	)

	var plain_data: Dictionary = ItemDatabase.create_item("leather_armor").to_dict()
	check("一般物品的 to_dict 裡 runeword_id 是空的", plain_data.get("runeword_id") == "")
	plain_data.erase("runeword_id")
	check("舊資料沒有 runeword_id 時還原出來不是符文之語", not ItemInstance.from_dict(plain_data).is_runeword())

	var inventory: Inventory = Inventory.new()
	inventory.place(armor, 4, 1)
	var restored_inventory: Inventory = Inventory.from_dict(
		JSON.parse_string(JSON.stringify(inventory.to_dict()))
	)
	var restored_armor: ItemInstance = restored_inventory.get_item_at(4, 1)
	check(
		"背包存檔還原後，裡面的物品仍是符文之語",
		restored_armor != null and restored_armor.runeword_id == "bedrock"
	)


func _test_equipped_stats() -> void:
	var player: Player = _create_player()
	var stats: StatsComponent = player.get_stats()
	var equipment: Equipment = player.get_equipment()
	var base_min: float = stats.get_stat("damage_min")
	var base_max: float = stats.get_stat("damage_max")
	var base_attack_speed: float = stats.get_stat("attack_speed")
	var base_life: float = stats.get_stat("life")
	var base_defense: float = stats.get_stat("defense")

	# 短劍 2～5；燧紋 +2 最大；鋒紋各 +1；裂曉 +2 最小、+4 最大、+10% 攻擊速度
	var sword: ItemInstance = _make("short_sword", 2, ["flint", "edge"])
	equipment.equip(sword, "weapon")
	check(
		"穿上符文之語武器後，傷害與攻擊速度是底材、符文、符文之語三者相加",
		is_equal_approx(stats.get_stat("damage_min"), base_min + 2.0 + 1.0 + 2.0)
		and is_equal_approx(stats.get_stat("damage_max"), base_max + 5.0 + 2.0 + 1.0 + 4.0)
		and is_equal_approx(stats.get_stat("attack_speed"), base_attack_speed * 1.1),
		"傷害 %s～%s，攻速 %s" % [
			stats.get_stat("damage_min"), stats.get_stat("damage_max"), stats.get_stat("attack_speed")
		]
	)

	# 同樣的符文但順序相反：只有符文的效果
	var failed: ItemInstance = _make("short_sword", 2, ["edge", "flint"])
	equipment.equip(failed, "weapon")
	check(
		"換成順序相反、沒有成功的短劍後，只剩符文本身的效果",
		is_equal_approx(stats.get_stat("damage_min"), base_min + 2.0 + 1.0)
		and is_equal_approx(stats.get_stat("damage_max"), base_max + 5.0 + 2.0 + 1.0)
		and is_equal_approx(stats.get_stat("attack_speed"), base_attack_speed)
	)
	equipment.unequip("weapon")

	# 皮帽的靜泉：泉紋 +2 體力（+6 生命）、岩紋 +6% 防禦；靜泉 +20 生命、+5 防禦
	var cap: ItemInstance = _make("leather_cap", 2, ["spring", "crag"])
	equipment.equip(cap, "helm")
	check(
		"穿上符文之語頭盔後，生命與防禦正確",
		is_equal_approx(stats.get_stat("life"), base_life + 6.0 + 20.0)
		and is_equal_approx(stats.get_stat("defense"), (base_defense + float(cap.defense) + 5.0) * 1.06),
		"生命 %s、防禦 %s" % [stats.get_stat("life"), stats.get_stat("defense")]
	)
	equipment.unequip("helm")
	check(
		"脫下後屬性回到基礎值",
		is_equal_approx(stats.get_stat("life"), base_life)
		and is_equal_approx(stats.get_stat("defense"), base_defense)
		and is_equal_approx(stats.get_stat("damage_max"), base_max)
	)
	_free_player(player)


func _test_tooltip() -> void:
	var sword: ItemInstance = _make("short_sword", 2, ["flint", "edge"])
	var lines: Array[Dictionary] = ItemTooltip.build_lines(sword)
	var expected: Array[String] = ["裂曉", "短劍", "'燧紋 鋒紋'", "傷害：2–5"]
	for modifier: Dictionary in sword.get_rune_modifiers() + sword.get_runeword_modifiers():
		expected.append(StatSystem.format_modifier(modifier))
	check(
		"符文之語的說明：名稱、底材名、'符文順序'、傷害、所有修正值",
		_texts(lines) == expected and expected.size() == 4 + 3 + 3,
		_join(lines)
	)
	check(
		"符文之語的名稱是暗金色，而且和其他名稱顏色都不同",
		lines[0]["color"] == ItemInstance.COLOR_RUNEWORD
		and ItemInstance.COLOR_RUNEWORD != ItemInstance.COLOR_RARE
		and ItemInstance.COLOR_RUNEWORD != ItemInstance.COLOR_RUNE
		and ItemInstance.COLOR_RUNEWORD != ItemInstance.COLOR_SOCKETED
	)
	check("底材名另起一行，顏色和稀有物品的底材名相同", lines[1]["color"] == ItemTooltip.BASE_NAME_COLOR)

	var armor: ItemInstance = _make("leather_armor", 3, ["crag", "flint", "ruin"])
	lines = ItemTooltip.build_lines(armor)
	check(
		"三顆符文的說明：'岩紋 燧紋 墟紋'，接著是防禦",
		lines[0]["text"] == "磐嶽"
		and lines[1]["text"] == "皮甲"
		and lines[2]["text"] == "'岩紋 燧紋 墟紋'"
		and lines[3]["text"] == "防禦：%d" % armor.defense
		and lines.size() == 4 + armor.get_rune_modifiers().size() + armor.get_runeword_modifiers().size(),
		_join(lines)
	)

	var failed: ItemInstance = _make("short_sword", 2, ["edge", "flint"])
	lines = ItemTooltip.build_lines(failed)
	check(
		"沒有成功的物品維持一般有孔物品的說明",
		lines[0]["text"] == "短劍"
		and lines[0]["color"] == ItemInstance.COLOR_SOCKETED
		and _texts(lines).has("插槽 (2/2)"),
		_join(lines)
	)


# 在背包格子裡用手上的符文插：插滿的那一下變成符文之語
func _test_grid_insert() -> void:
	var inventory: Inventory = Inventory.new()
	var equipment: Equipment = Equipment.new()
	var held_layer: CanvasLayer = HELD_ITEM_SCENE.instantiate() as CanvasLayer
	add_child(held_layer)
	var held: HeldItem = held_layer.get_node("HeldItem") as HeldItem
	var screen: InventoryScreen = SCREEN_SCENE.instantiate() as InventoryScreen
	add_child(screen)
	screen.setup(inventory, equipment, held)
	screen.open()
	var grid: InventoryGrid = screen.get_grid()

	var cap: ItemInstance = _socketed("leather_cap", 2)
	inventory.place(cap, 0, 0)
	var cell_center: Vector2 = Vector2(0.5, 0.5) * InventoryGrid.CELL_SIZE

	held.hold(ItemDatabase.create_rune("spring"))
	grid.click_at(cell_center)
	check("在背包裡插第一顆時還不是符文之語", not cap.is_runeword() and cap.socketed_runes.size() == 1)
	held.hold(ItemDatabase.create_rune("crag"))
	grid.click_at(cell_center)
	check(
		"在背包裡插滿最後一顆時變成符文之語，手上的符文消失",
		cap.runeword_id == "stillspring" and not held.is_holding() and inventory.has_item(cap)
	)

	held.hold(ItemDatabase.create_rune("flint"))
	grid.click_at(cell_center)
	check(
		"符文之語已經沒有空孔，再拿符文點它是互換",
		held.item == cap and cap.socketed_runes.size() == 2 and cap.runeword_id == "stillspring"
	)

	remove_child(screen)
	screen.free()
	remove_child(held_layer)
	held_layer.free()


func _test_debug_kit() -> void:
	var player: Player = _create_player()
	check("debug_runeword_kit 預設關閉，背包是空的", not player.debug_runeword_kit and player.get_inventory().get_items().is_empty())
	_free_player(player)

	player = PLAYER_SCENE.instantiate() as Player
	player.starting_equipment.clear()
	player.debug_runeword_kit = true
	add_child(player)
	var items: Array[ItemInstance] = player.get_inventory().get_items()

	var rune_total: int = 0
	for runeword_id: String in ItemDatabase.get_runeword_ids():
		rune_total += ItemDatabase.get_runeword(runeword_id)["runes"].size()
	check(
		"開啟後背包裡有每組配方的底材和全部需要的符文",
		items.size() == ItemDatabase.get_runeword_count() + rune_total,
		"背包裡有 %d 件" % items.size()
	)

	# 每組配方：找到孔數剛好、類型符合的底材，把背包裡對應的符文依序插進去
	var made: Array[String] = []
	for runeword_id: String in ItemDatabase.get_runeword_ids():
		var runeword: Dictionary = ItemDatabase.get_runeword(runeword_id)
		var target: ItemInstance = null
		for item: ItemInstance in items:
			if (
				not item.is_rune()
				and not item.is_runeword()
				and item.socketed_runes.is_empty()
				and item.sockets == runeword["runes"].size()
				and runeword["allowed_bases"].has(ItemDatabase.get_base(item.base_id)["type"])
			):
				target = item
				break
		if target == null:
			continue
		for rune_id: String in runeword["runes"]:
			for item: ItemInstance in player.get_inventory().get_items():
				if item.is_rune() and item.rune_id == rune_id:
					if target.insert_rune(item):
						player.get_inventory().remove(item)
					break
		if target.runeword_id == runeword_id:
			made.append(runeword_id)
	check(
		"用背包裡的東西可以湊出全部 3 組符文之語",
		made == ItemDatabase.get_runeword_ids(),
		"做出 %s" % str(made)
	)
	var leftover_runes: int = 0
	for item: ItemInstance in player.get_inventory().get_items():
		if item.is_rune():
			leftover_runes += 1
	check("符文剛好用完，沒有多的", leftover_runes == 0, "剩 %d 顆" % leftover_runes)
	_free_player(player)


# 孔數夠做這組配方的第一個底材 id，找不到時回傳空字串
func _find_base_for(runeword: Dictionary) -> String:
	for base_id: String in ItemDatabase.get_base_ids():
		var base: Dictionary = ItemDatabase.get_base(base_id)
		if (
			runeword["allowed_bases"].has(base["type"])
			and int(base["max_sockets"]) >= runeword["runes"].size()
		):
			return base_id
	return ""


# 指定孔數的普通物品，還沒插任何符文
func _socketed(base_id: String, sockets: int) -> ItemInstance:
	var item: ItemInstance = ItemDatabase.create_item(base_id)
	item.sockets = sockets
	return item


# 指定孔數的普通物品，並依序插入 rune_ids
func _make(base_id: String, sockets: int, rune_ids: Array) -> ItemInstance:
	var item: ItemInstance = _socketed(base_id, sockets)
	for rune_id: String in rune_ids:
		item.insert_rune(ItemDatabase.create_rune(rune_id))
	return item


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
