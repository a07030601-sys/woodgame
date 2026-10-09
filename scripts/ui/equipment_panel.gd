class_name EquipmentPanel
extends Control

# 裝備欄的顯示與滑鼠操作。資料在 Equipment，手上的物品在 HeldItem，這裡只負責畫面與點擊。
# 排列參考暗黑 2：頭盔在上方中間，身體護甲在中間，武器在左側，手套在左下，靴子在右下。

signal hovered_item_changed(item: ItemInstance)

const PANEL_SIZE: Vector2 = Vector2(400.0, 232.0)
# 欄位名 -> 欄位在面板上的範圍（本地座標）。每格與背包格子一樣是 40 像素。
const SLOT_RECTS: Dictionary = {
	"helm": Rect2(160.0, 8.0, 80.0, 80.0),
	"armor": Rect2(160.0, 96.0, 80.0, 120.0),
	"weapon": Rect2(40.0, 16.0, 80.0, 120.0),
	"gloves": Rect2(40.0, 144.0, 80.0, 80.0),
	"boots": Rect2(280.0, 144.0, 80.0, 80.0),
}
# 空欄位上顯示的名稱
const SLOT_LABELS: Dictionary = {
	"weapon": "武器",
	"helm": "頭盔",
	"armor": "護甲",
	"gloves": "手套",
	"boots": "靴子",
}
const LABEL_FONT_SIZE: int = 12
const BACKGROUND_COLOR: Color = Color(0.13, 0.13, 0.15, 1.0)
const SLOT_COLOR: Color = Color(0.1, 0.1, 0.12, 1.0)
const SLOT_LINE_COLOR: Color = Color(0.3, 0.3, 0.34, 1.0)
const SLOT_LABEL_COLOR: Color = Color(0.45, 0.45, 0.5, 1.0)

var _equipment: Equipment = null
var _held: HeldItem = null
# 手上沒東西時，滑鼠底下那個欄位裡的物品
var _hovered_item: ItemInstance = null
# 預覽顯示在哪個欄位、是為哪一件物品算的；_preview_item 為 null 代表不顯示預覽。
# 與背包格子一樣，預覽狀態自己記住物品，不在 _draw 時才去讀手上的物品。
var _preview_slot: String = ""
var _preview_item: ItemInstance = null
var _preview_ok: bool = false


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	visibility_changed.connect(_refresh_hover)


func setup(equipment: Equipment, held: HeldItem) -> void:
	_equipment = equipment
	_held = held
	_equipment.equipment_changed.connect(_on_equipment_changed)
	_held.changed.connect(_on_data_changed)
	_on_data_changed()


func _process(_delta: float) -> void:
	_refresh_hover()


func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		click_at(mouse_event.position)
		accept_event()


# local_position 落在哪個欄位上，不在任何欄位上時回傳空字串
func get_slot_at(local_position: Vector2) -> String:
	for slot: String in SLOT_RECTS:
		var rect: Rect2 = SLOT_RECTS[slot]
		if rect.has_point(local_position):
			return slot
	return ""


# 欄位的中心點（本地座標）
func get_slot_center(slot: String) -> Vector2:
	var rect: Rect2 = SLOT_RECTS[slot]
	return rect.get_center()


func get_preview_item() -> ItemInstance:
	return _preview_item


func get_hovered_item() -> ItemInstance:
	return _hovered_item


# 處理在 local_position 的一次左鍵點擊：
# 手上有物品時穿上，換下來的物品變成手上的物品；手上沒東西時脫下該欄位的裝備拿到手上。
func click_at(local_position: Vector2) -> void:
	if _equipment == null:
		return
	var slot: String = get_slot_at(local_position)
	if slot.is_empty():
		return

	if _held.is_holding():
		var result: Dictionary = _equipment.equip(_held.item, slot)
		if result["success"]:
			_held.hold(result["swapped_item"])
	else:
		var item: ItemInstance = _equipment.unequip(slot)
		if item != null:
			_held.hold(item)


func _on_equipment_changed(_slot: String) -> void:
	_on_data_changed()


# 裝備或手上的物品一變就立刻重算，不等下一次 _process（原因見 InventoryGrid）
func _on_data_changed() -> void:
	_refresh_hover()
	queue_redraw()


func _refresh_hover() -> void:
	if _equipment == null:
		return

	var hovered_item: ItemInstance = null
	var preview_slot: String = ""
	var preview_item: ItemInstance = null
	var preview_ok: bool = false

	# 畫面沒顯示時一律清空
	if is_visible_in_tree():
		var slot: String = get_slot_at(get_local_mouse_position())
		if not slot.is_empty():
			if _held.is_holding():
				preview_slot = slot
				preview_item = _held.item
				preview_ok = _equipment.can_equip(preview_item, slot)
			else:
				hovered_item = _equipment.get_item(slot)

	if (
		preview_slot != _preview_slot
		or preview_item != _preview_item
		or preview_ok != _preview_ok
	):
		_preview_slot = preview_slot
		_preview_item = preview_item
		_preview_ok = preview_ok
		queue_redraw()

	if hovered_item != _hovered_item:
		_hovered_item = hovered_item
		queue_redraw()
		hovered_item_changed.emit(_hovered_item)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	if _equipment == null:
		return

	var font: Font = get_theme_default_font()
	for slot: String in SLOT_RECTS:
		var slot_rect: Rect2 = SLOT_RECTS[slot]
		draw_rect(slot_rect, SLOT_COLOR)
		draw_rect(slot_rect, SLOT_LINE_COLOR, false, 1.0)

		var item: ItemInstance = _equipment.get_item(slot)
		if item == null:
			_draw_slot_label(font, slot_rect, SLOT_LABELS[slot])
		else:
			# 物品依自己的格數大小畫在欄位中央
			var item_size: Vector2 = Vector2(item.get_size()) * InventoryGrid.CELL_SIZE
			var item_rect: Rect2 = Rect2(slot_rect.get_center() - item_size * 0.5, item_size)
			InventoryGrid.draw_item(self, item_rect, item, font, 1.0)
			if item == _hovered_item:
				draw_rect(item_rect, InventoryGrid.HOVER_COLOR)

	if _preview_item != null:
		var preview_rect: Rect2 = SLOT_RECTS[_preview_slot]
		draw_rect(
			preview_rect,
			InventoryGrid.PREVIEW_OK_COLOR if _preview_ok else InventoryGrid.PREVIEW_BLOCKED_COLOR
		)


func _draw_slot_label(font: Font, slot_rect: Rect2, text: String) -> void:
	var baseline_y: float = (
		slot_rect.position.y
		+ (slot_rect.size.y - font.get_height(LABEL_FONT_SIZE)) * 0.5
		+ font.get_ascent(LABEL_FONT_SIZE)
	)
	draw_string(
		font,
		Vector2(slot_rect.position.x, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		slot_rect.size.x,
		LABEL_FONT_SIZE,
		SLOT_LABEL_COLOR
	)
