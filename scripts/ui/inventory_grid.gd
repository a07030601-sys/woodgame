class_name InventoryGrid
extends Control

# 背包格子的顯示與滑鼠操作。資料在 Inventory，手上的物品在 HeldItem，這裡只負責畫面與點擊。

signal hovered_item_changed(item: ItemInstance)

const CELL_SIZE: int = 40
const ITEM_FONT_SIZE: int = 12
const ITEM_BORDER_WIDTH: float = 2.0
const CELL_COLOR: Color = Color(0.1, 0.1, 0.12, 1.0)
const CELL_LINE_COLOR: Color = Color(0.3, 0.3, 0.34, 1.0)
const ITEM_FILL_COLOR: Color = Color(0.2, 0.2, 0.25, 1.0)
const HOVER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.12)
const PREVIEW_OK_COLOR: Color = Color(0.2, 0.9, 0.2, 0.35)
const PREVIEW_BLOCKED_COLOR: Color = Color(0.9, 0.2, 0.2, 0.35)
# 手上的符文可以插進滑鼠底下的物品時，綠色預覽外面多一圈這個顏色的外框，和一般的放置預覽區別
const INSERT_OUTLINE_COLOR: Color = Color(1.0, 0.75, 0.2, 1.0)
const INSERT_OUTLINE_WIDTH: float = 3.0

var _inventory: Inventory = null
var _held: HeldItem = null
# 手上沒東西時，滑鼠底下的物品
var _hovered_item: ItemInstance = null
# 放置預覽是為哪一件物品算的；null 代表不顯示預覽。
# 預覽狀態自己記住物品，不在 _draw 時才去讀手上的物品，兩者才不會對不上。
var _preview_item: ItemInstance = null
var _preview_cell: Vector2i = Vector2i.ZERO
var _preview_ok: bool = false
# 預覽是「把手上的符文插進這件物品」時，這裡是那件物品；一般的放置預覽時為 null
var _preview_insert_target: ItemInstance = null


func _ready() -> void:
	clip_contents = true
	visibility_changed.connect(_refresh_hover)


func setup(inventory: Inventory, held: HeldItem) -> void:
	_inventory = inventory
	_held = held
	custom_minimum_size = Vector2(inventory.width, inventory.height) * CELL_SIZE
	_inventory.changed.connect(_on_data_changed)
	_held.changed.connect(_on_data_changed)
	_on_data_changed()


func _process(_delta: float) -> void:
	_refresh_hover()


func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		click_at(mouse_event.position)
		accept_event()


# local_position 所在的格子，可能在背包範圍外
func get_cell_at(local_position: Vector2) -> Vector2i:
	return Vector2i((local_position / CELL_SIZE).floor())


# 手上的物品中心對準 local_position 時，物品左上角會落在哪一格
func get_drop_cell(local_position: Vector2, item: ItemInstance) -> Vector2i:
	var item_pixel_size: Vector2 = Vector2(item.get_size()) * CELL_SIZE
	return Vector2i(((local_position - item_pixel_size * 0.5) / CELL_SIZE).round())


# 手上的 item 放到 cell 時如果是「把符文插進那一格的物品」，回傳那件物品，否則回傳 null。
# 只看背包裡的物品，而且要該物品還有空孔；不能插入時就照一般的放置或互換處理。
func get_insert_target_at(item: ItemInstance, cell: Vector2i) -> ItemInstance:
	if _inventory == null or item == null or not item.is_rune():
		return null
	var target: ItemInstance = _inventory.get_item_at(cell.x, cell.y)
	if target == null or not target.can_insert_rune(item):
		return null
	return target


# 處理在 local_position 的一次左鍵點擊：
# 手上沒東西時拿起該格的物品；手上有東西時放下，互換出來的物品變成手上的物品。
# 手上是符文、該格的物品可以插入時改成插入，手上的符文消失。
func click_at(local_position: Vector2) -> void:
	if _inventory == null:
		return

	if _held.is_holding():
		var cell: Vector2i = get_drop_cell(local_position, _held.item)
		var insert_target: ItemInstance = get_insert_target_at(_held.item, cell)
		if insert_target != null:
			if insert_target.insert_rune(_held.item):
				_held.take()
			return
		var result: Dictionary = _inventory.place_or_swap(_held.item, cell.x, cell.y)
		if result["success"]:
			_held.hold(result["swapped_item"])
	else:
		var cell: Vector2i = get_cell_at(local_position)
		var item: ItemInstance = _inventory.get_item_at(cell.x, cell.y)
		if item != null:
			_inventory.remove(item)
			_held.hold(item)


# 畫一件物品：邊框（顏色見 ItemInstance.get_display_color()）加上底材名或符文名。背包格子和手上的物品共用。
static func draw_item(
	canvas: CanvasItem, rect: Rect2, item: ItemInstance, font: Font, alpha: float
) -> void:
	var inner: Rect2 = rect.grow(-1.0)
	var fill_color: Color = ITEM_FILL_COLOR
	fill_color.a = alpha
	var border_color: Color = item.get_display_color()
	border_color.a = alpha
	canvas.draw_rect(inner, fill_color)
	canvas.draw_rect(inner.grow(-ITEM_BORDER_WIDTH * 0.5), border_color, false, ITEM_BORDER_WIDTH)

	var text: String = item.get_base_name()
	var text_width: float = inner.size.x - 6.0
	var text_size: Vector2 = font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, text_width, ITEM_FONT_SIZE
	)
	var text_position: Vector2 = Vector2(
		inner.position.x + 3.0,
		inner.position.y + (inner.size.y - text_size.y) * 0.5 + font.get_ascent(ITEM_FONT_SIZE)
	)
	canvas.draw_multiline_string(
		font,
		text_position,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		text_width,
		ITEM_FONT_SIZE,
		-1,
		Color(1.0, 1.0, 1.0, alpha)
	)


# 放置預覽目前是為哪一件物品顯示的，沒有預覽時回傳 null
func get_preview_item() -> ItemInstance:
	return _preview_item


# 目前的預覽是「插入符文」時，回傳會被插入的那件物品；一般的放置預覽或沒有預覽時回傳 null
func get_preview_insert_target() -> ItemInstance:
	return _preview_insert_target


func get_hovered_item() -> ItemInstance:
	return _hovered_item


# 背包或手上的物品一變就立刻重算，不等下一次 _process。
# 重畫可能排在 _process 之前（例如中間先跑了一次物理幀），等到 _process 才更新的話，
# _draw 會拿到「手上還有物品」時算的舊預覽。
func _on_data_changed() -> void:
	_refresh_hover()
	queue_redraw()


# 依目前的滑鼠位置、手上的物品與背包內容，重算滑鼠底下的物品與放置預覽
func _refresh_hover() -> void:
	if _inventory == null:
		return

	var hovered_item: ItemInstance = null
	var preview_item: ItemInstance = null
	var preview_cell: Vector2i = Vector2i.ZERO
	var preview_ok: bool = false
	var preview_insert_target: ItemInstance = null

	# 畫面沒顯示時一律清空，重新開啟時才不會殘留關閉前的狀態
	if is_visible_in_tree():
		var local_position: Vector2 = get_local_mouse_position()
		if Rect2(Vector2.ZERO, size).has_point(local_position):
			if _held.is_holding():
				preview_item = _held.item
				preview_cell = get_drop_cell(local_position, preview_item)
				preview_insert_target = get_insert_target_at(preview_item, preview_cell)
				preview_ok = (
					preview_insert_target != null
					or _inventory.can_place_or_swap(preview_item, preview_cell.x, preview_cell.y)
				)
			else:
				var cell: Vector2i = get_cell_at(local_position)
				hovered_item = _inventory.get_item_at(cell.x, cell.y)

	if (
		preview_item != _preview_item
		or preview_cell != _preview_cell
		or preview_ok != _preview_ok
		or preview_insert_target != _preview_insert_target
	):
		_preview_item = preview_item
		_preview_cell = preview_cell
		_preview_ok = preview_ok
		_preview_insert_target = preview_insert_target
		queue_redraw()

	if hovered_item != _hovered_item:
		_hovered_item = hovered_item
		queue_redraw()
		hovered_item_changed.emit(_hovered_item)


func _draw() -> void:
	if _inventory == null:
		return

	var grid_size: Vector2 = Vector2(_inventory.width, _inventory.height) * CELL_SIZE
	draw_rect(Rect2(Vector2.ZERO, grid_size), CELL_COLOR)
	for x: int in range(_inventory.width + 1):
		draw_line(Vector2(x * CELL_SIZE, 0.0), Vector2(x * CELL_SIZE, grid_size.y), CELL_LINE_COLOR)
	for y: int in range(_inventory.height + 1):
		draw_line(Vector2(0.0, y * CELL_SIZE), Vector2(grid_size.x, y * CELL_SIZE), CELL_LINE_COLOR)

	var font: Font = get_theme_default_font()
	for item: ItemInstance in _inventory.get_items():
		var rect: Rect2 = _get_item_rect(_inventory.get_item_position(item), item)
		draw_item(self, rect, item, font, 1.0)
		if item == _hovered_item:
			draw_rect(rect, HOVER_COLOR)

	if _preview_insert_target != null and _inventory.has_item(_preview_insert_target):
		# 插入符文：整件目標物品蓋上綠色，再加一圈外框
		var target_rect: Rect2 = _get_item_rect(
			_inventory.get_item_position(_preview_insert_target), _preview_insert_target
		)
		draw_rect(target_rect, PREVIEW_OK_COLOR)
		draw_rect(
			target_rect.grow(-INSERT_OUTLINE_WIDTH * 0.5),
			INSERT_OUTLINE_COLOR,
			false,
			INSERT_OUTLINE_WIDTH
		)
	elif _preview_item != null:
		var preview_rect: Rect2 = _get_item_rect(_preview_cell, _preview_item)
		draw_rect(preview_rect, PREVIEW_OK_COLOR if _preview_ok else PREVIEW_BLOCKED_COLOR)


func _get_item_rect(cell: Vector2i, item: ItemInstance) -> Rect2:
	return Rect2(Vector2(cell) * CELL_SIZE, Vector2(item.get_size()) * CELL_SIZE)
