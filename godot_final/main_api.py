# main_api.py
import sys
import subprocess
import json
import base64
import io
import asyncio
from contextlib import asynccontextmanager
import requests
import uvicorn
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
from PIL import Image
from summarizer_plus import summarize_news_plus, summarize_article_plus
from speech_whisper_stream import listen_once, listen_stream
from ocr_helper import OCRHelper
from llm_stream import (
    aiter_chat_tokens,
    token_to_sse, done_sse, error_sse,
    conversation_history,
    SYSTEM_PROMPT,
    TOOLS,
    reload_config,
)
from gmail_helper import get_gmail
from memory_helper import (
    init_db,
    upsert_memory,
    delete_memory,
    get_all_memories,
    inject_memory_to_prompt,
    get_today_memory_events,
    replace_today_auto_memories,
)
from social_routes import router as social_router
from village_memory_routes import router as village_memory_router
from village_schedule_routes import router as village_schedule_router

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL_NAME = "qwen2.5:7b"


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    try:
        yield
    finally:
        await asyncio.to_thread(summarize_today_memories_on_shutdown)


app = FastAPI(title="Godot Ollama API", version="4.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── 村莊路由 ─────────────────────────────────────────────
app.include_router(social_router,          prefix="/social",         tags=["Village Social"])
app.include_router(village_memory_router,  prefix="/village/memory", tags=["Village Memory"])
app.include_router(village_schedule_router, prefix="/schedule",      tags=["Village Schedule"])


# ─── OCR 單例 ─────────────────────────────────────────────

_ocr_helper = None

def get_ocr():
    global _ocr_helper
    if _ocr_helper is None:
        print("載入 OCR 引擎...")
        _ocr_helper = OCRHelper(use_angle_cls=True)
        print("OCR 引擎載入完成")
    return _ocr_helper


# ─── 資料模型 ─────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str
    temperature: float = 0.7
    max_tokens: int = 4000

class StreamChatRequest(BaseModel):
    message: str
    session_id: str = "default"
    temperature: float = 0.7
    max_tokens: int = 512
    agent_name: Optional[str] = None

class ChatResponse(BaseModel):
    success: bool
    response: str = ""
    error: str = ""

class SummaryRequest(BaseModel):
    title: str = ""
    text: str

class SummaryResponse(BaseModel):
    success: bool
    summary: str = ""
    points: List[str] = []
    error: str = ""

class ImageChatRequest(BaseModel):
    message: str = "幫我辨識這張圖片的文字"
    image_base64: str
    mode: str = "ocr_then_llm"

class GmailComposeRequest(BaseModel):
    to:      str
    subject: str
    body:    str
    refine:  bool = True

class GmailSendRequest(BaseModel):
    to:      str
    subject: str
    body:    str


# ─── 自動記憶判斷 / 關機總結 ─────────────────────────────

def _extract_json_object(text: str) -> dict:
    text = (text or "").strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        try:
            return json.loads(text[start:end + 1])
        except json.JSONDecodeError:
            pass
    return {"memories": []}


def _ollama_json(messages: list[dict], timeout: int = 60) -> dict:
    payload = {
        "model": MODEL_NAME,
        "messages": messages,
        "stream": False,
        "format": "json",
        "options": {
            "temperature": 0.1,
            "num_predict": 1200,
        },
    }
    response = requests.post(OLLAMA_URL, json=payload, timeout=timeout)
    response.raise_for_status()
    content = response.json().get("message", {}).get("content", "")
    return _extract_json_object(content)


def auto_remember_conversation(
    user_text: str,
    assistant_text: str,
    session_id: str = "default",
    agent_name: Optional[str] = None,
) -> None:
    """
    每句普通對話結束後即時判斷是否要記住。
    若 agent_name 有值，記憶同時寫入 user 分區與該 Agent 的記憶分區。
    注意：tool call 的路徑不呼叫這個函式，避免工具使用內容被自動寫入記憶。
    """
    user_text = (user_text or "").strip()
    assistant_text = (assistant_text or "").strip()
    if not user_text:
        return

    messages = [
        {
            "role": "system",
            "content": (
                "你是桌面寵物助手的記憶分類器。請只根據這一輪普通對話判斷是否值得記住。\n"
                "不要記 tool 執行結果、不要記閒聊客套、不要記一次性的指令。\n\n"

                "【記憶 key 命名規則 — 必須嚴格遵守，不可自創其他 key 名】\n"
                "使用者名字     → 固定用「使用者名字」\n"
                "使用者職業     → 固定用「使用者職業」\n"
                "使用者喜好     → 固定用「使用者喜好:XXX」（例如「使用者喜好:飲料」）\n"
                "今日心情       → 固定用「今日心情」\n"
                "近期計畫       → 固定用「近期計畫:XXX」\n\n"

                "【個性記憶 — 觀察使用者對助手的期待與反應】\n"
                "若使用者的言語暗示他希望助手有某種個性傾向，請以 personality: 為前綴寫入記憶。\n"
                "personality key 只能從以下幾個選：\n"
                "  personality:語氣       → 說話風格，例如「輕鬆口語，少用敬語」\n"
                "  personality:撒嬌程度   → 例如「主人喜歡可愛反應，可以多一點」\n"
                "  personality:對主人稱呼 → 例如「叫對方笨蛋主人（親暱）」\n"
                "  personality:活潑程度   → 例如「主人喜歡話多一點的風格」\n"
                "  personality:傲嬌程度   → 例如「主人喜歡被嗆但帶關心的語氣」\n"
                "personality 記憶的 importance 固定填 permanent，不可填其他值。\n"
                "只有使用者明確稱讚、糾正、或明顯表達偏好時才寫入，閒聊不要亂寫。\n\n"

                "importance 只能是 permanent、days_7、days_3：\n"
                "permanent=應永久保留；days_7=近期但可能過期；days_3=今天/短暫狀態。\n"
                "只輸出 JSON，格式：{\"memories\":[{\"key\":\"...\",\"value\":\"...\",\"importance\":\"permanent|days_7|days_3\"}]}\n"
                "若沒有值得記住的內容，輸出 {\"memories\":[]}。"
            ),
        },
        {
            "role": "user",
            "content": (
                f"使用者：{user_text}\n"
                f"助手：{assistant_text}\n\n"
                "請判斷這一輪對話要不要新增或更新記憶。"
            ),
        },
    ]

    try:
        data = _ollama_json(messages)
        memories = data.get("memories", [])
        if not isinstance(memories, list):
            return
        for item in memories:
            if not isinstance(item, dict):
                continue
            key = str(item.get("key", "")).strip()
            value = str(item.get("value", "")).strip()
            importance = str(item.get("importance", "days_7")).strip()
            # personality 記憶強制 permanent，不信任小模型的判斷
            if key.startswith("personality:"):
                importance = "permanent"
            if key and value:
                upsert_memory(
                    key,
                    value,
                    importance,
                    source="auto",
                    session_id=session_id,
                    user_text=user_text,
                    assistant_text=assistant_text,
                    record_event=True,
                )
                # 若處於 Agent 助手模式，同步寫入 Agent 記憶分區
                if agent_name:
                    from memory_helper import upsert_agent_memory
                    upsert_agent_memory(agent_name, key, value, importance)
    except Exception as e:
        print(f"[memory] 自動記憶判斷失敗：{e}")


def summarize_today_memories_on_shutdown() -> None:
    events = get_today_memory_events()
    if not events:
        print("[memory] 今日沒有需要關機總結的記憶")
        return

    event_lines = []
    for event in events:
        event_lines.append(
            f"- [{event['importance']}] {event['key']}：{event['value']} "
            f"(source={event['source']}, time={event['created_at']})"
        )

    messages = [
        {
            "role": "system",
            "content": (
                "你是桌面寵物助手的每日記憶總結器。請把今天 DB 裡的候選記憶去重、合併、重新分類。"
                "只保留未來真的有助於陪伴與協助使用者的內容。"
                "以下規則必須嚴格遵守，不可違反：\n"
                "1. personality: 前綴的個性記憶必須全部保留，importance 固定維持 permanent。\n"
                "2. 今日心情、今日狀態類的記憶必須保留，importance 固定用 days_3。\n"
                "3. 使用者明確說出的喜好、身分、習慣必須保留，importance 用 permanent。\n"
                "可以刪除的：工具執行結果、無意義閒聊、重複的內容（只保留最新一筆）。"
                "importance 只能是 permanent、days_7、days_3："
                "permanent=永久重要；days_7=一週內有用；days_3=三天內有用。"
                "只輸出 JSON，格式：{\"memories\":[{\"key\":\"...\",\"value\":\"...\",\"importance\":\"permanent|days_7|days_3\"}]}"
            ),
        },
        {
            "role": "user",
            "content": "今天的候選記憶如下：\n" + "\n".join(event_lines),
        },
    ]

    try:
        data = _ollama_json(messages, timeout=90)
        memories = data.get("memories", [])
        if not isinstance(memories, list):
            memories = []
        cleaned = [
            item for item in memories
            if isinstance(item, dict)
            and str(item.get("key", "")).strip()
            and str(item.get("value", "")).strip()
        ]
        count = replace_today_auto_memories(cleaned)
        print(f"[memory] 關機總結完成：保留 {count} 筆今日精簡記憶")
    except Exception as e:
        print(f"[memory] 關機總結失敗，保留即時記憶結果：{e}")


# ─── Tool 執行 ────────────────────────────────────────────

def execute_tool(tool_name: str, tool_args: dict) -> str:
    try:
        if tool_name == "summarize_news":
            summary, points = summarize_news_plus(
                tool_args.get("title", ""), tool_args.get("text", "")
            )
            return f"摘要：{summary}\n重點：{chr(10).join(points)}"

        elif tool_name == "summarize_article":
            summary, points = summarize_article_plus(
                tool_args.get("title", ""), tool_args.get("text", "")
            )
            return f"摘要：{summary}\n{chr(10).join(points)}"

        elif tool_name == "open_ocr":
            subprocess.Popen([sys.executable, "ocr_gui_runner.py"])
            return "OCR視窗已開啟"

        elif tool_name == "open_calculator":
            subprocess.Popen(["calc.exe"])
            return f"計算器已開啟，算式：{tool_args.get('expression', '')}"

        elif tool_name == "add_schedule":
            schedule_text = tool_args.get("schedule_text", "").strip()
            if not schedule_text:
                return "錯誤：無法從你說的內容中提取日程資訊，請再說一次。"
            print(f"[schedule] 新增日程：{schedule_text}")
            return f"SCHEDULE_ADD:{schedule_text}"

        elif tool_name == "open_gmail_web":
            import webbrowser
            webbrowser.open("https://mail.google.com/mail/u/0/#inbox")
            return "已開啟 Gmail 網頁。"

        elif tool_name == "check_gmail":
            max_results = int(tool_args.get("max_results", 20))
            gmail       = get_gmail()
            result      = gmail.check_today_unread(max_results=max_results)
            emails      = result["emails"]
            count       = result["count"]

            if count == 0:
                return (
                    "今天沒有未讀郵件。\n"
                    "請詢問使用者是否需要開啟 Gmail 網頁，或是有其他需要幫忙的事。"
                )

            lines = [f"今天共有 {count} 封未讀郵件："]
            for i, e in enumerate(emails, 1):
                lines.append(
                    f"第 {i} 封｜寄件人：{e['sender']}｜主旨：{e['subject']}"
                )
            lines.append(
                "\n請將以上信件清單告訴使用者，然後詢問他：要幫他開啟 Gmail 網頁查看，還是要幫他直接發送回覆？"
            )
            return "\n".join(lines)

        elif tool_name == "compose_gmail":
            to      = tool_args.get("to", "")
            subject = tool_args.get("subject", "")
            body    = tool_args.get("body", "")
            if not all([to, subject, body]):
                return "錯誤：缺少收件人、主旨或內文，請再說一次"
            gmail   = get_gmail()
            preview = gmail.compose_preview(to, subject, body, refine=True)
            return (
                f"[郵件預覽]\n"
                f"{preview['preview_text']}\n\n"
                f"原文 {len(preview['original_body'])} 字 → "
                f"精簡後 {len(preview['refined_body'])} 字\n"
                f"請問確認發送嗎？"
            )

        elif tool_name == "add_memory":
            key        = tool_args.get("key", "").strip()
            value      = tool_args.get("value", "").strip()
            importance = tool_args.get("importance", "days_7")
            if not key or not value:
                return "錯誤：key 和 value 都不能為空"
            return upsert_memory(key, value, importance, source="manual")

        elif tool_name == "fetch_url":
            from summarizer_plus import fetch_url_content
            url = tool_args.get("url", "").strip()
            if not url:
                return "錯誤：未提供 URL"
            title, text = fetch_url_content(url)
            if not text:
                return f"錯誤：無法取得網頁內容（{url}）"
            # 回傳給 LLM，讓它接著呼叫 summarize_news/summarize_article
            return f"TITLE:{title}\nTEXT:{text[:6000]}"
        elif tool_name == "get_weather":
            import requests as _req
            location = tool_args.get("location", "").strip() or "Taipei" 
            try:
                r = _req.get(
                    f"https://wttr.in/{location}",
                    params={"format": "j1", "lang": "zh"},
                    timeout=10,
                    headers={"User-Agent": "curl/7.0"}
                )
                r.raise_for_status()
                data = r.json()

                current = data["current_condition"][0]
                desc    = current["lang_zh"][0]["value"]
                temp    = current["temp_C"]
                feel    = current["FeelsLikeC"]
                humid   = current["humidity"]
                wind    = current["windspeedKmph"]

                today = data["weather"][0]
                max_t = today["maxtempC"]
                min_t = today["mintempC"]
                rain  = today["hourly"][4].get("chanceofrain", "?")

                result = (
                    f"{location} 天氣：{desc}\n"
                    f"氣溫：{min_t}°C ~ {max_t}°C，目前 {temp}°C（體感 {feel}°C）\n"
                    f"降雨機率：{rain}%，濕度：{humid}%，風速：{wind} km/h"
                )
                if str(rain).isdigit() and int(rain) >= 40:
                    result += "\n建議帶傘"
                return result
            except Exception as e:
                return f"天氣查詢失敗：{e}"
            
        else:   
            return f"未知工具：{tool_name}"

    except Exception as e:
        return f"工具執行失敗：{str(e)}"
        


# ─── 基本端點 ─────────────────────────────────────────────

@app.get("/")
async def root():
    return {"message": "Godot Ollama API 服務運行中", "status": "healthy", "version": "4.0.0"}

@app.get("/health")
async def health_check():
    return {"status": "running", "model": MODEL_NAME}

@app.post("/admin/reload")
async def admin_reload():
    try:
        reload_config()
        return {"success": True, "message": "已重新載入 system_prompt.md & tools.json"}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ─── 語音聆聽 ─────────────────────────────────────────────

@app.post("/listen")
def listen_microphone():
    result = listen_once(timeout=10)
    return result

@app.post("/listen_stream")
async def listen_microphone_stream(timeout: float = 15.0):
    async def generator():
        async for chunk in listen_stream(timeout=timeout):
            yield chunk
    return StreamingResponse(
        generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ─── OCR 端點 ─────────────────────────────────────────────

@app.post("/open_ocr")
async def open_ocr_window():
    try:
        subprocess.Popen([sys.executable, "ocr_gui_runner.py"])
        return {"success": True, "message": "視窗啟動指令已發送"}
    except Exception as e:
        return {"success": False, "error": str(e)}


# ─── 文字版 tool call 解析 ────────────────────────────────
import re as _re

def _parse_text_tool_calls(content: str) -> list:
    tool_calls = []
    blocks = _re.findall(r'<tool_call>(.*?)</tool_call>', content, _re.DOTALL)
    if not blocks:
        blocks = _re.findall(
            r'\{[^{}]*"name"\s*:\s*"[^"]+"\s*,\s*"arguments"\s*:\s*\{[^{}]*\}[^{}]*\}',
            content, _re.DOTALL
        )
    for block in blocks:
        block = block.strip()
        try:
            obj = json.loads(block)
            name = obj.get("name") or obj.get("function", {}).get("name")
            args = obj.get("arguments") or obj.get("parameters") or {}
            if name:
                tool_calls.append({"function": {"name": name, "arguments": args}})
        except (json.JSONDecodeError, AttributeError):
            continue
    return tool_calls


# ─── Tool-aware 串流核心 ──────────────────────────────────

async def _tool_aware_stream(
    user_text:   str,
    session_id:  str,
    temperature: float = 0.7,
    max_tokens:  int   = 512,
    agent_name:  Optional[str] = None,
):
    loop    = asyncio.get_event_loop()
    history = conversation_history.get(session_id)

    from llm_stream import SYSTEM_PROMPT
    from memory_helper import get_agent_memory_context

    bare_prompt     = SYSTEM_PROMPT
    enriched_prompt = inject_memory_to_prompt(SYSTEM_PROMPT)

    # 若有 agent_name，在 system prompt 前注入 agent 身份與記憶
    if agent_name:
        agent_ctx = get_agent_memory_context(agent_name, max_items=10)
        agent_latest_story = ""
        agent_dir = _STORIES_DIR / agent_name
        if agent_dir.exists():
            files = sorted(agent_dir.glob("story_*.json"), reverse=True)
            if files:
                try:
                    data = _json_mod.loads(files[0].read_text(encoding="utf-8"))
                    agent_latest_story = "\n".join(data.get("entries", [])[-5:])
                except Exception:
                    pass
        agent_header = (
            f"【你現在是村莊居民「{agent_name}」，暫時離開村莊協助主人。】\n"
            f"請以{agent_name}的身份和口吻與主人對話，保持角色一致。\n"
        )
        if agent_ctx:
            agent_header += f"\n【{agent_name}的記憶摘要】\n{agent_ctx}\n"
        if agent_latest_story:
            agent_header += f"\n【最新日誌片段】\n{agent_latest_story}\n"
        agent_header += "\n---\n"
        bare_prompt     = agent_header + SYSTEM_PROMPT
        enriched_prompt = agent_header + inject_memory_to_prompt(SYSTEM_PROMPT)

    detect_messages = [{"role": "system", "content": bare_prompt}]
    if history:
        detect_messages.extend(history)
    detect_messages.append({"role": "user", "content": user_text})

    payload_detect = {
        "model":    MODEL_NAME,
        "messages": detect_messages,
        "stream":   False,
        "tools":    TOOLS,
        "options":  {"temperature": temperature, "num_predict": max_tokens},
    }

    try:
        resp = await loop.run_in_executor(
            None,
            lambda: requests.post(OLLAMA_URL, json=payload_detect, timeout=60),
        )
        resp.raise_for_status()
    except Exception as e:
        yield error_sse(f"tool detection 失敗：{e}")
        return

    result     = resp.json()
    msg        = result.get("message", {})
    tool_calls = msg.get("tool_calls", [])

    if not tool_calls:
        content_text = msg.get("content", "")
        tool_calls = _parse_text_tool_calls(content_text)
        if tool_calls:
            print(f"[tool] 從文字解析到工具呼叫：{[tc['function']['name'] for tc in tool_calls]}")

    if tool_calls:
        print(f"[tool] 偵測到工具呼叫：{[tc['function']['name'] for tc in tool_calls]}")

        tool_results: list[str] = []
        for tc in tool_calls:
            tool_name = tc["function"]["name"]
            tool_args = tc["function"].get("arguments", {})
            if isinstance(tool_args, str):
                tool_args = json.loads(tool_args)
            print(f"[tool] {tool_name} → {tool_args}")
            tool_result = await loop.run_in_executor(
                None, lambda: execute_tool(tool_name, tool_args)
            )
            tool_results.append(tool_result)

        tool_results_text = "\n".join(tool_results)
        second_user_msg = (
            f"工具執行結果如下：\n{tool_results_text}\n\n"
            f"請根據以上資訊，用繁體中文自然地回覆使用者的問題：「{user_text}」"
        )
        second_messages = [{"role": "system", "content": enriched_prompt}]
        if history:
            second_messages.extend(history)
        second_messages.append({"role": "user", "content": second_user_msg})

        payload_stream = {
            "model":    MODEL_NAME,
            "messages": second_messages,
            "stream":   True,
            "options":  {"temperature": temperature, "num_predict": max_tokens},
        }
        full_reply: list[str] = []
        try:
            with requests.post(OLLAMA_URL, json=payload_stream, stream=True, timeout=60) as r:
                r.raise_for_status()
                for raw in r.iter_lines():
                    if not raw:
                        continue
                    chunk = json.loads(raw)
                    token = chunk.get("message", {}).get("content", "")
                    if token:
                        full_reply.append(token)
                        yield token_to_sse(token)
                    if chunk.get("done"):
                        break
        except Exception as e:
            yield error_sse(str(e))
            return

        complete = "".join(full_reply)
        conversation_history.add_assistant(session_id, complete)
        yield done_sse()

    else:
        direct_messages = [{"role": "system", "content": enriched_prompt}]
        if history:
            direct_messages.extend(history)
        direct_messages.append({"role": "user", "content": user_text})

        payload_stream = {
            "model":    MODEL_NAME,
            "messages": direct_messages,
            "stream":   True,
            "options":  {"temperature": temperature, "num_predict": max_tokens},
        }

        full_reply: list[str] = []
        try:
            with requests.post(OLLAMA_URL, json=payload_stream, stream=True, timeout=60) as r:
                r.raise_for_status()
                for raw in r.iter_lines():
                    if not raw:
                        continue
                    chunk = json.loads(raw)
                    token = chunk.get("message", {}).get("content", "")
                    if token:
                        full_reply.append(token)
                        yield token_to_sse(token)
                    if chunk.get("done"):
                        break
        except Exception as e:
            yield error_sse(str(e))
            return

        complete = "".join(full_reply)
        conversation_history.add_assistant(session_id, complete)
        await loop.run_in_executor(
            None,
            lambda: auto_remember_conversation(user_text, complete, session_id, agent_name),
        )
        yield done_sse()


# ─── 串流對話端點 ─────────────────────────────────────────

@app.get("/chat_stream")
async def chat_stream_get(
    message:     str   = Query(...),
    session_id:  str   = Query("default"),
    temperature: float = Query(0.7),
    max_tokens:  int   = Query(512),
    agent_name:  Optional[str] = Query(None),
):
    async def generator():
        print(f"[/chat_stream] session={session_id} agent={agent_name} → {message}")
        conversation_history.add_user(session_id, message)
        async for chunk in _tool_aware_stream(message, session_id, temperature, max_tokens, agent_name):
            yield chunk

    return StreamingResponse(
        generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.post("/chat_stream")
async def chat_stream_post(request: StreamChatRequest):
    async def generator():
        print(f"[/chat_stream POST] session={request.session_id} agent={request.agent_name} → {request.message}")
        conversation_history.add_user(request.session_id, request.message)
        async for chunk in _tool_aware_stream(
            request.message, request.session_id, request.temperature, request.max_tokens, request.agent_name
        ):
            yield chunk

    return StreamingResponse(
        generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ─── 語音 → LLM 串流 ──────────────────────────────────────

@app.get("/voice_chat_stream")
async def voice_chat_stream(
    session_id: str   = Query("default"),
    timeout:    float = Query(10.0),
):
    async def generator():
        loop = asyncio.get_event_loop()
        asr_result = await loop.run_in_executor(
            None, lambda: listen_once(timeout=timeout)
        )

        if not asr_result.get("success") or not asr_result.get("text", "").strip():
            yield error_sse(asr_result.get("error", "語音辨識失敗或無輸入"))
            return

        user_text = asr_result["text"].strip()
        yield f"event: asr_result\ndata: {user_text.replace(chr(10), ' ')}\n\n"

        conversation_history.add_user(session_id, user_text)
        async for chunk in _tool_aware_stream(user_text, session_id):
            yield chunk

    return StreamingResponse(
        generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ─── 對話歷史管理 ─────────────────────────────────────────

@app.delete("/history/{session_id}")
async def clear_history(session_id: str):
    conversation_history.clear(session_id)
    return {"success": True, "message": f"已清除 session '{session_id}' 的對話歷史"}

@app.get("/history/{session_id}")
async def get_history(session_id: str):
    return {"session_id": session_id, "history": conversation_history.get(session_id)}


# ─── 圖片 OCR + LLM ──────────────────────────────────────

@app.post("/chat_with_image", response_model=ChatResponse)
async def chat_with_image(request: ImageChatRequest):
    try:
        try:
            img_bytes = base64.b64decode(request.image_base64)
            img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
        except Exception as e:
            return ChatResponse(success=False, error=f"圖片解碼失敗：{e}")

        print("🔍 開始 OCR 辨識...")
        ocr = get_ocr()
        ocr_text = ocr.extract_text_from_pil(img)
        print(f"📄 OCR 結果：{ocr_text[:100]}...")

        if not ocr_text.strip():
            return ChatResponse(success=False, error="圖片中沒有偵測到任何文字")

        if request.mode == "ocr_only":
            return ChatResponse(success=True, response=ocr_text)

        combined_message = (
            f"{request.message}\n\n"
            f"以下是從圖片中辨識到的文字內容：\n---\n{ocr_text}\n---\n請根據以上內容回應。"
        )

        messages = [{"role": "user", "content": combined_message}]
        payload = {
            "model": MODEL_NAME,
            "messages": messages,
            "stream": False,
            "tools": TOOLS,
            "options": {"temperature": 0.7, "num_predict": 4000},
        }

        response = requests.post(OLLAMA_URL, json=payload, timeout=60)
        if response.status_code != 200:
            return ChatResponse(success=False, error=f"Ollama Error: {response.status_code}")

        result     = response.json()
        message    = result.get("message", {})
        tool_calls = message.get("tool_calls", [])

        if tool_calls:
            messages.append({"role": "assistant", "content": "", "tool_calls": tool_calls})
            for tc in tool_calls:
                tool_name = tc["function"]["name"]
                tool_args = tc["function"].get("arguments", {})
                if isinstance(tool_args, str):
                    tool_args = json.loads(tool_args)
                tool_result = execute_tool(tool_name, tool_args)
                messages.append({"role": "tool", "content": tool_result})

            payload2 = {
                "model": MODEL_NAME,
                "messages": messages,
                "stream": False,
                "options": {"temperature": 0.7, "num_predict": 4000},
            }
            response2 = requests.post(OLLAMA_URL, json=payload2, timeout=60)
            if response2.status_code != 200:
                return ChatResponse(success=False, error=f"Ollama Error (2nd): {response2.status_code}")

            final_reply = response2.json().get("message", {}).get("content", "").strip()
            return ChatResponse(success=True, response=final_reply)

        else:
            ai_reply = message.get("content", "").strip()
            return ChatResponse(success=True, response=ai_reply)

    except Exception as e:
        return ChatResponse(success=False, error=str(e))


# ─── 摘要端點 ─────────────────────────────────────────────

@app.post("/summarize/news", response_model=SummaryResponse)
async def api_summarize_news(request: SummaryRequest):
    try:
        summary_text, points_list = summarize_news_plus(request.title, request.text)
        return SummaryResponse(success=True, summary=summary_text, points=points_list)
    except Exception as e:
        return SummaryResponse(success=False, error=str(e))

@app.post("/summarize/article", response_model=SummaryResponse)
async def api_summarize_article(request: SummaryRequest):
    try:
        summary_text, points_list = summarize_article_plus(request.title, request.text)
        return SummaryResponse(success=True, summary=summary_text, points=points_list)
    except Exception as e:
        return SummaryResponse(success=False, error=str(e))


# ─── Gmail 端點 ───────────────────────────────────────────

@app.get("/gmail/inbox")
async def gmail_inbox(max_results: int = 5):
    try:
        gmail    = get_gmail()
        emails   = gmail.check_new_emails(max_results=max_results)
        tts_text = gmail.format_for_tts(emails)
        return {
            "success":  True,
            "count":    len(emails),
            "emails":   emails,
            "tts_text": tts_text,
        }
    except Exception as e:
        return {
            "success":  False,
            "error":    str(e),
            "tts_text": f"讀取郵件失敗：{str(e)}",
        }

@app.post("/gmail/compose")
async def gmail_compose(request: GmailComposeRequest):
    try:
        gmail   = get_gmail()
        preview = gmail.compose_preview(
            to=request.to,
            subject=request.subject,
            body=request.body,
            refine=request.refine,
        )
        return {"success": True, **preview}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/gmail/send")
async def gmail_send(request: GmailSendRequest):
    try:
        gmail  = get_gmail()
        result = gmail.send_email(
            to=request.to,
            subject=request.subject,
            body=request.body,
        )
        tts = (
            f"郵件已成功發送給 {request.to}。"
            if result["success"]
            else f"郵件發送失敗：{result['error']}"
        )
        return {**result, "tts_text": tts}
    except Exception as e:
        return {
            "success":  False,
            "error":    str(e),
            "tts_text": f"發送失敗：{str(e)}",
        }


# ─── 記憶管理端點 ─────────────────────────────────────────

class MemoryUpsertRequest(BaseModel):
    key:        str
    value:      str
    importance: str = "days_7"

@app.get("/memory")
async def memory_list():
    return {"memories": get_all_memories()}

@app.post("/memory")
async def memory_add(request: MemoryUpsertRequest):
    result = upsert_memory(request.key, request.value, request.importance)
    return {"success": True, "message": result}

@app.delete("/memory/{key}")
async def memory_delete(key: str):
    result = delete_memory(key)
    return {"success": True, "message": result}


# ─── 日程表端點 ───────────────────────────────────────────
current_schedules = []
class ScheduleAddRequest(BaseModel):
    text: str

@app.post("/schedule/add")
async def schedule_add(request: ScheduleAddRequest):
    print(f"[schedule/add] Godot 傳入日程：{request.text}")
    return {"success": True, "text": request.text}

@app.get("/schedule/get")
async def schedule_get():
    today_events = get_today_memory_events()
    
    # 如果資料庫是空的，就回傳模擬資料，確保格式漂亮
    formatted_text = "【今天的日程表】\n"
    events_to_show = today_events if today_events else current_schedules
    
    for idx, item in enumerate(events_to_show, 1):
        formatted_text += f"{idx}. {item}\n"
        
    return {"success": True, "schedule_content": formatted_text}

# ─── 村莊 Agent 提取 API ──────────────────────────────────

import json as _json_mod
from pathlib import Path as _Path

_STORIES_DIR = _Path(__file__).parent.parent / "GodotMap" / "stories"
_active_assistant: dict = {}   # {"agent": str, "data": dict}


class AgentExtractRequest(BaseModel):
    agent: str

class AgentReturnRequest(BaseModel):
    agent:            str
    conversation_log: list = []

class MemorySyncRequest(BaseModel):
    agent:     str
    user_text: str
    note:      str


@app.post("/village/agent/extract")
async def village_agent_extract(req: AgentExtractRequest):
    from memory_helper import get_agent_db_summary, get_agent_memory_context
    agent = req.agent
    summary = get_agent_db_summary(agent)

    # 讀取最新日誌
    agent_dir = _STORIES_DIR / agent
    latest_story = ""
    if agent_dir.exists():
        files = sorted(agent_dir.glob("story_*.json"), reverse=True)
        if files:
            try:
                data = _json_mod.loads(files[0].read_text(encoding="utf-8"))
                latest_story = "\n".join(data.get("entries", []))
            except Exception:
                pass

    snapshot = {
        "agent":        agent,
        "summary":      summary,
        "latest_story": latest_story,
    }
    _active_assistant["agent"] = agent
    _active_assistant["data"]  = snapshot
    print(f"[village] Agent {agent} 進入助手模式")
    return {"success": True, "agent": agent, "snapshot": snapshot}


@app.post("/village/agent/return")
async def village_agent_return(req: AgentReturnRequest):
    agent = req.agent
    if req.conversation_log:
        for turn in req.conversation_log:
            user_text = turn.get("user", "")
            asst_text = turn.get("assistant", "")
            if user_text and asst_text:
                # 同時寫入 user 分區與 Agent 記憶分區
                auto_remember_conversation(
                    user_text, asst_text,
                    session_id=f"village_{agent}",
                    agent_name=agent,
                )
    _active_assistant.clear()
    print(f"[village] Agent {agent} 返回村莊，對話記憶已同步（user + agent 分區）")
    return {"success": True, "agent": agent}


@app.get("/village/agent/{agent_name}/context")
async def village_agent_context(agent_name: str):
    from memory_helper import get_agent_db_summary, get_agent_memory_context
    summary = get_agent_db_summary(agent_name)
    agent_dir = _STORIES_DIR / agent_name
    latest_story = ""
    if agent_dir.exists():
        files = sorted(agent_dir.glob("story_*.json"), reverse=True)
        if files:
            try:
                data = _json_mod.loads(files[0].read_text(encoding="utf-8"))
                latest_story = "\n".join(data.get("entries", []))
            except Exception:
                pass
    return {
        "agent":        agent_name,
        "summary":      summary,
        "latest_story": latest_story,
    }


@app.get("/village/agent/active")
async def village_agent_active():
    if _active_assistant.get("agent"):
        return {"active": True, "agent": _active_assistant["agent"]}
    return {"active": False, "agent": ""}


@app.post("/village/memory/sync")
async def village_memory_sync(req: MemorySyncRequest):
    key   = f"village_{req.agent}:{req.note[:20]}" if req.note else f"village_{req.agent}"
    result = upsert_memory(key, req.note, "days_7", source="village_sync")
    print(f"[village] 記憶同步 → {req.agent}: {req.note[:40]}")
    return {"success": True, "message": result}


# ─── 啟動 ─────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 55)
    print("  Godot Ollama API v4.1.0（整合版）")
    print("  http://127.0.0.1:8000")
    print()
    print("  ── 桌面寵物路由 ──────────────────────────")
    print("  串流對話：  GET/POST /chat_stream")
    print("  語音串流：  GET      /voice_chat_stream")
    print("  語音辨識：  POST     /listen")
    print("  Gmail 收信：GET      /gmail/inbox")
    print("  Gmail 預覽：POST     /gmail/compose")
    print("  Gmail 發送：POST     /gmail/send")
    print("  日程新增：  POST     /schedule/add")
    print("  記憶列表：  GET      /memory")
    print("  記憶新增：  POST     /memory")
    print("  記憶刪除：  DELETE   /memory/{key}")
    print()
    print("  ── 村莊模擬路由 ──────────────────────────")
    print("  社交決策：  POST     /social/check")
    print("  社交完成：  POST     /social/complete")
    print("  關係查詢：  GET      /social/relationship/{a}/{b}")
    print("  日程建議：  POST     /schedule/suggest_variant")
    print("  記憶儲存：  POST     /village/memory/save")
    print("  記憶載入：  POST     /village/memory/context")
    print()
    print("  ── Agent 提取 API ────────────────────────")
    print("  提取 Agent：POST     /village/agent/extract")
    print("  送回村莊：  POST     /village/agent/return")
    print("  當前助手：  GET      /village/agent/active")
    print("  取得 Context：GET    /village/agent/{name}/context")
    print("  記憶同步：  POST     /village/memory/sync")
    print("=" * 55)
    uvicorn.run("main_api:app", host="0.0.0.0", port=8000, reload=True, log_level="info")