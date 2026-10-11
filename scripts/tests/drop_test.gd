extends TestBase

# 掉寶與撿取的測試：掉落擲骰、地上物品、撿取、從手上丟到地上。
# 滑鼠滑過變亮、實際點擊地上的物品、畫面上的提示文字長相無法在這裡驗證，要在編輯器裡實際操作。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const MONSTER_SCENE: PackedScene = preload("res://scenes/monster.tscn")
const HELD_ITEM_SCENE: PackedScene = preload("res://scenes/ui/held_item.tscn")
const SCREEN_MESSAGE_SCENE: PackedScene = preload("res://scenes/ui/screen_message.tscn")
const TEST_SEED: int = 20261011
const ROLL_COUNT: int = 2000
# 等角色走到定位時最多等幾個物理幀
const MAX_WALK_FRAMES: int = 240
# 殺這麼多隻怪物都沒掉任何東西的機率約千萬分之二
const MONSTER_COUNT: int = 30

var _inventory_full_count: int = 0


func _get_test_name() -> String:
	return "掉寶與撿取"


func _get_header_note() -> String:
	return "（種子 %d）" % TEST_SEED


func _run_tests() -> void:
	_test_default_table()
	_test_reproducible()
	_test_drop_chance()
	_test_zero_weight()
	_test_inventory_full()
	_test_ground_item()
	_test_pick_up()
	_test_drop_from_hand()
	_test_monster_drop()
	await _test_walk_to_pick_up()
	await _test_click_world_with_held_item()


func _test_default_table() -> void:
	check("default 掉落表有載入", ItemDatabase.has_drop_table(DropRoller.DEFAULT_TABLE_ID))
	var table: Dictionary = ItemDatabase.get_drop_table(DropRoller.DEFAULT_TABLE_ID)
	var weights: Dictionary = table.get("quality_weights", {})
	check(
		"default 掉落表的內容與 drop_tables.json 相同",
		is_equal_approx(float(table.get("drop_chance", -1.0)), 40.0)
		and is_equal_approx(float(weights.get("normal", -1.0)), 60.0)
		and is_equal_approx(float(weights.get("magic", -1.0)), 30.0)
		and is_equal_approx(float(weights.get("rare", -1.0)), 10.0)
		and is_equal_approx(float(weights.get("set", -1.0)), 4.0)
		and is_equal_approx(float(table.get("rune_weight", -1.0)), 5.0),
		str(table)
	)
	check("不存在的掉落表擲不出物品", DropRoller.roll("not_exist", _make_rng(TEST_SEED)) == null)


func _test_reproducible() -> void:
	var first: Array[Dictionary] = _roll_many(TEST_SEED)
	var second: Array[Dictionary] = _roll_many(TEST_SEED)
	check("相同種子擲 %d 次的結果完全相同" % ROLL_COUNT, first == second)

	var drop_count: int = 0
	for result: Dictionary in first:
		if not result.is_empty():
			drop_count += 1
	check(
		"這組結果裡同時有掉落與沒掉落",
		drop_count > 0 and drop_count < ROLL_COUNT,
		"掉落 %d 次" % drop_count
	)
	check("不同種子的結果不同", first != _roll_many(TEST_SEED + 1))


func _test_drop_chance() -> void:
	var rng: RandomNumberGenerator = _make_rng(TEST_SEED)
	var counts: Dictionary = _count_qualities(
		ItemDatabase.get_drop_table(DropRoller.DEFAULT_TABLE_ID), rng
	)
	var drop_count: int = ROLL_COUNT - counts["none"]
	check(
		"default 表的掉落次數接近 40%",
		drop_count > ROLL_COUNT * 0.35 and drop_count < ROLL_COUNT * 0.45,
		"%d 次裡掉落 %d 次" % [ROLL_COUNT, drop_count]
	)
	check(
		"default 表的品質數量：普通最多、稀有最少，三種都有",
		counts["normal"] > counts["magic"] and counts["magic"] > counts["rare"] and counts["rare"] > 0,
		str(counts)
	)
	check(
		"default 表會掉套裝物品，數量比稀有少",
		counts["set"] > 0 and counts["set"] < counts["rare"],
		str(counts)
	)
	check(
		"default 表會掉符文，數量比稀有少",
		counts["rune"] > 0 and counts["rune"] < counts["rare"],
		str(counts)
	)

	var all_weights: Dictionary = {"normal": 60, "magic": 30, "rare": 10}
	counts = _count_qualities({"drop_chance": 0, "quality_weights": all_weights}, rng)
	check("掉落機率 0 時完全不掉", counts["none"] == ROLL_COUNT, str(counts))
	counts = _count_qualities({"drop_chance": 100, "quality_weights": all_weights}, rng)
	check("掉落機率 100 時每次都掉", counts["none"] == 0, str(counts))


func _test_zero_weight() -> void:
	var rng: RandomNumberGenerator = _make_rng(TEST_SEED)
	var counts: Dictionary = _count_qualities(
		{"drop_chance": 100, "quality_weights": {"normal": 0, "magic": 50, "rare": 50}}, rng
	)
	check(
		"普通的權重為 0 時不會出現普通物品，其他兩種都會出現",
		counts["normal"] == 0 and counts["magic"] > 0 and counts["rare"] > 0,
		str(counts)
	)

	counts = _count_qualities(
		{"drop_chance": 100, "quality_weights": {"normal": 0, "magic": 0, "rare": 1}}, rng
	)
	check("只有稀有的權重不是 0 時全部都是稀有", counts["rare"] == ROLL_COUNT, str(counts))

	# 沒列出的品質等於權重 0
	counts = _count_qualities({"drop_chance": 100, "quality_weights": {"normal": 5}}, rng)
	check("沒列出權重的品質不會出現", counts["normal"] == ROLL_COUNT, str(counts))

	check("沒有 rune_weight 的掉落表不會掉符文", counts["rune"] == 0, str(counts))
	check("沒列出 set 權重的掉落表不會掉套裝物品", counts["set"] == 0, str(counts))

	counts = _count_qualities({"drop_chance": 100, "quality_weights": {"set": 1}}, rng)
	check("只有 set 有權重時全部都是套裝物品", counts["set"] == ROLL_COUNT, str(counts))

	counts = _count_qualities(
		{"drop_chance": 100, "quality_weights": {"normal": 60, "magic": 30, "rare": 10}, "rune_weight": 0},
		rng
	)
	check("rune_weight 為 0 時不會掉符文", counts["rune"] == 0 and counts["none"] == 0, str(counts))

	counts = _count_qualities(
		{"drop_chance": 100, "quality_weights": {"normal": 0, "magic": 0, "rare": 0}, "rune_weight": 5},
		rng
	)
	check("只有符文有權重時全部都是符文", counts["rune"] == ROLL_COUNT, str(counts))

	check(
		"所有權重都是 0 時抽不出品質",
		DropRoller.pick_quality({"normal": 0, "magic": 0, "rare": 0}, rng).is_empty()
	)


func _test_inventory_full() -> void:
	var inventory: Inventory = Inventory.new()
	_fill_inventory(inventory)
	var item_count: int = inventory.get_items().size()

	var extra: ItemInstance = ItemDatabase.create_item("leather_cap")
	check("背包滿時 add_item_auto 回傳 false", not inventory.add_item_auto(extra))
	check(
		"失敗後背包內容不變，物品不在背包裡也沒有被改動",
		inventory.get_items().size() == item_count
		and not inventory.has_item(extra)
		and extra.base_id == "leather_cap"
	)


func _test_ground_item() -> void:
	var rng: RandomNumberGenerator = _make_rng(TEST_SEED)
	var item: ItemInstance = ItemGenerator.generate("hand_axe", ItemInstance.QUALITY_MAGIC, rng)
	var ground_item: GroundItem = GroundItem.spawn(self, item, Vector2(400.0, 300.0))
	var label: Label = ground_item.get_node("Label") as Label

	check("地上物品顯示物品的完整名稱", label.text == item.get_display_name(), label.text)
	check(
		"名稱文字是品質顏色",
		label.get_theme_color("font_color") == item.get_quality_color()
	)
	check(
		"名稱文字的範圍內算點到，範圍外不算",
		ground_item.contains_point(Vector2(400.0, 300.0))
		and not ground_item.contains_point(Vector2(400.0, 400.0))
	)
	check(
		"find_at 找得到該位置的地上物品，空地回傳 null",
		GroundItem.find_at(get_tree(), Vector2(400.0, 300.0)) == ground_item
		and GroundItem.find_at(get_tree(), Vector2(-900.0, -900.0)) == null
	)

	ground_item.set_hovered(true)
	var hover_color: Color = label.get_theme_color("font_color")
	check(
		"滑過時文字比品質顏色亮",
		ground_item.is_hovered() and hover_color.get_luminance() > item.get_quality_color().get_luminance()
	)
	ground_item.set_hovered(false)
	check("滑鼠離開後恢復品質顏色", label.get_theme_color("font_color") == item.get_quality_color())

	var upper: GroundItem = GroundItem.spawn(
		self, ItemDatabase.create_item("leather_cap"), Vector2(400.0, 300.0)
	)
	check("名稱疊在一起時 find_at 回傳後放的那件", GroundItem.find_at(get_tree(), Vector2(400.0, 300.0)) == upper)

	_free_ground_item(upper)
	_free_ground_item(ground_item)


func _test_pick_up() -> void:
	var player: Player = _create_player()
	var message: ScreenMessage = SCREEN_MESSAGE_SCENE.instantiate() as ScreenMessage
	add_child(message)
	_inventory_full_count = 0
	player.inventory_full.connect(_on_inventory_full)
	var inventory: Inventory = player.get_inventory()

	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	var ground_item: GroundItem = GroundItem.spawn(self, cap, Vector2(50.0, 0.0))
	check("背包有空位時撿取成功", player.pick_up(ground_item))
	check(
		"撿起後物品在背包裡，地上物品被移除",
		inventory.has_item(cap) and ground_item.is_queued_for_deletion()
	)
	check("撿取成功時不顯示提示", message.get_message().is_empty() and _inventory_full_count == 0)
	inventory.remove(cap)

	_fill_inventory(inventory)
	var extra: ItemInstance = ItemDatabase.create_item("leather_cap")
	var full_ground_item: GroundItem = GroundItem.spawn(self, extra, Vector2(50.0, 0.0))
	check("背包滿時撿取失敗", not player.pick_up(full_ground_item))
	check(
		"撿取失敗時物品留在地上，沒有進背包",
		full_ground_item.is_inside_tree()
		and not full_ground_item.is_queued_for_deletion()
		and full_ground_item.item == extra
		and not inventory.has_item(extra)
		and GroundItem.find_at(get_tree(), Vector2(50.0, 0.0)) == full_ground_item
	)
	check(
		"撿取失敗時畫面顯示「背包已滿」",
		message.get_message() == "背包已滿" and _inventory_full_count == 1,
		message.get_message()
	)

	inventory.remove(inventory.get_item_at(0, 0))
	check(
		"空出位置後同一件物品可以撿起來",
		player.pick_up(full_ground_item) and inventory.has_item(extra)
	)

	remove_child(message)
	message.free()
	_free_player(player)


func _test_drop_from_hand() -> void:
	var player: Player = _create_player()
	player.global_position = Vector2(300.0, 200.0)
	var held_layer: CanvasLayer = HELD_ITEM_SCENE.instantiate() as CanvasLayer
	add_child(held_layer)
	var held: HeldItem = held_layer.get_node("HeldItem") as HeldItem

	check("手上沒有物品時丟不出東西", player.drop_held_item() == null)

	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	held.hold(sword)
	var dropped: GroundItem = player.drop_held_item()
	check(
		"丟下後手上變空，物品變成地上物品",
		dropped != null and dropped.item == sword and not held.is_holding()
	)
	check(
		"地上物品在角色腳邊",
		dropped != null and dropped.global_position.distance_to(player.global_position) < 60.0
	)
	check("丟下的物品沒有進背包", not player.get_inventory().has_item(sword))
	check("丟下的物品可以再撿回來", dropped != null and player.pick_up(dropped) and player.get_inventory().has_item(sword))

	remove_child(held_layer)
	held_layer.free()
	_free_player(player)


# 怪物死亡時依 default 表擲骰，掉落的物品要出現在死亡位置附近
func _test_monster_drop() -> void:
	var death_position: Vector2 = Vector2(2000.0, 2000.0)
	for i: int in MONSTER_COUNT:
		var monster: Monster = MONSTER_SCENE.instantiate() as Monster
		monster.position = death_position
		add_child(monster)
		monster.take_damage(99999)

	var dropped: Array[GroundItem] = _get_ground_items()
	var all_near: bool = true
	var all_have_item: bool = true
	for ground_item: GroundItem in dropped:
		if ground_item.global_position.distance_to(death_position) > Monster.DROP_SCATTER_RADIUS + 0.01:
			all_near = false
		var item: ItemInstance = ground_item.item
		if item == null:
			all_have_item = false
		elif item.is_rune():
			if not ItemDatabase.has_rune(item.rune_id):
				all_have_item = false
		elif not ItemDatabase.has_base(item.base_id):
			all_have_item = false
	check(
		"殺死 %d 隻怪物會掉出物品，但不是每隻都掉" % MONSTER_COUNT,
		dropped.size() > 0 and dropped.size() < MONSTER_COUNT,
		"掉了 %d 件" % dropped.size()
	)
	check("怪物掉落的物品都在死亡位置附近", all_near)
	check("怪物掉落的都是有效的物品", all_have_item)

	for ground_item: GroundItem in dropped:
		_free_ground_item(ground_item)


func _test_walk_to_pick_up() -> void:
	var player: Player = _create_player()
	var message: ScreenMessage = SCREEN_MESSAGE_SCENE.instantiate() as ScreenMessage
	add_child(message)
	var inventory: Inventory = player.get_inventory()

	var cap: ItemInstance = ItemDatabase.create_item("leather_cap")
	var ground_item: GroundItem = GroundItem.spawn(self, cap, Vector2(120.0, 0.0))
	player.move_to_pick_up(ground_item)
	check("還沒走到之前不會撿起來", not inventory.has_item(cap))
	for frame: int in MAX_WALK_FRAMES:
		if inventory.has_item(cap):
			break
		await get_tree().physics_frame
	check(
		"走到物品旁邊後自動撿起",
		inventory.has_item(cap) and player.global_position.distance_to(Vector2(120.0, 0.0)) <= player.pickup_range + 1.0,
		"角色位置 %s" % player.global_position
	)
	await get_tree().process_frame
	check("撿起後地上物品消失", not is_instance_valid(ground_item))
	inventory.remove(cap)

	_fill_inventory(inventory)
	var extra: ItemInstance = ItemDatabase.create_item("leather_cap")
	var target_position: Vector2 = player.global_position + Vector2(0.0, 120.0)
	var full_ground_item: GroundItem = GroundItem.spawn(self, extra, target_position)
	player.move_to_pick_up(full_ground_item)
	for frame: int in MAX_WALK_FRAMES:
		if not message.get_message().is_empty():
			break
		await get_tree().physics_frame
	check(
		"背包滿時走到旁邊也撿不起來，物品留在地上並顯示「背包已滿」",
		message.get_message() == "背包已滿"
		and is_instance_valid(full_ground_item)
		and not full_ground_item.is_queued_for_deletion()
		and not inventory.has_item(extra)
	)
	var stopped_position: Vector2 = player.global_position
	for frame: int in 5:
		await get_tree().physics_frame
	check(
		"撿不起來之後角色停在物品旁邊",
		player.global_position == stopped_position
		and stopped_position.distance_to(target_position) <= player.pickup_range + 1.0
	)

	_free_ground_item(full_ground_item)
	remove_child(message)
	message.free()
	_free_player(player)


# 手上有物品時在遊戲世界按下左鍵：物品丟到地上，角色不移動
func _test_click_world_with_held_item() -> void:
	var player: Player = _create_player()
	player.global_position = Vector2(-600.0, 500.0)
	var held_layer: CanvasLayer = HELD_ITEM_SCENE.instantiate() as CanvasLayer
	add_child(held_layer)
	var held: HeldItem = held_layer.get_node("HeldItem") as HeldItem
	var sword: ItemInstance = ItemDatabase.create_item("short_sword")
	held.hold(sword)

	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	check("測試準備：這個事件會被當成 move_click", click.is_action_pressed("move_click"))
	player._unhandled_input(click)

	var dropped: Array[GroundItem] = _get_ground_items()
	check(
		"手上有物品時點遊戲世界，物品變成腳邊的地上物品",
		not held.is_holding()
		and dropped.size() == 1
		and dropped[0].item == sword
		and dropped[0].global_position.distance_to(player.global_position) < 60.0
	)
	var start_position: Vector2 = player.global_position
	for frame: int in 5:
		await get_tree().physics_frame
	check("丟下物品的那次點擊不會讓角色移動", player.global_position == start_position)

	for ground_item: GroundItem in dropped:
		_free_ground_item(ground_item)
	remove_child(held_layer)
	held_layer.free()
	_free_player(player)


func _make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# 用 default 表擲 ROLL_COUNT 次，每次的結果轉成 Dictionary，沒掉落時是空的 Dictionary
func _roll_many(seed_value: int) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = _make_rng(seed_value)
	var results: Array[Dictionary] = []
	for i: int in ROLL_COUNT:
		var item: ItemInstance = DropRoller.roll(DropRoller.DEFAULT_TABLE_ID, rng)
		results.append(item.to_dict() if item != null else {})
	return results


# 用 table 擲 ROLL_COUNT 次，回傳每種品質出現的次數，符文算在 "rune"，沒掉落算在 "none"
func _count_qualities(table: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var counts: Dictionary = {"none": 0, "normal": 0, "magic": 0, "rare": 0, "set": 0, "rune": 0}
	for i: int in ROLL_COUNT:
		var item: ItemInstance = DropRoller.roll_table(table, rng)
		if item == null:
			counts["none"] += 1
		elif item.is_rune():
			counts["rune"] += 1
		else:
			counts[item.quality] += 1
	return counts


# 用皮帽把背包塞到一件都放不下
func _fill_inventory(inventory: Inventory) -> void:
	while inventory.add_item_auto(ItemDatabase.create_item("leather_cap")):
		pass


# 沒有起始裝備、背包是空的玩家
func _create_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.starting_equipment.clear()
	add_child(player)
	return player


func _free_player(player: Player) -> void:
	remove_child(player)
	player.free()


# 目前還在地上（沒有等待移除）的所有地上物品
func _get_ground_items() -> Array[GroundItem]:
	var ground_items: Array[GroundItem] = []
	for node: Node in get_tree().get_nodes_in_group(GroundItem.GROUP):
		var ground_item: GroundItem = node as GroundItem
		if ground_item != null and not ground_item.is_queued_for_deletion():
			ground_items.append(ground_item)
	return ground_items


func _free_ground_item(ground_item: GroundItem) -> void:
	ground_item.get_parent().remove_child(ground_item)
	ground_item.free()


func _on_inventory_full() -> void:
	_inventory_full_count += 1
