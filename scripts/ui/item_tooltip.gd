class_name ItemTooltip
extends PanelContainer

# 物品說明框：顯示時跟在滑鼠游標旁邊。

const NAME_FONT_SIZE: int = 16
const LINE_FONT_SIZE: int = 14
const BASE_NAME_COLOR: Color = Color(0.75, 0.75, 0.75, 1.0)
const BASE_STAT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const AFFIX_COLOR: Color = Color(0.55, 0.65, 1.0, 1.0)
const MOUSE_OFFSET: Vector2 = Vector2(18.0, 18.0)

@onready var _lines: VBoxContainer = $Lines


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	if visible:
		_follow_mouse()


func show_item(item: ItemInstance) -> void:
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()

	var lines: Array[Dictionary] = build_lines(item)
	for index: int in lines.size():
		var label: Label = Label.new()
		label.text = lines[index]["text"]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", lines[index]["color"])
		label.add_theme_font_size_override("font_size", NAME_FONT_SIZE if index == 0 else LINE_FONT_SIZE)
		_lines.add_child(label)

	show()
	# 內容變少時讓外框縮回剛好的大小
	reset_size()
	_follow_mouse()


# 說明框的每一行：{"text": String, "color": Color}。
# 第一行是名稱（品質顏色），稀有物品第二行是底材名，接著是底材的傷害或防禦，再來是每條詞綴修正值。
static func build_lines(item: ItemInstance) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	lines.append({"text": item.get_display_name(), "color": item.get_quality_color()})
	if item.quality == ItemInstance.QUALITY_RARE:
		lines.append({"text": item.get_base_name(), "color": BASE_NAME_COLOR})

	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	if base.has("damage"):
		var damage: Array = base["damage"]
		lines.append({"text": "傷害：%d–%d" % [int(damage[0]), int(damage[1])], "color": BASE_STAT_COLOR})
	if base.has("defense"):
		lines.append({"text": "防禦：%d" % item.defense, "color": BASE_STAT_COLOR})

	for modifier: Dictionary in item.get_affix_modifiers():
		lines.append({"text": StatSystem.format_modifier(modifier), "color": AFFIX_COLOR})
	return lines


# 放在游標右下方；會超出畫面時改放到另一側
func _follow_mouse() -> void:
	if not is_inside_tree():
		return
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport_rect().size
	var target: Vector2 = mouse_position + MOUSE_OFFSET
	if target.x + size.x > viewport_size.x:
		target.x = mouse_position.x - MOUSE_OFFSET.x - size.x
	if target.y + size.y > viewport_size.y:
		target.y = mouse_position.y - MOUSE_OFFSET.y - size.y
	position = Vector2(maxf(target.x, 0.0), maxf(target.y, 0.0))
