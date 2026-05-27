# Utopet AI Agent

一個以 **本地 LLM（Ollama）** 為核心的 AI 桌面寵物與模擬村莊整合專案。  
桌面寵物能聆聽語音、辨識螢幕文字、管理記憶、收發 Gmail、閱讀網頁摘要；  
村莊裡四位性格各異的 AI 居民自主生活、建立關係、每日生成日記故事。  
兩套 Godot 前端共用同一個 Python FastAPI 後端，完全在本機運行，不依賴任何雲端 AI 服務。

![Godot](https://img.shields.io/badge/Godot-4.4-blue?logo=godotengine)
![Python](https://img.shields.io/badge/Python-3.10%2B-yellow?logo=python)
![FastAPI](https://img.shields.io/badge/FastAPI-0.100%2B-green?logo=fastapi)
![Ollama](https://img.shields.io/badge/LLM-Ollama-black)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 目錄

- [專案架構](#專案架構)
- [功能概覽](#功能概覽)
- [系統需求](#系統需求)
- [快速開始](#快速開始)
- [子專案說明](#子專案說明)
  - [godot\_final — Python 後端](#godot_final--python-後端)
  - [GodotMap — 村莊模擬](#cluade-godotmaptest--村莊模擬)
  - [godot-4-ui — 桌面寵物 UI](#godot-4-ui--桌面寵物-ui)
- [API 總覽](#api-總覽)
- [常見問題](#常見問題)

---

## 專案架構

```
Utopet-AI-Agent/
├── godot_final/              # Python FastAPI 後端（共用核心）
├── GodotMap/      # Godot 4 村莊模擬前端
└── godot-4-ui/               # Godot 4 桌面寵物 UI 前端
```

```
┌─────────────────────────────────────────────────┐
│               Godot 前端（兩套）                  │
│   ┌──────────────────┐  ┌────────────────────┐   │
│   │  村莊模擬        │  │  桌面寵物 UI       │   │
│   │ GodotMapTest     │  │  godot-4-ui        │   │
│   └────────┬─────────┘  └─────────┬──────────┘   │
└────────────┼──────────────────────┼──────────────┘
             │  HTTP / SSE          │
             ▼                      ▼
┌─────────────────────────────────────────────────┐
│         Python FastAPI 後端  :8000               │
│  godot_final/main_api.py                        │
│                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ LLM 串流 │ │ 語音辨識 │ │ 記憶 / 日程 / OCR│ │
│  │ llm_stream│ │ whisper  │ │  memory_helper   │ │
│  └──────────┘ └──────────┘ └──────────────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │  Gmail   │ │  社交引擎 │ │   網頁摘要       │ │
│  │  IMAP/   │ │ social_  │ │  summarizer_plus │ │
│  │  SMTP    │ │  system  │ │  trafilatura     │ │
│  └──────────┘ └──────────┘ └──────────────────┘ │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
         ┌───────────────────┐
         │  Ollama  :11434   │
         │  qwen2.5:7b       │
         │  qwen3.5:9b-q4_KM │
         │  qwen2.5:1.5b     │
         └───────────────────┘
```

---

## 功能概覽

### 桌面寵物（godot-4-ui + godot_final）

| 功能 | 說明 |
|------|------|
| **串流對話** | 透過 Ollama 本地 LLM 即時串流回覆，支援 SSE |
| **語音辨識** | faster-whisper medium 模型，繁體中文語音輸入 |
| **螢幕 OCR** | RapidOCR / PaddleOCR 雙後端，截圖文字辨識 |
| **長期記憶** | SQLite 儲存，分 permanent / days\_7 / days\_3 三級，自動老化 |
| **自動記憶** | 每輪對話結束後 LLM 判斷是否寫入記憶，關機時統整當日記憶 |
| **Tool Calling** | LLM 可自主觸發 OCR、計算器、Gmail、網頁摘要、天氣等工具 |
| **Gmail** | IMAP 收信、SMTP 寄信，LLM 自動潤飾信件內文 |
| **網頁摘要** | trafilatura 抓取正文，LLM 生成新聞 / 文章摘要與重點列表 |
| **日程管理** | 新增日程文字，Godot 端 UI 顯示今日行程 |

### 村莊模擬（GodotMap + godot_final）

| 功能 | 說明 |
|------|------|
| **四位 AI Agent** | Jack（伐木工）、Mike（礦工）、Fin（釣魚人）、Buba（農夫），各具職業特性 |
| **每日自主排程** | 06:00 起床至 22:00 就寢，三種日程變體由 LLM 依前日狀態推薦 |
| **生理數值** | 飢餓、疲憊、心情動態變化，影響社交意願 |
| **三維關係系統** | 信任度 / 好感度 / 社交債務，關係狀態機（Normal → Cold War → Blocked） |
| **即時對話生成** | 兩 Agent 靠近自動觸發，qwen3.5:9b 生成繁體中文對話（受關係與記憶影響） |
| **對話冷卻** | 每對 Agent 各自獨立 60 秒冷卻，避免頻繁對話 |
| **每日故事** | 20:00 四篇故事平行生成（qwen2.5:1.5b），以文學筆法記錄角色一天 |
| **Agent 提取模式** | 村莊居民可暫時離開村莊，作為桌面寵物助手與使用者互動 |
| **自主尋路** | Godot NavigationAgent2D，建築半透明遮擋效果 |

---

## 系統需求

### 必要軟體

| 軟體 | 版本 | 用途 |
|------|------|------|
| [Python](https://www.python.org/downloads/) | 3.10 或 3.11 | 後端 API |
| [Ollama](https://ollama.com/download) | 最新版 | 本地 LLM 推理 |
| [Godot Engine](https://godotengine.org/download) | 4.4 Standard | 遊戲前端 |

### 硬體建議

| 項目 | 建議規格 |
|------|---------|
| RAM | 16 GB 以上 |
| GPU | NVIDIA（CUDA）或 Apple Silicon，可用 CPU 但較慢 |
| 儲存 | 約 15 GB（Python 環境 + Ollama 模型 + Whisper 模型） |

### Ollama 模型

| 模型 | 用途 | 大小 |
|------|------|------|
| `qwen2.5:7b` | 桌面寵物對話、記憶判斷、Gmail 潤飾 | ~5 GB |
| `qwen3.5:9b-q4_K_M` | 村莊 Agent 即時對話 | ~6 GB |
| `qwen2.5:1.5b` | 故事生成、日程建議 | ~1 GB |

> 只使用桌面寵物時僅需 `qwen2.5:7b`；只使用村莊模擬時需 `qwen3.5:9b-q4_K_M` + `qwen2.5:1.5b`。

---

## 快速開始

### 步驟 1：安裝 Ollama 並下載模型

前往 [https://ollama.com/download](https://ollama.com/download) 安裝 Ollama，然後在終端機執行：

```powershell
ollama pull qwen2.5:7b
ollama pull qwen2.5:1.5b
# 村莊模擬需要（可選）：
ollama pull qwen3.5:9b-q4_K_M
```

若要同時執行村莊模擬（需雙模型並存），設定環境變數：

```powershell
# Windows PowerShell（永久設定）
[System.Environment]::SetEnvironmentVariable("OLLAMA_MAX_LOADED_MODELS", "2", "User")
```

### 步驟 2：設定 Python 後端

```powershell
cd godot_final
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

下載語音辨識模型（約 1.5 GB，可選，僅語音功能需要）：

```powershell
python download_model.py
```

### 步驟 3：啟動後端

```powershell
# 確認 Ollama 已在執行中（若尚未啟動）
ollama serve

# 啟動 Python API
cd godot_final
.\.venv\Scripts\activate
python main_api.py
```

啟動成功後在瀏覽器確認：`http://127.0.0.1:8000/docs`

### 步驟 4：開啟 Godot 前端

1. 開啟 **Godot 4.4**
2. 點選「匯入」→ 選擇 `GodotMap/project.godot`（村莊）或 `godot-4-ui/project.godot`（桌面寵物）
3. 按 **F5** 執行

---

## 子專案說明

### godot_final — Python 後端

**位置：** `godot_final/`  
**入口：** `python main_api.py`（監聽 `http://127.0.0.1:8000`）

#### 主要檔案

| 檔案 | 功能 |
|------|------|
| `main_api.py` | FastAPI 主入口，整合所有路由 |
| `llm_stream.py` | Ollama 串流對話，SSE 輸出 |
| `speech_whisper_stream.py` | faster-whisper 串流語音辨識 |
| `ocr_helper.py` | OCR 雙後端（RapidOCR / PaddleOCR） |
| `memory_helper.py` | SQLite 長期記憶，自動老化與關機總結 |
| `gmail_helper.py` | Gmail IMAP 收信 / SMTP 寄信 |
| `summarizer_plus.py` | trafilatura 網頁抓取 + LLM 摘要 |
| `social_routes.py` | 村莊社交引擎 API |
| `village_memory_routes.py` | 村莊 Agent 記憶 API |
| `village_schedule_routes.py` | 日程變體建議 API |
| `system_prompt.md` | 桌面寵物人設與工具說明 |
| `tools.json` | Tool Calling 工具定義 |
| `download_model.py` | Whisper 模型一鍵下載腳本 |

#### 語音辨識設定

預設使用 NVIDIA GPU：

```python
# speech_whisper.py / speech_whisper_stream.py
device="cuda"
compute_type="float16"
```

無 GPU 時改為：

```python
device="cpu"
compute_type="int8"
```

#### Gmail 設定

開啟 `gmail_helper.py`，填入 Gmail 帳號與 App 密碼：

```python
GMAIL_ADDRESS      = "your@gmail.com"
GMAIL_APP_PASSWORD = "xxxx xxxx xxxx xxxx"  # 16 碼 App 密碼
```

> App 密碼申請：[https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)（需先開啟兩步驟驗證）

---

### GodotMap — 村莊模擬

**位置：** `GodotMap/`  
**引擎：** Godot 4.4 Forward Plus  
**解析度：** 336 × 256（像素藝術風格）

#### 四位 AI 居民

| 角色 | 職業 | 個性 | 日程特色 |
|------|------|------|---------|
| **Jack** | 伐木工 | 勤奮踏實 | 森林砍樹 → 市集 → 回家 |
| **Mike** | 礦工 | 沉默寡言 | 市集巡禮 / 自然漫步（礦洞建設中） |
| **Fin** | 釣魚人 | 悠閒自在 | 溪邊釣魚 → 偶爾探索 |
| **Buba** | 農夫 | 熱心助人 | 農田耕作 → 動物照料 |

每位 Agent 有三種日程變體（A/B/C），Day 2 起由 LLM 依前日故事與關係狀態推薦。

#### 操作快捷鍵

| 按鍵 | 功能 |
|------|------|
| `T` | 切換時間速度（x1 / x2 / x5 / x10 / x30） |
| `P` | 暫停 / 繼續 |
| `R` | 重置時間至 06:00，重啟所有排程 |
| `I` | 輸出所有 Agent 當前狀態 |
| `H` | 輸出今日行程預覽 |
| `M` | 開關滑鼠點擊移動模式 |
| `S` | 停止所有 Agent 移動 |
| `F1`~`F4` | 強制 Jack / Mike / Fin / Buba 跳至下一排程 |

#### UI 面板

| 圖示 | 位置 | 功能 |
|------|------|------|
| ⚙️ | 左下角 | 時間速度控制 + 暫停 |
| 📊 | 右下角 | Agent 生理數值即時顯示 |
| 💬 | 右下角 | 對話歷史瀏覽 |
| 📚 | 右下角 | 每日故事瀏覽 / 手動觸發生成 |

#### Python 後端需求

啟動村莊模擬前，需先執行 `godot_final/main_api.py`（port 8000）。

```powershell
# 也需要這兩個 Ollama 模型
ollama pull qwen3.5:9b-q4_K_M   # 即時對話
ollama pull qwen2.5:1.5b         # 故事生成 + 日程建議
```

---

### godot-4-ui — 桌面寵物 UI

**位置：** `godot-4-ui/`  
**引擎：** Godot 4.4 GL Compatibility  
**特性：** 透明視窗、無邊框、永遠置頂

#### 主要功能

- **角色對話**：點擊桌面寵物開啟對話框，LLM 串流回覆（SSE）
- **語音輸入**：呼叫 `/listen_stream` 進行語音辨識
- **右鍵選單**：快速存取各功能（OCR、Gmail、設定等）
- **行程管理**：查看今日日程
- **網頁瀏覽**：內嵌網頁介面 + 文章摘要
- **背包 / 市場**：物品系統 UI
- **設定**：角色外觀、語言、API 位址等

#### Python 後端需求

使用前需先啟動 `godot_final/main_api.py`（port 8000），並在 Godot 專案設定中確認 API 位址為 `http://127.0.0.1:8000`。

---

## API 總覽

後端啟動後，完整 API 文件可在瀏覽器查看：`http://127.0.0.1:8000/docs`

### 桌面寵物核心端點

| 方法 | 路徑 | 功能 |
|------|------|------|
| GET | `/health` | 服務健康檢查 |
| GET/POST | `/chat_stream` | LLM 串流對話（SSE） |
| GET | `/voice_chat_stream` | 語音辨識 → 串流回覆 |
| POST | `/listen` | 單次語音辨識 |
| POST | `/open_ocr` | 開啟 OCR 視窗 |
| POST | `/chat_with_image` | 圖片 OCR + LLM 理解 |
| POST | `/summarize/news` | 新聞摘要 |
| POST | `/summarize/article` | 文章摘要 |
| GET | `/gmail/inbox` | 讀取未讀郵件 |
| POST | `/gmail/compose` | 產生郵件預覽（LLM 潤飾） |
| POST | `/gmail/send` | 發送郵件 |
| GET | `/memory` | 列出所有記憶 |
| POST | `/memory` | 新增 / 更新記憶 |
| DELETE | `/memory/{key}` | 刪除記憶 |
| POST | `/schedule/add` | 新增日程 |
| POST | `/admin/reload` | 熱重載 system\_prompt.md & tools.json |

### 村莊模擬端點

| 方法 | 路徑 | 功能 |
|------|------|------|
| POST | `/social/register` | 註冊 Agent 人格 |
| POST | `/social/check` | 判斷是否觸發對話 |
| GET | `/social/relationship/{a}/{b}` | 查詢兩人關係值 |
| POST | `/social/complete` | 對話結束，更新關係 |
| POST | `/social/tick` | 推進社交時鐘 |
| POST | `/village/memory/save` | 儲存對話記憶 |
| POST | `/village/memory/context` | 取得記憶摘要 |
| POST | `/schedule/suggest_variant` | LLM 推薦隔日日程變體 |
| POST | `/village/agent/extract` | 提取 Agent 進入助手模式 |
| POST | `/village/agent/return` | Agent 返回村莊，同步記憶 |
| GET | `/village/agent/active` | 查詢當前活躍 Agent |

---

## 常見問題

**Q：後端啟動時出現 `ModuleNotFoundError`？**  
A：確認已執行 `pip install -r requirements.txt`，且使用的是虛擬環境中的 Python。

**Q：語音辨識失敗，提示找不到模型？**  
A：執行 `python download_model.py` 下載 faster-whisper-medium 模型（約 1.5 GB）。

**Q：對話沒有回應 / 一直顯示 Loading？**  
A：確認 Ollama 正在執行（`ollama serve`），且所需模型已下載（`ollama list`）。

**Q：沒有 NVIDIA GPU，語音辨識可以用嗎？**  
A：可以。將 `speech_whisper.py` 和 `speech_whisper_stream.py` 中的 `device="cuda"` 改為 `device="cpu"`、`compute_type="float16"` 改為 `compute_type="int8"`，速度較慢但可正常運作。

**Q：村莊裡的故事生成失敗？**  
A：通常是 `qwen2.5:1.5b` 冷啟動的 timeout 問題。稍等幾秒後手動點擊 📚 再次觸發即可。

**Q：OCR 功能無法使用？**  
A：`requirements.txt` 已包含 `rapidocr-onnxruntime`。若偏好 PaddleOCR（精度更高），另外執行：`pip install paddleocr paddlepaddle`

**Q：Gmail 無法連線，顯示 AUTHENTICATIONFAILED？**  
A：填入的必須是 Google **應用程式密碼**（16 碼），而非 Gmail 登入密碼。申請位置：[https://myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)

---

## 授權

本專案使用 [MIT License](LICENSE)。  
村莊地圖美術使用 [Cute Fantasy](https://shubibubi.itch.io/cute-fantasy) 素材包，請遵守其原始授權條款。
