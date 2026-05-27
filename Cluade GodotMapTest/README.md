# 🏡 GodotAgentMap — AI 驅動的模擬小鎮

一個基於 **Godot 4.4** 開發的 AI Agent 模擬系統。  
四位性格各異的居民在小鎮上自主生活、對話、建立關係，並在每日結束時生成個人日記故事，所有對話與敘事均由本地 LLM（Ollama）即時生成。

![Godot](https://img.shields.io/badge/Godot-4.4-blue?logo=godotengine)
![Python](https://img.shields.io/badge/Python-3.10%2B-yellow?logo=python)
![Ollama](https://img.shields.io/badge/LLM-Ollama-black)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📋 目錄

- [功能概覽](#功能概覽)
- [系統需求](#系統需求)
- [環境安裝](#環境安裝)
- [啟動步驟](#啟動步驟)
- [操作說明](#操作說明)
- [專案結構](#專案結構)
- [架構說明](#架構說明)

---

## ✨ 功能概覽

### 🤖 四位 AI Agent

| 角色 | 職業 | 個性 |
|------|------|------|
| **Jack** | 伐木工 | 勤奮踏實，熱愛森林 |
| **Mike** | 礦工 | 沉默寡言，專注採礦 |
| **Fin** | 釣魚人 | 悠閒自在，享受水邊 |
| **Buba** | 農夫 | 熱心助人，照料農田 |

每位 Agent 具備：
- **日程排程**：每天從 06:00 起床到 22:00 就寢，依職業特性執行不同活動
- **生理狀態**：飢餓值、疲憊值、心情值，隨時間與活動動態變化
- **自主移動**：透過 NavigationAgent2D 在地圖上自主尋路

### 💬 LLM 驅動的即時對話

- Agent 互相接近時自動觸發對話
- 透過 **Ollama**（本地 LLM）生成自然的繁體中文對話
- 對話內容受**關係狀態**影響（信任度、好感度、冷戰狀態）
- 對話歷史可在 UI 面板中瀏覽

### 🧠 社交引擎（Python 後端）

- **三維關係系統**：信任度（trust）/ 好感度（affection）/ 社交債務（social_debt）
- **社交狀態機**：Normal → Cold War → Blocked
- **記憶系統**：對話記錄持久化存儲，影響後續互動
- **生理影響**：疲憊、飢餓等狀態影響 Agent 的社交意願

### 📚 每日故事生成

- 每天 **20:00**（遊戲內時間）自動觸發
- 四位 Agent 的故事**平行生成**，不互相阻塞
- 以文學敘事風格（第三人稱段落）描述角色一天的經歷
- 故事以 **JSON 格式**存儲於 `stories/<AgentName>/` 目錄

### 🎮 遊戲 UI

| 按鈕 | 位置 | 功能 |
|------|------|------|
| ⚙️ | 左下角 | 時間速度控制（x1/x2/x5/x10/x30）+ 暫停 |
| 📊 | 右下角 | Agent 狀態面板（飢餓、疲憊、心情） |
| 💬 | 右下角 | 對話歷史瀏覽 |
| 📚 | 右下角 | 每日故事瀏覽 / 手動觸發生成 |

### 🔍 相機控制

- **滾輪上下**：以滑鼠游標為中心縮放視角
- 縮放範圍：全地圖（84×64 格）→ 單棟建築（~10×8 格）
- 自動邊界限制，不露出地圖外的灰色區域

---

## 💻 系統需求

### 必要軟體

| 軟體 | 版本要求 | 用途 |
|------|----------|------|
| **Godot Engine** | 4.4（Forward Plus） | 遊戲引擎 |
| **Ollama** | 最新版 | 本地 LLM 推理 |
| **Python** | 3.10 以上 | 社交引擎後端 |

### 硬體建議

| 配置 | 規格 |
|------|------|
| RAM | 16 GB 以上（雙模型同時載入需 ~10 GB） |
| GPU | 支援 CUDA / Metal 的 GPU（可用 CPU 但較慢） |
| 儲存空間 | 約 10 GB（兩個 LLM 模型） |

### LLM 模型

| 模型 | 用途 | 大小 |
|------|------|------|
| `qwen3.5:9b-q4_K_M` | Agent 日常對話 | ~6 GB |
| `qwen2.5:1.5b` | 每日故事生成 | ~1 GB |

---

## 🛠 環境安裝

### 1. 安裝 Godot 4.4

前往 [Godot 官方網站](https://godotengine.org/download) 下載 **Godot 4.4 Standard**（非 .NET 版本）。

### 2. 安裝 Ollama

```bash
# Windows：前往 https://ollama.com/download 下載安裝程式
# macOS：
brew install ollama
```

安裝完成後，下載所需模型：

```bash
ollama pull qwen3.5:9b-q4_K_M
ollama pull qwen2.5:1.5b
```

設定允許同時載入兩個模型的環境變數：

```bash
# Windows PowerShell（永久設定）
[System.Environment]::SetEnvironmentVariable("OLLAMA_MAX_LOADED_MODELS", "2", "User")

# macOS / Linux（加入 ~/.bashrc 或 ~/.zshrc）
export OLLAMA_MAX_LOADED_MODELS=2
```

### 3. 安裝 Python 依賴

```bash
cd GodotPY
pip install fastapi uvicorn pydantic
# 若需要語音功能：
pip install vosk sounddevice
```

> **提示**：建議使用虛擬環境 `python -m venv venv` 避免套件衝突。

---

## 🚀 啟動步驟

每次執行需要開啟 **三個服務**，建議開三個終端機視窗分別執行：

### 終端機 1：啟動 Ollama

```bash
ollama serve
```

確認輸出包含 `Listening on 127.0.0.1:11434`。

### 終端機 2：啟動 Python 後端 API

```bash
cd GodotPY
python main.py
# 或使用 uvicorn：
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

確認輸出包含 `Uvicorn running on http://127.0.0.1:8000`。

### 終端機 3（可選）：驗證服務正常

```bash
# 測試 Ollama
curl http://127.0.0.1:11434/api/tags

# 測試 Python API
curl http://127.0.0.1:8000/docs
```

### 啟動遊戲

1. 開啟 **Godot 4.4**
2. 選擇「匯入」→ 瀏覽到專案資料夾，選取 `project.godot`
3. 點擊「編輯」進入編輯器
4. 按 **F5** 執行（或點選右上角播放按鈕）

---

## 🎮 操作說明

### 鍵盤快捷鍵

| 按鍵 | 功能 |
|------|------|
| `T` | 循環切換時間速度（x1 → x2 → x5 → x10 → x30） |
| `P` | 暫停 / 繼續時間推進 |
| `R` | 重置時間到 06:00，重啟所有 Agent 行程 |
| `I` | 在終端機輸出所有 Agent 當前狀態 |
| `H` | 在終端機輸出今日行程預覽 |
| `M` | 開關滑鼠點擊移動（點地圖讓 Agent 走過去） |
| `S` | 立即停止所有 Agent 移動 |
| `F1` | Jack 跳過當前任務，執行下一個行程 |
| `F2` | Mike 跳過當前任務，執行下一個行程 |
| `F3` | Fin 跳過當前任務，執行下一個行程 |
| `F4` | Buba 跳過當前任務，執行下一個行程 |

### 滑鼠操作

| 操作 | 功能 |
|------|------|
| 滾輪向上 | 以游標為中心放大視角 |
| 滾輪向下 | 以游標為中心縮小視角 |
| 左鍵點擊地圖 | 選中 Agent 後移動（需先開啟 `M` 模式） |

### UI 面板說明

**⚙️ 速度控制面板**（左下角）
- 點擊 ⚙️ 開啟/關閉
- 選擇速度：x1 / x2 / x5 / x10 / x30
- ⏸ 按鈕：暫停時間，此時可任意觀察 Agent 狀態

**📊 Agent 狀態面板**（右下角）
- 顯示四位 Agent 的即時數值
- 飢餓 / 疲憊 / 心情 / 當前活動

**💬 對話歷史**（右下角）
- 記錄所有 Agent 之間的對話
- 可按 Agent 篩選

**📚 故事面板**（右下角）
- 瀏覽歷史生成的日記故事
- 點擊📚 → 選擇 Agent → 閱讀故事
- 20:00 自動生成，也可手動點擊觸發

---

## 📁 專案結構

```
GodotAgentMap/
│
├── world.tscn                      # 主場景（地圖、Agent、相機）
├── world.gd                        # 世界主控：時間系統、鍵盤控制、相機縮放
│
├── Jack_Agent.gd                   # Jack 的行程、狀態、移動邏輯
├── Mike_Agent.gd                   # Mike
├── Fin_Agent.gd                    # Fin
├── Buba_Agent.gd                   # Buba
│
├── agent_conversation_manager.gd   # Agent 接近偵測 + LLM 對話觸發 + 社交引擎整合
├── llm_api_manager_optimized.gd    # Ollama API 封裝（對話用，qwen3.5:9b）
│
├── agent_status_panel.gd           # 右下角 📊 狀態面板 UI
├── conversation_history_ui.gd      # 右下角 💬 對話歷史 UI
├── story_generator_ui.gd           # 右下角 📚 故事生成 UI（qwen2.5:1.5b）
├── speed_control_ui.gd             # 左下角 ⚙️ 速度控制 UI
│
├── deskpet_manager.gd              # 桌寵系統管理器
├── python_api_client.gd            # Python 後端 API 呼叫封裝
│
├── project.godot                   # Godot 專案設定（viewport 336×256）
├── world_tileset.tres              # 地圖 Tileset 資源
├── new_navigation_polygon.tres     # 導航網格
│
├── GodotPY/                        # Python FastAPI 後端
│   ├── main.py                     # FastAPI 應用入口（port 8000）
│   ├── social_routes.py            # 社交引擎 API 路由
│   ├── social_system.py            # 社交引擎核心邏輯
│   ├── memory_routes.py            # 記憶系統 API 路由
│   ├── memory_manager.py           # 記憶存取與摘要
│   └── ...                         # 其他功能模組
│
├── stories/                        # 自動生成的日記故事（JSON）
│   ├── Jack/
│   │   └── story_2026-05-06_20-00.json
│   ├── Mike/
│   ├── Fin/
│   └── Buba/
│
├── assets/                         # 遊戲美術資源（Cute Fantasy 素材包）
├── tileset/                        # 地圖格子資源
└── NoUse/                          # 舊版 / 測試用腳本存檔
```

---

## 🏗 架構說明

### 整體運作流程

```
Godot 遊戲引擎
    │
    ├─ 時間推進（1 遊戲秒 = 1 現實秒，可加速）
    │
    ├─ Agent 自主排程（每分鐘 tick）
    │       └─ 移動到目標地點 → 執行活動
    │
    ├─ 接近偵測（CheckArea2D）
    │       └─ 觸發對話流程：
    │               1. 查詢 Python API /social/check（決定是否對話）
    │               2. 平行載入記憶 + 關係資料
    │               3. 發送 Ollama API 生成對話
    │               4. 對話結束 → POST /social/complete（更新關係）
    │
    └─ 20:00 故事生成
            └─ 四篇平行請求 → Ollama（qwen2.5:1.5b）→ 存 JSON
```

### API 端點（Python 後端，port 8000）

| 方法 | 路徑 | 功能 |
|------|------|------|
| POST | `/social/register` | 註冊 Agent 人格設定 |
| POST | `/social/check` | 檢查兩 Agent 是否應對話 |
| GET | `/social/relationship/{a}/{b}` | 查詢兩人關係值 |
| POST | `/social/complete` | 對話結束，更新關係 |
| POST | `/social/tick` | 推進社交時鐘（每分鐘） |
| POST | `/memory/save` | 儲存對話記憶 |
| GET | `/memory/context` | 取得記憶摘要（注入 LLM prompt） |

### 對話生成 Prompt 流程

```
Agent 狀態（心情、飢餓、職業）
    + 關係資料（信任度、好感度、冷戰狀態）
    + 歷史記憶摘要
    ↓
組合成 System + User Prompt
    ↓
Ollama qwen3.5:9b（local，port 11434）
    ↓
繁體中文對話（4 句，各說 2 句）
```

---

## ⚠️ 常見問題

**Q：對話一直用備用對話，沒有 LLM 生成的內容？**  
A：確認 Ollama 是否正在執行（`ollama serve`），以及模型是否已下載（`ollama list`）。

**Q：Python API 連不上？**  
A：確認 `python main.py` 有成功啟動，並監聽在 `127.0.0.1:8000`。若有 port 衝突請修改 `main.py` 中的 port 設定，並同步修改各 `.gd` 檔中的 `SOCIAL_API` 常數。

**Q：故事生成顯示「失敗 result=13」？**  
A：timeout 問題，通常是 `qwen2.5:1.5b` 模型尚未載入（冷啟動）。稍等幾秒後手動點擊 📚 再次觸發即可。

**Q：地圖顯示比例不正確（畫面拉長或扁）？**  
A：確認使用的是 Godot **4.4** 版本，且未修改 `project.godot` 中的 viewport 設定（336×256）。

---

## 📝 授權

本專案使用 [MIT License](LICENSE)。  
地圖素材使用 [Cute Fantasy](https://shubibubi.itch.io/cute-fantasy) 素材包，請遵守其原始授權條款。
