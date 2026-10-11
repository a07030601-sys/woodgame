extends TestBase

# 單件的件數詞綴與套裝說明框的測試：
# - set_items.json 的 set_bonuses 資料
# - 單件詞綴何時生效（SetBonusCalculator 與玩家的屬性）
# - 說明框資料（ItemTooltip.build_lines）裡每一行的文字與「是否生效」
# - 裝備變動時，正在顯示的說明框立刻更新
# 說明框實際畫出來的顏色與排版，要在編輯器裡確認。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const SCREEN_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const HELD_ITEM_SCENE: PackedScene = preload("res://scenes/ui/held_item.tscn")
const CELL: float = InventoryGrid.CELL_SIZE
const GREEN: Color = ItemInstance.COLOR_SET
const GRAY: Color = ItemTooltip.SET_INACTIVE_COLOR
# 有單件件數詞綴的套裝物品 -> 門檻，新增或移除時要一起更新
const EXPECTED_ITEM_BONUS_THRESHOLDS: Dictionary = {
	"mistwood_jerkin": [3],
	"mistwood_grips": [2],
	"starchase_treads": [2],
}

var _player: Player = null
var _stats: StatsComponent = null
var _equipment: Equipment = null


func _get_test_name() -> String:
	return "單件件數詞綴與套裝說明框"


func _run_tests() -> void:
	_test_data()
	_test_item_bonus_thresholds()
	_test_item_bonus_stats()
	_test_item_bonus_in_inventory()
	_test_lines_nothing_worn()
	_test_lines_partial()
	_test_lines_full_set()
	_test_lines_item_bonus_needs_worn()
	_test_lines_other_set()
	_free_player()
	await _test_tooltip_updates_on_equipment_change()


func _test_data() -> void:
	var found: Dictionary = {}
	var problems: Array[String] = []
	for set_item_id: String in ItemDatabase.get_set_item_ids():
		var set_item: Dictionary = ItemDatabase.get_set_item(set_item_id)
		if not set_item.has("set_bonuses"):
			continue
		var bonuses: Dictionary = set_item["set_bonuses"]
		var set_size: int = ItemDatabase.get_set(set_item["set_id"])["items"].size()
		found[set_item_id] = SetBonusCalculator.get_thresholds(bonuses)
		for threshold: int in SetBonusCalculator.get_thresholds(bonuses):
			if threshold < 2 or threshold > set_size:
				problems.append("%s 的門檻 %d" % [set_item_id, threshold])
			if SetBonusCalculator.get_threshold_modifiers(bonuses, threshold).is_empty():
				problems.append("%s 的 %d 件沒有修正值" % [set_item_id, threshold])
			for modifier: Dictionary in SetBonusCalculator.get_threshold_modifiers(bonuses, threshold):
				if not StatSystem.STAT_NAMES.has(modifier["stat"]):
					problems.append("%s 用了不認得的屬性 %s" % [set_item_id, modifier["stat"]])

	var expected: Dictionary = {}
	for set_item_id: String in EXPECTED_ITEM_BONUS_THRESHOLDS:
		var thresholds: Array[int] = []
		thresholds.assign(EXPECTED_ITEM_BONUS_THRESHOLDS[set_item_id])
		expected[set_item_id] = thresholds
	check("有單件件數詞綴的是獵衣（3 件）、護手（2 件）、逐星之履（2 件）", found == expected, str(found))
	check("單件詞綴的門檻在 2 到該套件數之間，修正值都合格", problems.is_empty(), "；".join(problems))

	# 兩套各有 1～2 件帶詞綴
	var per_set: Dictionary = {}
	for set_item_id: String in found:
		var set_id: String = ItemDatabase.get_set_item(set_item_id)["set_id"]
		per_set[set_id] = int(per_set.get(set_id, 0)) + 1
	check(
		"兩套各有 1～2 件帶單件詞綴",
		per_set.size() == ItemDatabase.get_set_count()
		and per_set.values().min() >= 1
		and per_set.values().max() <= 2,
		str(per_set)
	)


func _test_item_bonus_thresholds() -> void:
	check(
		"護手的詞綴：1 件時沒有，2 件與 3 件時是 +5% 攻擊速度",
		SetBonusCalculator.get_item_bonus_modifiers("mistwood_grips", 1).is_empty()
		and SetBonusCalculator.get_item_bonus_modifiers("mistwood_grips", 2)
		== [{"stat": "attack_speed", "value": 5.0, "type": "percent"}]
		and SetBonusCalculator.get_item_bonus_modifiers("mistwood_grips", 3).size() == 1
	)
	check(
		"獵衣的詞綴：2 件時沒有，3 件時是 +10% 生命",
		SetBonusCalculator.get_item_bonus_modifiers("mistwood_jerkin", 2).is_empty()
		and SetBonusCalculator.get_item_bonus_modifiers("mistwood_jerkin", 3)
		== [{"stat": "life", "value": 10.0, "type": "percent"}]
	)
	check(
		"沒有 set_bonuses 的套裝物品、不存在的套裝物品都沒有詞綴",
		SetBonusCalculator.get_item_bonus_modifiers("mistwood_hood", 3).is_empty()
		and SetBonusCalculator.get_item_bonus_modifiers("not_exist", 3).is_empty()
	)

	# calculate 把單件詞綴併在同一套的修正值清單裡，接在套裝的件數加成後面
	var equipment: Equipment = Equipment.new()
	equipment.equip(_set_item("mistwood_hood"), "helm")
	equipment.equip(_set_item("mistwood_grips"), "gloves")
	var expected: Array[Dictionary] = [
		{"stat": "life", "value": 15.0, "type": "flat"},
		{"stat": "attack_speed", "value": 5.0, "type": "percent"},
	]
	check(
		"calculate 的結果同時有套裝 2 件加成與護手的 2 件詞綴",
		SetBonusCalculator.calculate(equipment)["mistwood"]["modifiers"] == expected,
		str(SetBonusCalculator.calculate(equipment))
	)


func _test_item_bonus_stats() -> void:
	_reset_player()
	var base_attack_speed: float = _stats.get_stat("attack_speed")
	var base_life: float = _stats.get_stat("life")
	var base_defense: float = _stats.get_stat("defense")

	# 護手本身 +8% 攻擊速度，2 件詞綴再 +5%
	var grips: ItemInstance = _set_item("mistwood_grips")
	_equipment.equip(grips, "gloves")
	check(
		"只穿護手 1 件，件數不足，單件詞綴不生效",
		is_equal_approx(_stats.get_stat("attack_speed"), base_attack_speed * 1.08)
		and not _stats.has_source("set_mistwood"),
		str(_stats.get_stat("attack_speed"))
	)

	var hood: ItemInstance = _set_item("mistwood_hood")
	_equipment.equip(hood, "helm")
	check(
		"再穿上兜帽達到 2 件，護手的詞綴生效",
		is_equal_approx(_stats.get_stat("attack_speed"), base_attack_speed * 1.13),
		str(_stats.get_stat("attack_speed"))
	)

	# 獵衣的詞綴要 3 件。生命：兜帽 +12、獵衣 3 點體力 +9、套裝 2 件 +15
	_equipment.unequip("gloves")
	var jerkin: ItemInstance = _set_item("mistwood_jerkin")
	_equipment.equip(jerkin, "armor")
	check(
		"兜帽加獵衣是 2 件，獵衣的 3 件詞綴不生效",
		is_equal_approx(_stats.get_stat("life"), base_life + 12.0 + 9.0 + 15.0)
		and is_equal_approx(_stats.get_stat("attack_speed"), base_attack_speed),
		str(_stats.get_stat("life"))
	)
	_equipment.equip(grips, "gloves")
	check(
		"穿滿 3 件後獵衣的詞綴生效，生命再 +10%",
		is_equal_approx(_stats.get_stat("life"), (base_life + 12.0 + 9.0 + 15.0) * 1.1),
		str(_stats.get_stat("life"))
	)
	_equipment.unequip("helm")
	check(
		"脫回 2 件後獵衣的詞綴消失，護手的詞綴還在",
		is_equal_approx(_stats.get_stat("life"), base_life + 9.0 + 15.0)
		and is_equal_approx(_stats.get_stat("attack_speed"), base_attack_speed * 1.13),
		"生命 %s、攻速 %s" % [_stats.get_stat("life"), _stats.get_stat("attack_speed")]
	)

	# 逐星之履：皮靴防禦 3（底材最大值）、本身 +2，2 件詞綴再 +4
	_reset_player()
	var treads: ItemInstance = _set_item("starchase_treads")
	_equipment.equip(treads, "boots")
	check(
		"只穿逐星之履時防禦沒有詞綴的 +4",
		is_equal_approx(_stats.get_stat("defense"), base_defense + 3.0 + 2.0),
		str(_stats.get_stat("defense"))
	)
	_equipment.equip(_set_item("starchase_blade"), "weapon")
	check(
		"再穿上逐星之刃達到 2 件，防禦多了詞綴的 +4",
		is_equal_approx(_stats.get_stat("defense"), base_defense + 3.0 + 2.0 + 4.0),
		str(_stats.get_stat("defense"))
	)
	_equipment.equip(ItemDatabase.create_item("short_sword"), "weapon")
	check(
		"武器換成普通短劍後詞綴消失",
		is_equal_approx(_stats.get_stat("defense"), base_defense + 3.0 + 2.0)
		and not _stats.has_source("set_starchase")
	)


func _test_item_bonus_in_inventory() -> void:
	_reset_player()
	var base_attack_speed: float = _stats.get_stat("attack_speed")
	var base_life: float = _stats.get_stat("life")

	# 兜帽與獵衣穿在身上（2 件），護手放在背包
	var grips: ItemInstance = _set_item("mistwood_grips")
	_equipment.equip(_set_item("mistwood_hood"), "helm")
	_equipment.equip(_set_item("mistwood_jerkin"), "armor")
	_player.get_inventory().add_item_auto(grips)
	check(
		"件數已達 2 件，但護手放在背包時它的詞綴不生效",
		is_equal_approx(_stats.get_stat("attack_speed"), base_attack_speed),
		str(_stats.get_stat("attack_speed"))
	)
	check(
		"護手在背包時件數仍是 2 件，獵衣的 3 件詞綴也不生效",
		SetBonusCalculator.count_pieces(_equipment) == {"mistwood": 2}
		and is_equal_approx(_stats.get_stat("life"), base_life + 12.0 + 9.0 + 15.0)
	)
	check(
		"護手在背包時，套裝的修正值清單裡只有套裝的 2 件加成",
		SetBonusCalculator.calculate(_equipment)["mistwood"]["modifiers"]
		== [{"stat": "life", "value": 15.0, "type": "flat"}]
	)

	_player.get_inventory().remove(grips)
	_equipment.equip(grips, "gloves")
	check(
		"從背包拿出來穿上後，護手自己的詞綴才生效",
		is_equal_approx(_stats.get_stat("attack_speed"), base_attack_speed * 1.13)
	)


# 什麼都沒穿（或沒有傳入 Equipment）時，每一行都是未生效
func _test_lines_nothing_worn() -> void:
	var grips: ItemInstance = _set_item("mistwood_grips")
	for equipment: Equipment in [null, Equipment.new()]:
		var label: String = "沒有傳入 Equipment" if equipment == null else "什麼都沒穿"
		var lines: Array[Dictionary] = ItemTooltip.build_lines(grips, equipment)
		var expected: Array[String] = [
			"霧林護手",
			"皮手套",
			"防禦：3",
			_mod("attack_speed", 8.0, "percent"),
			_mod("strength", 2.0, "flat"),
			_mod("attack_speed", 5.0, "percent") + " (2 件)",
			"",
			"霧林獵裝",
			"霧林兜帽",
			"霧林獵衣",
			"霧林護手",
			_mod("life", 15.0, "flat") + " (2 件)",
			_mod("defense", 25.0, "percent") + " (3 件)",
			_mod("move_speed", 5.0, "percent") + " (3 件)",
		]
		check("%s時護手的說明：每一行的文字與順序" % label, _texts(lines) == expected, _join(lines))
		check(
			"%s時：單件詞綴、三件成員、三條件數加成都是未生效" % label,
			_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [false]
			and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [false, false, false]
			and _states(lines, ItemTooltip.LINE_SET_BONUS) == [false, false, false],
			_describe(lines)
		)
		check("%s時：未生效的每一行都是灰色" % label, _colors_match_states(lines), _describe(lines))

	var hood_lines: Array[Dictionary] = ItemTooltip.build_lines(_set_item("mistwood_hood"), null)
	check(
		"沒有單件詞綴的兜帽，說明裡沒有單件詞綴那一行",
		_states(hood_lines, ItemTooltip.LINE_ITEM_BONUS).is_empty()
		and _texts(hood_lines).slice(0, 6)
		== ["霧林兜帽", "皮帽", "防禦：4", _mod("life", 12.0, "flat"), _mod("defense", 3.0, "flat"), ""],
		_join(hood_lines)
	)


# 兜帽與護手穿在身上（2 件）
func _test_lines_partial() -> void:
	var equipment: Equipment = Equipment.new()
	var hood: ItemInstance = _set_item("mistwood_hood")
	var grips: ItemInstance = _set_item("mistwood_grips")
	var jerkin: ItemInstance = _set_item("mistwood_jerkin")
	equipment.equip(hood, "helm")
	equipment.equip(grips, "gloves")

	# 穿在身上的護手
	var lines: Array[Dictionary] = ItemTooltip.build_lines(grips, equipment)
	check(
		"2 件時身上護手的單件詞綴生效，文字後面沒有「(2 件)」",
		_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [true]
		and _texts_of(lines, ItemTooltip.LINE_ITEM_BONUS) == [_mod("attack_speed", 5.0, "percent")],
		_describe(lines)
	)
	check(
		"2 件時成員清單：兜帽已穿、獵衣未穿、護手已穿",
		_texts_of(lines, ItemTooltip.LINE_SET_MEMBER) == ["霧林兜帽", "霧林獵衣", "霧林護手"]
		and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [true, false, true],
		_describe(lines)
	)
	check(
		"2 件時件數加成：2 件那條生效且沒有標件數，3 件那兩條未生效並標「(3 件)」",
		_states(lines, ItemTooltip.LINE_SET_BONUS) == [true, false, false]
		and _texts_of(lines, ItemTooltip.LINE_SET_BONUS)
		== [
			_mod("life", 15.0, "flat"),
			_mod("defense", 25.0, "percent") + " (3 件)",
			_mod("move_speed", 5.0, "percent") + " (3 件)",
		],
		_describe(lines)
	)
	check("2 件時生效的是綠色、未生效的是灰色", _colors_match_states(lines), _describe(lines))

	# 放在背包的獵衣：件數用身上的 Equipment 算，所以和上面看到的成員與件數加成一樣
	lines = ItemTooltip.build_lines(jerkin, equipment)
	check(
		"背包裡的獵衣：成員與件數加成的狀態和身上的物品看到的一樣",
		_states(lines, ItemTooltip.LINE_SET_MEMBER) == [true, false, true]
		and _states(lines, ItemTooltip.LINE_SET_BONUS) == [true, false, false],
		_describe(lines)
	)
	check(
		"背包裡的獵衣：它的 3 件詞綴未生效，標「(3 件)」",
		_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [false]
		and _texts_of(lines, ItemTooltip.LINE_ITEM_BONUS) == [_mod("life", 10.0, "percent") + " (3 件)"],
		_describe(lines)
	)

	# 沒有帶件數標記的那幾行（名稱、底材名、固定修正值）不會有 active
	var plain_line_has_state: bool = false
	for index: int in 5:
		if lines[index].has("active") or lines[index].has("kind"):
			plain_line_has_state = true
	check("名稱、底材名、防禦與固定修正值那幾行沒有生效狀態", not plain_line_has_state)


func _test_lines_full_set() -> void:
	var equipment: Equipment = Equipment.new()
	var hood: ItemInstance = _set_item("mistwood_hood")
	var jerkin: ItemInstance = _set_item("mistwood_jerkin")
	var grips: ItemInstance = _set_item("mistwood_grips")
	equipment.equip(hood, "helm")
	equipment.equip(jerkin, "armor")
	equipment.equip(grips, "gloves")

	var lines: Array[Dictionary] = ItemTooltip.build_lines(jerkin, equipment)
	var expected: Array[String] = [
		"霧林獵衣",
		"皮甲",
		"防禦：10",
		_mod("defense", 20.0, "percent"),
		_mod("vitality", 3.0, "flat"),
		_mod("life", 10.0, "percent"),
		"",
		"霧林獵裝",
		"霧林兜帽",
		"霧林獵衣",
		"霧林護手",
		_mod("life", 15.0, "flat"),
		_mod("defense", 25.0, "percent"),
		_mod("move_speed", 5.0, "percent"),
	]
	check("穿滿 3 件時獵衣的說明：每一行都沒有件數標記", _texts(lines) == expected, _join(lines))
	check(
		"穿滿 3 件時：單件詞綴、三件成員、三條件數加成全部生效",
		_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [true]
		and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [true, true, true]
		and _states(lines, ItemTooltip.LINE_SET_BONUS) == [true, true, true],
		_describe(lines)
	)
	check("穿滿 3 件時帶狀態的每一行都是綠色", _colors_match_states(lines), _describe(lines))
	check(
		"名稱是綠色、底材名與空行不是套裝的顏色、套裝名稱是綠色",
		lines[0]["color"] == GREEN
		and lines[1]["color"] == ItemTooltip.BASE_NAME_COLOR
		and lines[6]["text"] == ""
		and lines[7]["color"] == GREEN
		and lines[7]["kind"] == ItemTooltip.LINE_SET_NAME
	)
	check(
		"固定修正值不受件數影響，一直是一般修正值的顏色",
		lines[3]["color"] == ItemTooltip.AFFIX_COLOR and lines[4]["color"] == ItemTooltip.AFFIX_COLOR
	)

	# 脫掉一件後重新產生，狀態跟著變
	equipment.unequip("helm")
	lines = ItemTooltip.build_lines(jerkin, equipment)
	check(
		"脫成 2 件後重新產生：獵衣的 3 件詞綴與 3 件加成變回未生效",
		_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [false]
		and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [false, true, true]
		and _states(lines, ItemTooltip.LINE_SET_BONUS) == [true, false, false],
		_describe(lines)
	)


# 單件詞綴要「這一件自己」穿在身上才算生效
func _test_lines_item_bonus_needs_worn() -> void:
	var equipment: Equipment = Equipment.new()
	equipment.equip(_set_item("mistwood_hood"), "helm")
	equipment.equip(_set_item("mistwood_jerkin"), "armor")

	# 件數已經是 2，但護手在背包
	var grips_in_bag: ItemInstance = _set_item("mistwood_grips")
	var lines: Array[Dictionary] = ItemTooltip.build_lines(grips_in_bag, equipment)
	check(
		"件數已達 2 件但護手沒穿：它的單件詞綴未生效並標「(2 件)」",
		_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [false]
		and _texts_of(lines, ItemTooltip.LINE_ITEM_BONUS) == [_mod("attack_speed", 5.0, "percent") + " (2 件)"],
		_describe(lines)
	)
	check(
		"同一份說明裡，套裝的 2 件加成是生效的",
		_states(lines, ItemTooltip.LINE_SET_BONUS) == [true, false, false]
		and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [true, true, false],
		_describe(lines)
	)

	# 身上穿著一件護手，背包裡還有另一件一樣的
	var worn_grips: ItemInstance = _set_item("mistwood_grips")
	equipment.equip(worn_grips, "gloves")
	check(
		"身上那件護手的單件詞綴生效",
		_states(ItemTooltip.build_lines(worn_grips, equipment), ItemTooltip.LINE_ITEM_BONUS) == [true]
	)
	lines = ItemTooltip.build_lines(grips_in_bag, equipment)
	check(
		"背包裡另一件一樣的護手，單件詞綴未生效；成員清單裡護手是已穿上",
		_states(lines, ItemTooltip.LINE_ITEM_BONUS) == [false]
		and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [true, true, true],
		_describe(lines)
	)


# 兩套互不影響
func _test_lines_other_set() -> void:
	var equipment: Equipment = Equipment.new()
	var blade: ItemInstance = _set_item("starchase_blade")
	var treads: ItemInstance = _set_item("starchase_treads")
	equipment.equip(_set_item("mistwood_hood"), "helm")
	equipment.equip(_set_item("mistwood_jerkin"), "armor")
	equipment.equip(_set_item("mistwood_grips"), "gloves")
	equipment.equip(treads, "boots")

	var lines: Array[Dictionary] = ItemTooltip.build_lines(treads, equipment)
	check(
		"霧林穿滿、逐星只穿靴子：逐星之履的說明裡只有靴子已穿，加成都未生效",
		_texts_of(lines, ItemTooltip.LINE_SET_MEMBER) == ["逐星之刃", "逐星之履"]
		and _states(lines, ItemTooltip.LINE_SET_MEMBER) == [false, true]
		and _states(lines, ItemTooltip.LINE_ITEM_BONUS) == [false]
		and _states(lines, ItemTooltip.LINE_SET_BONUS) == [false, false, false],
		_describe(lines)
	)

	equipment.equip(blade, "weapon")
	lines = ItemTooltip.build_lines(treads, equipment)
	check(
		"逐星穿滿後：靴子的 2 件詞綴與三條 2 件加成全部生效",
		_states(lines, ItemTooltip.LINE_SET_MEMBER) == [true, true]
		and _states(lines, ItemTooltip.LINE_ITEM_BONUS) == [true]
		and _states(lines, ItemTooltip.LINE_SET_BONUS) == [true, true, true]
		and _texts_of(lines, ItemTooltip.LINE_ITEM_BONUS) == [_mod("defense", 4.0, "flat")],
		_describe(lines)
	)

	# 非套裝物品不受 Equipment 影響
	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	check(
		"一般物品傳不傳 Equipment 的說明都一樣，沒有任何帶狀態的行",
		_texts(ItemTooltip.build_lines(sword, equipment)) == _texts(ItemTooltip.build_lines(sword))
		and _describe(ItemTooltip.build_lines(sword, equipment)).is_empty()
	)


# 裝備變動時，背包畫面上正在顯示的說明框要立刻換成新的內容，不等下一幀
func _test_tooltip_updates_on_equipment_change() -> void:
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
	var tooltip: ItemTooltip = screen.get_tooltip()

	# 等版面排好，再把面板移到讓滑鼠位置落在格子的 (1, 1) 中央
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = screen.get_node("Panel")
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	panel.position -= grid.get_global_rect().position + Vector2(1.5, 1.5) * CELL - mouse_position
	await get_tree().process_frame
	check(
		"測試準備：滑鼠位置落在格子內",
		Rect2(Vector2.ZERO, grid.size).has_point(grid.get_local_mouse_position())
	)

	check("滑鼠底下沒有物品時，說明框沒有內容", tooltip.get_lines().is_empty() and not tooltip.visible)

	# 護手佔 (1, 1)～(2, 2)，放在滑鼠底下
	var grips: ItemInstance = _set_item("mistwood_grips")
	inventory.place(grips, 1, 1)
	check(
		"滑鼠底下有護手時顯示它的說明，一開始成員都未穿上",
		tooltip.visible
		and grid.get_hovered_item() == grips
		and _states(tooltip.get_lines(), ItemTooltip.LINE_SET_MEMBER) == [false, false, false],
		_describe(tooltip.get_lines())
	)

	var hood: ItemInstance = _set_item("mistwood_hood")
	equipment.equip(hood, "helm")
	check(
		"穿上兜帽的那一刻，顯示中的說明框立刻把兜帽標成已穿上",
		_states(tooltip.get_lines(), ItemTooltip.LINE_SET_MEMBER) == [true, false, false]
		and _states(tooltip.get_lines(), ItemTooltip.LINE_SET_BONUS) == [false, false, false],
		_describe(tooltip.get_lines())
	)

	equipment.equip(_set_item("mistwood_jerkin"), "armor")
	check(
		"再穿上獵衣，說明框立刻顯示 2 件加成生效；背包裡的護手自己的詞綴仍未生效",
		_states(tooltip.get_lines(), ItemTooltip.LINE_SET_MEMBER) == [true, true, false]
		and _states(tooltip.get_lines(), ItemTooltip.LINE_SET_BONUS) == [true, false, false]
		and _states(tooltip.get_lines(), ItemTooltip.LINE_ITEM_BONUS) == [false],
		_describe(tooltip.get_lines())
	)
	check(
		"畫面上的每一行文字和資料一致",
		_label_texts(tooltip) == _texts(tooltip.get_lines()) and _label_colors_match(tooltip),
		str(_label_texts(tooltip))
	)

	equipment.unequip("helm")
	check(
		"脫下兜帽，說明框立刻變回只有獵衣已穿、沒有加成生效",
		_states(tooltip.get_lines(), ItemTooltip.LINE_SET_MEMBER) == [false, true, false]
		and _states(tooltip.get_lines(), ItemTooltip.LINE_SET_BONUS) == [false, false, false],
		_describe(tooltip.get_lines())
	)

	# 換成非套裝物品也要更新
	equipment.equip(ItemDatabase.create_item("leather_armor"), "armor")
	check(
		"身體護甲換成普通皮甲，說明框立刻變成全部未穿上",
		_states(tooltip.get_lines(), ItemTooltip.LINE_SET_MEMBER) == [false, false, false],
		_describe(tooltip.get_lines())
	)

	# 手上拿著物品時不顯示；裝備變動也不會讓它跑出來
	held.hold(ItemDatabase.create_rune("flint"))
	equipment.equip(hood, "helm")
	check("手上拿著物品時，裝備變動不會讓說明框跑出來", not tooltip.visible and tooltip.get_lines().is_empty())
	held.take()
	check(
		"放下手上的物品後說明框回來，內容是最新的件數",
		tooltip.visible and _states(tooltip.get_lines(), ItemTooltip.LINE_SET_MEMBER) == [true, false, false],
		_describe(tooltip.get_lines())
	)

	screen.close()
	equipment.unequip("helm")
	check("背包關閉後，裝備變動不會讓說明框跑出來", not tooltip.visible and tooltip.get_lines().is_empty())
	await get_tree().physics_frame
	await get_tree().process_frame

	remove_child(screen)
	screen.free()
	remove_child(held_layer)
	held_layer.free()


# 沒有起始裝備、背包是空的全新玩家
func _reset_player() -> void:
	_free_player()
	_player = PLAYER_SCENE.instantiate() as Player
	_player.starting_equipment.clear()
	add_child(_player)
	_stats = _player.get_stats()
	_equipment = _player.get_equipment()


func _free_player() -> void:
	if _player == null:
		return
	remove_child(_player)
	_player.free()
	_player = null


func _set_item(set_item_id: String) -> ItemInstance:
	return ItemDatabase.create_set_item(set_item_id)


# 修正值的顯示文字。屬性的中文名稱以 StatSystem 為準，這裡不寫死。
func _mod(stat: String, value: float, type: String) -> String:
	return StatSystem.format_modifier({"stat": stat, "value": value, "type": type})


func _texts(lines: Array[Dictionary]) -> Array[String]:
	var texts: Array[String] = []
	for line: Dictionary in lines:
		texts.append(line["text"])
	return texts


# 某一種行的文字，依出現順序
func _texts_of(lines: Array[Dictionary], kind: String) -> Array[String]:
	var texts: Array[String] = []
	for line: Dictionary in lines:
		if line.get("kind", "") == kind:
			texts.append(line["text"])
	return texts


# 某一種行的「是否生效」，依出現順序
func _states(lines: Array[Dictionary], kind: String) -> Array[bool]:
	var states: Array[bool] = []
	for line: Dictionary in lines:
		if line.get("kind", "") == kind:
			states.append(line["active"])
	return states


# 單件詞綴、成員、件數加成的每一行：生效的是綠色，未生效的是灰色
func _colors_match_states(lines: Array[Dictionary]) -> bool:
	for line: Dictionary in lines:
		var kind: String = line.get("kind", "")
		if kind.is_empty() or kind == ItemTooltip.LINE_SET_NAME:
			continue
		if line["color"] != (GREEN if line["active"] else GRAY):
			return false
	return true


# 帶狀態的每一行，失敗時印出來看
func _describe(lines: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for line: Dictionary in lines:
		if line.has("kind") and line["kind"] != ItemTooltip.LINE_SET_NAME:
			parts.append("%s=%s" % [line["text"], "生效" if line["active"] else "未生效"])
	return "、".join(parts)


func _join(lines: Array[Dictionary]) -> String:
	return " / ".join(_texts(lines))


# 說明框實際放在畫面上的每一個 Label 的文字
func _label_texts(tooltip: ItemTooltip) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in tooltip.get_node("Lines").get_children():
		if not child.is_queued_for_deletion():
			texts.append((child as Label).text)
	return texts


# 畫面上每一個 Label 的顏色是否等於資料裡那一行的顏色
func _label_colors_match(tooltip: ItemTooltip) -> bool:
	var labels: Array[Label] = []
	for child: Node in tooltip.get_node("Lines").get_children():
		if not child.is_queued_for_deletion():
			labels.append(child as Label)
	var lines: Array[Dictionary] = tooltip.get_lines()
	if labels.size() != lines.size():
		return false
	for index: int in labels.size():
		if labels[index].get_theme_color("font_color") != lines[index]["color"]:
			return false
	return true
