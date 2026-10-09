class_name Equipment
extends RefCounted

# 角色身上的裝備欄資料，不含介面。每個欄位最多一件，物品底材的 slot 要與欄位相符才能穿。
# 這裡只管誰穿在哪裡；裝備提供的屬性由持有者（玩家）在 equipment_changed 時交給屬性元件。

signal equipment_changed(slot: String)

const SLOTS: Array[String] = ["weapon", "helm", "armor", "gloves", "boots"]

# 欄位名 -> 穿在該欄位的物品；空的欄位不會出現在裡面
var _items: Dictionary = {}


# 物品底材的 slot 與欄位相符才可以穿
func can_equip(item: ItemInstance, slot: String) -> bool:
	if item == null or not SLOTS.has(slot):
		return false
	return item.get_slot() == slot


# 穿到指定欄位。回傳 {"success": bool, "swapped_item": ItemInstance}：
# - 欄位是空的：穿上，swapped_item 為 null
# - 欄位已有裝備：穿上，原本那件放在 swapped_item
# - 欄位不符：不穿，success 為 false
func equip(item: ItemInstance, slot: String) -> Dictionary:
	var result: Dictionary = {"success": false, "swapped_item": null}
	if not can_equip(item, slot):
		return result

	var previous: ItemInstance = get_item(slot)
	result["success"] = true
	if previous == item:
		return result

	result["swapped_item"] = previous
	_items[slot] = item
	equipment_changed.emit(slot)
	return result


# 回傳脫下的物品，欄位是空的時回傳 null
func unequip(slot: String) -> ItemInstance:
	var item: ItemInstance = get_item(slot)
	if item == null:
		return null
	_items.erase(slot)
	equipment_changed.emit(slot)
	return item


# 欄位是空的或欄位名不存在時回傳 null
func get_item(slot: String) -> ItemInstance:
	if not _items.has(slot):
		return null
	return _items[slot]


func to_dict() -> Dictionary:
	var data: Dictionary = {}
	for slot: String in SLOTS:
		var item: ItemInstance = get_item(slot)
		if item != null:
			data[slot] = item.to_dict()
	return data


# 與欄位不符或底材不存在的物品會警告並略過
static func from_dict(data: Dictionary) -> Equipment:
	var equipment: Equipment = Equipment.new()
	for slot: String in SLOTS:
		if typeof(data.get(slot)) != TYPE_DICTIONARY:
			continue
		var item: ItemInstance = ItemInstance.from_dict(data[slot])
		if not equipment.equip(item, slot)["success"]:
			push_warning("Equipment：略過不能穿在 %s 的物品 %s" % [slot, item.base_id])
	return equipment
