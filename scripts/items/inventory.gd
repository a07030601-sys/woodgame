class_name Inventory
extends RefCounted

# 背包的格子資料，不含任何介面。物品依底材的 size（[寬, 高]）佔用格子，
# 位置一律指物品左上角那一格，x 往右、y 往下，從 0 開始。
# 同一件物品在背包裡只會有一個位置：對已在背包裡的物品呼叫 place() 等於移動它。

signal changed

const DEFAULT_WIDTH: int = 10
const DEFAULT_HEIGHT: int = 4
const NO_POSITION: Vector2i = Vector2i(-1, -1)

var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT

# 長度為 width * height，每格存佔用它的物品，空格為 null
var _grid: Array[ItemInstance] = []
# 物品 -> 左上角位置（Vector2i），順序就是放入的順序
var _positions: Dictionary = {}


func _init(p_width: int = DEFAULT_WIDTH, p_height: int = DEFAULT_HEIGHT) -> void:
	width = maxi(p_width, 1)
	height = maxi(p_height, 1)
	_grid.resize(width * height)


# 物品佔用的格數 [寬, 高]，查不到底材時回傳 Vector2i.ZERO
func get_item_size(item: ItemInstance) -> Vector2i:
	if item == null:
		return Vector2i.ZERO
	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	if base.is_empty():
		return Vector2i.ZERO
	var size: Array = base["size"]
	return Vector2i(int(size[0]), int(size[1]))


func has_item(item: ItemInstance) -> bool:
	return _positions.has(item)


# 物品左上角的位置，不在背包裡時回傳 NO_POSITION
func get_item_position(item: ItemInstance) -> Vector2i:
	if not _positions.has(item):
		return NO_POSITION
	return _positions[item]


# 背包裡的所有物品，依放入的順序排列
func get_items() -> Array[ItemInstance]:
	var items: Array[ItemInstance] = []
	items.assign(_positions.keys())
	return items


# 物品佔用的任一格都查得到該物品；空格或範圍外回傳 null
func get_item_at(x: int, y: int) -> ItemInstance:
	if not _is_in_bounds(x, y):
		return null
	return _grid[_index(x, y)]


# 是否在範圍內且不與其他物品重疊。物品自己目前佔用的格子不算重疊。
func can_place(item: ItemInstance, x: int, y: int) -> bool:
	if not _fits_in_bounds(item, x, y):
		return false
	return _get_overlapping_items(item, x, y).is_empty()


# 放到指定位置，成功與否回傳 bool。物品已在背包裡時會從原位置移過來。
func place(item: ItemInstance, x: int, y: int) -> bool:
	if not can_place(item, x, y):
		return false
	_clear_cells(item)
	_fill_cells(item, x, y)
	changed.emit()
	return true


# 物品不在背包裡時回傳 false
func remove(item: ItemInstance) -> bool:
	if not _positions.has(item):
		return false
	_clear_cells(item)
	changed.emit()
	return true


# 從左上角開始，先往下再往右找第一個可放的位置，找不到時回傳 NO_POSITION
func find_free_position(item: ItemInstance) -> Vector2i:
	for x: int in width:
		for y: int in height:
			if can_place(item, x, y):
				return Vector2i(x, y)
	return NO_POSITION


# 自動放到空位，成功與否回傳 bool。物品已在背包裡時回傳 false。
func add_item_auto(item: ItemInstance) -> bool:
	if item == null or _positions.has(item):
		return false
	var position: Vector2i = find_free_position(item)
	if position == NO_POSITION:
		return false
	return place(item, position.x, position.y)


# 放到指定位置，必要時與原本在那裡的物品互換。回傳 {"success": bool, "swapped_item": ItemInstance}：
# - 目標範圍沒有其他物品：放入，swapped_item 為 null
# - 剛好壓到一件：放入，那一件被移出背包並放在 swapped_item
# - 壓到兩件以上或超出範圍：不放入，success 為 false
func place_or_swap(item: ItemInstance, x: int, y: int) -> Dictionary:
	var result: Dictionary = {"success": false, "swapped_item": null}
	if not _fits_in_bounds(item, x, y):
		return result

	var overlapping: Array[ItemInstance] = _get_overlapping_items(item, x, y)
	if overlapping.size() > 1:
		return result

	if overlapping.size() == 1:
		_clear_cells(overlapping[0])
		result["swapped_item"] = overlapping[0]
	_clear_cells(item)
	_fill_cells(item, x, y)
	result["success"] = true
	changed.emit()
	return result


func to_dict() -> Dictionary:
	var items: Array = []
	for item: ItemInstance in _positions:
		var position: Vector2i = _positions[item]
		items.append({"x": position.x, "y": position.y, "item": item.to_dict()})
	return {"width": width, "height": height, "items": items}


# 放不進去的物品（位置超出範圍、互相重疊、底材不存在）會警告並略過
static func from_dict(data: Dictionary) -> Inventory:
	var inventory: Inventory = Inventory.new(
		int(data.get("width", DEFAULT_WIDTH)), int(data.get("height", DEFAULT_HEIGHT))
	)

	var entries: Variant = data.get("items", [])
	if typeof(entries) != TYPE_ARRAY:
		return inventory
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("item")) != TYPE_DICTIONARY:
			push_warning("Inventory：略過格式不對的物品資料 %s" % str(entry))
			continue
		var item: ItemInstance = ItemInstance.from_dict(entry["item"])
		var x: int = int(entry.get("x", -1))
		var y: int = int(entry.get("y", -1))
		if not inventory.place(item, x, y):
			push_warning("Inventory：略過放不進 (%d, %d) 的物品 %s" % [x, y, item.base_id])
	return inventory


func _is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func _index(x: int, y: int) -> int:
	return y * width + x


func _fits_in_bounds(item: ItemInstance, x: int, y: int) -> bool:
	var size: Vector2i = get_item_size(item)
	if size.x <= 0 or size.y <= 0:
		return false
	return x >= 0 and y >= 0 and x + size.x <= width and y + size.y <= height


# 目標範圍內除了 item 自己以外的物品，每件只列一次。呼叫前要先確認範圍合法。
func _get_overlapping_items(item: ItemInstance, x: int, y: int) -> Array[ItemInstance]:
	var size: Vector2i = get_item_size(item)
	var overlapping: Array[ItemInstance] = []
	for cell_x: int in range(x, x + size.x):
		for cell_y: int in range(y, y + size.y):
			var occupant: ItemInstance = _grid[_index(cell_x, cell_y)]
			if occupant != null and occupant != item and not overlapping.has(occupant):
				overlapping.append(occupant)
	return overlapping


func _fill_cells(item: ItemInstance, x: int, y: int) -> void:
	var size: Vector2i = get_item_size(item)
	for cell_x: int in range(x, x + size.x):
		for cell_y: int in range(y, y + size.y):
			_grid[_index(cell_x, cell_y)] = item
	_positions[item] = Vector2i(x, y)


# 物品不在背包裡時什麼都不做
func _clear_cells(item: ItemInstance) -> void:
	if not _positions.has(item):
		return
	for index: int in _grid.size():
		if _grid[index] == item:
			_grid[index] = null
	_positions.erase(item)
