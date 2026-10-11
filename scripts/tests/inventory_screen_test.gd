extends TestBase

# 背包介面的測試：不靠真的滑鼠，直接呼叫格子的 click_at() 與畫面的 open() / close()。
# 畫面長相、游標跟隨、預覽顏色無法在這裡驗證，要在編輯器裡實際操作。

const SCREEN_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const HELD_ITEM_SCENE: PackedScene = preload("res://scenes/ui/held_item.tscn")
const TEST_SEED: int = 20261010
const CELL: float = InventoryGrid.CELL_SIZE

var _inventory: Inventory = null
var _equipment: Equipment = null
var _screen: InventoryScreen = null
var _grid: InventoryGrid = null
# 手上的物品是獨立於背包畫面的一層
var _held_layer: CanvasLayer = null
var _held: HeldItem = null
var _equipment_panel: EquipmentPanel = null


func _get_test_name() -> String:
	return "InventoryScreen"


func _run_tests() -> void:
	_test_pick_up_and_place()
	_test_swap()
	_test_close()
	_test_tooltip_lines()
	_test_equipment_panel()
	await _test_preview_matches_hand()


# 每組測試都用全新的背包、畫面與手上的物品
func _reset() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.free()
		remove_child(_held_layer)
		_held_layer.free()
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


func _test_pick_up_and_place() -> void:
	_reset()
	check("畫面一開始是關閉的", not _screen.is_open())
	_screen.open()
	check("開啟後 is_open 為 true", _screen.is_open())

	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	_inventory.place(cap, 0, 0)

	_grid.click_at(_cell_center(5, 2))
	check("點空格時什麼都不會發生", not _held.is_holding() and _inventory.has_item(cap))

	# 皮帽佔 (0, 0)～(1, 1)，點它右下角那一格
	_grid.click_at(_cell_center(1, 1))
	check(
		"點背包裡的物品會拿到手上並從背包移除",
		_held.item == cap and not _inventory.has_item(cap) and _inventory.get_items().is_empty()
	)
	check("手上的物品所在的那一層畫在背包畫面之上", _held_layer.layer > _screen.layer)

	# 物品中心對準游標，所以要放到左上角 (4, 1) 就點在物品中央
	_grid.click_at(_item_center(4, 1, cap))
	check(
		"手上有物品時點空位會放下",
		not _held.is_holding() and _inventory.get_item_position(cap) == Vector2i(4, 1)
	)

	_grid.click_at(_cell_center(4, 1))
	_grid.click_at(_item_center(9, 3, cap))
	check(
		"放到會超出範圍的位置時物品留在手上",
		_held.item == cap and not _inventory.has_item(cap)
	)


func _test_swap() -> void:
	_reset()
	_screen.open()
	var armor: ItemInstance = ItemDatabase.create_item("leather_armor")
	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	_inventory.place(armor, 0, 0)
	_inventory.place(cap, 6, 0)

	_held.hold(sword)
	_grid.click_at(_item_center(1, 0, sword))
	check(
		"壓到一件時互換，換出來的物品變成手上的物品",
		_held.item == armor
		and _inventory.get_item_position(sword) == Vector2i(1, 0)
		and not _inventory.has_item(armor)
	)

	# 短劍在 (1, 0)，再放一頂皮帽在 (2, 0)，手上的皮甲放到 (1, 0) 會同時壓到兩件
	var second_cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	_inventory.place(second_cap, 2, 0)
	_grid.click_at(_item_center(1, 0, armor))
	check(
		"壓到兩件時不放下，物品留在手上",
		_held.item == armor
		and not _inventory.has_item(armor)
		and _inventory.has_item(sword)
		and _inventory.has_item(second_cap)
	)


func _test_close() -> void:
	_reset()
	_screen.open()
	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	_held.hold(sword)

	_screen.close()
	check("手上有物品時也能關閉", not _screen.is_open())
	check(
		"關閉後物品留在手上，沒有放回背包",
		_held.item == sword and _held.visible and _inventory.get_items().is_empty()
	)
	check("關閉後不再阻止玩家的滑鼠操作", not _screen.is_blocking_world_input())

	_screen.open()
	check("重新開啟後手上還是同一件物品", _held.item == sword)

	_reset()
	_screen.open()
	for i: int in 10:
		_inventory.add_item_auto(ItemDatabase.create_item("leather_cap"))
	var extra: ItemInstance = ItemDatabase.create_item("leather_cap")
	_held.hold(extra)
	_screen.close()
	check(
		"背包滿的時候手上有物品也能關閉，物品留在手上",
		not _screen.is_open() and _held.item == extra and not _inventory.has_item(extra)
	)

	_reset()
	_screen.toggle()
	var was_open: bool = _screen.is_open()
	_screen.toggle()
	check("toggle 會開啟再關閉", was_open and not _screen.is_open())


func _test_tooltip_lines() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = TEST_SEED

	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	var lines: Array[Dictionary] = ItemTooltip.build_lines(sword)
	check(
		"普通武器的說明：名稱與傷害",
		lines.size() == 2
		and lines[0]["text"] == "短劍"
		and lines[0]["color"] == sword.get_quality_color()
		and lines[1]["text"] == "傷害：2–5",
		_join_lines(lines)
	)

	var armor: ItemInstance = ItemGenerator.generate("leather_armor", ItemInstance.QUALITY_MAGIC, rng)
	lines = ItemTooltip.build_lines(armor)
	var affix_modifiers: Array[Dictionary] = armor.get_affix_modifiers()
	check(
		"魔法防具的說明：名稱、防禦、每條詞綴修正值",
		lines.size() == 2 + affix_modifiers.size()
		and lines[0]["text"] == armor.get_display_name()
		and lines[0]["color"] == armor.get_quality_color()
		and lines[1]["text"] == "防禦：%d" % armor.defense
		and lines[2]["text"] == StatSystem.format_modifier(affix_modifiers[0]),
		_join_lines(lines)
	)

	var rare: ItemInstance = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_RARE, rng)
	lines = ItemTooltip.build_lines(rare)
	affix_modifiers = rare.get_affix_modifiers()
	var affix_lines_match: bool = lines.size() == 3 + affix_modifiers.size()
	if affix_lines_match:
		for index: int in affix_modifiers.size():
			if lines[3 + index]["text"] != StatSystem.format_modifier(affix_modifiers[index]):
				affix_lines_match = false
	check(
		"稀有物品的說明：名稱、底材名、傷害、每條詞綴修正值",
		affix_lines_match
		and lines[0]["text"] == rare.rare_name
		and lines[0]["color"] == rare.get_quality_color()
		and lines[1]["text"] == "短劍"
		and lines[2]["text"] == "傷害：2–5",
		_join_lines(lines)
	)


func _test_equipment_panel() -> void:
	_reset()
	_screen.open()
	var all_slots_have_rect: bool = true
	for slot: String in Equipment.SLOTS:
		if _equipment_panel.get_slot_at(_equipment_panel.get_slot_center(slot)) != slot:
			all_slots_have_rect = false
	check("五個裝備欄位都點得到", all_slots_have_rect)

	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	var axe: ItemInstance = ItemDatabase.create_item("hand_axe")
	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")

	_held.hold(cap)
	_equipment_panel.click_at(_equipment_panel.get_slot_center("weapon"))
	check(
		"欄位不符時不穿上，物品留在手上",
		_held.item == cap and _equipment.get_item("weapon") == null
	)

	_equipment_panel.click_at(_equipment_panel.get_slot_center("helm"))
	check("點相符的空欄位會穿上，手上變空", not _held.is_holding() and _equipment.get_item("helm") == cap)

	_held.hold(sword)
	_equipment_panel.click_at(_equipment_panel.get_slot_center("weapon"))
	_held.hold(axe)
	_equipment_panel.click_at(_equipment_panel.get_slot_center("weapon"))
	check(
		"欄位已有裝備時互換，換下的物品變成手上的物品",
		_held.item == sword and _equipment.get_item("weapon") == axe
	)

	_equipment_panel.click_at(Vector2(2.0, 2.0))
	check("點在欄位以外的地方不會有反應", _held.item == sword and _equipment.get_item("weapon") == axe)

	_screen.close()
	check(
		"手上有物品時關閉，物品不會收進背包也不會穿上",
		_held.item == sword and not _inventory.has_item(sword) and _equipment.get_item("weapon") == axe
	)
	_held.take()
	_screen.open()

	_equipment_panel.click_at(_equipment_panel.get_slot_center("weapon"))
	check(
		"手上沒有物品時點已穿上的裝備會脫下並拿到手上",
		_held.item == axe and _equipment.get_item("weapon") == null
	)
	check("裝備欄的預覽不會殘留舊物品", _equipment_panel.get_preview_item() == null or _equipment_panel.get_preview_item() == axe)

	_equipment_panel.click_at(_equipment_panel.get_slot_center("boots"))
	check("手上有物品時點不符的空欄位沒有反應", _held.item == axe and _equipment.get_item("boots") == null)


# 防止再發生：放下物品後，重畫若排在下一次 _process 之前，
# 格子曾拿著「手上還有物品」時的舊預覽去畫，結果對 null 呼叫 get_size() 而出錯。
# 預覽狀態必須在手上的物品或背包一變動時就立刻跟著更新。
func _test_preview_matches_hand() -> void:
	_reset()
	_screen.open()
	# 等版面排好，再把面板移到讓滑鼠位置落在格子的 (1, 1) 附近
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Control = _screen.get_node("Panel")
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	panel.position -= _grid.get_global_rect().position + Vector2(1.5, 1.5) * CELL - mouse_position
	await get_tree().process_frame
	var mouse_local: Vector2 = _grid.get_local_mouse_position()
	check("測試準備：滑鼠位置落在格子內", Rect2(Vector2.ZERO, _grid.size).has_point(mouse_local))

	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	_held.hold(cap)
	check("拿著物品且滑鼠在格子上時，立刻顯示該物品的預覽", _grid.get_preview_item() == cap)

	_grid.click_at(mouse_local)
	check(
		"放下物品後預覽立刻消失，不等下一幀",
		not _held.is_holding() and _inventory.has_item(cap) and _grid.get_preview_item() == null
	)
	# 讓重畫在物理幀之後、_process 之前發生，也就是原本出錯的時機
	await get_tree().physics_frame
	await get_tree().process_frame
	check("放下後滑鼠底下的物品就是剛放下的那件", _grid.get_hovered_item() == cap)

	_grid.click_at(mouse_local)
	check(
		"拿起物品後立刻顯示預覽，且不再有滑鼠底下的物品",
		_held.item == cap and _grid.get_preview_item() == cap and _grid.get_hovered_item() == null
	)

	# 互換：格子裡放一把短劍，手上的皮帽壓上去
	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	_inventory.place(sword, 1, 0)
	_grid.click_at(mouse_local)
	check(
		"互換後預覽立刻改成換出來的那件物品",
		_held.item == sword and _grid.get_preview_item() == sword
	)
	await get_tree().physics_frame
	await get_tree().process_frame

	_screen.close()
	check(
		"關閉後物品還在手上，但格子沒有預覽也沒有滑鼠底下的物品",
		_held.item == sword and _grid.get_preview_item() == null and _grid.get_hovered_item() == null
	)
	_screen.open()
	check(
		"重新開啟後立刻顯示手上那件物品的預覽",
		_held.item == sword and _grid.get_preview_item() == sword
	)
	await get_tree().physics_frame
	await get_tree().process_frame


# 某一格的中心點（格子的本地座標）
func _cell_center(x: int, y: int) -> Vector2:
	return Vector2(x + 0.5, y + 0.5) * CELL


# 物品左上角在 (x, y) 時，物品的中心點
func _item_center(x: int, y: int, item: ItemInstance) -> Vector2:
	return (Vector2(x, y) + Vector2(item.get_size()) * 0.5) * CELL


func _join_lines(lines: Array[Dictionary]) -> String:
	var texts: Array[String] = []
	for line: Dictionary in lines:
		texts.append(line["text"])
	return " / ".join(texts)
