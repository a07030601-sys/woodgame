class_name InventoryScreen
extends CanvasLayer

# 背包畫面：右側面板（上方是裝備欄、下方是背包格子）與物品說明框。
# 手上拿著的物品（HeldItem）是獨立的一層，不屬於這個畫面，關閉背包時它會留在游標上。
# 開啟時遊戲不暫停。

# 加入這個群組的節點可以用 is_blocking_world_input() 阻止玩家用滑鼠移動或攻擊
const WORLD_INPUT_BLOCKERS_GROUP: String = "world_input_blockers"

var _held: HeldItem = null
# 玩家身上的裝備，套裝物品的說明框用它算件數
var _equipment: Equipment = null

@onready var _panel: PanelContainer = $Panel
@onready var _equipment_panel: EquipmentPanel = $Panel/Margin/VBox/EquipmentPanel
@onready var _grid: InventoryGrid = $Panel/Margin/VBox/Grid
@onready var _tooltip: ItemTooltip = $Tooltip


func _ready() -> void:
	add_to_group(WORLD_INPUT_BLOCKERS_GROUP)
	hide()
	_grid.hovered_item_changed.connect(_on_hovered_item_changed)
	_equipment_panel.hovered_item_changed.connect(_on_hovered_item_changed)

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var held: HeldItem = get_tree().get_first_node_in_group(HeldItem.GROUP) as HeldItem
	if held == null:
		push_warning("InventoryScreen：找不到 %s 群組的 HeldItem" % HeldItem.GROUP)
		return
	setup(player.get_inventory(), player.get_equipment(), held)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()


func setup(inventory: Inventory, equipment: Equipment, held: HeldItem) -> void:
	_held = held
	_held.changed.connect(_on_held_changed)
	_equipment = equipment
	_equipment.equipment_changed.connect(_on_equipment_changed)
	_grid.setup(inventory, held)
	_equipment_panel.setup(equipment, held)


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	show()


# 手上的物品不受影響，會繼續留在游標上
func close() -> void:
	_tooltip.hide_item()
	hide()


func get_grid() -> InventoryGrid:
	return _grid


func get_equipment_panel() -> EquipmentPanel:
	return _equipment_panel


func get_tooltip() -> ItemTooltip:
	return _tooltip


# 背包開著且滑鼠在面板上時，玩家不能用滑鼠移動或攻擊
func is_blocking_world_input() -> bool:
	if not visible:
		return false
	return _panel.get_global_rect().has_point(get_viewport().get_mouse_position())


# 依目前滑鼠底下的物品重建說明框。背包格子與裝備欄同一時間最多只有一邊有物品；
# 手上拿著物品時不顯示。內容每次都重新產生，裝備變動後件數才會是新的。
func _refresh_tooltip() -> void:
	var item: ItemInstance = _grid.get_hovered_item()
	if item == null:
		item = _equipment_panel.get_hovered_item()

	if item != null and not _held.is_holding():
		_tooltip.show_item(item, _equipment)
	else:
		_tooltip.hide_item()


# 背包格子或裝備欄的滑鼠底下物品改變時都會呼叫
func _on_hovered_item_changed(_item: ItemInstance) -> void:
	_refresh_tooltip()


func _on_held_changed() -> void:
	_refresh_tooltip()


# 裝備一變動，正在顯示的說明框就要立刻更新（套裝的件數、已穿上的成員都可能不同）
func _on_equipment_changed(_slot: String) -> void:
	_refresh_tooltip()
