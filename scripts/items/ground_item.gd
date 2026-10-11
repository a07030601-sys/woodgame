class_name GroundItem
extends Node2D

# 掉在地上的物品：以品質顏色顯示物品名稱，滑鼠滑過時變亮。
# 點擊、走過去與撿取都由 Player 處理，這裡只負責顯示，以及回答「這個位置有沒有點到我」。

const GROUP: String = "ground_items"
const SCENE_PATH: String = "res://scenes/ground_item.tscn"
# 滑鼠滑過時文字往白色靠近的比例
const HOVER_LIGHTEN: float = 0.5
const BACKGROUND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.65)
# 普通物品的文字本來就是白色，所以滑過時底色也一起變亮
const HOVER_BACKGROUND_COLOR: Color = Color(0.28, 0.28, 0.4, 0.9)

var item: ItemInstance = null

var _is_hovered: bool = false
var _background: StyleBoxFlat = StyleBoxFlat.new()

@onready var _label: Label = $Label


func _ready() -> void:
	_background.set_content_margin_all(2.0)
	_background.content_margin_left = 6.0
	_background.content_margin_right = 6.0
	_label.add_theme_stylebox_override("normal", _background)
	_refresh()


# 在 parent 底下建立一件地上物品，world_position 是名稱文字的中心點
static func spawn(parent: Node, new_item: ItemInstance, world_position: Vector2) -> GroundItem:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	var ground_item: GroundItem = scene.instantiate() as GroundItem
	ground_item.item = new_item
	parent.add_child(ground_item)
	ground_item.global_position = world_position
	return ground_item


# world_point 底下的地上物品；名稱疊在一起時回傳畫在最上面的那件，沒有就回傳 null
static func find_at(tree: SceneTree, world_point: Vector2) -> GroundItem:
	var nodes: Array[Node] = tree.get_nodes_in_group(GROUP)
	for index: int in range(nodes.size() - 1, -1, -1):
		var ground_item: GroundItem = nodes[index] as GroundItem
		if (
			ground_item != null
			and not ground_item.is_queued_for_deletion()
			and ground_item.contains_point(world_point)
		):
			return ground_item
	return null


# world_point 是否落在名稱文字的範圍內
func contains_point(world_point: Vector2) -> bool:
	if not is_node_ready():
		return false
	return Rect2(_label.position, _label.size).has_point(to_local(world_point))


func is_hovered() -> bool:
	return _is_hovered


func set_hovered(hovered: bool) -> void:
	if hovered == _is_hovered:
		return
	_is_hovered = hovered
	_refresh()


func _refresh() -> void:
	if item == null:
		return

	var color: Color = item.get_display_color()
	_label.text = item.get_display_name()
	_label.add_theme_color_override(
		"font_color", color.lightened(HOVER_LIGHTEN) if _is_hovered else color
	)
	_background.bg_color = HOVER_BACKGROUND_COLOR if _is_hovered else BACKGROUND_COLOR
	# 文字的中心對準節點位置
	_label.reset_size()
	_label.position = -_label.size * 0.5
