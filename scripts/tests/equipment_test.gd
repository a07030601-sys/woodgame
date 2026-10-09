extends TestBase

# Equipment 的測試，以及「玩家的屬性元件 + Equipment」的整合測試。
# 整合測試直接建立玩家場景，確認穿脫裝備時屬性有跟著變。
# 測試依賴 data/bases.json：短劍傷害 2–5、手斧傷害 3–6。

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var _changed_slots: Array[String] = []


func _get_test_name() -> String:
	return "Equipment"


func _run_tests() -> void:
	_test_can_equip()
	_test_equip_and_unequip()
	_test_swap()
	_test_changed_signal()
	_test_serialization()
	_test_stats_follow_equipment()
	_test_affix_stats()
	_test_starting_equipment()


func _test_can_equip() -> void:
	var equipment: Equipment = Equipment.new()
	var sword: ItemInstance = _item("short_sword")
	check("欄位清單是武器、頭盔、身體護甲、手套、靴子", Equipment.SLOTS == ["weapon", "helm", "armor", "gloves", "boots"])
	check("武器可以穿在 weapon", equipment.can_equip(sword, "weapon"))
	check("武器不能穿在 helm", not equipment.can_equip(sword, "helm"))
	check(
		"每種底材都只能穿在自己的欄位",
		equipment.can_equip(_item("hand_axe"), "weapon")
		and equipment.can_equip(_item("leather_cap"), "helm")
		and equipment.can_equip(_item("leather_armor"), "armor")
		and equipment.can_equip(_item("leather_gloves"), "gloves")
		and equipment.can_equip(_item("leather_boots"), "boots")
		and not equipment.can_equip(_item("leather_gloves"), "boots")
	)
	check(
		"不存在的欄位或空物品都不能穿",
		not equipment.can_equip(sword, "ring") and not equipment.can_equip(null, "weapon")
	)


func _test_equip_and_unequip() -> void:
	var equipment: Equipment = Equipment.new()
	var sword: ItemInstance = _item("short_sword")
	var cap: ItemInstance = _item("leather_cap")

	check("空欄位查不到物品", equipment.get_item("weapon") == null)

	var result: Dictionary = equipment.equip(sword, "weapon")
	check(
		"欄位是空的就直接穿上",
		result["success"] and result["swapped_item"] == null and equipment.get_item("weapon") == sword
	)

	result = equipment.equip(cap, "weapon")
	check(
		"欄位不符時拒絕，原本的裝備不受影響",
		not result["success"]
		and result["swapped_item"] == null
		and equipment.get_item("weapon") == sword
		and equipment.get_item("helm") == null
	)

	check("脫下時回傳該物品", equipment.unequip("weapon") == sword)
	check("脫下後欄位是空的", equipment.get_item("weapon") == null)
	check("空欄位脫下回傳 null", equipment.unequip("weapon") == null and equipment.unequip("ring") == null)


func _test_swap() -> void:
	var equipment: Equipment = Equipment.new()
	var sword: ItemInstance = _item("short_sword")
	var axe: ItemInstance = _item("hand_axe")
	equipment.equip(sword, "weapon")

	var result: Dictionary = equipment.equip(axe, "weapon")
	check(
		"已有裝備時穿上並回傳被換下的那件",
		result["success"] and result["swapped_item"] == sword and equipment.get_item("weapon") == axe
	)

	result = equipment.equip(axe, "weapon")
	check(
		"重複穿同一件不會把自己換下來",
		result["success"] and result["swapped_item"] == null and equipment.get_item("weapon") == axe
	)


func _test_changed_signal() -> void:
	var equipment: Equipment = Equipment.new()
	equipment.equipment_changed.connect(_on_equipment_changed)
	var sword: ItemInstance = _item("short_sword")

	_changed_slots.clear()
	equipment.equip(sword, "weapon")
	equipment.equip(_item("leather_cap"), "helm")
	check("穿上時發出 equipment_changed 並帶欄位名", _changed_slots == ["weapon", "helm"])

	_changed_slots.clear()
	equipment.equip(_item("leather_cap"), "weapon")
	equipment.equip(sword, "weapon")
	equipment.unequip("boots")
	check("失敗或沒有變化的操作不發出訊號", _changed_slots.is_empty())

	_changed_slots.clear()
	equipment.equip(_item("hand_axe"), "weapon")
	equipment.unequip("weapon")
	check("互換與脫下各發出一次訊號", _changed_slots == ["weapon", "weapon"])


func _test_serialization() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261010
	var equipment: Equipment = Equipment.new()
	var rare_sword: ItemInstance = ItemGenerator.generate("short_sword", ItemInstance.QUALITY_RARE, rng)
	var magic_boots: ItemInstance = ItemGenerator.generate("leather_boots", ItemInstance.QUALITY_MAGIC, rng)
	equipment.equip(rare_sword, "weapon")
	equipment.equip(magic_boots, "boots")

	var saved: Dictionary = equipment.to_dict()
	var restored: Equipment = Equipment.from_dict(saved)
	check(
		"to_dict 還原後每個欄位的物品內容相同",
		restored.get_item("weapon") != null
		and restored.get_item("weapon").to_dict() == rare_sword.to_dict()
		and restored.get_item("boots") != null
		and restored.get_item("boots").to_dict() == magic_boots.to_dict()
		and restored.to_dict() == saved
	)
	check(
		"還原後空的欄位仍然是空的",
		restored.get_item("helm") == null and restored.get_item("armor") == null and restored.get_item("gloves") == null
	)

	# 存檔會經過 JSON，數字讀回來都是 float
	var from_json: Equipment = Equipment.from_dict(JSON.parse_string(JSON.stringify(saved)))
	check("經過 JSON 文字再還原後內容相同", from_json.to_dict() == saved)


func _test_stats_follow_equipment() -> void:
	var player: Player = _create_player()
	var stats: StatsComponent = player.get_stats()
	var equipment: Equipment = player.get_equipment()

	check(
		"空手的基礎傷害是 1～2",
		_is_stat(stats, "damage_min", 1.0) and _is_stat(stats, "damage_max", 2.0)
	)

	equipment.equip(_item("short_sword"), "weapon")
	check(
		"穿上短劍後傷害變成 3～7",
		_is_stat(stats, "damage_min", 3.0) and _is_stat(stats, "damage_max", 7.0),
		_describe_damage(stats)
	)
	check("屬性元件多了 equip_weapon 這個來源", stats.has_source("equip_weapon"))

	equipment.equip(_item("hand_axe"), "weapon")
	check(
		"換成手斧後傷害變成 4～8，不殘留短劍的數值",
		_is_stat(stats, "damage_min", 4.0) and _is_stat(stats, "damage_max", 8.0),
		_describe_damage(stats)
	)

	var armor: ItemInstance = _item("leather_armor")
	equipment.equip(armor, "armor")
	check(
		"穿上防具後防禦等於擲出的防禦值，傷害不變",
		_is_stat(stats, "defense", float(armor.defense)) and _is_stat(stats, "damage_min", 4.0)
	)

	equipment.unequip("weapon")
	check(
		"脫下武器後傷害回到基礎值，防具的防禦還在",
		_is_stat(stats, "damage_min", 1.0)
		and _is_stat(stats, "damage_max", 2.0)
		and _is_stat(stats, "defense", float(armor.defense))
		and not stats.has_source("equip_weapon"),
		_describe_damage(stats)
	)

	equipment.unequip("armor")
	check(
		"全部脫下後所有屬性回到基礎值",
		_is_stat(stats, "defense", 0.0) and _is_stat(stats, "damage_min", 1.0) and not stats.has_source("equip_armor")
	)
	_free_player(player)


func _test_affix_stats() -> void:
	var player: Player = _create_player()
	var stats: StatsComponent = player.get_stats()
	var equipment: Equipment = player.get_equipment()

	# 手動組一頂帶詞綴的皮帽：生命 +10、體力 +5（體力每點再給 3 生命）
	var cap: ItemInstance = _item("leather_cap")
	cap.quality = ItemInstance.QUALITY_MAGIC
	cap.affixes.append({"id": "prefix_life", "modifiers": [{"stat": "life", "value": 10.0, "type": "flat"}]})
	cap.affixes.append({"id": "suffix_vitality", "modifiers": [{"stat": "vitality", "value": 5.0, "type": "flat"}]})

	equipment.equip(cap, "helm")
	check(
		"裝備上的詞綴會影響屬性（含體力的衍生效果）",
		_is_stat(stats, "vitality", 5.0) and _is_stat(stats, "life", 125.0),
		"體力 %s、生命 %s" % [stats.get_stat("vitality"), stats.get_stat("life")]
	)

	equipment.unequip("helm")
	check("脫下後詞綴的效果消失", _is_stat(stats, "vitality", 0.0) and _is_stat(stats, "life", 100.0))
	_free_player(player)


func _test_starting_equipment() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.debug_start_items = false
	add_child(player)
	var weapon: ItemInstance = player.get_equipment().get_item("weapon")
	check(
		"預設的起始裝備是一把普通品質的短劍",
		weapon != null and weapon.base_id == "short_sword" and weapon.quality == ItemInstance.QUALITY_NORMAL
	)
	check(
		"開場時起始裝備的數值已經算進屬性",
		_is_stat(player.get_stats(), "damage_min", 3.0) and _is_stat(player.get_stats(), "damage_max", 7.0),
		_describe_damage(player.get_stats())
	)
	_free_player(player)

	player = PLAYER_SCENE.instantiate() as Player
	player.debug_start_items = false
	player.starting_equipment.assign(["short_sword", "hand_axe", "leather_cap"])
	add_child(player)
	check(
		"起始裝備有兩把武器時，第二把放進背包",
		player.get_equipment().get_item("weapon").base_id == "short_sword"
		and player.get_equipment().get_item("helm").base_id == "leather_cap"
		and player.get_inventory().get_items().size() == 1
		and player.get_inventory().get_items()[0].base_id == "hand_axe"
	)
	_free_player(player)


# 沒有起始裝備、背包是空的玩家
func _create_player() -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.debug_start_items = false
	player.starting_equipment.clear()
	add_child(player)
	return player


func _free_player(player: Player) -> void:
	remove_child(player)
	player.free()


func _is_stat(stats: StatsComponent, stat_name: String, expected: float) -> bool:
	return is_equal_approx(stats.get_stat(stat_name), expected)


func _describe_damage(stats: StatsComponent) -> String:
	return "實際 %s～%s" % [stats.get_stat("damage_min"), stats.get_stat("damage_max")]


func _item(base_id: String) -> ItemInstance:
	return ItemDatabase.create_item(base_id)


func _on_equipment_changed(slot: String) -> void:
	_changed_slots.append(slot)
