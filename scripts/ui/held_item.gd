class_name HeldItem
extends Control

# 「手上拿著的物品」：同一時間最多一件，顯示時跟著滑鼠游標移動。
# 它不屬於背包，背包格子、之後的裝備欄和丟到地上都共用這一個。

signal changed

var item: ItemInstance = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func _process(_delta: float) -> void:
	if item != null:
		_follow_mouse()


func is_holding() -> bool:
	return item != null


# 把物品拿到手上；傳入 null 代表手上變空
func hold(new_item: ItemInstance) -> void:
	item = new_item
	_refresh()
	changed.emit()


# 交出手上的物品並清空，手上沒有物品時回傳 null
func take() -> ItemInstance:
	var taken: ItemInstance = item
	hold(null)
	return taken


func _refresh() -> void:
	visible = item != null
	if item != null:
		size = Vector2(item.get_size()) * InventoryGrid.CELL_SIZE
		_follow_mouse()
	queue_redraw()


# 物品的中心對準游標
func _follow_mouse() -> void:
	if is_inside_tree():
		position = get_viewport().get_mouse_position() - size * 0.5


func _draw() -> void:
	if item != null:
		InventoryGrid.draw_item(self, Rect2(Vector2.ZERO, size), item, get_theme_default_font(), 0.85)
