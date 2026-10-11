class_name ItemTooltip
extends PanelContainer

# 物品說明框：顯示時跟在滑鼠游標旁邊。

const NAME_FONT_SIZE: int = 16
const LINE_FONT_SIZE: int = 14
const BASE_NAME_COLOR: Color = Color(0.75, 0.75, 0.75, 1.0)
const BASE_STAT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const AFFIX_COLOR: Color = Color(0.55, 0.65, 1.0, 1.0)
const MOUSE_OFFSET: Vector2 = Vector2(18.0, 18.0)
const RUNE_TYPE_TEXT: String = "符文"
const RUNE_WEAPON_HEADER: String = "武器："
const RUNE_ARMOR_HEADER: String = "防具："
# 套裝物品的說明裡，還沒生效的件數詞綴、還沒穿上的套裝成員用這個顏色
const SET_INACTIVE_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)
# 套裝相關的那幾行會多帶 "kind" 與 "active"，kind 是以下其中一種
const LINE_ITEM_BONUS: String = "item_bonus"
const LINE_SET_NAME: String = "set_name"
const LINE_SET_MEMBER: String = "set_member"
const LINE_SET_BONUS: String = "set_bonus"

# 目前顯示的內容，沒有顯示時是空的
var _current_lines: Array[Dictionary] = []

@onready var _lines: VBoxContainer = $Lines


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func _process(_delta: float) -> void:
	if visible:
		_follow_mouse()


# equipment 是玩家身上的裝備，套裝物品用它算件數；不傳時當成什麼都沒穿
func show_item(item: ItemInstance, equipment: Equipment = null) -> void:
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()

	var lines: Array[Dictionary] = build_lines(item, equipment)
	_current_lines = lines
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


# 隱藏說明框並清掉內容。一律用這個，不要直接呼叫 hide()，get_lines() 才不會留著舊內容。
func hide_item() -> void:
	_current_lines = []
	hide()


# 目前顯示的每一行（格式見 build_lines），沒有顯示時回傳空陣列
func get_lines() -> Array[Dictionary]:
	return _current_lines


# 說明框的每一行：{"text": String, "color": Color}。畫面只照這份資料畫，不另外判斷。
# 第一行是名稱（顏色見 ItemInstance.get_display_color()），稀有物品第二行是底材名，
# 接著是底材的傷害或防禦，有孔的物品顯示「插槽 (已插入/孔數)」與已插入的符文名稱，
# 再來是每條詞綴與符文的修正值。
# 符文、符文之語、套裝物品的內容不同，見 _build_rune_lines()、_build_runeword_lines()、
# _build_set_item_lines()。equipment 是玩家身上的裝備，只有套裝物品會用到。
static func build_lines(item: ItemInstance, equipment: Equipment = null) -> Array[Dictionary]:
	if item.is_rune():
		return _build_rune_lines(item)
	if item.is_runeword():
		return _build_runeword_lines(item)
	if item.is_set_item():
		return _build_set_item_lines(item, equipment)

	var lines: Array[Dictionary] = []
	lines.append({"text": item.get_display_name(), "color": item.get_display_color()})
	if item.quality == ItemInstance.QUALITY_RARE:
		lines.append({"text": item.get_base_name(), "color": BASE_NAME_COLOR})

	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	if base.has("damage"):
		var damage: Array = base["damage"]
		lines.append({"text": "傷害：%d–%d" % [int(damage[0]), int(damage[1])], "color": BASE_STAT_COLOR})
	if base.has("defense"):
		lines.append({"text": "防禦：%d" % item.defense, "color": BASE_STAT_COLOR})
	if item.sockets > 0:
		lines.append({
			"text": "插槽 (%d/%d)" % [item.socketed_runes.size(), item.sockets],
			"color": ItemInstance.COLOR_SOCKETED,
		})
		for rune_id: String in item.socketed_runes:
			lines.append({
				"text": str(ItemDatabase.get_rune(rune_id).get("name", rune_id)),
				"color": ItemInstance.COLOR_RUNE,
			})

	# 符文提供的修正值接在詞綴後面，同一個列表一起顯示
	for modifier: Dictionary in item.get_affix_modifiers() + item.get_rune_modifiers():
		lines.append({"text": StatSystem.format_modifier(modifier), "color": AFFIX_COLOR})
	return lines


# 套裝物品的說明，件數一律用 equipment（玩家身上的裝備）計算，物品在背包或裝備欄都一樣：
# - 綠色的名稱、底材名、底材的傷害或防禦
# - 這一件固定的修正值
# - 這一件的件數詞綴：生效時綠色；未生效時灰色，後面加「(N 件)」。
#   要這一件自己穿在身上、而且該套件數達到門檻才算生效。
# - 空一行，接著是套裝名稱
# - 套裝的每一件成員：已穿上綠色，未穿上灰色
# - 套裝的件數加成：每個門檻的每條修正值一行，生效時綠色；未生效時灰色，後面加「(N 件)」
# 後四種的每一行會多帶 "kind"（LINE_ 開頭的常數）與 "active"（是否生效／已穿上）。
static func _build_set_item_lines(item: ItemInstance, equipment: Equipment) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	lines.append({"text": item.get_display_name(), "color": item.get_display_color()})
	lines.append({"text": item.get_base_name(), "color": BASE_NAME_COLOR})

	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	if base.has("damage"):
		var damage: Array = base["damage"]
		lines.append({"text": "傷害：%d–%d" % [int(damage[0]), int(damage[1])], "color": BASE_STAT_COLOR})
	if base.has("defense"):
		lines.append({"text": "防禦：%d" % item.defense, "color": BASE_STAT_COLOR})

	for modifier: Dictionary in item.get_set_item_modifiers():
		lines.append({"text": StatSystem.format_modifier(modifier), "color": AFFIX_COLOR})

	var set_id: String = item.get_set_id()
	var set_data: Dictionary = ItemDatabase.get_set(set_id)
	var equipped_ids: Array = SetBonusCalculator.get_equipped_pieces(equipment).get(set_id, [])
	var piece_count: int = equipped_ids.size()
	# 這一件本身有沒有穿在身上：看的是同一件物品，背包裡另一件一樣的不算
	var is_worn: bool = equipment != null and equipment.get_item(item.get_slot()) == item

	var item_bonuses: Dictionary = ItemDatabase.get_set_item(item.set_item_id).get("set_bonuses", {})
	for threshold: int in SetBonusCalculator.get_thresholds(item_bonuses):
		var is_active: bool = is_worn and piece_count >= threshold
		for modifier: Dictionary in SetBonusCalculator.get_threshold_modifiers(item_bonuses, threshold):
			lines.append(_make_bonus_line(LINE_ITEM_BONUS, modifier, threshold, is_active))

	lines.append({"text": "", "color": BASE_STAT_COLOR})
	lines.append({
		"text": item.get_set_name(),
		"color": ItemInstance.COLOR_SET,
		"kind": LINE_SET_NAME,
		"active": piece_count > 0,
	})

	for member_id: Variant in set_data.get("items", []):
		var is_equipped: bool = equipped_ids.has(member_id)
		lines.append({
			"text": str(ItemDatabase.get_set_item(str(member_id)).get("name", member_id)),
			"color": ItemInstance.COLOR_SET if is_equipped else SET_INACTIVE_COLOR,
			"kind": LINE_SET_MEMBER,
			"active": is_equipped,
		})

	var set_bonuses: Dictionary = set_data.get("bonuses", {})
	for threshold: int in SetBonusCalculator.get_thresholds(set_bonuses):
		for modifier: Dictionary in SetBonusCalculator.get_threshold_modifiers(set_bonuses, threshold):
			lines.append(_make_bonus_line(LINE_SET_BONUS, modifier, threshold, piece_count >= threshold))
	return lines


# 件數詞綴或件數加成的一行：生效時綠色；未生效時灰色，後面加「(N 件)」
static func _make_bonus_line(
	kind: String, modifier: Dictionary, threshold: int, is_active: bool
) -> Dictionary:
	var text: String = StatSystem.format_modifier(modifier)
	if not is_active:
		text += " (%d 件)" % threshold
	return {
		"text": text,
		"color": ItemInstance.COLOR_SET if is_active else SET_INACTIVE_COLOR,
		"kind": kind,
		"active": is_active,
		"threshold": threshold,
	}


# 符文之語的說明：名稱（暗金色）、底材名、以「'符文A 符文B'」列出的符文順序、底材的傷害或防禦，
# 再來是所有修正值（符文各自的效果，接著是符文之語的效果）。
static func _build_runeword_lines(item: ItemInstance) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	lines.append({"text": item.get_display_name(), "color": item.get_display_color()})
	lines.append({"text": item.get_base_name(), "color": BASE_NAME_COLOR})

	var rune_names: Array[String] = []
	for rune_id: String in item.socketed_runes:
		rune_names.append(str(ItemDatabase.get_rune(rune_id).get("name", rune_id)))
	lines.append({"text": "'%s'" % " ".join(rune_names), "color": ItemInstance.COLOR_RUNE})

	var base: Dictionary = ItemDatabase.get_base(item.base_id)
	if base.has("damage"):
		var damage: Array = base["damage"]
		lines.append({"text": "傷害：%d–%d" % [int(damage[0]), int(damage[1])], "color": BASE_STAT_COLOR})
	if base.has("defense"):
		lines.append({"text": "防禦：%d" % item.defense, "color": BASE_STAT_COLOR})

	for modifier: Dictionary in item.get_rune_modifiers() + item.get_runeword_modifiers():
		lines.append({"text": StatSystem.format_modifier(modifier), "color": AFFIX_COLOR})
	return lines


# 符文的說明：名稱、「符文」，接著分成「武器：」與「防具：」兩段，各自列出插在該類裝備上的修正值，
# 兩段之間空一行。
static func _build_rune_lines(item: ItemInstance) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	lines.append({"text": item.get_display_name(), "color": item.get_display_color()})
	lines.append({"text": RUNE_TYPE_TEXT, "color": BASE_NAME_COLOR})

	var rune: Dictionary = ItemDatabase.get_rune(item.rune_id)
	lines.append({"text": RUNE_WEAPON_HEADER, "color": BASE_STAT_COLOR})
	for modifier: Dictionary in rune.get("weapon_mods", []):
		lines.append({"text": StatSystem.format_modifier(modifier), "color": AFFIX_COLOR})

	lines.append({"text": "", "color": BASE_STAT_COLOR})
	lines.append({"text": RUNE_ARMOR_HEADER, "color": BASE_STAT_COLOR})
	for modifier: Dictionary in rune.get("armor_mods", []):
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
