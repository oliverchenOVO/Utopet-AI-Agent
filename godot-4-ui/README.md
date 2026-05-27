# godot-4-ui — 桌面寵物 UI

基於 **Godot 4.4 GL Compatibility** 開發的桌面寵物前端。視窗透明、無邊框、永遠置頂，角色顯示在桌面上，僅角色本體區域可點擊，不遮擋其他視窗操作。

## 功能

| 功能 | 觸發方式 |
|------|---------|
| **串流對話** | 點擊角色 → 對話框，支援 SSE 即時串流回覆 |
| **語音輸入** | 右鍵 → Talk，開啟語音辨識視窗 |
| **網頁瀏覽 / 摘要** | 右鍵 → Internet，內嵌網頁 + AI 摘要 |
| **角色設定** | 右鍵 → 角色設定，更換外觀與名稱 |
| **背包系統** | 右鍵 → 背包，管理持有物品 |
| **市場購物** | 右鍵 → 市場，消費金幣購買道具 |
| **日程管理** | 右鍵 → 日程，查看今日行程 |
| **設定** | 右鍵 → 設定，調整音量、AI 開關等 |
| **對話歷史** | 右鍵 → 歷史，瀏覽完整聊天紀錄 |

## 前置需求

啟動前需先在背景執行 `godot_final` 的 Python 後端：

```powershell
cd ../godot_final
.\.venv\Scripts\activate
python main_api.py
```

後端預設監聽 `http://127.0.0.1:8000`，若要更改請同步修改 `code/right_click_ui.gd` 中的 `BASE_URL`。

## 啟動方式

1. 開啟 **Godot 4.4**
2. 匯入此資料夾的 `project.godot`
3. 按 **F5** 執行

## 專案結構

```
godot-4-ui/
├── project.godot          # Godot 專案設定
├── code/                  # GDScript 腳本
│   ├── GlobalState.gd     # 全域狀態（金錢、飢餓、AI 開關、對話歷史）
│   ├── main_window.gd     # 主視窗：透明視窗、滑鼠穿透、角色互動
│   ├── right_click_ui.gd  # 右鍵選單：功能入口
│   ├── dialog_box.gd      # 對話框：SSE 串流對話
│   ├── speak_window.gd    # 語音輸入視窗
│   ├── internet.gd        # 網頁瀏覽 + AI 摘要
│   ├── character.gd       # 角色動畫與狀態
│   ├── schedule.gd        # 日程顯示
│   ├── backpack.gd        # 背包系統
│   ├── market.gd          # 市場購物
│   ├── setting.gd         # 設定面板
│   └── history_window.gd  # 對話歷史瀏覽
├── Scene/                 # 場景檔（.tscn）
├── Assets/                # 角色與 UI 圖片資源
└── theme/                 # UI 主題樣式
```

## 注意事項

- 需要 Godot **4.4** 版本，使用 **GL Compatibility** 渲染器（非 Forward Plus）。
- 視窗透明功能在部分 Linux 桌面環境下可能需要額外設定。
- 語音功能需要麥克風，且後端已載入 faster-whisper 模型（`python download_model.py`）。
