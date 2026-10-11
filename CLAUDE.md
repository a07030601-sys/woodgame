# ARPG 專案規則

## 專案簡介

- 引擎：Godot 4.7.2
- 類型：2D 俯視角、暗黑破壞神 2 風格的單機刷寶 ARPG
- 單人開發、單機遊戲（無連線功能）
- **目前階段：階段 4：裝備與背包**

## 程式語言

- 程式一律使用 GDScript（Godot 4 語法）。
- 變數、參數、回傳值都要加上型別標註。

## 資料驅動

- 物品、詞綴、符文、符文之語、套裝全部用 JSON 資料驅動，放在 `data/`，不寫死在程式裡。
- 符文、符文之語、套裝的名稱一律自創，不沿用既有遊戲的名稱。

## 物品資料

- `data/bases.json`：底材清單（陣列）。每筆的欄位：
  - `id`、`name`、`type`（`sword`、`axe`、`helm`、`armor`、`gloves`、`boots`）
  - `slot`（`weapon`、`helm`、`armor`、`gloves`、`boots`）
  - `size`：背包佔用格數 `[寬, 高]`；`max_sockets`：最大孔數
  - 武器有 `damage`：`[最小, 最大]`；防具有 `defense`：`[最小, 最大]`
- `data/affixes.json`：詞綴清單（陣列）。每筆的欄位：
  - `id`、`name`（寫法見下方「物品命名規則」）
  - `affix_type`（`prefix` 或 `suffix`）、`group`（同一件物品不會出現兩個相同 group 的詞綴）
  - `weight`（出現權重）、`allowed_types`（可出現的底材 `type`）
  - `modifiers`：每筆包含 `stat`、`type`（`flat` 或 `percent`）、`min`、`max`；`stat` 必須在 `StatSystem.STAT_NAMES` 內
- `data/rare_names.json`：`first_words` 是共用的字詞陣列；`second_words` 是「底材 `type` -> 字詞陣列」，每種底材 `type` 都要有一組。
- `data/runes.json`：符文清單（陣列）。每筆的欄位：`id`、`name`、`weapon_mods`、`armor_mods`。後兩者是符文插在武器、防具上各自提供的修正值，格式就是「屬性計算」的修正值（`stat`、`value`、`type`，數值固定不擲骰）。
- `data/runewords.json`：符文之語清單（陣列）。每筆的欄位：`id`、`name`、`runes`（符文 id，有順序）、`allowed_bases`（可用的底材 `type`）、`modifiers`（修正值，格式與符文相同）。只能用 `runes.json` 裡的符文和 `bases.json` 裡的底材類型。
- `data/sets.json`：套裝清單（陣列）。每筆的欄位：`id`、`name`、`items`（套裝物品 id 清單）、`bonuses`（「件數（文字）-> 修正值清單」，例如 `"2"`、`"3"`）。目前只讀取，還沒有計算件數加成。
- `data/set_items.json`：套裝物品清單（陣列）。每筆的欄位：`id`、`name`、`base`（`bases.json` 的底材 id）、`set_id`、`modifiers`（固定的修正值）。載入時 `base` 或 `set_id` 不存在會 `push_error` 並略過；`sets.json` 的 `items` 指到不存在的套裝物品也會 `push_error`。
- `data/item_settings.json`：物品生成的設定。`socket_chance` 是普通品質的物品生成時有孔的機率（百分比）。
- `ItemDatabase`（Autoload）啟動時讀取並檢查以上資料，有問題的那筆會 `push_warning` 並略過。用 `get_base(id)`、`get_affix(id)`、`get_rune(id)`、`get_runeword(id)`、`get_set(id)`、`get_set_item(id)` 查資料，用 `create_item(base_id)` 建立普通物品（沒有孔），用 `create_rune(rune_id)` 建立符文物品，用 `create_set_item(set_item_id)` 建立套裝物品。
- `ItemInstance`（`scripts/items/item_instance.gd`，`RefCounted`）代表一件實際的物品，欄位：`base_id`、`rune_id`、`quality`、`sockets`（孔數）、`socketed_runes`（已插入的符文 id）、`runeword_id`（符文之語 id）、`set_item_id`（套裝物品 id）、`affixes`、`defense`（生成時擲出的防禦值）、`rare_name`（稀有物品的名稱）。
  - 符文也是 `ItemInstance`：`rune_id` 有值、`base_id` 是空的（`is_rune()`），佔 1 × 1 格，沒有裝備欄位，本身不提供修正值。背包、手上的物品、地上物品都走同一套流程，不另外做一套。
  - 底材與詞綴的固定資料不複製進物品，需要時用 id 查 `ItemDatabase`。
  - `affixes` 的每一項是 `{"id": 詞綴 id, "modifiers": [已擲好數值的修正值]}`。
  - 鑲嵌：`can_insert_rune(rune_item)` 在物品還有空孔且對方是符文時為 true；`insert_rune(rune_item)` 把符文 id 加到 `socketed_runes` 的最後並回傳是否成功。符文插入後不能取出。
  - 已插入的符文提供的修正值用 `get_rune_modifiers()` 取得：底材 `slot` 是 `weapon` 時用符文的 `weapon_mods`，其他都用 `armor_mods`。
  - 符文之語：孔全部插滿的那一下，`insert_rune()` 會用 `RunewordMatcher.find_match()`（`scripts/items/runeword_matcher.gd`）比對一次，成功就記下 `runeword_id`（`is_runeword()`）。全部符合才成功：物品是普通品質、孔數等於配方的符文數量、符文順序完全一致、底材 `type` 在 `allowed_bases` 裡。符文之語的修正值用 `get_runeword_modifiers()` 取得，與符文各自的效果疊加。
  - 套裝物品：品質是 `set`，`set_item_id` 有值（`is_set_item()`）。內容完全固定：沒有詞綴、孔數一律 0、防禦值取底材的最大值，同一件每次建立都相同。該件固定的修正值用 `get_set_item_modifiers()` 取得，所屬套裝用 `get_set_id()` / `get_set_name()`。
  - `get_modifiers()` 回傳物品的所有修正值（底材、詞綴、已插入的符文、符文之語、套裝物品本身的修正值；不含套裝的件數加成）；`to_dict()` / `ItemInstance.from_dict()` 用於存檔與還原。
  - `get_display_name()` 依下方命名規則組出名稱；`get_base_name()` 回傳底材名（符文回傳符文名）。`get_quality_color()`：普通白、魔法藍、稀有黃、套裝綠。套裝物品的 `get_display_name()` 是該件套裝物品的名稱。
  - 介面上顯示物品（名稱文字、背包裡的邊框）一律用 `get_display_color()`：符文橘色、符文之語暗金色、有孔的普通物品灰色，其餘是品質顏色。符文之語的 `get_display_name()` 是符文之語的名稱，不含底材名。
- `ItemGenerator.generate(base_id, quality, rng)`（`scripts/items/item_generator.gd`）依品質生成物品，所有隨機都來自傳入的 `rng`：
  - `normal`：沒有詞綴。依 `socket_chance` 決定有沒有孔，有孔時孔數在 1 到底材 `max_sockets` 之間。
  - `magic`：最多 1 個前綴加 1 個後綴，至少 1 個。一律 0 孔。
  - `rare`：3～4 個詞綴，前綴與後綴各最多 2 個。一律 0 孔。
  - `set` 不在這裡生成，套裝物品一律用 `ItemDatabase.create_set_item()` 建立。
  - 詞綴依 `weight` 抽選，只選 `allowed_types` 符合的，同一件物品不重複 `group`；每條修正值在 `min` 到 `max` 之間擲出整數。

- `Inventory`（`scripts/items/inventory.gd`，`RefCounted`）是背包的格子資料，不含介面，預設 10 × 4。
  - 物品依底材的 `size` 佔用格子；位置指物品左上角那一格，x 往右、y 往下，從 0 開始。
  - 同一件物品只會有一個位置，對已在背包裡的物品呼叫 `place()` 等於移動它。
  - `find_free_position()` 從左上角開始，先往下再往右找。
  - `place_or_swap()` 回傳 `{"success": bool, "swapped_item": ItemInstance}`：壓到一件時互換，壓到兩件以上或超出範圍時失敗。
  - 內容改變時發出 `changed`；`to_dict()` / `Inventory.from_dict()` 包含每件物品與位置。

## 裝備

- `Equipment`（`scripts/items/equipment.gd`，`RefCounted`）是裝備欄資料，欄位為 `Equipment.SLOTS`：`weapon`、`helm`、`armor`、`gloves`、`boots`。
  - 物品底材的 `slot` 與欄位相符才能穿（`can_equip()`）。
  - `equip()` 回傳 `{"success": bool, "swapped_item": ItemInstance}`，與 `Inventory.place_or_swap()` 相同；`unequip()` 回傳脫下的物品。
  - 變動時發出 `equipment_changed(slot)`；`to_dict()` / `Equipment.from_dict()` 用於存檔與還原。
- 玩家擁有一個 `Equipment`（`Player.get_equipment()`）。裝備變動時，該欄位有物品就對屬性元件 `add_source("equip_" + 欄位名, 物品的 get_modifiers())`，空了就 `remove_source`。
- 玩家空手的基礎傷害是 1～2，武器的傷害以 flat 修正值加在上面。`Player.starting_equipment`（底材 id 清單）決定開場自動穿上的普通裝備，預設是一把短劍。
- 除錯用的開關（預設都關閉）：`Player.debug_start_items` 開場在背包放幾件隨機的魔法與稀有裝備；`Player.debug_runeword_kit` 開場在背包放入能湊出每一組符文之語的底材（孔數剛好）和需要的符文；`Player.debug_set_kit` 開場在背包放入每一套套裝的全部套裝物品。

## 背包介面

- 玩家擁有一個 `Inventory`（`Player.get_inventory()`）。`toggle_inventory`（I 鍵）開關背包畫面，遊戲不暫停。
- `scenes/ui/inventory_screen.tscn`（`InventoryScreen`）由幾個獨立的部分組成，腳本都在 `scripts/ui/`：
  - `InventoryGrid`：背包格子的顯示與點擊，每格 `CELL_SIZE` 像素。資料仍在 `Inventory`，格子只負責畫面。
  - `ItemTooltip`：物品說明框，內容由 `ItemTooltip.build_lines(item)` 產生。有孔的物品顯示「插槽 (已插入/孔數)」，接著列出已插入的符文名稱，符文的修正值接在詞綴修正值後面一起顯示；符文分成「武器：」與「防具：」兩段，各自列出修正值；符文之語依序顯示名稱、底材名、「'符文A 符文B'」、底材的傷害或防禦、所有修正值；套裝物品依序顯示綠色的名稱、底材名、底材的傷害或防禦、修正值，最後一行是綠色的套裝名稱。
  - `EquipmentPanel`：面板上方的 5 個裝備欄，排列參考暗黑 2（頭盔在上方中間，身體護甲在中間，武器在左側，手套在左下，靴子在右下）。欄位位置定義在 `EquipmentPanel.SLOT_RECTS`。
  - 格子和裝備欄的預覽狀態都要「自己記住是為哪件物品算的」，並在資料一變動時立刻重算，不能等到 `_draw` 才去讀手上的物品。
- `HeldItem`（`scenes/ui/held_item.tscn`）是「手上拿著的物品」，同一時間最多一件，跟著游標移動。它不屬於背包，也不屬於背包畫面：放在自己的 `CanvasLayer`（layer 100），永遠畫在最上層。背包格子、裝備欄和丟到地上都共用這一個，用群組 `HeldItem.GROUP` 找到它，用 `hold()` / `take()` 存取。
- 手上的物品以中心對準游標；放下時用 `InventoryGrid.get_drop_cell()` 換算左上角的格子。
- 鑲嵌符文：手上拿著符文、點背包裡還有空孔的物品時插入，手上的符文消失（`InventoryGrid.get_insert_target_at()` 判斷）；預覽是蓋住整件目標物品的綠色加一圈外框。不能插入時照一般的放置或互換處理。只支援背包裡的物品，裝備欄上的物品不能插。
- 關閉背包時手上的物品留在游標上，不會自動放回背包。
- 手上有物品時點遊戲世界，會把物品丟在角色腳邊變成地上物品（`Player.drop_held_item()`），角色不移動也不攻擊。
- 會擋住遊戲世界滑鼠操作的介面要加入群組 `world_input_blockers`，並提供 `is_blocking_world_input() -> bool`。玩家在點擊和按住左鍵跟隨游標時都會檢查，回傳 true 就不移動也不攻擊。
- 屬性的中文名稱在 `StatSystem.STAT_DISPLAY_NAMES`；修正值轉成文字一律用 `StatSystem.format_modifier()`（例如「+5 力量」「+12% 攻擊速度」）。

## 掉寶與撿取

- `data/drop_tables.json`：「掉落表 id -> 掉落表」，目前只有 `default`。每張表的欄位：
  - `drop_chance`：掉落機率，以百分比表示（`40` 代表 40%）。
  - `quality_weights`：「品質 -> 權重」，品質是 `normal`、`magic`、`rare`、`set`，權重為 0 或沒列出的品質不會出現。
  - `rune_weight`：掉出符文的權重，與品質權重一起比；可以省略，省略或為 0 時不掉符文。
  - 由 `ItemDatabase` 讀取與檢查，用 `get_drop_table(id)` 查詢；機率與權重不寫死在程式裡。
- `DropRoller.roll(table_id, rng)`（`scripts/items/drop_roller.gd`）擲一次掉落，沒掉落時回傳 null；所有隨機都來自傳入的 `rng`。掉出裝備時底材從所有底材平均抽選，再交給 `ItemGenerator.generate()`；擲到 `set` 時從所有套裝物品平均抽一件；掉出符文時從所有符文平均抽一顆。
- 怪物死亡時用 `Monster.drop_table_id`（預設 `default`）擲骰，掉落的物品放在死亡位置附近。
- `GroundItem`（`scenes/ground_item.tscn`）是地上物品：以品質顏色顯示物品名稱，滑鼠滑過時變亮。用 `GroundItem.spawn(parent, item, 位置)` 建立，加到主場景底下；它只負責顯示，點擊與撿取都由 `Player` 處理。
- 點擊地上物品時角色走過去（`Player.move_to_pick_up()`），抵達後呼叫 `Player.pick_up()`：`add_item_auto` 成功就從地上移除；背包滿了就留在地上，並發出 `Player.inventory_full`。
- `ScreenMessage`（`scenes/ui/screen_message.tscn`）是畫面上方的短暫提示文字，收到 `inventory_full` 時顯示「背包已滿」。

## 物品命名規則

中文的修飾語放在名詞前面，底材名一律在最後。新增詞綴與字詞時都要遵守：

- **前綴**：不帶「的」的兩字形容詞，例如「鋒銳」「堅韌」。
- **後綴**：「〇〇之」的形式，例如「磐根之」「掠風之」。
- **魔法物品名稱**＝後綴 + 前綴 + 底材名，三段直接相接：
  - 兩者都有：「掠風之裂骨手斧」；只有前綴：「裂骨手斧」；只有後綴：「掠風之手斧」。
  - 任何後綴配任何前綴都要念得順，命名時要把各種組合念過一遍。
- **稀有物品名稱**＝第一段 + 第二段，不含底材名，例如「霜痕之握」：
  - 第一段是共用的氣氛字詞（`first_words`），例如「灰燼」「霜痕」。
  - 第二段是「之〇」的形式，依底材 `type` 從對應的字詞表選（`second_words`），要能讓人聯想到該部位，例如手套用「之握」、頭盔用「之冠」。
  - 不同 `type` 的第二段字詞不要重複。
  - 物品說明框會在名稱的下一行另外顯示底材名（`get_base_name()`）。
- 詞綴與稀有字詞的名稱一律自創。

## 屬性計算

- 所有屬性加成一律轉成修正值：`{"stat": String, "value": float, "type": String}`。
- `type` 只有 `flat` 或 `percent` 兩種。
- `percent` 的 `value` 以百分比表示：`20` 代表 +20%，不是 `0.2`。
- 由 StatSystem 統一計算（`StatSystem.calculate(base_stats, modifiers)`），每個屬性的公式為：

  ```
  最終值 = （基礎值 + 所有 flat 總和）×（1 + 所有 percent 總和 ÷ 100）
  ```

- StatSystem 只負責計算，不保存任何角色的資料；內部用 float 計算，不四捨五入，要取整由使用端決定。
- 目前支援的屬性名稱（定義在 `StatSystem.STAT_NAMES`，新增屬性時兩邊都要更新）：
  `strength`、`vitality`、`life`、`damage_min`、`damage_max`、`attack_speed`、`move_speed`、`defense`
- 主屬性的衍生效果（比例是 StatSystem 的常數）。先算出 `strength` 與 `vitality` 的最終值，再用來計算：
  - 每點 `strength` 讓 `damage_min` 與 `damage_max` 各 +1%，併入這兩個屬性的 percent 總和（`STRENGTH_DAMAGE_PERCENT_PER_POINT = 1.0`）。
  - 每點 `vitality` 讓 `life` +3，併入 `life` 的 flat 總和（`VITALITY_LIFE_PER_POINT = 3.0`）。
- `attack_speed` 定義為「每秒攻擊次數」，攻擊間隔（秒）= 1 ÷ `attack_speed`。
- 角色用 `StatsComponent`（`scripts/components/stats_component.gd`）保存基礎屬性與按來源分組的修正值，最終值用 `get_stat()` 讀取；裝備等加成用 `add_source()` / `remove_source()` 加入與移除。
- 屬性名稱不在清單內、`type` 不合法或缺少欄位的修正值，會用 `push_warning` 警告並忽略。

## 全域資料

- 全域資料使用 Autoload：`ItemDatabase`、`StatSystem`，腳本放在 `scripts/autoload/`。

## 工作流程

- 每次只做一個小功能，不主動加入沒要求的功能。
- 完成後用繁體中文說明如何在 Godot 裡測試。
- **每次修改程式後，先用 headless 執行全部測試，全部通過才回報；有 FAIL 時先自行修正。**

## 測試

- 測試腳本放在 `scripts/tests/`，繼承 `TestBase`（`scripts/tests/test_base.gd`），覆寫 `_get_test_name()` 與 `_run_tests()`，用 `check(名稱, 條件, 失敗說明)` 記錄每一項。
- 測試場景放在 `scenes/tests/`，檔名以 `_test.tscn` 結尾就會被 `run_all_tests` 自動找到並執行。
- 在專案根目錄用 headless 執行全部測試（Godot 命令列執行檔在 `C:\Godot_v4.7.2-stable_win64_console.exe`）：

  ```
  C:\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
  C:\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/tests/run_all_tests.tscn
  ```

  - 第一行讓 Godot 重新掃描專案。新增或改名 `class_name`、新增檔案之後一定要先跑，否則腳本會找不到新類別而解析失敗。
  - 第二行執行測試，最後印出每個測試與總計的 PASS、FAIL 數量。全部通過時結束碼為 0，有任何 FAIL 時為 1。
  - 腳本解析失敗時測試不會自己結束，執行時要加上逾時；看到輸出有「總計：」且結束碼為 0 才算通過。
- 單獨執行一個測試：在編輯器開啟該場景按 F6，或用
  `C:\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://scenes/tests/<名稱>_test.tscn --quit-after 5`。
- 需要滑鼠操作或看畫面的項目無法用 headless 驗證，仍要由使用者在編輯器裡測試。
- 等使用者測試確認後才 commit，不要自動 commit。

## 待辦（暫不實作）

- 獨特物品（階段 7）
- 防禦的減傷公式（階段 7）
- 物品等級與詞綴等級需求（階段 7）

## 資料夾結構

```
res://
├── scenes/              場景檔（.tscn），主場景為 scenes/main.tscn
│   ├── ui/              介面場景（傷害數字、屬性面板等）
│   └── tests/           測試場景（*_test.tscn）與 run_all_tests.tscn
├── scripts/
│   ├── autoload/        Autoload 單例（ItemDatabase、StatSystem）
│   ├── components/      可重複使用的元件（血量元件、屬性元件、血條等）
│   ├── player/          玩家相關腳本
│   ├── monsters/        怪物相關腳本
│   ├── items/           物品相關腳本
│   ├── ui/              介面相關腳本
│   └── tests/           測試腳本
├── data/                JSON 資料（物品、詞綴、符文、符文之語、套裝）
├── assets/              美術、音效等素材
├── project.godot
└── CLAUDE.md
```
