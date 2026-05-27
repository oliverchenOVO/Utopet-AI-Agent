# Godot Ollama API 使用說明

這個資料夾是一個給 Godot 桌面寵物使用的本機 API 服務。主要入口是 `main_api.py`，啟動後會在 `http://127.0.0.1:8000` 提供聊天、語音辨識、OCR、Gmail、摘要、記憶與日程等功能。

## 主要檔案

- `main_api.py`：FastAPI 伺服器入口。
- `llm_stream.py`：連接本機 Ollama，處理串流聊天。
- `speech_whisper_stream.py` / `speech_whisper.py`：使用 faster-whisper 做中文語音辨識。
- `ocr_helper.py`、`ocr_gui_runner.py`、`ocr_result_window.py`：OCR 與獨立 PyQt 視窗。
- `gmail_helper.py`：使用 Gmail IMAP/SMTP 收信、預覽與寄信。
- `memory_helper.py`：SQLite 長期記憶，資料存在 `pet_memory.db`（自動建立，不含於 repo）。
- `tools.json`：提供給 Ollama tool calling 的工具定義。
- `system_prompt.md`：桌面寵物助手的人設與工具使用規則。
- `download_model.py`：下載 faster-whisper-medium 模型的輔助腳本。

## 安裝步驟

### 1. 建立虛擬環境並安裝套件

建議使用 Python 3.10 或 3.11。

```powershell
cd godot_final
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

### 2. 下載語音辨識模型（約 1.5 GB）

```powershell
python download_model.py
```

模型會下載到 `./faster-whisper-medium/`。若已有模型資料夾，可跳過此步驟。

### 3. 安裝並啟動 Ollama

```powershell
ollama pull qwen2.5:7b
ollama serve
```

程式預設呼叫 `http://127.0.0.1:11434/api/chat`。

## 啟動 API

```powershell
.\.venv\Scripts\activate
python main_api.py
```

啟動成功後可開啟：

```
http://127.0.0.1:8000
http://127.0.0.1:8000/docs
```

## 常用 API

- `GET /health`：檢查服務是否運作。
- `GET /chat_stream?message=你好`：串流文字聊天，Godot 可用 SSE 接收。
- `POST /chat_stream`：用 JSON 傳送串流聊天。
- `GET /voice_chat_stream`：錄音、語音辨識，再串流回覆。
- `POST /listen`：只做一次語音辨識。
- `POST /open_ocr`：開啟 OCR 視窗。
- `POST /chat_with_image`：傳 base64 圖片做 OCR 或圖片文字理解。
- `POST /summarize/news`：新聞摘要。
- `POST /summarize/article`：文章摘要。
- `GET /gmail/inbox`：讀取 Gmail 未讀信件。
- `POST /gmail/compose`：產生寄信預覽。
- `POST /gmail/send`：實際寄出 Gmail。
- `GET /memory`：查看記憶。
- `POST /memory`：新增或更新記憶。
- `DELETE /memory/{key}`：刪除記憶。
- `POST /schedule/add`：新增日程文字，交給 Godot 端處理。
- `POST /admin/reload`：重新載入 `system_prompt.md` 和 `tools.json`。

## Godot 連接方式

Godot 端可以把 API base URL 設為：

```
http://127.0.0.1:8000
```

文字聊天建議串接 `GET /chat_stream` 或 `POST /chat_stream`。回傳格式是 Server-Sent Events：

```
event: token
data: 回覆片段

event: done
data: [DONE]
```

## 語音辨識設定

語音辨識預設使用 NVIDIA GPU：

```python
device="cuda"
compute_type="float16"
```

如果電腦沒有 NVIDIA GPU，請把 `speech_whisper.py` 和 `speech_whisper_stream.py` 裡的設定改成：

```python
device="cpu"
compute_type="int8"
```

電腦需要有可用麥克風，`sounddevice` 才能錄音。

## OCR 設定

`ocr_helper.py` 會優先嘗試 PaddleOCR，失敗後改用 RapidOCR（已含於 `requirements.txt`）。

若要改用 PaddleOCR：

```powershell
pip install paddleocr paddlepaddle
```

## Gmail 設定

`gmail_helper.py` 使用 Gmail IMAP/SMTP，不需要 Google Cloud OAuth，但需要 Gmail 應用程式密碼。

申請步驟：

1. 登入 Google 帳戶，開啟兩步驟驗證：`https://myaccount.google.com/security`
2. 前往 `https://myaccount.google.com/apppasswords`，建立應用程式密碼。
3. 複製產生的 16 碼密碼。
4. 填入 `gmail_helper.py`：

```python
GMAIL_ADDRESS      = "你的 Gmail"
GMAIL_APP_PASSWORD = "你的 16 碼應用程式密碼"
```

> 請勿將真實密碼上傳到公開 repo。

## 記憶資料庫

記憶資料存在 `pet_memory.db`（已加入 `.gitignore`，不會上傳）。第一次啟動 `main_api.py` 時會自動建立。

查看目前記憶：

```powershell
python memory_see.py
```

## 已知外部需求

以下不由 `pip install` 處理，需另外準備：

- Ollama 已安裝並執行（`ollama serve`）
- Ollama 已下載 `qwen2.5:7b`（`ollama pull qwen2.5:7b`）
- 語音辨識模型已下載（`python download_model.py`）
- 若使用 GPU 語音辨識，需要 NVIDIA GPU 與 CUDA 環境
- 若使用 Gmail，需要 Gmail 兩步驟驗證與應用程式密碼
