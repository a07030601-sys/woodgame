extends TestBase

# 鑲嵌符文的測試：ItemInstance 的插入規則與修正值、背包格子的插入操作、說明框、穿上後的屬性。
# 插入預覽的長相（綠色加外框）無法在這裡驗證，要在編輯器裡實際操作。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const SCREEN_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const HELD_ITEM_SCENE: PackedScene = preload("res://scenes/ui/held_item.tscn")
const CELL: float = InventoryGrid.CELL_SIZE

var _inventory: Inventory = null
var _equipment: Equipment = null
var _screen: InventoryScreen = null
var _grid: InventoryGrid = null
var _held_layer: CanvasLayer = null
var _held: HeldItem = null
var _equipment_panel: EquipmentPanel = null


func _get_test_name() -> String:
	return "鑲嵌符文"


func _run_tests() -> void:
	_test_can_insert()
	_test_insert_until_full()
	_test_modifiers()
	_test_serialization()
	_test_equipped_stats()
	_test_tooltip()
	_test_grid_insert()
	_test_grid_cannot_insert()
	_test_equipment_panel_does_not_insert()
	await _test_insert_preview()
	_free_screen()


func _test_can_insert() -> void:
	var flint: ItemInstance = ItemDatabase.create_rune("flint")
	var plain: ItemInstance = ItemDatabase.create_item("short_sword")
	check(
		"沒孔的物品不能插",
		not plain.can_insert_rune(flint) and not plain.insert_rune(flint) and plain.socketed_runes.is_empty()
	)

	var sword: ItemInstance = _socketed("short_sword", 2)
	check("有空孔的物品可以插符文", sword.can_insert_rune(flint))
	check(
		"不是符文的物品不能拿來插",
		not sword.can_insert_rune(ItemDatabase.create_item("leather_cap"))
		and not sword.can_insert_rune(null)
		and not sword.insert_rune(ItemDatabase.create_item("leather_cap"))
		and sword.socketed_runes.is_empty()
	)

	var unknown: ItemInstance = ItemInstance.new()
	unknown.rune_id = "not_exist"
	check("資料裡沒有的符文不能插", not sword.can_insert_rune(unknown))
	check(
		"符文不能插進符文",
		not flint.can_insert_rune(ItemDatabase.create_rune("gale"))
		and not flint.insert_rune(ItemDatabase.create_rune("gale"))
	)

	var gloves: ItemInstance = ItemGenerator.generate(
		"leather_gloves", ItemInstance.QUALITY_NORMAL, RandomNumberGenerator.new()
	)
	check("max_sockets 為 0 的手套不能插", not gloves.can_insert_rune(flint))


func _test_insert_until_full() -> void:
	var armor: ItemInstance = _socketed("leather_armor", 3)
	var inserted: Array[String] = []
	var counts_ok: bool = true
	for rune_id: String in ["gale", "flint", "gale"]:
		if not armor.insert_rune(ItemDatabase.create_rune(rune_id)):
			counts_ok = false
		inserted.append(rune_id)
		if armor.socketed_runes.size() != inserted.size():
			counts_ok = false
	check("每插一顆，已插入的數量就加一", counts_ok, str(armor.socketed_runes))
	check(
		"符文依插入順序排在下一個位置，同一顆可以重複插",
		armor.socketed_runes == inserted and armor.sockets == 3,
		str(armor.socketed_runes)
	)

	var extra: ItemInstance = ItemDatabase.create_rune("crag")
	check(
		"孔滿後不能再插，內容不變",
		not armor.can_insert_rune(extra)
		and not armor.insert_rune(extra)
		and armor.socketed_runes == inserted
	)

	var one_socket: ItemInstance = _socketed("leather_cap", 1)
	one_socket.insert_rune(ItemDatabase.create_rune("spring"))
	check(
		"只有一個孔的物品插一顆就滿了",
		one_socket.socketed_runes.size() == 1 and not one_socket.can_insert_rune(extra)
	)


func _test_modifiers() -> void:
	# 每一顆符文都各插在武器與防具上檢查
	var weapon_ok: bool = true
	var armor_ok: bool = true
	var detail: String = ""
	for rune_id: String in ItemDatabase.get_rune_ids():
		var rune: Dictionary = ItemDatabase.get_rune(rune_id)

		var sword: ItemInstance = _socketed("short_sword", 1)
		sword.insert_rune(ItemDatabase.create_rune(rune_id))
		if not _same_modifiers(sword.get_rune_modifiers(), rune["weapon_mods"]):
			weapon_ok = false
			detail = "%s：%s" % [rune_id, str(sword.get_rune_modifiers())]

		for base_id: String in ["leather_cap", "leather_armor"]:
			var armor: ItemInstance = _socketed(base_id, 1)
			armor.insert_rune(ItemDatabase.create_rune(rune_id))
			if not _same_modifiers(armor.get_rune_modifiers(), rune["armor_mods"]):
				armor_ok = false
				detail = "%s：%s" % [rune_id, str(armor.get_rune_modifiers())]
	check("插在武器上拿的是 weapon_mods", weapon_ok, detail)
	check("插在頭盔與身體護甲上拿的是 armor_mods", armor_ok, detail)

	var axe: ItemInstance = _socketed("hand_axe", 2)
	var before: Array[Dictionary] = axe.get_modifiers()
	check("還沒插符文時沒有符文的修正值", axe.get_rune_modifiers().is_empty())
	axe.insert_rune(ItemDatabase.create_rune("flint"))
	axe.insert_rune(ItemDatabase.create_rune("edge"))
	# 燧紋：+2 最大傷害；鋒紋：最小、最大傷害各 +1
	var expected: Array[Dictionary] = before.duplicate()
	expected.append({"stat": "damage_max", "value": 2.0, "type": "flat"})
	expected.append({"stat": "damage_min", "value": 1.0, "type": "flat"})
	expected.append({"stat": "damage_max", "value": 1.0, "type": "flat"})
	check(
		"get_modifiers 是底材的修正值再加上每顆符文的效果",
		axe.get_modifiers() == expected,
		str(axe.get_modifiers())
	)

	var stats: Dictionary = StatSystem.calculate({}, axe.get_modifiers())
	check(
		"含符文的修正值可以交給 StatSystem 計算",
		is_equal_approx(stats["damage_min"], 3.0 + 1.0) and is_equal_approx(stats["damage_max"], 6.0 + 2.0 + 1.0),
		"%s～%s" % [stats["damage_min"], stats["damage_max"]]
	)

	var cap: ItemInstance = _socketed("leather_cap", 2)
	cap.insert_rune(ItemDatabase.create_rune("flint"))
	cap.insert_rune(ItemDatabase.create_rune("flint"))
	stats = StatSystem.calculate({}, cap.get_modifiers())
	check(
		"同一顆符文插兩次效果會疊加",
		is_equal_approx(stats["defense"], float(cap.defense) + 3.0 + 3.0),
		str(stats["defense"])
	)

	var modifiers: Array[Dictionary] = cap.get_rune_modifiers()
	modifiers[0]["value"] = 999.0
	check(
		"改動回傳的修正值不會影響符文資料",
		is_equal_approx(float(ItemDatabase.get_rune("flint")["armor_mods"][0]["value"]), 3.0)
		and is_equal_approx(cap.get_rune_modifiers()[0]["value"], 3.0)
	)


func _test_serialization() -> void:
	var sword: ItemInstance = _socketed("short_sword", 2)
	sword.insert_rune(ItemDatabase.create_rune("ruin"))
	var data: Dictionary = sword.to_dict()
	check("to_dict 裡有已插入的符文", data.get("socketed_runes") == ["ruin"] and data.get("sockets") == 2)

	var restored: ItemInstance = ItemInstance.from_dict(data)
	var from_json: ItemInstance = ItemInstance.from_dict(JSON.parse_string(JSON.stringify(data)))
	check(
		"插入後 to_dict 還原的內容相同",
		restored.to_dict() == data
		and restored.socketed_runes == sword.socketed_runes
		and restored.get_modifiers() == sword.get_modifiers()
	)
	check(
		"經過 JSON 文字再還原後內容相同",
		from_json.to_dict() == data and from_json.get_modifiers() == sword.get_modifiers()
	)
	check(
		"還原出來的物品可以繼續插，孔滿後一樣不能再插",
		from_json.insert_rune(ItemDatabase.create_rune("gale"))
		and not from_json.can_insert_rune(ItemDatabase.create_rune("gale"))
		and sword.socketed_runes.size() == 1
	)

	var inventory: Inventory = Inventory.new()
	inventory.place(sword, 3, 0)
	var restored_inventory: Inventory = Inventory.from_dict(
		JSON.parse_string(JSON.stringify(inventory.to_dict()))
	)
	var restored_sword: ItemInstance = restored_inventory.get_item_at(3, 0)
	check(
		"背包存檔還原後，物品上的符文還在",
		restored_sword != null and restored_sword.to_dict() == data
	)


func _test_equipped_stats() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.starting_equipment.clear()
	add_child(player)
	var stats: StatsComponent = player.get_stats()
	var equipment: Equipment = player.get_equipment()
	var base_min: float = stats.get_stat("damage_min")
	var base_max: float = stats.get_stat("damage_max")
	var base_life: float = stats.get_stat("life")
	var base_defense: float = stats.get_stat("defense")

	# 短劍 2～5，燧紋 +2 最大傷害，岩紋 +2 力量（每點力量讓傷害 +1%）
	var sword: ItemInstance = _socketed("short_sword", 2)
	sword.insert_rune(ItemDatabase.create_rune("flint"))
	sword.insert_rune(ItemDatabase.create_rune("crag"))
	equipment.equip(sword, "weapon")
	check(
		"插了符文的武器穿上後，傷害與力量照符文的 weapon_mods 增加",
		is_equal_approx(stats.get_stat("strength"), 2.0)
		and is_equal_approx(stats.get_stat("damage_min"), (base_min + 2.0) * 1.02)
		and is_equal_approx(stats.get_stat("damage_max"), (base_max + 5.0 + 2.0) * 1.02),
		"力量 %s、傷害 %s～%s" % [
			stats.get_stat("strength"), stats.get_stat("damage_min"), stats.get_stat("damage_max")
		]
	)

	var plain: ItemInstance = ItemDatabase.create_item("short_sword")
	equipment.equip(plain, "weapon")
	check(
		"換成沒插符文的短劍後，符文的效果消失",
		is_equal_approx(stats.get_stat("strength"), 0.0)
		and is_equal_approx(stats.get_stat("damage_min"), base_min + 2.0)
		and is_equal_approx(stats.get_stat("damage_max"), base_max + 5.0)
	)

	# 泉紋插在防具上是 +2 體力（每點體力 +3 生命），燧紋是 +3 防禦
	var armor: ItemInstance = _socketed("leather_armor", 2)
	armor.insert_rune(ItemDatabase.create_rune("spring"))
	armor.insert_rune(ItemDatabase.create_rune("flint"))
	equipment.equip(armor, "armor")
	check(
		"插了符文的防具穿上後，屬性照符文的 armor_mods 增加",
		is_equal_approx(stats.get_stat("vitality"), 2.0)
		and is_equal_approx(stats.get_stat("life"), base_life + 6.0)
		and is_equal_approx(stats.get_stat("defense"), base_defense + float(armor.defense) + 3.0),
		"體力 %s、生命 %s、防禦 %s" % [
			stats.get_stat("vitality"), stats.get_stat("life"), stats.get_stat("defense")
		]
	)

	equipment.unequip("armor")
	equipment.unequip("weapon")
	check(
		"全部脫下後屬性回到基礎值",
		is_equal_approx(stats.get_stat("damage_max"), base_max)
		and is_equal_approx(stats.get_stat("life"), base_life)
		and is_equal_approx(stats.get_stat("defense"), base_defense)
	)
	remove_child(player)
	player.free()


func _test_tooltip() -> void:
	var sword: ItemInstance = _socketed("short_sword", 3)
	sword.insert_rune(ItemDatabase.create_rune("edge"))
	var lines: Array[Dictionary] = ItemTooltip.build_lines(sword)
	var edge: Dictionary = ItemDatabase.get_rune("edge")
	var expected: Array[String] = [
		"短劍",
		"傷害：2–5",
		"插槽 (1/3)",
		"鋒紋",
		StatSystem.format_modifier(edge["weapon_mods"][0]),
		StatSystem.format_modifier(edge["weapon_mods"][1]),
	]
	check("插了一顆的說明：插槽 (1/3)、符文名稱、符文的修正值", _texts(lines) == expected, _join(lines))
	check(
		"符文名稱是符文的顏色，符文的修正值和詞綴用同一種顏色",
		lines.size() == expected.size()
		and lines[3]["color"] == ItemInstance.COLOR_RUNE
		and lines[4]["color"] == ItemTooltip.AFFIX_COLOR
	)

	sword.insert_rune(ItemDatabase.create_rune("flint"))
	lines = ItemTooltip.build_lines(sword)
	expected = [
		"短劍",
		"傷害：2–5",
		"插槽 (2/3)",
		"鋒紋",
		"燧紋",
		StatSystem.format_modifier(edge["weapon_mods"][0]),
		StatSystem.format_modifier(edge["weapon_mods"][1]),
		StatSystem.format_modifier(ItemDatabase.get_rune("flint")["weapon_mods"][0]),
	]
	check("插了兩顆的說明：符文名稱依插入順序列出", _texts(lines) == expected, _join(lines))

	var cap: ItemInstance = _socketed("leather_cap", 1)
	cap.insert_rune(ItemDatabase.create_rune("flint"))
	lines = ItemTooltip.build_lines(cap)
	check(
		"防具的說明顯示的是符文的 armor_mods",
		_texts(lines).has("插槽 (1/1)")
		and lines[lines.size() - 1]["text"]
		== StatSystem.format_modifier(ItemDatabase.get_rune("flint")["armor_mods"][0]),
		_join(lines)
	)


func _test_grid_insert() -> void:
	_reset()
	var armor: ItemInstance = _socketed("leather_armor", 2)
	_inventory.place(armor, 2, 0)

	var flint: ItemInstance = ItemDatabase.create_rune("flint")
	_held.hold(flint)
	# 皮甲佔 (2, 0)～(3, 2)，點它右下角那一格
	_grid.click_at(_cell_center(3, 2))
	check(
		"手上拿著符文點背包裡有空孔的物品會插入",
		armor.socketed_runes == _ids(["flint"])
	)
	check(
		"插入後手上的符文消失，也沒有跑進背包",
		not _held.is_holding() and not _inventory.has_item(flint) and _inventory.get_items().size() == 1
	)
	check("被插入的物品留在原位", _inventory.get_item_position(armor) == Vector2i(2, 0))

	_held.hold(ItemDatabase.create_rune("gale"))
	_grid.click_at(_cell_center(2, 0))
	check(
		"第二顆插進下一個孔",
		armor.socketed_runes == _ids(["flint", "gale"]) and not _held.is_holding()
	)

	_held.hold(ItemDatabase.create_rune("crag"))
	_grid.click_at(_cell_center(8, 1))
	check(
		"手上拿著符文點空格是一般的放下",
		not _held.is_holding() and _inventory.get_item_at(8, 1) != null and _inventory.get_item_at(8, 1).is_rune()
	)


func _test_grid_cannot_insert() -> void:
	_reset()
	var full: ItemInstance = _socketed("leather_cap", 1)
	full.insert_rune(ItemDatabase.create_rune("flint"))
	var plain: ItemInstance = ItemDatabase.create_item("leather_cap")
	_inventory.place(full, 0, 0)
	_inventory.place(plain, 4, 0)

	var gale: ItemInstance = ItemDatabase.create_rune("gale")
	_held.hold(gale)
	_grid.click_at(_cell_center(1, 1))
	check(
		"孔滿的物品不能插，照原本的規則互換",
		_held.item == full
		and full.socketed_runes == _ids(["flint"])
		and _inventory.get_item_at(1, 1) == gale
		and not _inventory.has_item(full)
	)

	_held.take()
	var crag: ItemInstance = ItemDatabase.create_rune("crag")
	_held.hold(crag)
	_grid.click_at(_cell_center(4, 0))
	check(
		"沒孔的物品不能插，照原本的規則互換",
		_held.item == plain and plain.socketed_runes.is_empty() and _inventory.get_item_at(4, 0) == crag
	)

	# 手上不是符文時，有空孔的物品也只是一般的互換
	_reset()
	var socketed: ItemInstance = _socketed("leather_cap", 2)
	_inventory.place(socketed, 0, 0)
	var other_cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	_held.hold(other_cap)
	_grid.click_at(_item_center(0, 0, other_cap))
	check(
		"手上不是符文時維持一般的互換",
		_held.item == socketed and socketed.socketed_runes.is_empty() and _inventory.has_item(other_cap)
	)

	# 符文壓到另一顆符文：互換
	_reset()
	var first: ItemInstance = ItemDatabase.create_rune("flint")
	var second: ItemInstance = ItemDatabase.create_rune("gale")
	_inventory.place(first, 5, 2)
	_held.hold(second)
	_grid.click_at(_cell_center(5, 2))
	check("符文點到另一顆符文是互換", _held.item == first and _inventory.get_item_at(5, 2) == second)


func _test_equipment_panel_does_not_insert() -> void:
	_reset()
	var sword: ItemInstance = _socketed("short_sword", 2)
	_equipment.equip(sword, "weapon")
	var flint: ItemInstance = ItemDatabase.create_rune("flint")
	_held.hold(flint)
	_equipment_panel.click_at(_equipment_panel.get_slot_center("weapon"))
	check(
		"裝備欄上的物品不能插：符文留在手上，裝備不變",
		_held.item == flint and _equipment.get_item("weapon") == sword and sword.socketed_runes.is_empty()
	)


# 預覽：手上的符文滑到可以插的物品上時，預覽記住的是那件物品；不能插時是一般的放置預覽
func _test_insert_preview() -> void:
	_reset()
	# 等版面排好，再把面板移到讓滑鼠位置落在格子的 (1, 1) 中央
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = _screen.get_node("Panel")
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	panel.position -= _grid.get_global_rect().position + Vector2(1.5, 1.5) * CELL - mouse_position
	await get_tree().process_frame
	var mouse_local: Vector2 = _grid.get_local_mouse_position()
	check("測試準備：滑鼠位置落在格子內", Rect2(Vector2.ZERO, _grid.size).has_point(mouse_local))

	# 皮甲佔 (1, 0)～(2, 2)，滑鼠在它上面
	var armor: ItemInstance = _socketed("leather_armor", 1)
	_inventory.place(armor, 1, 0)

	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	_held.hold(cap)
	check(
		"手上不是符文時是一般的放置預覽",
		_grid.get_preview_item() == cap and _grid.get_preview_insert_target() == null
	)
	_held.take()

	var flint: ItemInstance = ItemDatabase.create_rune("flint")
	_held.hold(flint)
	check(
		"手上的符文滑到有空孔的物品上，立刻顯示插入預覽",
		_grid.get_preview_item() == flint and _grid.get_preview_insert_target() == armor
	)

	_grid.click_at(mouse_local)
	check(
		"點擊後插入，預覽立刻消失",
		armor.socketed_runes == _ids(["flint"])
		and not _held.is_holding()
		and _grid.get_preview_item() == null
		and _grid.get_preview_insert_target() == null
	)
	# 讓重畫在物理幀之後、_process 之前發生，確認不會拿舊的預覽去畫
	await get_tree().physics_frame
	await get_tree().process_frame
	check("插入後滑鼠底下的物品就是被插入的那件", _grid.get_hovered_item() == armor)

	var gale: ItemInstance = ItemDatabase.create_rune("gale")
	_held.hold(gale)
	check(
		"孔滿之後再拿符文滑上去，變回一般的放置預覽",
		_grid.get_preview_item() == gale and _grid.get_preview_insert_target() == null
	)

	_screen.close()
	check("關閉背包後沒有插入預覽", _grid.get_preview_insert_target() == null)
	await get_tree().physics_frame
	await get_tree().process_frame


# 每組介面測試都用全新的背包、畫面與手上的物品
func _reset() -> void:
	_free_screen()
	_inventory = Inventory.new()
	_equipment = Equipment.new()
	_held_layer = HELD_ITEM_SCENE.instantiate() as CanvasLayer
	add_child(_held_layer)
	_held = _held_layer.get_node("HeldItem") as HeldItem
	_screen = SCREEN_SCENE.instantiate() as InventoryScreen
	add_child(_screen)
	_screen.setup(_inventory, _equipment, _held)
	_grid = _screen.get_grid()
	_equipment_panel = _screen.get_equipment_panel()
	_screen.open()


func _free_screen() -> void:
	if _screen == null:
		return
	remove_child(_screen)
	_screen.free()
	_screen = null
	remove_child(_held_layer)
	_held_layer.free()
	_held_layer = null


# 指定孔數的普通物品，還沒插任何符文
func _socketed(base_id: String, sockets: int) -> ItemInstance:
	var item: ItemInstance = ItemDatabase.create_item(base_id)
	item.sockets = sockets
	return item


# 物品的符文修正值是否與符文資料裡的那一組相同（數值以 float 比較）
func _same_modifiers(actual: Array[Dictionary], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in actual.size():
		var expected_modifier: Dictionary = expected[index]
		if (
			actual[index]["stat"] != expected_modifier["stat"]
			or actual[index]["type"] != expected_modifier["type"]
			or not is_equal_approx(actual[index]["value"], float(expected_modifier["value"]))
		):
			return false
	return true


func _ids(ids: Array) -> Array[String]:
	var typed: Array[String] = []
	typed.assign(ids)
	return typed


# 某一格的中心點（格子的本地座標）
func _cell_center(x: int, y: int) -> Vector2:
	return Vector2(x + 0.5, y + 0.5) * CELL


# 物品左上角在 (x, y) 時，物品的中心點
func _item_center(x: int, y: int, item: ItemInstance) -> Vector2:
	return (Vector2(x, y) + Vector2(item.get_size()) * 0.5) * CELL


func _texts(lines: Array[Dictionary]) -> Array[String]:
	var texts: Array[String] = []
	for line: Dictionary in lines:
		texts.append(line["text"])
	return texts


func _join(lines: Array[Dictionary]) -> String:
	return " / ".join(_texts(lines))
