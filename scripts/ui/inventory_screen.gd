class_name InventoryScreen
extends CanvasLayer

# 背包畫面：右側面板（上方預留裝備欄、下方是背包格子）、手上拿著的物品、物品說明框。
# 開啟時遊戲不暫停。

# 加入這個群組的節點可以用 is_blocking_world_input() 阻止玩家用滑鼠移動或攻擊
const WORLD_INPUT_BLOCKERS_GROUP: String = "world_input_blockers"
const FULL_MESSAGE: String = "背包已滿，手上的物品放不回去"

var _inventory: Inventory = null

@onready var _panel: PanelContainer = $Panel
@onready var _grid: InventoryGrid = $Panel/Margin/VBox/Grid
@onready var _message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var _message_timer: Timer = $MessageTimer
@onready var _held: HeldItem = $HeldItem
@onready var _tooltip: ItemTooltip = $Tooltip


func _ready() -> void:
	add_to_group(WORLD_INPUT_BLOCKERS_GROUP)
	hide()
	_message_label.text = ""
	_message_timer.timeout.connect(_on_message_timer_timeout)
	_grid.hovered_item_changed.connect(_on_hovered_item_changed)
	_held.changed.connect(_on_held_changed)

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player != null:
		setup(player.get_inventory())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()
		get_viewport().set_input_as_handled()


func setup(inventory: Inventory) -> void:
	_inventory = inventory
	_grid.setup(inventory, _held)


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	show()


# 手上有物品時會先自動放回背包空位；放不下時不關閉並顯示提示，回傳 false
func close() -> bool:
	if _held.is_holding():
		if _inventory == null or not _inventory.add_item_auto(_held.item):
			_show_message(FULL_MESSAGE)
			return false
		_held.take()

	_tooltip.hide()
	hide()
	return true


func get_held_item() -> HeldItem:
	return _held


func get_grid() -> InventoryGrid:
	return _grid


func get_message() -> String:
	return _message_label.text


# 背包開著時，滑鼠在面板上或手上有物品，玩家都不能用滑鼠移動或攻擊
func is_blocking_world_input() -> bool:
	if not visible:
		return false
	if _held.is_holding():
		return true
	return _panel.get_global_rect().has_point(get_viewport().get_mouse_position())


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_timer.start()


func _on_message_timer_timeout() -> void:
	_message_label.text = ""


func _on_hovered_item_changed(item: ItemInstance) -> void:
	if item != null and not _held.is_holding():
		_tooltip.show_item(item)
	else:
		_tooltip.hide()


func _on_held_changed() -> void:
	if _held.is_holding():
		_tooltip.hide()
