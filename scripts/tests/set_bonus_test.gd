extends TestBase

# 套裝件數加成的測試：SetBonusCalculator 的計算，以及玩家穿脫裝備時屬性元件的來源與最終屬性。
# 每一步都拿「基礎值 + 身上每件物品自己的修正值 + 應該生效的套裝加成」交給 StatSystem 算出預期值，
# 再和玩家實際的全部屬性比對，所以多了或少了任何一條加成都會被抓到。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const MISTWOOD: String = "mistwood"
const STARCHASE: String = "starchase"
const MISTWOOD_SOURCE: String = "set_mistwood"
const STARCHASE_SOURCE: String = "set_starchase"

# 霧林獵裝 2 件：+15 生命
const MISTWOOD_2: Array[Dictionary] = [
	{"stat": "life", "value": 15.0, "type": "flat"},
]
# 霧林獵裝 3 件：+25% 防禦、+5% 移動速度
const MISTWOOD_3: Array[Dictionary] = [
	{"stat": "defense", "value": 25.0, "type": "percent"},
	{"stat": "move_speed", "value": 5.0, "type": "percent"},
]
# 逐星行裝 2 件：+10% 最小傷害、+10% 最大傷害、+5% 移動速度
const STARCHASE_2: Array[Dictionary] = [
	{"stat": "damage_min", "value": 10.0, "type": "percent"},
	{"stat": "damage_max", "value": 10.0, "type": "percent"},
	{"stat": "move_speed", "value": 5.0, "type": "percent"},
]
# 單件的件數詞綴（set_items.json 的 set_bonuses），那一件自己穿在身上、該套件數達到門檻才生效：
# 霧林護手 2 件：+5% 攻擊速度
const GRIPS_2: Array[Dictionary] = [
	{"stat": "attack_speed", "value": 5.0, "type": "percent"},
]
# 霧林獵衣 3 件：+10% 生命
const JERKIN_3: Array[Dictionary] = [
	{"stat": "life", "value": 10.0, "type": "percent"},
]
# 逐星之履 2 件：+4 防禦
const TREADS_2: Array[Dictionary] = [
	{"stat": "defense", "value": 4.0, "type": "flat"},
]

var _player: Player = null
var _stats: StatsComponent = null
var _equipment: Equipment = null
# 沒穿任何裝備時的屬性：屬性名稱 -> 數值
var _base_stats: Dictionary = {}


func _get_test_name() -> String:
	return "套裝件數加成"


func _run_tests() -> void:
	_test_data_matches()
	_test_calculator()
	_test_one_piece()
	_test_two_pieces()
	_test_three_pieces()
	_test_three_to_two_to_one()
	_test_inventory_not_counted()
	_test_both_sets()
	_test_replace_with_non_set()
	_test_starting_equipment()
	_free_player()


# 這份測試把加成的內容寫成常數，先確認和 sets.json 一致
func _test_data_matches() -> void:
	check(
		"測試裡的加成內容和 sets.json 一致",
		SetBonusCalculator.get_bonus_modifiers(MISTWOOD, 2) == MISTWOOD_2
		and SetBonusCalculator.get_bonus_modifiers(MISTWOOD, 3) == MISTWOOD_2 + MISTWOOD_3
		and SetBonusCalculator.get_bonus_modifiers(STARCHASE, 2) == STARCHASE_2
		and SetBonusCalculator.get_item_bonus_modifiers("mistwood_grips", 2) == GRIPS_2
		and SetBonusCalculator.get_item_bonus_modifiers("mistwood_jerkin", 3) == JERKIN_3
		and SetBonusCalculator.get_item_bonus_modifiers("starchase_treads", 2) == TREADS_2,
		"霧林 3 件：%s" % str(SetBonusCalculator.get_bonus_modifiers(MISTWOOD, 3))
	)


func _test_calculator() -> void:
	check(
		"件數不到門檻時沒有任何修正值",
		SetBonusCalculator.get_bonus_modifiers(MISTWOOD, 0).is_empty()
		and SetBonusCalculator.get_bonus_modifiers(MISTWOOD, 1).is_empty()
		and SetBonusCalculator.get_bonus_modifiers(STARCHASE, 1).is_empty()
	)
	check(
		"件數超過最高門檻時和穿滿一樣，不存在的套裝沒有修正值",
		SetBonusCalculator.get_bonus_modifiers(MISTWOOD, 9) == MISTWOOD_2 + MISTWOOD_3
		and SetBonusCalculator.get_bonus_modifiers("not_exist", 3).is_empty()
	)

	var equipment: Equipment = Equipment.new()
	check(
		"空的裝備欄沒有任何套裝",
		SetBonusCalculator.calculate(equipment).is_empty()
		and SetBonusCalculator.count_pieces(equipment).is_empty()
		and SetBonusCalculator.calculate(null).is_empty()
	)

	equipment.equip(_set_item("mistwood_hood"), "helm")
	equipment.equip(_set_item("mistwood_jerkin"), "armor")
	equipment.equip(_set_item("starchase_blade"), "weapon")
	equipment.equip(ItemDatabase.create_item("leather_boots"), "boots")
	var result: Dictionary = SetBonusCalculator.calculate(equipment)
	check(
		"輸出每一套的件數：霧林 2 件、逐星 1 件，非套裝物品不算",
		SetBonusCalculator.count_pieces(equipment) == {MISTWOOD: 2, STARCHASE: 1}
		and result.size() == 2
		and result[MISTWOOD]["count"] == 2
		and result[STARCHASE]["count"] == 1,
		str(result)
	)
	check(
		"輸出每一套生效的修正值：霧林是 2 件加成，逐星只有 1 件所以是空的",
		result[MISTWOOD]["modifiers"] == MISTWOOD_2 and result[STARCHASE]["modifiers"].is_empty(),
		str(result)
	)

	# 同一個 set_item_id 只算一次
	var duplicates: Array[ItemInstance] = [
		_set_item("mistwood_hood"), _set_item("mistwood_hood"), _set_item("mistwood_hood"),
	]
	check(
		"同一件套裝物品有三件時只算 1 件",
		SetBonusCalculator.count_pieces_in(duplicates) == {MISTWOOD: 1}
	)
	duplicates.append(_set_item("mistwood_grips"))
	duplicates.append(ItemDatabase.create_rune("flint"))
	duplicates.append(ItemDatabase.create_item("short_sword"))
	check(
		"再加一件不同的才是 2 件，符文與一般物品不算",
		SetBonusCalculator.count_pieces_in(duplicates) == {MISTWOOD: 2}
	)


func _test_one_piece() -> void:
	_reset_player()
	var hood: ItemInstance = _set_item("mistwood_hood")
	_equipment.equip(hood, "helm")
	check("只穿 1 件時屬性元件沒有套裝的來源", not _stats.has_source(MISTWOOD_SOURCE))
	_check_stats("只穿 1 件沒有加成，屬性只有那一件自己的數值", [hood], [])

	var blade: ItemInstance = _set_item("starchase_blade")
	_equipment.equip(blade, "weapon")
	check(
		"兩套各穿 1 件時兩套都沒有來源",
		not _stats.has_source(MISTWOOD_SOURCE) and not _stats.has_source(STARCHASE_SOURCE)
	)
	_check_stats("兩套各穿 1 件沒有加成", [hood, blade], [])


func _test_two_pieces() -> void:
	_reset_player()
	var hood: ItemInstance = _set_item("mistwood_hood")
	var grips: ItemInstance = _set_item("mistwood_grips")
	_equipment.equip(hood, "helm")
	_equipment.equip(grips, "gloves")
	check("穿 2 件時屬性元件多了 set_mistwood 這個來源", _stats.has_source(MISTWOOD_SOURCE))
	_check_stats("穿 2 件觸發 2 件加成", [hood, grips], MISTWOOD_2 + GRIPS_2)
	# 兜帽 +12 生命，2 件加成 +15 生命
	check(
		"穿 2 件時生命是基礎值 + 12 + 15",
		is_equal_approx(_stats.get_stat("life"), _base_stats["life"] + 12.0 + 15.0),
		str(_stats.get_stat("life"))
	)
	check(
		"穿 2 件時還沒有 3 件加成的移動速度",
		is_equal_approx(_stats.get_stat("move_speed"), _base_stats["move_speed"])
	)


func _test_three_pieces() -> void:
	_reset_player()
	var pieces: Array[ItemInstance] = _equip_mistwood()
	check("穿 3 件時有 set_mistwood 這個來源", _stats.has_source(MISTWOOD_SOURCE))
	_check_stats(
		"A 套穿 3 件時 2 件和 3 件加成都生效",
		pieces,
		MISTWOOD_2 + MISTWOOD_3 + GRIPS_2 + JERKIN_3
	)

	# 防禦：兜帽 4 + 3、獵衣 10、護手 3，共 20；百分比是獵衣的 20% 加上 3 件加成的 25%
	var flat_defense: float = _base_stats["defense"] + 4.0 + 3.0 + 10.0 + 3.0
	check(
		"穿 3 件時防禦的百分比是單件的 20% 加上 3 件加成的 25%",
		is_equal_approx(_stats.get_stat("defense"), flat_defense * 1.45),
		"實際 %s，預期 %s" % [_stats.get_stat("defense"), flat_defense * 1.45]
	)
	# 生命：兜帽 +12、獵衣的 3 點體力 +9、2 件加成 +15，再乘上獵衣 3 件詞綴的 +10%
	check(
		"穿 3 件時 2 件加成的生命還在，獵衣的 3 件詞綴再 +10%",
		is_equal_approx(_stats.get_stat("life"), (_base_stats["life"] + 12.0 + 9.0 + 15.0) * 1.1),
		str(_stats.get_stat("life"))
	)
	check(
		"穿 3 件時移動速度 +5%",
		is_equal_approx(_stats.get_stat("move_speed"), _base_stats["move_speed"] * 1.05)
	)


func _test_three_to_two_to_one() -> void:
	_reset_player()
	var pieces: Array[ItemInstance] = _equip_mistwood()
	var hood: ItemInstance = pieces[0]
	var jerkin: ItemInstance = pieces[1]

	_equipment.unequip("gloves")
	check("從 3 件脫成 2 件時來源還在", _stats.has_source(MISTWOOD_SOURCE))
	_check_stats("從 3 件脫成 2 件時只剩 2 件加成", [hood, jerkin], MISTWOOD_2)
	check(
		"脫成 2 件後 3 件加成的移動速度消失",
		is_equal_approx(_stats.get_stat("move_speed"), _base_stats["move_speed"])
	)

	_equipment.unequip("armor")
	check("脫到 1 件時來源被移除", not _stats.has_source(MISTWOOD_SOURCE))
	_check_stats("脫到 1 件時套裝加成完全消失，屬性回到只有單件數值", [hood], [])

	_equipment.unequip("helm")
	_check_stats("全部脫下後屬性回到基礎值", [], [])

	# 再穿回去要重新生效
	_equipment.equip(hood, "helm")
	_equipment.equip(jerkin, "armor")
	_check_stats("脫下後再穿回 2 件，2 件加成重新生效", [hood, jerkin], MISTWOOD_2)


func _test_inventory_not_counted() -> void:
	_reset_player()
	var hood: ItemInstance = _set_item("mistwood_hood")
	var jerkin: ItemInstance = _set_item("mistwood_jerkin")
	var grips: ItemInstance = _set_item("mistwood_grips")
	_equipment.equip(hood, "helm")
	_player.get_inventory().add_item_auto(jerkin)
	_player.get_inventory().add_item_auto(grips)
	check(
		"身上 1 件、背包 2 件時，件數是 1",
		SetBonusCalculator.count_pieces(_equipment) == {MISTWOOD: 1}
	)
	check("背包裡的套裝物品不計入件數，沒有套裝的來源", not _stats.has_source(MISTWOOD_SOURCE))
	_check_stats("背包裡有另外兩件時，屬性仍然只有身上那一件", [hood], [])

	# 從背包拿出來穿上才算
	_player.get_inventory().remove(jerkin)
	_equipment.equip(jerkin, "armor")
	_check_stats("把背包裡的一件穿上後才觸發 2 件加成", [hood, jerkin], MISTWOOD_2)

	# 脫下放回背包就不算
	_player.get_inventory().add_item_auto(_equipment.unequip("armor"))
	_check_stats("脫下放回背包後加成消失", [hood], [])


func _test_both_sets() -> void:
	_reset_player()
	var pieces: Array[ItemInstance] = _equip_mistwood()
	var blade: ItemInstance = _set_item("starchase_blade")
	var treads: ItemInstance = _set_item("starchase_treads")
	_equipment.equip(blade, "weapon")
	_equipment.equip(treads, "boots")
	pieces.append(blade)
	pieces.append(treads)

	check(
		"兩套同時穿滿時件數是 3 件與 2 件，兩個來源都在",
		SetBonusCalculator.count_pieces(_equipment) == {MISTWOOD: 3, STARCHASE: 2}
		and _stats.has_source(MISTWOOD_SOURCE)
		and _stats.has_source(STARCHASE_SOURCE)
	)
	_check_stats(
		"兩套同時穿滿時各自正確生效",
		pieces,
		MISTWOOD_2 + MISTWOOD_3 + GRIPS_2 + JERKIN_3 + STARCHASE_2 + TREADS_2
	)

	# 移動速度：靴子 10% + 霧林 3 件 5% + 逐星 2 件 5%
	check(
		"兩套同時穿滿時移動速度是 +20%",
		is_equal_approx(_stats.get_stat("move_speed"), _base_stats["move_speed"] * 1.2),
		str(_stats.get_stat("move_speed"))
	)
	# 最大傷害：(基礎 + 短劍 5 + 逐星之刃 4) ×（1 + 逐星 2 件 10% + 護手的 2 點力量 2%）
	check(
		"兩套同時穿滿時最大傷害的百分比是逐星 2 件的 10% 加上力量的 2%",
		is_equal_approx(_stats.get_stat("damage_max"), (_base_stats["damage_max"] + 5.0 + 4.0) * 1.12),
		str(_stats.get_stat("damage_max"))
	)

	# 脫掉其中一套的一件，不影響另一套
	_equipment.unequip("boots")
	pieces.erase(treads)
	check(
		"逐星脫成 1 件後只有逐星的來源被移除",
		_stats.has_source(MISTWOOD_SOURCE) and not _stats.has_source(STARCHASE_SOURCE)
	)
	_check_stats(
		"逐星脫成 1 件後，霧林的 3 件加成不受影響",
		pieces,
		MISTWOOD_2 + MISTWOOD_3 + GRIPS_2 + JERKIN_3
	)


func _test_replace_with_non_set() -> void:
	_reset_player()
	var blade: ItemInstance = _set_item("starchase_blade")
	var treads: ItemInstance = _set_item("starchase_treads")
	_equipment.equip(blade, "weapon")
	_equipment.equip(treads, "boots")
	_check_stats("測試準備：逐星 2 件加成生效", [blade, treads], STARCHASE_2 + TREADS_2)

	# 直接換上一把普通短劍（互換，不經過脫下）
	var plain_sword: ItemInstance = ItemDatabase.create_item("short_sword")
	var result: Dictionary = _equipment.equip(plain_sword, "weapon")
	check("換上普通短劍時，原本的套裝武器被換下來", result["swapped_item"] == blade)
	check("換成非套裝物品後套裝的來源被移除", not _stats.has_source(STARCHASE_SOURCE))
	_check_stats("換成非套裝物品後加成消失，不殘留數值", [plain_sword, treads], [])

	# 再換回來要重新生效
	_equipment.equip(blade, "weapon")
	_check_stats("換回套裝武器後 2 件加成重新生效", [blade, treads], STARCHASE_2 + TREADS_2)

	# 霧林 3 件時把一件換成稀有物品
	_reset_player()
	var pieces: Array[ItemInstance] = _equip_mistwood()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261014
	var rare_gloves: ItemInstance = ItemGenerator.generate("leather_gloves", ItemInstance.QUALITY_RARE, rng)
	_equipment.equip(rare_gloves, "gloves")
	_check_stats(
		"霧林 3 件時把手套換成稀有手套，只剩 2 件加成",
		[pieces[0], pieces[1], rare_gloves],
		MISTWOOD_2
	)


# 開場就穿著套裝物品時，加成也要算進去
func _test_starting_equipment() -> void:
	_free_player()
	_player = PLAYER_SCENE.instantiate() as Player
	_player.starting_equipment.clear()
	add_child(_player)
	_stats = _player.get_stats()
	_equipment = _player.get_equipment()

	# 存檔還原出來的物品是新的物件，也要能算件數
	var blade: ItemInstance = ItemInstance.from_dict(_set_item("starchase_blade").to_dict())
	var treads: ItemInstance = ItemInstance.from_dict(_set_item("starchase_treads").to_dict())
	_equipment.equip(blade, "weapon")
	_equipment.equip(treads, "boots")
	_check_stats("存檔還原出來的套裝物品穿上後，2 件加成一樣生效", [blade, treads], STARCHASE_2 + TREADS_2)


# 沒有起始裝備、背包是空的全新玩家，並記下沒穿裝備時的屬性
func _reset_player() -> void:
	_free_player()
	_player = PLAYER_SCENE.instantiate() as Player
	_player.starting_equipment.clear()
	add_child(_player)
	_stats = _player.get_stats()
	_equipment = _player.get_equipment()
	_base_stats.clear()
	for stat_name: String in StatSystem.STAT_NAMES:
		_base_stats[stat_name] = _stats.get_stat(stat_name)


func _free_player() -> void:
	if _player == null:
		return
	remove_child(_player)
	_player.free()
	_player = null


func _set_item(set_item_id: String) -> ItemInstance:
	return ItemDatabase.create_set_item(set_item_id)


# 穿上霧林獵裝三件，回傳 [兜帽, 獵衣, 護手]
func _equip_mistwood() -> Array[ItemInstance]:
	var pieces: Array[ItemInstance] = [
		_set_item("mistwood_hood"), _set_item("mistwood_jerkin"), _set_item("mistwood_grips"),
	]
	_equipment.equip(pieces[0], "helm")
	_equipment.equip(pieces[1], "armor")
	_equipment.equip(pieces[2], "gloves")
	return pieces


# 玩家的全部屬性是否等於「基礎值 + items 每件自己的修正值 + bonus_modifiers」
func _check_stats(title: String, items: Array, bonus_modifiers: Array) -> void:
	var modifiers: Array = []
	for item: ItemInstance in items:
		modifiers.append_array(item.get_modifiers())
	modifiers.append_array(bonus_modifiers)
	var expected: Dictionary = StatSystem.calculate(_base_stats, modifiers)

	var mismatches: Array[String] = []
	for stat_name: String in StatSystem.STAT_NAMES:
		if not is_equal_approx(_stats.get_stat(stat_name), expected[stat_name]):
			mismatches.append(
				"%s 實際 %s、預期 %s" % [stat_name, _stats.get_stat(stat_name), expected[stat_name]]
			)
	check(title, mismatches.is_empty(), "；".join(mismatches))
