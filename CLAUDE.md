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
- `ItemDatabase`（Autoload）啟動時讀取並檢查以上資料，有問題的那筆會 `push_warning` 並略過。用 `get_base(id)`、`get_affix(id)` 查資料，用 `create_item(base_id)` 建立普通物品。
- `ItemInstance`（`scripts/items/item_instance.gd`，`RefCounted`）代表一件實際的物品，欄位：`base_id`、`quality`、`sockets`、`socketed_runes`、`affixes`、`defense`（生成時擲出的防禦值）、`rare_name`（稀有物品的名稱）。
  - 底材與詞綴的固定資料不複製進物品，需要時用 id 查 `ItemDatabase`。
  - `affixes` 的每一項是 `{"id": 詞綴 id, "modifiers": [已擲好數值的修正值]}`。
  - `get_modifiers()` 回傳物品的所有修正值；`to_dict()` / `ItemInstance.from_dict()` 用於存檔與還原。
  - `get_display_name()` 依下方命名規則組出名稱；`get_base_name()` 回傳底材名。`get_quality_color()`：普通白、魔法藍、稀有黃。
- `ItemGenerator.generate(base_id, quality, rng)`（`scripts/items/item_generator.gd`）依品質生成物品，所有隨機都來自傳入的 `rng`：
  - `normal`：沒有詞綴。
  - `magic`：最多 1 個前綴加 1 個後綴，至少 1 個。
  - `rare`：3～4 個詞綴，前綴與後綴各最多 2 個。
  - 詞綴依 `weight` 抽選，只選 `allowed_types` 符合的，同一件物品不重複 `group`；每條修正值在 `min` 到 `max` 之間擲出整數。

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
