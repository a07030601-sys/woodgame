extends TestBase

# Inventory 的測試：用 F6 執行 scenes/tests/inventory_test.tscn，或用 run_all_tests 一起執行。
# 測試依賴 data/bases.json 的 size：短劍 1×3、皮帽 2×2、皮甲 2×3。

const TEST_SEED: int = 20261010

var _changed_count: int = 0


func _get_test_name() -> String:
	return "Inventory"


func _run_tests() -> void:
	_test_sizes()
	_test_bounds()
	_test_overlap()
	_test_get_item_at()
	_test_remove()
	_test_single_position()
	_test_find_free_position()
	_test_auto_fill()
	_test_swap()
	_test_changed_signal()
	_test_serialization()


func _test_sizes() -> void:
	var inventory: Inventory = Inventory.new()
	check("預設大小是 10 × 4", inventory.width == 10 and inventory.height == 4)
	check(
		"物品大小來自底材的 size",
		inventory.get_item_size(_item("short_sword")) == Vector2i(1, 3)
		and inventory.get_item_size(_item("leather_cap")) == Vector2i(2, 2)
		and inventory.get_item_size(_item("leather_armor")) == Vector2i(2, 3)
	)


func _test_bounds() -> void:
	var inventory: Inventory = Inventory.new()
	var sword: ItemInstance = _item("short_sword")

	check("左上角可以放", inventory.can_place(sword, 0, 0))
	check("剛好貼齊右下角可以放", inventory.can_place(sword, 9, 1))
	check("超出右邊不能放", not inventory.can_place(sword, 10, 0))
	check("超出下邊不能放", not inventory.can_place(sword, 0, 2))
	check("負數座標不能放", not inventory.can_place(sword, -1, 0) and not inventory.can_place(sword, 0, -1))
	check(
		"放到範圍外時 place 回傳 false 且背包不變",
		not inventory.place(sword, 0, 2) and inventory.get_items().is_empty()
	)
	check(
		"放到範圍內時 place 回傳 true",
		inventory.place(sword, 9, 1) and inventory.get_item_position(sword) == Vector2i(9, 1)
	)


func _test_overlap() -> void:
	var inventory: Inventory = Inventory.new()
	var armor: ItemInstance = _item("leather_armor")
	var cap: ItemInstance = _item("leather_cap")
	inventory.place(armor, 0, 0)

	check("與其他物品重疊時 can_place 為 false", not inventory.can_place(cap, 1, 2))
	check(
		"重疊時 place 被拒絕且原物品不受影響",
		not inventory.place(cap, 1, 2)
		and not inventory.has_item(cap)
		and inventory.get_item_at(1, 2) == armor
	)
	check("緊鄰但不重疊可以放", inventory.place(cap, 2, 0))


func _test_get_item_at() -> void:
	var inventory: Inventory = Inventory.new()
	var armor: ItemInstance = _item("leather_armor")
	inventory.place(armor, 3, 1)

	var all_cells_found: bool = true
	for x: int in range(3, 5):
		for y: int in range(1, 4):
			if inventory.get_item_at(x, y) != armor:
				all_cells_found = false
	check("物品佔用的任一格都查得到該物品", all_cells_found)
	check(
		"物品旁邊的空格查不到物品",
		inventory.get_item_at(2, 1) == null
		and inventory.get_item_at(5, 1) == null
		and inventory.get_item_at(3, 0) == null
	)
	check(
		"範圍外的座標回傳 null",
		inventory.get_item_at(-1, 0) == null and inventory.get_item_at(10, 0) == null and inventory.get_item_at(0, 4) == null
	)


func _test_remove() -> void:
	var inventory: Inventory = Inventory.new()
	var armor: ItemInstance = _item("leather_armor")
	inventory.place(armor, 0, 0)

	check("移除存在的物品回傳 true", inventory.remove(armor))
	var all_cells_empty: bool = true
	for x: int in range(0, 2):
		for y: int in range(0, 3):
			if inventory.get_item_at(x, y) != null:
				all_cells_empty = false
	check(
		"移除後格子空出",
		all_cells_empty and not inventory.has_item(armor) and inventory.get_item_position(armor) == Inventory.NO_POSITION
	)
	check("空出的格子可以再放別的物品", inventory.place(_item("leather_cap"), 0, 0))
	check("移除不在背包裡的物品回傳 false", not inventory.remove(armor))


func _test_single_position() -> void:
	var inventory: Inventory = Inventory.new()
	var sword: ItemInstance = _item("short_sword")
	inventory.place(sword, 0, 0)

	check("已在背包裡的物品再 place 到別處會成功", inventory.place(sword, 5, 0))
	check(
		"同一件物品只會在一個位置",
		inventory.get_item_at(0, 0) == null
		and inventory.get_item_at(5, 0) == sword
		and inventory.get_items().size() == 1
		and inventory.get_item_position(sword) == Vector2i(5, 0)
	)
	check(
		"物品可以移到與自己原位置部分重疊的地方",
		inventory.place(sword, 5, 1) and inventory.get_item_at(5, 0) == null and inventory.get_item_at(5, 3) == sword
	)
	check(
		"已在背包裡的物品不能再 add_item_auto",
		not inventory.add_item_auto(sword) and inventory.get_items().size() == 1
	)


func _test_find_free_position() -> void:
	var inventory: Inventory = Inventory.new()
	check("空背包的第一個空位是左上角", inventory.find_free_position(_item("leather_cap")) == Vector2i(0, 0))

	inventory.place(_item("leather_cap"), 0, 0)
	check("先往下找", inventory.find_free_position(_item("leather_cap")) == Vector2i(0, 2))

	inventory.place(_item("leather_cap"), 0, 2)
	check("這一欄滿了再往右找", inventory.find_free_position(_item("leather_cap")) == Vector2i(2, 0))


func _test_auto_fill() -> void:
	var inventory: Inventory = Inventory.new()
	# 10 × 4 的背包剛好放得下 10 件 2 × 2 的皮帽
	var added_count: int = 0
	for i: int in 10:
		if inventory.add_item_auto(_item("leather_cap")):
			added_count += 1
	check("自動放置直到放滿", added_count == 10 and inventory.get_items().size() == 10)

	var has_empty_cell: bool = false
	for x: int in inventory.width:
		for y: int in inventory.height:
			if inventory.get_item_at(x, y) == null:
				has_empty_cell = true
	check("放滿後沒有任何空格", not has_empty_cell)
	check(
		"放滿後自動放置失敗",
		not inventory.add_item_auto(_item("leather_cap"))
		and not inventory.add_item_auto(_item("short_sword"))
		and inventory.get_items().size() == 10
	)
	check(
		"放滿後 find_free_position 回傳 (-1, -1)",
		inventory.find_free_position(_item("short_sword")) == Vector2i(-1, -1)
	)

	var small: Inventory = Inventory.new(1, 2)
	check("物品比背包大時自動放置失敗", not small.add_item_auto(_item("short_sword")))


func _test_swap() -> void:
	var inventory: Inventory = Inventory.new()
	var armor: ItemInstance = _item("leather_armor")
	var cap: ItemInstance = _item("leather_cap")
	inventory.place(armor, 0, 0)
	inventory.place(cap, 4, 0)

	var new_cap: ItemInstance = _item("leather_cap")
	var result: Dictionary = inventory.place_or_swap(new_cap, 7, 0)
	check(
		"目標範圍沒有物品時直接放入",
		result["success"] and result["swapped_item"] == null and inventory.get_item_at(7, 0) == new_cap
	)

	var sword: ItemInstance = _item("short_sword")
	result = inventory.place_or_swap(sword, 1, 0)
	check("只壓到一件時互換成功並回傳該件", result["success"] and result["swapped_item"] == armor)
	check(
		"被換出的物品已不在背包裡，新物品在目標位置",
		not inventory.has_item(armor)
		and inventory.get_item_at(0, 0) == null
		and inventory.get_item_at(1, 2) == sword
		and inventory.get_item_position(sword) == Vector2i(1, 0)
	)

	# 短劍在 (1, 0)～(1, 2)，放一頂皮帽在 (2, 0)，再用皮甲同時壓到兩件
	var second_cap: ItemInstance = _item("leather_cap")
	inventory.place(second_cap, 2, 0)
	var item_count: int = inventory.get_items().size()
	result = inventory.place_or_swap(armor, 1, 0)
	check(
		"壓到兩件時失敗且背包不變",
		not result["success"]
		and result["swapped_item"] == null
		and not inventory.has_item(armor)
		and inventory.get_item_at(1, 0) == sword
		and inventory.get_item_at(2, 0) == second_cap
		and inventory.get_items().size() == item_count
	)

	result = inventory.place_or_swap(armor, 9, 0)
	check("超出範圍時失敗", not result["success"] and not inventory.has_item(armor))

	# 此時 (1, 0) 是短劍、(2, 0) 是皮帽、(7, 0) 是另一頂皮帽
	check(
		"can_place_or_swap 與 place_or_swap 的結果一致且不改變背包",
		inventory.can_place_or_swap(armor, 5, 0)
		and inventory.can_place_or_swap(armor, 7, 0)
		and not inventory.can_place_or_swap(armor, 1, 0)
		and not inventory.can_place_or_swap(armor, 9, 0)
		and inventory.get_items().size() == item_count
	)


func _test_changed_signal() -> void:
	var inventory: Inventory = Inventory.new()
	inventory.changed.connect(_on_inventory_changed)
	var armor: ItemInstance = _item("leather_armor")
	var sword: ItemInstance = _item("short_sword")

	_changed_count = 0
	inventory.place(armor, 0, 0)
	check("place 成功時發出 changed", _changed_count == 1)

	_changed_count = 0
	inventory.place(sword, 1, 0)
	inventory.remove(sword)
	inventory.place_or_swap(sword, 20, 20)
	check("失敗的操作不發出 changed", _changed_count == 0)

	_changed_count = 0
	inventory.place_or_swap(sword, 0, 0)
	check("互換只發出一次 changed", _changed_count == 1)

	_changed_count = 0
	inventory.remove(sword)
	inventory.add_item_auto(armor)
	check("remove 與 add_item_auto 成功時各發出一次 changed", _changed_count == 2)


func _test_serialization() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = TEST_SEED
	var inventory: Inventory = Inventory.new()
	var rare_sword: ItemInstance = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_RARE, rng)
	var magic_cap: ItemInstance = ItemGenerator.generate("leather_cap", ItemInstance.QUALITY_MAGIC, rng)
	inventory.place(rare_sword, 9, 1)
	inventory.place(magic_cap, 3, 2)
	inventory.place(_item("leather_armor"), 0, 0)

	var saved: Dictionary = inventory.to_dict()
	var restored: Inventory = Inventory.from_dict(saved)
	check(
		"to_dict 還原後大小與物品數量相同",
		restored.width == inventory.width and restored.height == inventory.height and restored.get_items().size() == 3
	)
	check(
		"to_dict 還原後每件物品的內容與位置相同",
		_has_same_item_at(restored, 9, 1, rare_sword)
		and _has_same_item_at(restored, 9, 3, rare_sword)
		and _has_same_item_at(restored, 4, 3, magic_cap)
		and restored.get_item_at(0, 0).base_id == "leather_armor"
		and restored.to_dict() == saved
	)
	check("還原出來的是新的物品，不是同一個物件", restored.get_item_at(9, 1) != rare_sword)

	# 存檔會經過 JSON，數字讀回來都是 float
	var from_json: Inventory = Inventory.from_dict(JSON.parse_string(JSON.stringify(saved)))
	check("經過 JSON 文字再還原後內容與位置相同", from_json.to_dict() == saved)

	var small: Inventory = Inventory.from_dict(Inventory.new(3, 5).to_dict())
	check("非預設大小的背包還原後大小相同", small.width == 3 and small.height == 5)


func _has_same_item_at(inventory: Inventory, x: int, y: int, expected: ItemInstance) -> bool:
	var item: ItemInstance = inventory.get_item_at(x, y)
	return item != null and item.to_dict() == expected.to_dict()


func _item(base_id: String) -> ItemInstance:
	return ItemDatabase.create_item(base_id)


func _on_inventory_changed() -> void:
	_changed_count += 1
