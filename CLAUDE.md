# ARPG 專案規則

## 專案簡介

- 引擎：Godot 4.7.2
- 類型：2D 俯視角、暗黑破壞神 2 風格的單機刷寶 ARPG
- 單人開發、單機遊戲（無連線功能）
- **目前階段：階段 2：怪物 AI 與重生**

## 程式語言

- 程式一律使用 GDScript（Godot 4 語法）。
- 變數、參數、回傳值都要加上型別標註。

## 資料驅動

- 物品、詞綴、符文、符文之語、套裝全部用 JSON 資料驅動，放在 `data/`，不寫死在程式裡。
- 符文、符文之語、套裝的名稱一律自創，不沿用既有遊戲的名稱。

## 屬性計算

- 所有屬性加成一律轉成修正值：`{"stat", "value", "type"}`。
- `type` 只有 `flat` 或 `percent` 兩種。
- 由 StatSystem 統一計算，公式為：

  ```
  最終值 = （基礎值 + 所有 flat）×（1 + 所有 percent 總和）
  ```

## 全域資料

- 全域資料使用 Autoload：`ItemDatabase`、`StatSystem`，腳本放在 `scripts/autoload/`。

## 工作流程

- 每次只做一個小功能，不主動加入沒要求的功能。
- 完成後用繁體中文說明如何在 Godot 裡測試。
- 等使用者測試確認後才 commit，不要自動 commit。

## 資料夾結構

```
res://
├── scenes/              場景檔（.tscn），主場景為 scenes/main.tscn
│   └── ui/              介面場景（傷害數字等）
├── scripts/
│   ├── autoload/        Autoload 單例（ItemDatabase、StatSystem）
│   ├── components/      可重複使用的元件（血量元件、血條等）
│   ├── player/          玩家相關腳本
│   ├── monsters/        怪物相關腳本
│   ├── items/           物品相關腳本
│   └── ui/              介面相關腳本
├── data/                JSON 資料（物品、詞綴、符文、符文之語、套裝）
├── assets/              美術、音效等素材
├── project.godot
└── CLAUDE.md
```
